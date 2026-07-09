## Placeholder rendering for squads: an owner-tinted circle per squad,
## positioned by lerping current_hex -> path[0] over edge_progress — pure
## rendering-side interpolation of the sim's per-tick integer-hex position,
## same "counting up between ticks is visual only" principle as the resource
## tick (07-data-architecture.md section 7/8). Sim logic only ever reads
## current_hex.
##
## Also draws regiment visuals (a ring around each Commander, a line to each
## of its escorts) straight off state.regiments/RegimentInstance.commander_id
## — no new sim state, just the missing visual for structure that already
## exists (build order item 2's deferred "control groups/regiment visuals").
class_name SquadView
extends Node2D

var squads: Array[SquadInstance] = []
var regiments: Array[RegimentInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color
## squad_id -> true. Multi-selection (drag-select/control groups), not a
## single id — InputController is the only mutator.
var selected_squad_ids: Dictionary = {}

const RADIUS := 10.0
const SELECTION_COLOR := Color.YELLOW
const REGIMENT_RING_COLOR := Color(1.0, 0.85, 0.2, 0.8)
const REGIMENT_LINE_COLOR := Color(1.0, 0.85, 0.2, 0.45)

func setup(p_squads: Array[SquadInstance], p_regiments: Array[RegimentInstance], p_owner_colors: Dictionary) -> void:
	squads = p_squads
	regiments = p_regiments
	owner_colors = p_owner_colors

func squad_pixel_position(squad: SquadInstance) -> Vector2:
	var from := HexView.axial_to_pixel(squad.current_hex)
	if squad.path.is_empty():
		return from
	var to := HexView.axial_to_pixel(squad.path[0])
	return from.lerp(to, squad.edge_progress)

func squad_at_pixel(point: Vector2) -> SquadInstance:
	for squad in squads:
		if squad_pixel_position(squad).distance_to(point) <= RADIUS:
			return squad
	return null

## Every squad whose current rendered position falls inside `rect` — the
## drag-select query. Rect is in the same world space as squad_pixel_position.
func squads_in_rect(rect: Rect2) -> Array[SquadInstance]:
	var result: Array[SquadInstance] = []
	for squad in squads:
		if rect.has_point(squad_pixel_position(squad)):
			result.append(squad)
	return result

func is_selected(squad_id: String) -> bool:
	return selected_squad_ids.has(squad_id)

func select_only(squad_id: String) -> void:
	selected_squad_ids = {squad_id: true}

func select_set(squad_ids: Array) -> void:
	selected_squad_ids = {}
	for id in squad_ids:
		selected_squad_ids[id] = true

func add_to_selection(squad_ids: Array) -> void:
	for id in squad_ids:
		selected_squad_ids[id] = true

func toggle_selection(squad_id: String) -> void:
	if selected_squad_ids.has(squad_id):
		selected_squad_ids.erase(squad_id)
	else:
		selected_squad_ids[squad_id] = true

func clear_selection() -> void:
	selected_squad_ids = {}

func _squad_by_id(squad_id: String) -> SquadInstance:
	for squad in squads:
		if squad.id == squad_id:
			return squad
	return null

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for regiment in regiments:
		var commander := _squad_by_id(regiment.commander_id)
		if commander == null:
			continue
		var commander_pos := squad_pixel_position(commander)
		draw_arc(commander_pos, RADIUS + 6.0, 0.0, TAU, 24, REGIMENT_RING_COLOR, 2.0)
		for squad_id in regiment.squad_ids:
			var escort := _squad_by_id(squad_id)
			if escort == null:
				continue
			draw_line(commander_pos, squad_pixel_position(escort), REGIMENT_LINE_COLOR, 1.0)

	for squad in squads:
		var pos := squad_pixel_position(squad)
		var color: Color = owner_colors.get(squad.owner_id, Color.WHITE)
		draw_circle(pos, RADIUS, color)
		if is_selected(squad.id):
			draw_arc(pos, RADIUS + 3.0, 0.0, TAU, 24, SELECTION_COLOR, 2.0)
