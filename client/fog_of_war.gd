## Fog-of-war overlay: darkens hexes the local player hasn't explored yet,
## and dims hexes that are explored but not currently visible (the "explored
## but not currently visible" fade from 01-map-and-terrain.md's Fog of War
## section). Reads state.visions, already computed every tick by
## VisionSystem.resolve_tick (sim_orchestrator.gd) — this is only the
## missing visual for output that already exists, per the build order's
## deferred item-2 list. Read-only, like every other client/ node: never
## calls VisionSystem.vision_for (which lazily creates entries), just reads.
class_name FogOfWar
extends Node2D

var grid: HexGrid
var hexes: Array[HexCoord] = []
var visions: Dictionary
var owner_id: String

const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.55)

func setup(p_grid: HexGrid, p_hexes: Array[HexCoord], p_visions: Dictionary, p_owner_id: String) -> void:
	grid = p_grid
	hexes = p_hexes
	visions = p_visions
	owner_id = p_owner_id

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	var pv: PlayerVision = visions.get(owner_id)
	var corners := HexView.corners()
	for hex in hexes:
		if pv != null and pv.is_visible(hex):
			continue
		var explored := pv != null and pv.is_explored(hex)
		var color: Color = EXPLORED_COLOR if explored else UNEXPLORED_COLOR
		var center := HexView.axial_to_pixel(hex)
		var points := PackedVector2Array()
		for corner in corners:
			points.append(center + corner)
		draw_colored_polygon(points, color)
