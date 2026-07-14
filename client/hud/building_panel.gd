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

var _content: VBoxContainer
var _reason_label: Label
var _shown_for_building_id: String = ""
## Snapshot of the shown building's level/ruin state as of the last _rebuild —
## compared every frame so an upgrade/rebuild/ruin transition rebuilds the
## panel (new Level text, cost, Max-level state) without needing a reselect.
var _shown_level: int = -1
var _shown_is_ruin: bool = false
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

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)

func _process(delta: float) -> void:
	var target_id := input_controller.selected_building_id
	var needs_rebuild := target_id != _shown_for_building_id
	if not needs_rebuild and target_id != "":
		var found := state.find_base_building(target_id)
		if not found.is_empty():
			var building: BuildingInstance = found["building"]
			needs_rebuild = building.level != _shown_level or building.is_ruin != _shown_is_ruin
	if needs_rebuild:
		_shown_for_building_id = target_id
		_rebuild()
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
	_content.add_child(UITheme.subtitle_label("%s  -  Pop %d/%d" % [base.base_def_id.capitalize(), used, cap]))
	_content.add_child(HSeparator.new())

	_build_level_section(building, def)

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

	_reason_label = UITheme.danger_label("")
	_reason_label.visible = false
	_content.add_child(_reason_label)

	_refresh_eligibility()

# --- Level / upgrade / rebuild ----------------------------------------------

func _build_level_section(building: BuildingInstance, def: Dictionary) -> void:
	if building.is_ruin:
		_content.add_child(UITheme.danger_label("RUINED"))
		var percent := BuildingStats.rebuild_cost_percent(def, state.building_defs) / 100.0
		var full_cost := BuildingStats.base_cost(def, building.material, state.building_defs)
		var scaled: Dictionary = {}
		for key in full_cost:
			scaled[key] = int(round(float(full_cost[key]) * percent))
		var material := building.material
		_add_action_row("Rebuild", scaled, -1.0, UITheme.PRIMARY,
			func(): return _rebuild_reason(def, material),
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
		var display_name := String(def.get("name", String(building_type).capitalize()))
		var cost := BuildingStats.base_cost(def, _first_material(def), state.building_defs)
		# Cached once here (the expensive tile scan) and reused by reason_fn.
		var has_valid_hex := UIEligibility.any_valid_hex(state, base, base_def, building_type)
		var bt := String(building_type)
		var base_id := base.id
		_add_action_row(display_name, cost, -1.0, "",
			func(): return UIEligibility.build_reason(state, base, bt, owner_id, has_valid_hex),
			func(): input_controller.start_placement(base_id, bt))
	if not any:
		_content.add_child(UITheme.muted_label("Nothing to build here"))

# --- Troop menu (Production) ------------------------------------------------

func _build_troop_menu(building: BuildingInstance) -> void:
	_content.add_child(UITheme.header_label("TRAIN"))
	var building_def: Dictionary = state.building_defs.get(building.building_type, {})
	var building_id := building.id
	var any := false
	for troop_type in state.troop_defs.keys():
		if not CommandProcessor._troop_unlocked(state, building, building_def, troop_type):
			continue
		any = true
		var tdef: Dictionary = state.troop_defs[troop_type]
		var display_name := String(tdef.get("name", troop_type))
		var cost: Dictionary = tdef.get("cost", {})
		var time := float(tdef.get("productionTime", 0.0))
		var tt := String(troop_type)
		_add_action_row(display_name, cost, time, "",
			func(): return UIEligibility.troop_reason(state, building_id, tt, owner_id),
			func(): state.command_queue.submit(state, "enqueue_production", [building_id, tt, owner_id], owner_id))
	if not any:
		_content.add_child(UITheme.muted_label("No troops unlocked yet"))
	_add_queue_status(building_id)

func _add_queue_status(building_id: String) -> void:
	_content.add_child(HSeparator.new())
	var training := UITheme.muted_label("")
	var queued := UITheme.muted_label("")
	var paused := UITheme.warning_label("")
	_content.add_child(training)
	_content.add_child(queued)
	_content.add_child(paused)
	var update := func():
		var queue: ProductionQueue = state.production_queues.get(building_id)
		if queue == null or queue.entries.is_empty():
			training.text = "Queue empty"
			queued.visible = false
			paused.visible = false
			return
		var front: Dictionary = queue.front()
		training.text = "Training: %s  (%.1fs)" % [String(front.get("troop_type", "")).capitalize(), float(front.get("remaining", 0.0))]
		queued.visible = queue.entries.size() > 1
		queued.text = "Queued: %d more" % (queue.entries.size() - 1)
		paused.visible = queue.paused
		paused.text = "Paused - %s" % String(queue.pause_reason).replace("_", " ")
	_live_updaters.append(update)

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

# --- Shared option-row plumbing ---------------------------------------------

## One clickable option: a full-width button plus a row of cost chips (and, for
## troops, a build-time chip). `variation` is the button's eligible look (""
## for a neutral slate button, UITheme.PRIMARY for a call to action); it's
## swapped to MUTED whenever reason_fn returns non-empty. Clicking runs
## reason_fn first and either shows the red reason or fires `action`.
func _add_action_row(label_text: String, named_cost: Dictionary, time_seconds: float, variation: String, reason_fn: Callable, action: Callable) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
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

func _rebuild_reason(def: Dictionary, material: String) -> String:
	var percent := BuildingStats.rebuild_cost_percent(def, state.building_defs) / 100.0
	var named := BuildingStats.base_cost(def, material, state.building_defs)
	var pool := state.pool_for(owner_id)
	for type in ResourceType.ALL:
		var key := String(UITheme.RESOURCE_LABEL[type]).to_lower()
		if named.has(key) and pool.get_amount(type) < float(named[key]) * percent:
			return "Not enough %s" % UITheme.RESOURCE_LABEL[type]
	return ""

func _first_material(def: Dictionary) -> String:
	var materials: Array = def.get("materials", [])
	return String(materials[0]) if not materials.is_empty() else ""
