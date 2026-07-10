## Per-base build menu (build order item 4): one Button per
## base_def.buildableBuildings entry for the currently selected base
## (InputController.selected_base_id) — shown as-is, no greyed-out
## "unavailable here" entries, per 09-ui-and-controls.md's Build Menu
## (Unique Bases) resolution (Capital's list is the full non-Unique
## superset; each Unique base's is its own shorter fixed list — already
## exactly what each base JSON's buildableBuildings array contains, so this
## widget does no filtering of its own). Pressing a button hands off to
## InputController.start_placement(), which owns the actual placement-mode
## click handling and the world-space valid-hex highlight
## (client/build_preview.gd) — this widget only ever issues that one call,
## consistent with every other client/ node never touching sim state
## directly.
class_name BuildMenu
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

var _list: VBoxContainer
var _shown_for_base_id: String = ""

const WIDTH := 220.0
const MARGIN := 12.0
const TOP := ResourceBar.HEIGHT + MARGIN + BasePanel.HEIGHT + MARGIN
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller

	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = TOP
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_list = VBoxContainer.new()
	_list.position = Vector2(4.0, 4.0)
	add_child(_list)

func _process(_delta: float) -> void:
	if input_controller.selected_base_id == _shown_for_base_id:
		return
	_shown_for_base_id = input_controller.selected_base_id
	_rebuild()

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	visible = _shown_for_base_id != ""
	if not visible:
		return
	var base := state.find_base(_shown_for_base_id)
	if base == null:
		visible = false
		return
	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})
	var building_types: Array = base_def.get("buildableBuildings", [])
	for building_type in building_types:
		var button := Button.new()
		button.text = String(building_type).capitalize()
		button.pressed.connect(_on_building_pressed.bind(building_type))
		_list.add_child(button)
	offset_bottom = TOP + building_types.size() * 32.0 + 8.0
	queue_redraw()

func _on_building_pressed(building_type: String) -> void:
	input_controller.start_placement(_shown_for_base_id, building_type)

func _draw() -> void:
	if visible:
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
