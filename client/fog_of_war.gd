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

var state: MatchState
var hexes: Array[HexCoord] = []
var owner_id: String

## Redraw is throttled to sim ticks (see state.tick) rather than every render
## frame — vision only ever changes on a fine tick (10Hz), so redrawing the
## full hex-polygon overlay at render framerate (60fps+) was pure wasted
## per-frame cost across the whole map for no visual benefit.
var _last_drawn_tick: int = -1

const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.55)

func setup(p_state: MatchState, p_hexes: Array[HexCoord], p_owner_id: String) -> void:
	state = p_state
	hexes = p_hexes
	owner_id = p_owner_id

func _process(_delta: float) -> void:
	if state == null or state.tick == _last_drawn_tick:
		return
	_last_drawn_tick = state.tick
	queue_redraw()

func _draw() -> void:
	if state == null or state.grid == null:
		return
	var pv: PlayerVision = state.visions.get(owner_id)
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
