## Per-building production queue panel (build order item 5): shown whenever
## InputController.selected_production_building_id is set (a Production-
## category building on the selected base was clicked — see
## input_controller.gd's case 3). Displays the FIFO queue (ProductionQueue.
## entries, sim/troops/production_queue.gd) with the in-progress entry's
## remaining time, a paused banner (pause_reason) when
## ProductionManager.pump has auto-paused it at the squad/Commander cap —
## queue pause/resume is fully automatic per 07-data-architecture.md lines
## 156-168, so this panel is display-only there, no pause/resume/cancel
## button — plus one Button per currently-unlocked troop type
## (CommandProcessor._troop_unlocked, reused rather than reimplementing the
## Command-Centre-vs-standard-building unlock rule) that enqueues via
## CommandProcessor.enqueue_production, the only production command that
## exists. Polled every _process like every other client/ view.
class_name ProductionPanel
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

var _button_list: VBoxContainer
var _shown_for_building_id: String = ""

const WIDTH := 240.0
const MARGIN := 12.0
const TOP := ResourceBar.HEIGHT + MARGIN
const HEADER_HEIGHT := 90.0
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const TEXT_COLOR := Color.WHITE
const PAUSED_COLOR := Color(1.0, 0.6, 0.2)
const FONT_SIZE := 16

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = MARGIN
	offset_right = MARGIN + WIDTH
	offset_top = TOP
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_button_list = VBoxContainer.new()
	_button_list.position = Vector2(4.0, HEADER_HEIGHT)
	add_child(_button_list)

func _found() -> Dictionary:
	if input_controller.selected_production_building_id == "":
		return {}
	return state.find_base_building(input_controller.selected_production_building_id)

func _process(_delta: float) -> void:
	if input_controller.selected_production_building_id != _shown_for_building_id:
		_shown_for_building_id = input_controller.selected_production_building_id
		_rebuild_buttons()
	queue_redraw()

func _rebuild_buttons() -> void:
	for child in _button_list.get_children():
		child.queue_free()
	visible = _shown_for_building_id != ""
	if not visible:
		return
	var found := _found()
	if found.is_empty():
		visible = false
		return
	var building: BuildingInstance = found["building"]
	var building_def: Dictionary = state.building_defs.get(building.building_type, {})
	for troop_type in state.troop_defs.keys():
		if not CommandProcessor._troop_unlocked(state, building, building_def, troop_type):
			continue
		var button := Button.new()
		button.text = String(state.troop_defs[troop_type].get("name", troop_type))
		button.pressed.connect(_on_troop_pressed.bind(troop_type))
		_button_list.add_child(button)
	offset_bottom = TOP + HEADER_HEIGHT + _button_list.get_child_count() * 32.0 + 8.0

func _on_troop_pressed(troop_type: String) -> void:
	if _shown_for_building_id == "":
		return
	state.command_queue.submit(state, "enqueue_production", [_shown_for_building_id, troop_type, owner_id], owner_id)

func _draw() -> void:
	if not visible:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	var found := _found()
	if found.is_empty():
		return
	var building: BuildingInstance = found["building"]
	var queue: ProductionQueue = state.production_queues.get(building.id)
	var font := get_theme_default_font()
	var y := 24.0
	draw_string(font, Vector2(12.0, y), String(building.building_type).capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	y += 24.0
	if queue == null or queue.entries.is_empty():
		draw_string(font, Vector2(12.0, y), "Queue empty", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
		return
	var front: Dictionary = queue.front()
	var remaining := float(front.get("remaining", 0.0))
	draw_string(font, Vector2(12.0, y), "Training: %s (%.1fs)" % [String(front.get("troop_type", "")), remaining], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	y += 24.0
	if queue.entries.size() > 1:
		draw_string(font, Vector2(12.0, y), "Queued: %d more" % (queue.entries.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	if queue.paused:
		draw_string(font, Vector2(12.0, HEADER_HEIGHT - 8.0), "PAUSED (%s)" % queue.pause_reason, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, PAUSED_COLOR)
