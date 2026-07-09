## Placeholder rendering for squads: an owner-tinted circle per squad,
## positioned by lerping current_hex -> path[0] over edge_progress — pure
## rendering-side interpolation of the sim's per-tick integer-hex position,
## same "counting up between ticks is visual only" principle as the resource
## tick (07-data-architecture.md section 7/8). Sim logic only ever reads
## current_hex.
class_name SquadView
extends Node2D

var squads: Array[SquadInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color
var selected_squad_id: String = ""

const RADIUS := 10.0
const SELECTION_COLOR := Color.YELLOW

func setup(p_squads: Array[SquadInstance], p_owner_colors: Dictionary) -> void:
	squads = p_squads
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

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	for squad in squads:
		var pos := squad_pixel_position(squad)
		var color: Color = owner_colors.get(squad.owner_id, Color.WHITE)
		draw_circle(pos, RADIUS, color)
		if squad.id == selected_squad_id:
			draw_arc(pos, RADIUS + 3.0, 0.0, TAU, 24, SELECTION_COLOR, 2.0)
