## The one consolidated, styled panel for a selected building — replaces the
## four old corner widgets (base_panel/build_menu/building_info_panel/
## production_panel). Shown on the right whenever
## InputController.selected_building_id is set (any of the local player's own
## base buildings). Top to bottom: title, base name + population, a Level row
## with an Upgrade button (or RUINED + Rebuild), then a category-specific body —
## the build menu for an HQ, the troop menu + queue for a Production building,
## the per-tick output for a Resource building.
##
## Ineligible build/upgrade/troop options are styled muted (UITheme.MUTED) but
## stay clickable: clicking one writes the reason (UIEligibility) into a red
## label instead of acting. The node tree is rebuilt only when the selected
## building changes; eligibility styling is re-checked on a throttle and live
## values (queue timers, next-tick countdown) every frame, via the two updater
## lists. Built entirely from client/ui/ui_theme.gd factories + real Control
## nodes — no _draw(), unlike the world-space views beneath it.
class_name BuildingPanel
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

const WIDTH := 420.0
const MARGIN := 12.0
const REFRESH_INTERVAL := 0.25
## The base-attached naval-landing buildings (Dock itself is standalone and not
## selectable) that get a Load/Unload section for an adjacent transport ship —
## the ship-side subset of BuildingPlacement.NAVAL_LANDING_BUILDING_TYPES.
const NAVAL_DOCK_BUILDINGS := ["port", "shipyard", "harbour"]

var _content: VBoxContainer
var _scroll: ScrollContainer
var _reason_label: Label
var _shown_for_building_id: String = ""
## Snapshot of the shown building's level/ruin state as of the last _rebuild —
## compared every frame so an upgrade/rebuild/ruin transition rebuilds the
## panel (new Level text, cost, Max-level state) without needing a reselect.
var _shown_level: int = -1
var _shown_is_ruin: bool = false
## Which BUILD-menu building_type is currently expanded to show its detail
## (notes/stats/cost/Build button) — "" when the menu is fully collapsed.
## Reset whenever the selected building changes, but survives a same-building
## _rebuild() (toggling expansion re-enters _rebuild() itself).
var _expanded_build_type: String = ""
## [{button: Button, variation: String, reason_fn: Callable}] — re-checked on a
## throttle to flip each option button between its normal look and MUTED.
var _option_updaters: Array = []
## Callables refreshing volatile text (queue timers, tick countdown) every frame.
var _live_updaters: Array[Callable] = []
var _refresh_accum := 0.0

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller

	# Top-right band under the resource bar, stopping short of the minimap's
	# bottom-right footprint (same layout contract build_menu.gd held).
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = ResourceBar.HEIGHT + MARGIN
	offset_bottom = -(Minimap.SIZE.y + Minimap.MARGIN + MARGIN)
	# STOP (not IGNORE): this panel owns real buttons, and its background must
	# also swallow clicks so they never fall through to a world move order.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# We scroll manually here (see _on_scroll_gui_input) rather than relying on
	# ScrollContainer's built-in wheel handling: the gui_input signal fires
	# BEFORE the built-in _gui_input, so any set_input_as_handled() we do to stop
	# the wheel falling through to the camera would also cancel the built-in
	# scroll. Doing the scroll ourselves and then accepting handles both.
	_scroll.gui_input.connect(_on_scroll_gui_input)
	panel.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	# PASS, not the Control default STOP: _content covers the full scroll area,
	# so without this every wheel event over any gap/label is eaten here before
	# it ever reaches the ScrollContainer's own scroll handling.
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)

const SCROLL_STEP := 40

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.scroll_vertical -= SCROLL_STEP
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.scroll_vertical += SCROLL_STEP
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	var target_id := input_controller.selected_building_id
	var building_changed := target_id != _shown_for_building_id
	var needs_rebuild := building_changed
	if not needs_rebuild and target_id != "":
		var found := state.find_base_building(target_id)
		if not found.is_empty():
			var building: BuildingInstance = found["building"]
			needs_rebuild = building.level != _shown_level or building.is_ruin != _shown_is_ruin
	if building_changed:
		_expanded_build_type = ""
	if needs_rebuild:
		_shown_for_building_id = target_id
		_rebuild()
		if building_changed and visible:
			UIJuice.pop_in(self)
	if not visible:
		return
	for updater in _live_updaters:
		updater.call()
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_eligibility()

func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	_option_updaters.clear()
	_live_updaters.clear()
	_reason_label = null
	_refresh_accum = 0.0

	var found := state.find_base_building(_shown_for_building_id) if _shown_for_building_id != "" else {}
	if found.is_empty():
		visible = false
		_shown_level = -1
		_shown_is_ruin = false
		return
	visible = true
	var base: BaseInstance = found["base"]
	var building: BuildingInstance = found["building"]
	_shown_level = building.level
	_shown_is_ruin = building.is_ruin
	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})

	_content.add_child(UITheme.title_label(String(def.get("name", building.building_type.capitalize()))))
	var used := Population.population_used(base, state.building_defs)
	var cap := Population.population_cap(base, state.building_defs)
	var base_label := base.display_name if base.display_name != "" else base.base_def_id.capitalize()
	_content.add_child(UITheme.subtitle_label("%s  -  Pop %d/%d" % [base_label, used, cap]))
	_content.add_child(HSeparator.new())

	_build_level_section(building, def, base.hq_level)

	if not building.is_ruin:
		if building.building_type == "hq":
			_content.add_child(HSeparator.new())
			_build_build_menu(base, base_def)
		elif String(def.get("category", "")) == "Production":
			_content.add_child(HSeparator.new())
			_build_troop_menu(building)
		elif String(def.get("category", "")) == "Resource":
			_content.add_child(HSeparator.new())
			_build_resource_body(building, def)

		# Cargo affordances, additive to whatever category body ran above (a Port
		# is Production, so it shows the troop menu AND the naval dock section).
		if building.building_type == "hangar":
			_content.add_child(HSeparator.new())
			_build_hangar_section(base, building)
		elif building.building_type in NAVAL_DOCK_BUILDINGS:
			_content.add_child(HSeparator.new())
			_build_naval_dock_section(building)

	_reason_label = UITheme.danger_label("")
	_reason_label.visible = false
	_content.add_child(_reason_label)

	_refresh_eligibility()

# --- Level / upgrade / rebuild ----------------------------------------------

func _build_level_section(building: BuildingInstance, def: Dictionary, hq_level: int) -> void:
	if building.is_ruin:
		_content.add_child(UITheme.danger_label("RUINED"))
		var percent := BuildingStats.rebuild_cost_percent(def, state.building_defs) / 100.0
		var full_cost := BuildingStats.base_cost(def, building.material, state.building_defs)
		var scaled: Dictionary = {}
		for key in full_cost:
			scaled[key] = int(round(float(full_cost[key]) * percent))
		var material := building.material
		_add_action_row("Rebuild", scaled, -1.0, UITheme.PRIMARY,
			func(): return _rebuild_reason(def, material, hq_level),
			func(): CommandProcessor.rebuild_building(state, _shown_for_building_id, owner_id))
		return

	_content.add_child(UITheme.body_label("Level %d" % building.level))
	if UIEligibility.upgrade_reason(state, _shown_for_building_id, owner_id) == "Max level":
		_content.add_child(UITheme.muted_label("Max level (fully upgraded)"))
		return
	var cost := BuildingStats.upgrade_cost(def, building.level, building.material, state.building_defs)
	_add_action_row("Upgrade", cost, -1.0, UITheme.PRIMARY,
		func(): return UIEligibility.upgrade_reason(state, _shown_for_building_id, owner_id),
		func(): CommandProcessor.upgrade_building(state, _shown_for_building_id, owner_id))

# --- Build menu (HQ) --------------------------------------------------------

func _build_build_menu(base: BaseInstance, base_def: Dictionary) -> void:
	_content.add_child(UITheme.header_label("BUILD"))
	var any := false
	for building_type in base_def.get("buildableBuildings", []):
		var def: Dictionary = state.building_defs.get(building_type, {})
		if def.get("isFixed", false):
			continue
		any = true
		var bt := String(building_type)
		var display_name := String(def.get("name", bt.capitalize()))
		# Cached once here (the expensive tile scan) and reused by reason_fn.
		var has_valid_hex := UIEligibility.any_valid_hex(state, base, base_def, bt)
		var reason_fn := func(): return UIEligibility.build_reason(state, base, bt, owner_id, has_valid_hex)

		var button := UITheme.action_button(display_name, "")
		button.pressed.connect(func():
			_expanded_build_type = "" if _expanded_build_type == bt else bt
			_rebuild())
		_content.add_child(button)
		_option_updaters.append({"button": button, "variation": "", "reason_fn": reason_fn})

		if _expanded_build_type == bt:
			_build_build_detail(base, bt, def, reason_fn)
	if not any:
		_content.add_child(UITheme.muted_label("Nothing to build here"))

## The pop-down shown under an expanded BUILD row: notes, a few headline
## stats if the def has any, then one cost row + Build button per material
## (just one, unbranded, for a single-material/no-material building like
## Turret; one per entry in `materials` for a Wall-style building where the
## player picks the resource, e.g. "Build (Stone)" / "Build (Steel)").
func _build_build_detail(base: BaseInstance, building_type: String, def: Dictionary, reason_fn: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS

	var notes := String(def.get("notes", ""))
	if notes != "":
		var notes_label := UITheme.muted_label(notes)
		notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(notes_label)

	for line in _building_stat_lines(def):
		box.add_child(UITheme.body_label(line))

	var materials: Array = def.get("materials", [])
	var base_id := base.id
	if materials.is_empty():
		var cost := BuildingStats.base_cost(def, "", state.building_defs)
		_build_material_row(box, "Build", cost, reason_fn,
			func(): input_controller.start_placement(base_id, building_type, ""))
	else:
		for material in materials:
			var mat := String(material)
			var cost := BuildingStats.base_cost(def, mat, state.building_defs)
			_build_material_row(box, "Build (%s)" % mat.capitalize(), cost, reason_fn,
				func(): input_controller.start_placement(base_id, building_type, mat))

	_content.add_child(box)

func _build_material_row(box: VBoxContainer, label_text: String, cost: Dictionary, reason_fn: Callable, action: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var button := UITheme.action_button(label_text, UITheme.PRIMARY)
	button.pressed.connect(func(): _handle_press(reason_fn, action))
	row.add_child(button)
	row.add_child(UITheme.cost_chips(cost))
	box.add_child(row)
	_option_updaters.append({"button": button, "variation": UITheme.PRIMARY, "reason_fn": reason_fn})

## A handful of headline stats for the detail pop-down — whichever of these
## the def's baseStats block has, in this fixed order. Buildings without a
## single-material baseStats block (Wall's per-material materialStats) fall
## back to the first material's stats, since the pop-down shows one Build
## button per material anyway and this is just a rough preview.
func _building_stat_lines(def: Dictionary) -> Array[String]:
	var stats: Dictionary = {}
	var non_prod: Dictionary = def.get("nonProductionUpgrade", {})
	var production_levels: Array = def.get("productionUpgradeLevels", [])
	var material_stats: Dictionary = def.get("materialStats", {})
	if not non_prod.is_empty():
		stats = non_prod.get("baseStats", {})
	elif not production_levels.is_empty():
		stats = {"hp": production_levels[0].get("hp", 0)}
	elif not material_stats.is_empty():
		stats = (material_stats.values()[0] as Dictionary).get("baseStats", {})

	var lines: Array[String] = []
	for key in ["hp", "damage", "range", "attackSpeed", "armor"]:
		if stats.has(key):
			lines.append("%s: %s" % [key.capitalize(), str(stats[key])])
	return lines

# --- Troop menu (Production) ------------------------------------------------

func _build_troop_menu(building: BuildingInstance) -> void:
	_content.add_child(UITheme.header_label("TRAIN"))
	var building_def: Dictionary = state.building_defs.get(building.building_type, {})
	var building_id := building.id
	var any := false
	var unlocked: Array = []
	for troop_type in state.troop_defs.keys():
		if CommandProcessor._troop_unlocked(state, building, building_def, troop_type):
			unlocked.append(troop_type)
	# Level 1 unlocks first, then level 2, and so on — matches the order the
	# player actually gains access to them as the building levels up.
	unlocked.sort_custom(func(a, b):
		return CommandProcessor._troop_unlock_level(state, building_def, a) < CommandProcessor._troop_unlock_level(state, building_def, b))
	for troop_type in unlocked:
		any = true
		var tdef: Dictionary = state.troop_defs[troop_type]
		var display_name := String(tdef.get("name", troop_type))
		var cost: Dictionary = tdef.get("cost", {})
		var time := float(tdef.get("productionTime", 0.0))
		var tt := String(troop_type)
		_add_action_row(display_name, cost, time, "",
			func(): return UIEligibility.troop_reason(state, building_id, tt, owner_id),
			func(): input_controller.submitter.submit("enqueue_production", [building_id, tt, owner_id], owner_id))
	if not any:
		_content.add_child(UITheme.muted_label("No troops unlocked yet"))
	_add_queue_status(building_id)

## Training row is a progress bar (0..1 across the front entry's
## production_time) with the troop name centered on top, e.g. "Training
## Basekiller x3 (21s)" when the front N queue entries are all the same
## troop — collapsing the old separate "Training: X" + "Queue (N more)"
## lines into one. Whatever's left after that leading run is shown grouped
## by run below (e.g. "Tonk x2, Glider x1"), same as the old "queued" line
## but with real names/counts instead of a bare total.
func _add_queue_status(building_id: String) -> void:
	_content.add_child(HSeparator.new())
	var bar := UITheme.progress_bar()
	var bar_label := UITheme.body_label("")
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bar_label)
	var empty_label := UITheme.muted_label("Queue empty")
	var rest := UITheme.muted_label("")
	var paused := UITheme.warning_label("")
	_content.add_child(bar)
	_content.add_child(empty_label)
	_content.add_child(rest)
	_content.add_child(paused)
	var update := func():
		var queue: ProductionQueue = state.production_queues.get(building_id)
		if queue == null or queue.entries.is_empty():
			bar.visible = false
			empty_label.visible = true
			rest.visible = false
			paused.visible = false
			return
		bar.visible = true
		empty_label.visible = false

		var front: Dictionary = queue.front()
		var troop_type := String(front.get("troop_type", ""))
		var run := 1
		while run < queue.entries.size() and String(queue.entries[run].get("troop_type", "")) == troop_type:
			run += 1
		var total := float(front.get("production_time", 0.0))
		var remaining := float(front.get("remaining", 0.0))
		bar.value = 1.0 - (remaining / total if total > 0.0 else 0.0)
		var troop_name := String(state.troop_defs.get(troop_type, {}).get("name", troop_type.capitalize()))
		var count_suffix := " x%d" % run if run > 1 else ""
		bar_label.text = "Training %s%s (%ds)" % [troop_name, count_suffix, int(ceil(remaining))]

		var rest_text := _grouped_queue_text(queue.entries, run)
		rest.visible = rest_text != ""
		rest.text = rest_text

		paused.visible = queue.paused
		paused.text = "Paused - %s" % String(queue.pause_reason).replace("_", " ")
	_live_updaters.append(update)

## Run-length-encodes `entries[start..]` by troop_type into lines like
## "Tonk x2, Glider x1" (singular runs drop the "x1").
func _grouped_queue_text(entries: Array[Dictionary], start: int) -> String:
	var parts: Array[String] = []
	var i := start
	while i < entries.size():
		var troop_type := String(entries[i].get("troop_type", ""))
		var count := 0
		while i < entries.size() and String(entries[i].get("troop_type", "")) == troop_type:
			count += 1
			i += 1
		var troop_name := String(state.troop_defs.get(troop_type, {}).get("name", troop_type.capitalize()))
		parts.append("%s x%d" % [troop_name, count] if count > 1 else troop_name)
	return ", ".join(parts)

# --- Resource body ----------------------------------------------------------

func _build_resource_body(building: BuildingInstance, def: Dictionary) -> void:
	_content.add_child(UITheme.header_label("PRODUCTION"))
	var output := BuildingStats.resource_output(def, building.level, state.building_defs)
	for type in output:
		_content.add_child(UITheme.body_label("%s:  %.1f / tick" % [UITheme.RESOURCE_LABEL.get(type, "?"), output[type]]))
	var tick := UITheme.muted_label("")
	_content.add_child(tick)
	var update := func():
		tick.text = "Next tick: %.1fs" % (Tuning.ECONOMY_TICK_SECONDS - state.economy_accumulator)
	_live_updaters.append(update)

# --- Hangar (Land / Launch) -------------------------------------------------

## The Hangar's landing pad: Land docks a flying friendly squad inside (which
## stops its fuel drain and hides it from enemy vision — see the fuel landing
## design), Launch sends a docked squad back out onto a valid neighbour hex.
## Both drive CargoSystem via dock_squad/undock_squad. The lists are a snapshot
## as of the last rebuild (a squad flying adjacent after selection won't appear
## until reselect) — same selection-time caching the build menu uses.
func _build_hangar_section(base: BaseInstance, building: BuildingInstance) -> void:
	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var capacity := int(BuildingStats.cargo_capacity(def, building.level, building.material, state.building_defs))
	_content.add_child(UITheme.header_label("HANGAR  -  %d/%d" % [building.docked_squad_ids.size(), capacity]))
	var dockable := _dockable_squads(base, building)
	if dockable.is_empty():
		_content.add_child(UITheme.muted_label("No aircraft in range to land"))
	else:
		for squad in dockable:
			var landing := squad
			var sdef: Dictionary = state.troop_defs.get(landing.troop_type, {})
			var name := String(sdef.get("name", landing.troop_type.capitalize()))
			var button := UITheme.action_button("Land %s (%d)" % [name, landing.member_ids.size()], UITheme.PRIMARY)
			var building_id := building.id
			button.pressed.connect(func(): input_controller.submitter.submit("dock_squad", [landing.id, building_id, owner_id], owner_id))
			_content.add_child(button)

	if building.docked_squad_ids.is_empty():
		_content.add_child(UITheme.muted_label("Hangar empty"))
		return
	for docked_id in building.docked_squad_ids:
		var docked := state.find_squad(docked_id)
		if docked == null:
			continue
		var ddef: Dictionary = state.troop_defs.get(docked.troop_type, {})
		var name := String(ddef.get("name", docked.troop_type.capitalize()))
		var squad_id := docked_id
		var building_id := building.id
		var button := UITheme.action_button("Launch %s" % name, "")
		button.pressed.connect(func():
			var target := _dock_launch_hex(building, docked)
			input_controller.submitter.submit("undock_squad", [squad_id, building_id, target, owner_id], owner_id))
		_content.add_child(button)

func _dockable_squads(base: BaseInstance, building: BuildingInstance) -> Array[SquadInstance]:
	var result: Array[SquadInstance] = []
	for squad in state.squads:
		if squad.owner_id != owner_id:
			continue
		if CargoSystem.can_dock(building, base.owner_id, squad, state.troop_defs, state.building_defs):
			result.append(squad)
	return result

## First hex — the building's own hex, then its neighbours — that a launching
## squad can legally land on. Falls back to the building hex, letting
## CargoSystem.undock reject it (red reason) if even that is blocked.
func _dock_launch_hex(building: BuildingInstance, squad: SquadInstance) -> HexCoord:
	var def: Dictionary = state.troop_defs.get(squad.troop_type, {})
	var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
	var overrides: Dictionary = def.get("terrainOverrides", {})
	for candidate in [building.hex] + HexCoord.neighbors(building.hex):
		if candidate == null:
			continue
		if candidate.equals(building.hex) or state.grid.edge_cost(building.hex, candidate, domain, overrides) != Terrain.INF:
			return candidate
	return building.hex

# --- Naval dock (Port / Shipyard / Harbour) ---------------------------------

## Load/Unload for a transport ship sitting on or beside this naval building —
## the building-side convenience for the same board_cargo/unload_cargo the ship's
## own squad panel offers. Only shown when such a ship is present; the coastal
## standalone Dock (not selectable) is served from the ship panel instead.
func _build_naval_dock_section(building: BuildingInstance) -> void:
	_content.add_child(UITheme.header_label("DOCK"))
	var ship := _adjacent_transport_ship(building)
	if ship == null:
		_content.add_child(UITheme.muted_label("No transport ship at the dock"))
		return
	var sdef: Dictionary = state.troop_defs.get(ship.troop_type, {})
	var capacity := int(float(sdef.get("cargoCapacity", 0)) * ship.member_ids.size())
	_content.add_child(UITheme.body_label("%s  -  %d/%d" % [String(sdef.get("name", ship.troop_type.capitalize())), ship.cargo_squad_ids.size(), capacity]))

	for other in state.squads:
		if other == ship or other.owner_id != owner_id:
			continue
		if not CargoSystem.can_board(ship, other, state.troop_defs, state.grid, state.bases, state.standalone_buildings, state.building_defs):
			continue
		var boarding := other
		var odef: Dictionary = state.troop_defs.get(boarding.troop_type, {})
		var name := String(odef.get("name", boarding.troop_type.capitalize()))
		var button := UITheme.action_button("Load %s (%d)" % [name, boarding.member_ids.size()], UITheme.PRIMARY)
		var ship_id := ship.id
		button.pressed.connect(func(): input_controller.submitter.submit("board_cargo", [ship_id, boarding.id, owner_id], owner_id))
		_content.add_child(button)

	for cargo_id in ship.cargo_squad_ids:
		var boarded := state.find_squad(cargo_id)
		if boarded == null:
			continue
		var bdef: Dictionary = state.troop_defs.get(boarded.troop_type, {})
		var name := String(bdef.get("name", boarded.troop_type.capitalize()))
		var boarded_id := cargo_id
		var ship_id := ship.id
		var dock_hex := building.hex
		var button := UITheme.action_button("Unload %s" % name, "")
		button.pressed.connect(func(): input_controller.submitter.submit("unload_cargo", [ship_id, boarded_id, dock_hex, owner_id], owner_id))
		_content.add_child(button)

## First friendly Naval transport (cargoCapacity > 0) on or adjacent to the dock
## building's hex, or null.
func _adjacent_transport_ship(building: BuildingInstance) -> SquadInstance:
	if building.hex == null:
		return null
	for squad in state.squads:
		if squad.owner_id != owner_id or squad.is_docked():
			continue
		var def: Dictionary = state.troop_defs.get(squad.troop_type, {})
		if float(def.get("cargoCapacity", 0)) <= 0.0:
			continue
		if String(def.get("domain", "")) != "Naval":
			continue
		if HexCoord.distance(building.hex, squad.current_hex) <= 1:
			return squad
	return null

# --- Shared option-row plumbing ---------------------------------------------

## One clickable option: a full-width button plus a row of cost chips (and, for
## troops, a build-time chip). `variation` is the button's eligible look (""
## for a neutral slate button, UITheme.PRIMARY for a call to action); it's
## swapped to MUTED whenever reason_fn returns non-empty. Clicking runs
## reason_fn first and either shows the red reason or fires `action`.
func _add_action_row(label_text: String, named_cost: Dictionary, time_seconds: float, variation: String, reason_fn: Callable, action: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var button := UITheme.action_button(label_text, variation)
	button.pressed.connect(func(): _handle_press(reason_fn, action))
	row.add_child(button)
	var chips := UITheme.cost_chips(named_cost)
	if time_seconds >= 0.0:
		chips.add_child(UITheme.chip("%ds" % int(round(time_seconds)), UITheme.TEXT_MUTED))
	row.add_child(chips)
	_content.add_child(row)
	_option_updaters.append({"button": button, "variation": variation, "reason_fn": reason_fn})

func _handle_press(reason_fn: Callable, action: Callable) -> void:
	var reason := String(reason_fn.call())
	if reason != "":
		if _reason_label != null:
			_reason_label.text = reason
			_reason_label.visible = true
		return
	if _reason_label != null:
		_reason_label.visible = false
	action.call()

func _refresh_eligibility() -> void:
	for entry in _option_updaters:
		var reason := String((entry["reason_fn"] as Callable).call())
		var button: Button = entry["button"]
		button.theme_type_variation = UITheme.MUTED if reason != "" else String(entry["variation"])
		button.tooltip_text = reason

# --- helpers ----------------------------------------------------------------

func _rebuild_reason(def: Dictionary, material: String, hq_level: int) -> String:
	var required_level := int(def.get("unlockHqLevel", 1))
	if hq_level < required_level:
		return "Requires HQ level %d" % required_level
	var percent := BuildingStats.rebuild_cost_percent(def, state.building_defs) / 100.0
	var named := BuildingStats.base_cost(def, material, state.building_defs)
	var pool := state.pool_for(owner_id)
	for type in ResourceType.ALL:
		var key := String(UITheme.RESOURCE_LABEL[type]).to_lower()
		if named.has(key) and pool.get_amount(type) < float(named[key]) * percent:
			return "Not enough %s" % UITheme.RESOURCE_LABEL[type]
	return ""

