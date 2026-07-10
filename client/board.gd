## Terrain rendering: flat-color hex fills, no textures/TileMap — per
## game-design/01-map-and-terrain.md's Rendering Notes. Draws every hex in
## one _draw() pass rather than instancing a Polygon2D node per hex; same
## flat-color result, far fewer nodes for this placeholder pass.
class_name Board
extends Node2D

var grid: HexGrid
var hexes: Array[HexCoord] = []

const TERRAIN_COLORS := {
	Terrain.Type.PLAINS: Color(0.55, 0.75, 0.35),
	Terrain.Type.FOREST: Color(0.20, 0.45, 0.20),
	Terrain.Type.HILLS: Color(0.65, 0.55, 0.35),
	Terrain.Type.RIVER: Color(0.35, 0.60, 0.85),
	Terrain.Type.OCEAN: Color(0.15, 0.35, 0.65),
}
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.25)
const ROAD_COLOR := Color(0.65, 0.5, 0.3)
const BRIDGE_COLOR := Color(0.4, 0.35, 0.3)

func setup(p_grid: HexGrid, p_hexes: Array[HexCoord]) -> void:
	grid = p_grid
	hexes = p_hexes
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	var corners := HexView.corners()
	for hex in hexes:
		var center := HexView.axial_to_pixel(hex)
		var points := PackedVector2Array()
		for corner in corners:
			points.append(center + corner)
		var color: Color = TERRAIN_COLORS.get(grid.get_terrain(hex), Color.MAGENTA)
		draw_colored_polygon(points, color)
		draw_polyline(points + PackedVector2Array([points[0]]), OUTLINE_COLOR, 1.0)

		var infrastructure := grid.get_infrastructure(hex)
		if infrastructure == Terrain.Infrastructure.ROAD:
			draw_line(center + Vector2(-HexView.HEX_SIZE * 0.5, 0), center + Vector2(HexView.HEX_SIZE * 0.5, 0), ROAD_COLOR, 3.0)
		elif infrastructure == Terrain.Infrastructure.BRIDGE:
			draw_line(center + Vector2(-HexView.HEX_SIZE * 0.5, 0), center + Vector2(HexView.HEX_SIZE * 0.5, 0), BRIDGE_COLOR, 5.0)
