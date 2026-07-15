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
var troop_info_panel: TroopInfoPanel
var camera_controller: CameraController

const WIDTH := 420.0
const MARGIN := 12.0
const REFRESH_INTERVAL := 0.25
## Screen-width fraction of the selected base's position past which the panel
## flips to the left edge (and back below the FLIP_BACK fraction) — the two
## thresholds give a dead band so a base sitting near the midpoint doesn't
## ping-pong sides as the camera drifts a few pixels.
const FLIP_TO_LEFT_RATIO := 0.60
const FLIP_TO_RIGHT_RATIO := 0.40
var _on_left := false
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
## Which TRAIN-menu troop_type has its info shown in troop_info_panel — "" when
## none. Reset whenever the selected building changes (same lifecycle as
## _expanded_build_type); survives a same-building _rebuild() so a queue
## mutation (enqueue/dequeue) doesn't close the info panel out from under it.
var _selected_troop_type: String = ""
## [{button: Button, variation: String, reason_fn: Callable}] — re-checked on a
## throttle to flip each option button between its normal look and MUTED.
var _option_updaters: Array = []
## Callables refreshing volatile text (queue timers, tick countdown) every frame.
var _live_updaters: Array[Callable] = []
var _refresh_accum := 0.0
## Structural signature (troop_type per entry + paused) of the shown
## building's production queue as of the last _rebuild — compared every frame
## like _shown_level/_shown_is_ruin so a dequeue/+1 mutation (which adds or
## removes a queue row's buttons, not just its live text) triggers a full
## rebuild instead of going stale until some unrelated change forces one.
var _shown_queue_key: String = ""

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController, p_troop_info_panel: TroopInfoPanel, p_camera_controller: CameraController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller
	troop_info_panel = p_troop_info_panel
	camera_controller = p_camera_controller

	# Top-right band under the resource bar, stopping short of the minimap's
	# bottom-right footprint (same layout contract build_menu.gd held). Flips
	# to the top-left band instead (_apply_side) whenever the selected base
	# sits far enough right on screen that this band would sit over its build
	# hexes — see _update_side. Vertical anchors set here (not _apply_side,
	# which only ever flips left/right) since Control's default anchor_bottom
	# is 0.0, not 1.0 -- leaving this unset collapses the panel to a sliver
	# pinned at the top instead of spanning down to the minimap.
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = ResourceBar.HEIGHT + MARGIN
	offset_bottom = -(Minimap.SIZE.y + Minimap.MARGIN + MARGIN)
	_apply_side(false)
	# STOP (not IGNORE): this panel owns real buttons, and its background must
	# also swallow clicks so they never fall through to a world move order.
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	# _scroll's sibling in this VBox (not a scrolled child) so the ineligible-
	# reason label below stays pinned and visible regardless of scroll position
	# or how far down the clicked button was — see _reason_label.
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
	# view — previously this lived at the bottom of a long BUILD/TRAIN list
	# and was easy to miss.
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

## Left/right anchor+offset swap; layout only, doesn't touch _content. Keeps
## troop_info_panel (which docks immediately beside this panel) in sync.
func _apply_side(on_left: bool) -> void:
	_on_left = on_left
	anchor_left = 0.0 if on_left else 1.0
	anchor_right = 0.0 if on_left else 1.0
	offset_left = MARGIN if on_left else -WIDTH - MARGIN
	offset_right = WIDTH + MARGIN if on_left else -MARGIN
	if troop_info_panel != null:
		troop_info_panel.set_side(on_left)

## Re-picks which side the panel docks on from the selected base's current
## screen-space position, with hysteresis (FLIP_TO_LEFT_RATIO /
## FLIP_TO_RIGHT_RATIO) so it doesn't flip back and forth as the camera pans.
func _update_side() -> void:
	var found := state.find_base_building(_shown_for_building_id) if _shown_for_building_id != "" else {}
	if found.is_empty():
		return
	var base: BaseInstance = found["base"]
	if base.hex_coord == null:
		return
	var world_pos := HexView.axial_to_pixel(base.hex_coord)
	var viewport_size := get_viewport().get_visible_rect().size
	var screen_x := viewport_size.x * 0.5 + (world_pos.x - camera_controller.position.x) * camera_controller.zoom.x
	var ratio := screen_x / viewport_size.x
	if not _on_left and ratio > FLIP_TO_LEFT_RATIO:
		_apply_side(true)
	elif _on_left and ratio < FLIP_TO_RIGHT_RATIO:
		_apply_side(false)

func _process(delta: float) -> void:
	var target_id := input_controller.selected_building_id
	var building_changed := target_id != _shown_for_building_id
	var needs_rebuild := building_changed
	if not needs_rebuild and target_id != "":
		var found := state.find_base_building(target_id)
		if not found.is_empty():
			var building: BuildingInstance = found["building"]
			needs_rebuild = building.level != _shown_level or building.is_ruin != _shown_is_ruin
		if not needs_rebuild:
			needs_rebuild = _queue_structure_key(target_id) != _shown_queue_key
	if building_changed:
		_expanded_build_type = ""
		_selected_troop_type = ""
		if troop_info_panel != null:
			troop_info_panel.hide_panel()
	if needs_rebuild:
		_shown_for_building_id = target_id
		_rebuild()
		if building_changed and visible:
			UIJuice.pop_in(self)
	if not visible:
		return
	_update_side()
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
	_reason_label.visible = false
	_reason_label.text = ""
	_refresh_accum = 0.0

	var found := state.find_base_building(_shown_for_building_id) if _shown_for_building_id != "" else {}
	if found.is_empty():
		visible = false
		_shown_level = -1
		_shown_is_ruin = false
		_shown_queue_key = ""
		if troop_info_panel != null:
			troop_info_panel.hide_panel()
		return
	visible = true
	var base: BaseInstance = found["base"]
	var building: BuildingInstance = found["building"]
	_shown_level = building.level
	_shown_is_ruin = building.is_ruin
	_shown_queue_key = _queue_structure_key(_shown_for_building_id)
	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})

	_content.add_child(UITheme.title_label(String(def.get("name", building.building_type.capitalize()))))
	var used := Population.population_used(base, state.building_defs)
	var cap := Population.population_cap(base, state.building_defs)
	var base_label := base.display_name if base.display_name != "" else base.base_def_id.capitalize()
	_content.add_child(UITheme.subtitle_label("%s  -  Pop %d/%d" % [base_label, used, cap]))

	if building.building_type == "hq":
		var hq_notes := String(def.get("notes", ""))
		if hq_notes != "":
			var hq_notes_label := UITheme.muted_label(hq_notes)
			hq_notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_content.add_child(hq_notes_label)

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
			func(): input_controller.submitter.submit("rebuild_building", [_shown_for_building_id, owner_id], owner_id))
		return

	_content.add_child(UITheme.body_label("Level %d" % building.level))
	if UIEligibility.upgrade_reason(state, _shown_for_building_id, owner_id) == "Max level":
		_content.add_child(UITheme.muted_label("Max level (fully upgraded)"))
		return
	var cost := BuildingStats.upgrade_cost(def, building.level, building.material, state.building_defs)
	_add_action_row("Upgrade", cost, -1.0, UITheme.PRIMARY,
		func(): return UIEligibility.upgrade_reason(state, _shown_for_building_id, owner_id),
		func(): input_controller.submitter.submit("upgrade_building", [_shown_for_building_id, owner_id], owner_id))

# --- Build menu (HQ) --------------------------------------------------------

func _build_build_menu(base: BaseInstance, base_def: Dictionary) -> void:
	_content.add_child(UITheme.header_label("BUILD"))
	var any := false
	for building_type in base_def.get("buildableBuildings", []):
		var def: Dictionary = state.building_defs.get(building_type, {})
		if def.get("isFixed", false):
			continue
		if base.hq_level < int(def.get("unlockHqLevel", 1)):
			continue
		any = true
		var bt := String(building_type)
		var display_name := String(def.get("name", bt.capitalize()))
		# Cached once here (the expensive tile scan) and reused by reason_fn.
		var has_valid_hex := UIEligibility.any_valid_hex(state, base, base_def, bt)
		var reason_fn := func(): return UIEligibility.build_reason(state, base, bt, owner_id, has_valid_hex)

		var button := UITheme.action_button(display_name, "")
		var base_id := base.id
		button.pressed.connect(func(): _toggle_build_row(base_id, bt, def, reason_fn))
		_content.add_child(button)
		_option_updaters.append({"button": button, "variation": "", "reason_fn": reason_fn})

		if _expanded_build_type == bt:
			_build_build_detail(base, bt, def, reason_fn, has_valid_hex)
	if not any:
		_content.add_child(UITheme.muted_label("Nothing to build here"))

## Expanding a BUILD row shows its notes/stats and, for a single-material
## building (the common case — Turret, House, ...), immediately enters
## placement mode too: there's nothing left to choose, so a separate "Build"
## click would just be an extra step between reading the row and seeing the
## green valid-hex tiles. Multi-material buildings (Wall) still need the
## player to pick a material first — see _build_material_row.
func _toggle_build_row(base_id: String, bt: String, def: Dictionary, reason_fn: Callable) -> void:
	var reason := ""
	if _expanded_build_type == bt:
		_expanded_build_type = ""
		input_controller.cancel_placement()
	else:
		_expanded_build_type = bt
		if def.get("materials", []).is_empty():
			reason = String(reason_fn.call())
			if reason == "":
				input_controller.start_placement(base_id, bt, "")
			else:
				input_controller.cancel_placement()
		else:
			input_controller.cancel_placement()
	# _rebuild() clears _reason_label as part of tearing down the old content —
	# set it only after, or it'd be wiped immediately.
	_rebuild()
	if reason != "":
		_reason_label.text = reason
		_reason_label.visible = true

## The pop-down shown under an expanded BUILD row: notes, then a few headline
## stats if the def has any. A single-material/no-material building (e.g.
## Turret) stops there — _toggle_build_row already put it in placement mode.
## A Wall-style building with a `materials` list instead gets one clickable
## cost row per material, since the player has to choose one before placement
## can start.
func _build_build_detail(base: BaseInstance, building_type: String, def: Dictionary, reason_fn: Callable, has_valid_hex: bool) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS

	var notes := String(def.get("notes", ""))
	if notes != "":
		var notes_label := UITheme.muted_label(notes)
		notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(notes_label)

	var materials: Array = def.get("materials", [])
	var base_id := base.id
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
			var mat_reason_fn := func(): return UIEligibility.build_reason(state, base, building_type, owner_id, has_valid_hex, mat)
			_build_material_row(box, String(mat).capitalize(), cost, mat_reason_fn,
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
		_build_troop_row(display_name, tt, cost, time, building_id,
			func(): return UIEligibility.troop_reason(state, building_id, tt, owner_id))
	if not any:
		_content.add_child(UITheme.muted_label("No troops unlocked yet"))
	_add_queue_status(building_id)
	if _selected_troop_type != "" and unlocked.has(_selected_troop_type):
		if troop_info_panel != null:
			troop_info_panel.show_troop(_selected_troop_type)
	elif troop_info_panel != null:
		troop_info_panel.hide_panel()

## One TRAIN-menu row: the troop's name (click opens/updates troop_info_panel
## with its stats/description instead of training — see
## _on_troop_name_pressed) plus a separate Train button that actually submits
## enqueue_production, greyed via `reason_fn` same as every other option row.
func _build_troop_row(display_name: String, troop_type: String, cost: Dictionary, time_seconds: float, building_id: String, reason_fn: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var name_button := UITheme.action_button(display_name, "")
	name_button.pressed.connect(func(): _on_troop_name_pressed(troop_type))
	row.add_child(name_button)

	var train_button := UITheme.action_button("Train", UITheme.PRIMARY)
	train_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	train_button.custom_minimum_size = Vector2(110, 0)
	var action := func(): input_controller.submitter.submit("enqueue_production", [building_id, troop_type, owner_id], owner_id)
	train_button.pressed.connect(func(): _handle_press(reason_fn, action))
	row.add_child(train_button)
	box.add_child(row)

	var chips := UITheme.cost_chips(cost)
	if time_seconds >= 0.0:
		chips.add_child(UITheme.chip("%ds" % int(round(time_seconds)), UITheme.TEXT_MUTED))
	box.add_child(chips)
	_content.add_child(box)
	_option_updaters.append({"button": train_button, "variation": UITheme.PRIMARY, "reason_fn": reason_fn})

func _on_troop_name_pressed(troop_type: String) -> void:
	_selected_troop_type = "" if _selected_troop_type == troop_type else troop_type
	if troop_info_panel == null:
		return
	if _selected_troop_type == "":
		troop_info_panel.hide_panel()
	else:
		troop_info_panel.show_troop(_selected_troop_type)

## One row per run of same-type consecutive queue entries. The first run
## (starting at entries[0], the one currently training or held complete if
## paused) is a progress bar with the troop name centered on top, e.g.
## "Training Basekiller x3 (21s)"; every later run is a plain muted label row,
## e.g. "Tonk x2". Each row gets a + button (queue one more, grouped right
## after the run) and a - button that drops the LAST entry in the run — never
## the actively-training entries[0] itself, so it only ever trims queued-but-
## not-yet-training copies (see CommandProcessor.can_dequeue_production);
## greyed out (disabled) when the run has only one entry, since there's
## nothing left in it to drop.
func _add_queue_status(building_id: String) -> void:
	_content.add_child(HSeparator.new())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(box)

	var queue: ProductionQueue = state.production_queues.get(building_id)
	if queue == null or queue.entries.is_empty():
		box.add_child(UITheme.muted_label("Queue empty"))
		return

	var i := 0
	var first := true
	while i < queue.entries.size():
		var troop_type := String(queue.entries[i].get("troop_type", ""))
		var run_start := i
		while i < queue.entries.size() and String(queue.entries[i].get("troop_type", "")) == troop_type:
			i += 1
		var run_len := i - run_start
		if first:
			_build_queue_front_row(box, building_id, troop_type, run_start, run_len)
			first = false
		else:
			_build_queue_rest_row(box, building_id, troop_type, run_start, run_len)

	var paused := UITheme.warning_label("")
	box.add_child(paused)
	var update := func():
		var q: ProductionQueue = state.production_queues.get(building_id)
		paused.visible = q != null and q.paused
		if paused.visible:
			paused.text = "Paused - %s" % String(q.pause_reason).replace("_", " ")
	_live_updaters.append(update)

func _build_queue_front_row(box: VBoxContainer, building_id: String, troop_type: String, run_start: int, run_len: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var bar := UITheme.progress_bar()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar_label := UITheme.body_label("")
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.add_child(bar_label)
	row.add_child(bar)
	_add_queue_buttons(row, building_id, troop_type, run_start, run_len)
	box.add_child(row)

	var update := func():
		var q: ProductionQueue = state.production_queues.get(building_id)
		if q == null or q.entries.is_empty():
			return
		var front: Dictionary = q.front()
		var total := float(front.get("production_time", 0.0))
		var remaining := float(front.get("remaining", 0.0))
		bar.value = 1.0 - (remaining / total if total > 0.0 else 0.0)
		var troop_name := String(state.troop_defs.get(troop_type, {}).get("name", troop_type.capitalize()))
		var count_suffix := " x%d" % run_len if run_len > 1 else ""
		bar_label.text = "Training %s%s (%ds)" % [troop_name, count_suffix, int(ceil(remaining))]
	_live_updaters.append(update)

func _build_queue_rest_row(box: VBoxContainer, building_id: String, troop_type: String, run_start: int, run_len: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var troop_name := String(state.troop_defs.get(troop_type, {}).get("name", troop_type.capitalize()))
	var label := UITheme.muted_label("%s x%d" % [troop_name, run_len] if run_len > 1 else troop_name)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_add_queue_buttons(row, building_id, troop_type, run_start, run_len)
	box.add_child(row)

## + (always, unless ineligible) / - (always shown, greyed out via `disabled`
## when run_len == 1 — nothing in this run to drop) for one queue run. Both
## target the LAST index in the run: for - that's the removal index passed to
## dequeue_production (never run_start itself when run_start == 0); for +
## that's the insert_after index, keeping the new copy grouped with its run.
func _add_queue_buttons(row: HBoxContainer, building_id: String, troop_type: String, run_start: int, run_len: int) -> void:
	var last_index := run_start + run_len - 1

	var minus := UITheme.action_button("-", UITheme.INFO_BUTTON)
	minus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	minus.custom_minimum_size = Vector2(40, 0)
	UITheme.shrink_button_padding(minus, theme, 4.0)
	minus.disabled = run_len <= 1
	minus.pressed.connect(func(): input_controller.submitter.submit("dequeue_production", [building_id, last_index, owner_id], owner_id))
	row.add_child(minus)

	var plus := UITheme.action_button("+", UITheme.INFO_BUTTON)
	plus.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plus.custom_minimum_size = Vector2(40, 0)
	UITheme.shrink_button_padding(plus, theme, 4.0)
	var reason_fn := func(): return UIEligibility.troop_reason(state, building_id, troop_type, owner_id)
	var action := func(): input_controller.submitter.submit("enqueue_production_after", [building_id, troop_type, last_index, owner_id], owner_id)
	plus.pressed.connect(func(): _handle_press(reason_fn, action))
	row.add_child(plus)
	_option_updaters.append({"button": plus, "variation": UITheme.INFO_BUTTON, "reason_fn": reason_fn})

## Structural signature (troop_type per entry + paused) of building_id's
## queue — see _shown_queue_key.
func _queue_structure_key(building_id: String) -> String:
	var queue: ProductionQueue = state.production_queues.get(building_id)
	if queue == null:
		return ""
	var parts: Array[String] = []
	for entry in queue.entries:
		parts.append(String(entry.get("troop_type", "")))
	return "|".join(parts) + ("#paused" if queue.paused else "")

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
## `tooltip` (e.g. a troop/building's "notes" description) shows on hover when
## the option is eligible; while ineligible, hover tooltip is suppressed and
## the reason instead shows in `_reason_label` on click (see _handle_press).
func _add_action_row(label_text: String, named_cost: Dictionary, time_seconds: float, variation: String, reason_fn: Callable, action: Callable, tooltip: String = "") -> void:
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
	_option_updaters.append({"button": button, "variation": variation, "reason_fn": reason_fn, "tooltip": tooltip})

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
		button.tooltip_text = String(entry.get("tooltip", "")) if reason == "" else ""

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

