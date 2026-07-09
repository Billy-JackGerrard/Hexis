## Click/drag handling for this scaffold slice: left-click a friendly squad
## to select it, shift-click to add/remove from selection, left-drag a box
## over friendly squads to select all of them, left-click elsewhere to issue
## a move order for the whole current selection. Number keys 1-9 recall a
## control group; Ctrl+number assigns the current selection to one. Resolves
## clicks/drags to hexes/squads/groups only — every actual mutation goes
## through CommandProcessor, the sim's single action-stream entry point
## (07-data-architecture.md section 8); this node never touches sim state
## directly. Focus-fire clicks are item 3/UI-layer scope
## (09-ui-and-controls.md), not this slice.
class_name InputController
extends Node2D

var state: MatchState
var owner_id: String
var squad_view: SquadView

var _drag_active := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
## Control groups: group number (1-9) -> Array of squad ids, same convention
## as most RTS games. Squads that no longer exist are dropped lazily on
## recall rather than eagerly on death — this node never listens for squad
## removal.
var _control_groups: Dictionary = {}

const DRAG_THRESHOLD := 6.0
const DRAG_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const DRAG_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.8)

func setup(p_state: MatchState, p_owner_id: String, p_squad_view: SquadView) -> void:
	state = p_state
	owner_id = p_owner_id
	squad_view = p_squad_view

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = true
			_drag_start = get_global_mouse_position()
			_drag_current = _drag_start
		else:
			_on_left_release(event)
		queue_redraw()
		return
	if event is InputEventMouseMotion and _drag_active:
		_drag_current = get_global_mouse_position()
		queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_control_group_key(event)

func _on_left_release(event: InputEventMouseButton) -> void:
	_drag_active = false
	var release_pos := get_global_mouse_position()
	var shift := event.shift_pressed

	if _drag_start.distance_to(release_pos) > DRAG_THRESHOLD:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(release_pos)
		var friendly_ids: Array = []
		for squad in squad_view.squads_in_rect(rect):
			if squad.owner_id == owner_id:
				friendly_ids.append(squad.id)
		if not friendly_ids.is_empty():
			if shift:
				squad_view.add_to_selection(friendly_ids)
			else:
				squad_view.select_set(friendly_ids)
		elif not shift:
			squad_view.clear_selection()
		return

	var clicked_squad := squad_view.squad_at_pixel(release_pos)
	if clicked_squad != null and clicked_squad.owner_id == owner_id:
		if shift:
			squad_view.toggle_selection(clicked_squad.id)
		else:
			squad_view.select_only(clicked_squad.id)
		return

	if squad_view.selected_squad_ids.is_empty():
		return
	var target_hex := HexView.pixel_to_axial(release_pos)
	for squad_id in squad_view.selected_squad_ids.keys():
		CommandProcessor.move_squad(state, squad_id, target_hex, owner_id)

func _handle_control_group_key(event: InputEventKey) -> void:
	var group := _digit_for_keycode(event.keycode)
	if group == -1:
		return
	if event.ctrl_pressed:
		_control_groups[group] = squad_view.selected_squad_ids.keys()
		return
	var live_ids: Array = []
	for id in _control_groups.get(group, []):
		if state.find_squad(id) != null:
			live_ids.append(id)
	_control_groups[group] = live_ids
	squad_view.select_set(live_ids)

func _digit_for_keycode(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1 + 1
	return -1

func _draw() -> void:
	if not _drag_active or _drag_start.distance_to(_drag_current) <= DRAG_THRESHOLD:
		return
	var rect := Rect2(_drag_start, Vector2.ZERO).expand(_drag_current)
	draw_rect(rect, DRAG_FILL_COLOR, true)
	draw_rect(rect, DRAG_BORDER_COLOR, false, 1.0)
