## Per-building info panel: shown whenever InputController.selected_building_id
## is set (any of the local player's own base buildings, including the HQ —
## unlike client/hud/build_menu.gd, which gates on HQ specifically). Always
## shows name/level and an upgrade button (CommandProcessor.upgrade_building,
## the one non-Production upgrade path — cost/max-level read straight off
## BuildingStats so this never duplicates that math); a Resource-category
## building additionally shows its per-tick output and a countdown to the
## next economy tick (state.economy_accumulator vs.
## SimOrchestrator.ECONOMY_TICK_SECONDS — read-only off sim state, same as
## every other client/ view). A Production building's per-troop buttons stay
## client/hud/production_panel.gd's job, not duplicated here. Bottom-left
## corner, mirroring Minimap's bottom-right placement so the two never
## overlap. Polled every _process like every other client/ view.
##
## A ruined building (is_ruin — including the Capital's Command Centre, which
## BaseFactory.seed_base now seeds pre-ruined per 02-bases-and-buildings.md)
## swaps the whole level/upgrade block for a "RUINED" label and a Rebuild
## button (CommandProcessor.rebuild_building) instead — this is currently the
## only UI entry point to that command, since it's not a build_menu.gd
## placement (isFixed buildings never appear there) and not an upgrade.
class_name BuildingInfoPanel
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

var _upgrade_button: Button
var _shown_for_building_id: String = ""

const WIDTH := 240.0
const HEIGHT := 150.0
const MARGIN := 12.0
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const TEXT_COLOR := Color.WHITE
const FONT_SIZE := 16

## ResourceType.Type -> display label, same names/order convention as
## client/hud/resource_bar.gd's DISPLAY_ORDER.
const RESOURCE_NAMES := {
	ResourceType.Type.FOOD: "Food",
	ResourceType.Type.STEEL: "Steel",
	ResourceType.Type.FUEL: "Fuel",
	ResourceType.Type.STONE: "Stone",
	ResourceType.Type.WOOD: "Wood",
}

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = MARGIN
	offset_right = MARGIN + WIDTH
	offset_top = -HEIGHT - MARGIN
	offset_bottom = -MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_upgrade_button = Button.new()
	_upgrade_button.position = Vector2(12.0, HEIGHT - 40.0)
	_upgrade_button.size = Vector2(WIDTH - 24.0, 28.0)
	_upgrade_button.pressed.connect(_on_action_button_pressed)
	add_child(_upgrade_button)

func _found() -> Dictionary:
	if input_controller.selected_building_id == "":
		return {}
	return state.find_base_building(input_controller.selected_building_id)

func _process(_delta: float) -> void:
	if input_controller.selected_building_id != _shown_for_building_id:
		_shown_for_building_id = input_controller.selected_building_id
	visible = _shown_for_building_id != "" and not _found().is_empty()
	queue_redraw()

func _on_action_button_pressed() -> void:
	if _shown_for_building_id == "":
		return
	var found := _found()
	if not found.is_empty() and (found["building"] as BuildingInstance).is_ruin:
		CommandProcessor.rebuild_building(state, _shown_for_building_id, owner_id)
	else:
		CommandProcessor.upgrade_building(state, _shown_for_building_id, owner_id)

func _draw() -> void:
	if not visible:
		return
	var found := _found()
	if found.is_empty():
		return
	var building: BuildingInstance = found["building"]
	var def: Dictionary = state.building_defs.get(building.building_type, {})

	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	var font := get_theme_default_font()
	var y := 24.0
	draw_string(font, Vector2(12.0, y), String(def.get("name", building.building_type.capitalize())), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	y += 24.0

	if building.is_ruin:
		draw_string(font, Vector2(12.0, y), "RUINED", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		_upgrade_button.visible = true
		var percent := BuildingStats.rebuild_cost_percent(def, state.building_defs) / 100.0
		var cost := BuildingStats.base_cost(def, building.material, state.building_defs)
		var scaled_cost: Dictionary = {}
		for key in cost:
			scaled_cost[key] = float(cost[key]) * percent
		_upgrade_button.text = "Rebuild (%s)" % _format_cost(scaled_cost)
		return

	draw_string(font, Vector2(12.0, y), "Level %d" % building.level, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	y += 24.0

	var max_level := BuildingStats.max_level(def, state.building_defs)
	var capped: bool = max_level > 0 and building.level >= max_level
	_upgrade_button.visible = not capped
	if capped:
		draw_string(font, Vector2(12.0, y), "Max level", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	else:
		var cost := BuildingStats.upgrade_cost(def, building.level, building.material, state.building_defs)
		_upgrade_button.text = "Upgrade (%s)" % _format_cost(cost)
	y += 24.0

	if def.get("category", "") == "Resource":
		var output := BuildingStats.resource_output(def, building.level, state.building_defs)
		for type in output:
			draw_string(font, Vector2(12.0, y), "%s: %.1f / tick" % [RESOURCE_NAMES.get(type, "?"), output[type]], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
			y += 20.0
		var remaining: float = SimOrchestrator.ECONOMY_TICK_SECONDS - state.economy_accumulator
		draw_string(font, Vector2(12.0, y), "Next tick: %.1fs" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)

func _format_cost(cost: Dictionary) -> String:
	if cost.is_empty():
		return "Free"
	var parts: Array[String] = []
	for key in cost:
		parts.append("%s %d" % [String(key).capitalize(), int(cost[key])])
	return ", ".join(parts)
