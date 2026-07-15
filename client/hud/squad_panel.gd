## The styled panel for a single selected squad — the squad-side counterpart to
## client/hud/building_panel.gd. Shown on the right (same band/width as the
## building panel, and mutually exclusive with it) whenever exactly one squad is
## selected and no building is. Top to bottom: title (troop name + N/cap), a
## per-troop HP bar for every living member, a Merge Squads button, and — only
## for the troop types that support them — an Engineer build menu
## (canBuildInfrastructure) and a cargo Load/Unload menu (cargoCapacity > 0).
##
## Same construction rules as BuildingPanel: built entirely from UITheme
## factories + real Control nodes (no _draw()); ineligible actions are styled
## MUTED but stay clickable, writing a red reason (UIEligibility) instead of
## acting; the node tree is rebuilt only when the selected squad — or a field
## that changes which rows exist (member/cargo count, the squad's hex) — changes,
## while live values (HP) refresh every frame and eligibility styling on a
## throttle, via the same two updater lists BuildingPanel uses.
##
## Everything this panel issues already exists as a CommandProcessor verb
## (merge_squads, place_standalone_building, board_cargo, unload_cargo), reached
## through CommandQueue.submit exactly like the building panel's own actions —
## this node only resolves the selected squad into those calls, never touches
## sim state directly.
class_name SquadPanel
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController
var squad_view: SquadView

const WIDTH := BuildingPanel.WIDTH
const MARGIN := 12.0
const REFRESH_INTERVAL := 0.25
## Engineer-buildable standalone buildings, in build-menu order. Kept as an
## explicit list (rather than scanning building_defs for isStandalone every
## rebuild) so the menu order is stable and intentional.
const STANDALONE_BUILDINGS := ["road", "bridge", "dock", "tower", "landmine"]

var _content: VBoxContainer
var _scroll: ScrollContainer
var _reason_label: Label
var _shown_for_squad_id: String = ""
## Snapshot of the shown squad's member/cargo count and hex as of the last
## _rebuild — compared every frame so a death, a board/unload, or a move (any of
## which changes which rows/eligibility apply) rebuilds without a reselect.
var _shown_member_count: int = -1
var _shown_cargo_count: int = -1
var _shown_hex_key: String = ""
## Commander only: member count of the squad's own regiment, as of the last
## _rebuild — tracked alongside member/cargo/hex so assigning/removing a
## regiment squad (which changes neither) still triggers a rebuild.
var _shown_regiment_size: int = -1
## Which Engineer BUILD-menu building_type is currently expanded to show its
## detail (notes/stats/cost/material rows) — "" when fully collapsed. Reset
## whenever the selected squad changes, but survives a same-squad _rebuild()
## (e.g. the squad moving), same lifecycle as BuildingPanel's
## _expanded_build_type.
var _expanded_standalone_type: String = ""
## [{button, variation, reason_fn}] — re-checked on a throttle to flip each
## option button between its normal look and MUTED, same shape as BuildingPanel.
var _option_updaters: Array = []
## Callables refreshing volatile text (HP bars) every frame.
var _live_updaters: Array[Callable] = []
var _refresh_accum := 0.0

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController, p_squad_view: SquadView) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller
	squad_view = p_squad_view

	# Same right-hand band as BuildingPanel (the two never show at once).
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = ResourceBar.HEIGHT + MARGIN
	offset_bottom = -(Minimap.SIZE.y + Minimap.MARGIN + MARGIN)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	# _scroll's sibling in this VBox (not a scrolled child) so the ineligible-
	# reason label below stays pinned and visible regardless of scroll position
	# — see _reason_label.
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(main_vbox)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# We scroll manually here (see _on_scroll_gui_input) rather than relying on
	# ScrollContainer's built-in wheel handling: the gui_input signal fires
	# BEFORE the built-in _gui_input, so any set_input_as_handled() we do to stop
	# the wheel falling through to the camera would also cancel the built-in
	# scroll. Doing the scroll ourselves and then accepting handles both.
	_scroll.gui_input.connect(_on_scroll_gui_input)
	main_vbox.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	# PASS, not the Control default STOP: _content covers the full scroll area,
	# so without this every wheel event over any gap/label is eaten here before
	# it ever reaches the ScrollContainer's own scroll handling.
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.add_child(_content)

	# Pinned below the scroll area (not inside _content, which gets torn down
	# and rebuilt on every selection change) so an ineligible-click reason
	# stays visible even when the button that triggered it is scrolled out of
	# view.
	_reason_label = UITheme.danger_label("")
	_reason_label.visible = false
	main_vbox.add_child(_reason_label)

const SCROLL_STEP := 40

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.scroll_vertical -= SCROLL_STEP
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.scroll_vertical += SCROLL_STEP
			get_viewport().set_input_as_handled()

## The single squad this panel is for, or null: only when exactly one squad is
## selected AND no building is (BuildingPanel owns the same band and takes
## precedence — selecting a building leaves the squad selection intact).
func _target_squad() -> SquadInstance:
	if input_controller.selected_building_id != "":
		return null
	if squad_view.selected_squad_ids.size() != 1:
		return null
	var id: String = squad_view.selected_squad_ids.keys()[0]
	return state.find_squad(id)

func _process(delta: float) -> void:
	var squad := _target_squad()
	var target_id := squad.id if squad != null else ""
	var squad_changed := target_id != _shown_for_squad_id
	var needs_rebuild := squad_changed
	if not needs_rebuild and squad != null:
		needs_rebuild = squad.member_ids.size() != _shown_member_count \
			or squad.cargo_squad_ids.size() != _shown_cargo_count \
			or squad.current_hex.to_key() != _shown_hex_key \
			or _regiment_size(squad) != _shown_regiment_size
	if squad_changed:
		_expanded_standalone_type = ""
	if needs_rebuild:
		_shown_for_squad_id = target_id
		_rebuild(squad)
		if squad_changed and visible:
			UIJuice.pop_in(self)
	if not visible:
		return
	for updater in _live_updaters:
		updater.call()
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_eligibility()

func _rebuild(squad: SquadInstance) -> void:
	for child in _content.get_children():
		child.queue_free()
	_option_updaters.clear()
	_live_updaters.clear()
	_reason_label.visible = false
	_reason_label.text = ""
	_refresh_accum = 0.0

	if squad == null:
		visible = false
		_shown_member_count = -1
		_shown_cargo_count = -1
		_shown_hex_key = ""
		_shown_regiment_size = -1
		return
	visible = true
	_shown_member_count = squad.member_ids.size()
	_shown_cargo_count = squad.cargo_squad_ids.size()
	_shown_hex_key = squad.current_hex.to_key()
	_shown_regiment_size = _regiment_size(squad)
	var def: Dictionary = state.troop_defs.get(squad.troop_type, {})

	var cap: int = max(1, int(def.get("maxSquadSize", 1)))
	_content.add_child(UITheme.title_label(String(def.get("name", squad.troop_type.capitalize()))))
	_content.add_child(UITheme.subtitle_label("Squad  -  %d/%d" % [squad.member_ids.size(), cap]))
	_content.add_child(HSeparator.new())

	_build_stats_section(def)
	_content.add_child(HSeparator.new())

	_build_health_section(squad, def)

	_content.add_child(HSeparator.new())
	_build_merge_row(squad)

	if bool(def.get("canBuildInfrastructure", false)):
		_content.add_child(HSeparator.new())
		_build_engineer_menu(squad)

	if float(def.get("cargoCapacity", 0)) > 0.0:
		_content.add_child(HSeparator.new())
		_build_cargo_menu(squad, def)

	if int(def.get("maxSquadsLed", 0)) > 0:
		_content.add_child(HSeparator.new())
		_build_regiment_menu(squad, def)

	_refresh_eligibility()

# --- Per-troop health -------------------------------------------------------

## Type line (domain + tags, e.g. "Land, Vehicle, Tank"), then a handful of
## headline combat stats, then the def's freeform "notes" description — the
## per-troop detail a build/train list can't afford the space for, shown once
## the player commits to selecting a squad on the map. Shared with
## TroopInfoPanel (client/hud/troop_stats_view.gd) so a troop clicked in the
## TRAIN menu shows the exact same block.
func _build_stats_section(def: Dictionary) -> void:
	TroopStatsView.build(_content, def)

## One fill bar per living member, value current_hp / def hp with a "cur/max"
## label centered on top — same bar-with-overlaid-label trick BuildingPanel's
## production queue uses. Bars are captured by member id so a live_updater can
## refresh their value/label each frame without a rebuild (a death changes the
## member count, which _process catches and rebuilds).

func _build_health_section(squad: SquadInstance, def: Dictionary) -> void:
	_content.add_child(UITheme.header_label("SQUAD HEALTH"))
	var max_hp := float(def.get("hp", 1.0))
	for troop_id in squad.member_ids:
		var bar := UITheme.progress_bar()
		var label := UITheme.body_label("")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		bar.add_child(label)
		_content.add_child(bar)
		var id := troop_id
		var update := func():
			var troop: TroopInstance = state.troops_by_id.get(id)
			if troop == null:
				bar.value = 0.0
				label.text = "-"
				return
			bar.value = clampf(troop.current_hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
			label.text = "%d / %d" % [int(ceil(troop.current_hp)), int(round(max_hp))]
		_live_updaters.append(update)

# --- Merge ------------------------------------------------------------------

## Merge Squads: drains a same-hex sibling squad into this one. The donor is
## re-resolved (UIEligibility.find_merge_donor) on every eligibility check and at
## click time rather than captured once, so the button stays correct as squads
## move on/off the hex without needing a rebuild.
func _build_merge_row(squad: SquadInstance) -> void:
	var reason_fn := func(): return UIEligibility.merge_reason(state, squad, UIEligibility.find_merge_donor(state, squad), owner_id)
	var action := func():
		var donor := UIEligibility.find_merge_donor(state, squad)
		if donor != null:
			input_controller.submitter.submit("merge_squads", [squad.id, donor.id, owner_id], owner_id)
	var button := UITheme.action_button("Merge Squads", "")
	button.pressed.connect(func(): _handle_press(reason_fn, action))
	_content.add_child(button)
	_option_updaters.append({"button": button, "variation": "", "reason_fn": reason_fn})

# --- Engineer build menu ----------------------------------------------------

## One row per Engineer-buildable standalone building — same expand-to-detail
## pattern as BuildingPanel's HQ BUILD menu (_toggle_build_row/
## _build_build_detail): clicking a row toggles a pop-down showing notes,
## headline stats, and cost, and — for a single/no-material building (Road,
## Landmine) — immediately enters placement mode too (green valid hexes via
## build_preview.gd, click-a-hex range = 2, per Tuning.STANDALONE_BUILD_RANGE).
## A multi-material building (Bridge, Dock, Tower) instead shows one clickable
## cost row per material, and placement only starts once one is picked.
func _build_engineer_menu(squad: SquadInstance) -> void:
	_content.add_child(UITheme.header_label("BUILD  (2 hexes)"))
	for building_type in STANDALONE_BUILDINGS:
		var def: Dictionary = state.building_defs.get(building_type, {})
		if def.is_empty():
			continue
		var bt := String(building_type)
		var display_name := String(def.get("name", bt.capitalize()))
		var reason_fn := func(): return UIEligibility.standalone_build_reason(state, squad, bt, owner_id)

		var button := UITheme.action_button(display_name, "")
		var squad_id := squad.id
		button.pressed.connect(func(): _toggle_standalone_row(squad_id, bt, reason_fn))
		_content.add_child(button)
		_option_updaters.append({"button": button, "variation": "", "reason_fn": reason_fn})

		if _expanded_standalone_type == bt:
			_build_standalone_detail(squad, bt, def, reason_fn)

## Mirrors BuildingPanel._toggle_build_row: expanding a no/single-material row
## enters placement immediately (if eligible); a multi-material row just opens
## the pop-down, leaving the player to pick a material first.
func _toggle_standalone_row(squad_id: String, bt: String, reason_fn: Callable) -> void:
	var def: Dictionary = state.building_defs.get(bt, {})
	var reason := ""
	if _expanded_standalone_type == bt:
		_expanded_standalone_type = ""
		input_controller.cancel_placement()
	else:
		_expanded_standalone_type = bt
		if def.get("materials", []).is_empty():
			reason = String(reason_fn.call())
			if reason == "":
				input_controller.start_standalone_placement(squad_id, bt, "")
			else:
				input_controller.cancel_placement()
		else:
			input_controller.cancel_placement()
	# _rebuild() clears _reason_label as part of tearing down the old content —
	# set it only after, or it'd be wiped immediately.
	_rebuild(state.find_squad(squad_id))
	if reason != "":
		_reason_label.text = reason
		_reason_label.visible = true

func _build_standalone_detail(squad: SquadInstance, building_type: String, def: Dictionary, reason_fn: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS

	var notes := String(def.get("notes", ""))
	if notes != "":
		var notes_label := UITheme.muted_label(notes)
		notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(notes_label)

	var materials: Array = def.get("materials", [])
	var squad_id := squad.id
	if materials.is_empty():
		for line in BuildingDetailView.stat_lines(def):
			box.add_child(UITheme.body_label(line))
		var cost := BuildingStats.base_cost(def, "", state.building_defs)
		box.add_child(UITheme.cost_chips(cost))
	else:
		for material in materials:
			var mat := String(material)
			for line in BuildingDetailView.stat_lines_for_material(def, mat):
				box.add_child(UITheme.body_label(line))
			var cost := BuildingStats.base_cost(def, mat, state.building_defs)
			var mat_reason_fn := func(): return UIEligibility.standalone_build_reason(state, squad, building_type, owner_id, mat)
			_build_material_row(box, mat.capitalize(), cost, mat_reason_fn,
				func(): input_controller.start_standalone_placement(squad_id, building_type, mat))

	_content.add_child(box)

## Mirrors BuildingPanel._build_material_row: a labelled cost row for one
## material choice, muted via `reason_fn` the same way every other option row
## is (see _refresh_eligibility below).
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

# --- Cargo (Load / Unload) --------------------------------------------------

## Load lists every friendly squad this carrier can currently board (the
## eligibility, including naval-landing-hex / cargoRequiresBuildingDock gating,
## lives entirely in CargoSystem.can_board — so a naval/air transport simply
## shows nothing to load until it's beside the right building). Unload lists the
## squads currently aboard; clicking drops one onto a valid nearby hex. Both are
## driven by a rebuild on cargo/member/hex change, so the list stays current as
## the carrier moves.
func _build_cargo_menu(squad: SquadInstance, _def: Dictionary) -> void:
	var capacity := int(float(_def.get("cargoCapacity", 0)) * squad.member_ids.size())
	_content.add_child(UITheme.header_label("CARGO  -  %d/%d" % [squad.cargo_squad_ids.size(), capacity]))

	var boardable := _boardable_squads(squad)
	if boardable.is_empty():
		_content.add_child(UITheme.muted_label("No units in range to load"))
	else:
		for other in boardable:
			var boarding := other
			var odef: Dictionary = state.troop_defs.get(boarding.troop_type, {})
			var name := String(odef.get("name", boarding.troop_type.capitalize()))
			var button := UITheme.action_button("Load %s (%d)" % [name, boarding.member_ids.size()], UITheme.PRIMARY)
			button.pressed.connect(func(): input_controller.submitter.submit("board_cargo", [squad.id, boarding.id, owner_id], owner_id))
			_content.add_child(button)

	if squad.cargo_squad_ids.is_empty():
		_content.add_child(UITheme.muted_label("Empty hold"))
		return
	for cargo_id in squad.cargo_squad_ids:
		var boarded := state.find_squad(cargo_id)
		if boarded == null:
			continue
		var bdef: Dictionary = state.troop_defs.get(boarded.troop_type, {})
		var name := String(bdef.get("name", boarded.troop_type.capitalize()))
		var boarded_id := cargo_id
		var button := UITheme.action_button("Unload %s" % name, "")
		button.pressed.connect(func():
			var target := _unload_target(squad)
			input_controller.submitter.submit("unload_cargo", [squad.id, boarded_id, target, owner_id], owner_id))
		_content.add_child(button)

## Friendly squads this carrier can board right now (CargoSystem.can_board holds
## every rule — adjacency, capacity, allowed tags, and the naval/building-dock
## location gates), skipping the carrier itself.
func _boardable_squads(carrier: SquadInstance) -> Array[SquadInstance]:
	var result: Array[SquadInstance] = []
	for other in state.squads:
		if other == carrier or other.owner_id != owner_id:
			continue
		if CargoSystem.can_board(carrier, other, state.troop_defs, state.grid, state.bases, state.standalone_buildings, state.building_defs):
			result.append(other)
	return result

## Where a squad unloaded from `carrier` lands: for a Naval carrier, the first
## adjacent Dock/Port/Shipyard/Harbour hex (a ship can't put troops onto bare
## water/coast — see CargoSystem.unload); for Land/Air carriers, the carrier's
## own hex (always passable for them, distance 0). Falls back to the carrier's
## hex if no landing is found, letting CargoSystem.unload reject it (red ping).
func _unload_target(carrier: SquadInstance) -> HexCoord:
	var def: Dictionary = state.troop_defs.get(carrier.troop_type, {})
	if String(def.get("domain", "")) == "Naval":
		for neighbor in HexCoord.neighbors(carrier.current_hex):
			if BuildingPlacement.is_naval_landing_hex(neighbor, state.bases, state.standalone_buildings):
				return neighbor
		return carrier.current_hex
	return carrier.current_hex

# --- Regiment (Commander only) -----------------------------------------------

## Squad count currently in `squad`'s own regiment (0 if it isn't a Commander,
## or leads none yet) — the extra _process poll _shown_regiment_size compares
## against so assigning/removing a member (which touches neither the
## Commander's member/cargo count nor its hex) still triggers a rebuild.
func _regiment_size(squad: SquadInstance) -> int:
	for regiment in state.regiments:
		if regiment.commander_id == squad.id:
			return regiment.squad_ids.size()
	return 0

## Assign lists every friendly squad this Commander could take command of
## (UIEligibility.assignable_squads: not itself, not already led by this
## Commander, not docked, not itself a Commander). Assigned lists the
## regiment's current members, each with a Remove button. Same
## eligible-list-then-current-list shape as _build_cargo_menu's Load/Unload.
func _build_regiment_menu(squad: SquadInstance, def: Dictionary) -> void:
	var max_led := int(def.get("maxSquadsLed", 0))
	var regiment: RegimentInstance = null
	for candidate in state.regiments:
		if candidate.commander_id == squad.id:
			regiment = candidate
			break
	var member_count := regiment.squad_ids.size() if regiment != null else 0
	_content.add_child(UITheme.header_label("REGIMENT  -  %d/%d" % [member_count, max_led]))

	var assignable := UIEligibility.assignable_squads(state, squad)
	if assignable.is_empty():
		_content.add_child(UITheme.muted_label("No squads to assign"))
	else:
		for other in assignable:
			var candidate_squad := other
			var odef: Dictionary = state.troop_defs.get(candidate_squad.troop_type, {})
			var name := String(odef.get("name", candidate_squad.troop_type.capitalize()))
			var reason_fn := func(): return UIEligibility.assign_to_commander_reason(state, squad, candidate_squad, owner_id)
			var action := func(): input_controller.submitter.submit("assign_to_commander", [candidate_squad.id, squad.id, owner_id], owner_id)
			var button := UITheme.action_button("Assign %s" % name, UITheme.PRIMARY)
			button.pressed.connect(func(): _handle_press(reason_fn, action))
			_content.add_child(button)
			_option_updaters.append({"button": button, "variation": UITheme.PRIMARY, "reason_fn": reason_fn})

	if regiment == null or regiment.squad_ids.is_empty():
		_content.add_child(UITheme.muted_label("No squads assigned"))
		return
	for member_id in regiment.squad_ids:
		var member := state.find_squad(member_id)
		if member == null:
			continue
		var mdef: Dictionary = state.troop_defs.get(member.troop_type, {})
		var mname := String(mdef.get("name", member.troop_type.capitalize()))
		var leaving_id := member_id
		var button := UITheme.action_button("Remove %s" % mname, "")
		button.pressed.connect(func(): input_controller.submitter.submit("leave_regiment", [leaving_id, owner_id], owner_id))
		_content.add_child(button)

# --- Shared option-row plumbing (mirrors BuildingPanel) ---------------------

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
		button.tooltip_text = ""
