## Click handling for this scaffold slice: left-click a friendly squad to
## select it, left-click elsewhere to issue a move order for the current
## selection. Resolves a click to a hex/squad only — every actual mutation
## goes through CommandProcessor, the sim's single action-stream entry point
## (07-data-architecture.md section 8); this node never touches sim state
## directly. Drag-select, control groups, and focus-fire clicks are
## item 3/UI-layer scope (09-ui-and-controls.md), not this slice.
class_name InputController
extends Node2D

var state: MatchState
var owner_id: String
var squad_view: SquadView

func setup(p_state: MatchState, p_owner_id: String, p_squad_view: SquadView) -> void:
	state = p_state
	owner_id = p_owner_id
	squad_view = p_squad_view

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var world_pos := get_global_mouse_position()

	var clicked_squad := squad_view.squad_at_pixel(world_pos)
	if clicked_squad != null and clicked_squad.owner_id == owner_id:
		squad_view.selected_squad_id = clicked_squad.id
		return

	if squad_view.selected_squad_id == "":
		return
	var target_hex := HexView.pixel_to_axial(world_pos)
	CommandProcessor.move_squad(state, squad_view.selected_squad_id, target_hex, owner_id)
