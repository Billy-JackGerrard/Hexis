## Placeholder rendering for base buildings: an owner-tinted rect per
## building at its hex (no sprites/art yet, per the build order's Art
## section — placeholder geometric shapes until the loop is validated).
## Skips Walls (hex == null; edge-keyed, not on a single hex — no visual
## for this first slice).
class_name BaseView
extends Node2D

var bases: Array[BaseInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color

const BUILDING_SIZE := 20.0
const HQ_SIZE := 26.0

func setup(p_bases: Array[BaseInstance], p_owner_colors: Dictionary) -> void:
	bases = p_bases
	owner_colors = p_owner_colors
	queue_redraw()

func _draw() -> void:
	for base in bases:
		var color: Color = owner_colors.get(base.owner_id, Color.WHITE)
		for building in base.buildings:
			if building.hex == null:
				continue
			var center := HexView.axial_to_pixel(building.hex)
			var size: float = HQ_SIZE if building.building_type == "hq" else BUILDING_SIZE
			var rect := Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size))
			draw_rect(rect, color, true)
			draw_rect(rect, Color.BLACK, false, 1.0)
