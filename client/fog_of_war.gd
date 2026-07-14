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
var camera_controller: CameraController

## Redraw throttle: tick change (vision only changes on a fine tick, 10Hz) OR
## camera pos/zoom change (see _visible_hex_rect — the drawn set is culled to
## the on-screen viewport, so panning/zooming must also requalify it, same
## "you are here" reasoning minimap.gd's own throttle already uses).
var _last_drawn_tick: int = -1
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: Vector2 = Vector2.INF

const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.55)

func setup(p_state: MatchState, p_hexes: Array[HexCoord], p_owner_id: String, p_camera_controller: CameraController) -> void:
	state = p_state
	hexes = p_hexes
	owner_id = p_owner_id
	camera_controller = p_camera_controller

func _process(_delta: float) -> void:
	if state == null:
		return
	var cam_pos := camera_controller.position
	var cam_zoom := camera_controller.zoom
	if state.tick == _last_drawn_tick and cam_pos == _last_cam_pos and cam_zoom == _last_cam_zoom:
		return
	_last_drawn_tick = state.tick
	_last_cam_pos = cam_pos
	_last_cam_zoom = cam_zoom
	queue_redraw()

## The camera's current visible world rect, +1 hex of margin so a hex just
## off-screen is still drawn before it scrolls into view (avoids a visible
## pop-in strip at the viewport edge during a pan).
func _visible_hex_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	var half_extent := vp_size / (2.0 * camera_controller.zoom)
	var margin := Vector2.ONE * HexView.HEX_SIZE
	return Rect2(camera_controller.position - half_extent - margin, (half_extent + margin) * 2.0)

## Iterating the whole generated map (thousands of hexes on a multi-player
## board) every redraw was the single biggest render cost in the game —
## immediate-mode draw_colored_polygon per hex, almost all of it entirely
## off-screen. Culled to the current viewport instead, same principle a real
## TileMap's built-in visible-cell culling would give for free.
func _draw() -> void:
	if state == null or state.grid == null or camera_controller == null:
		return
	var pv: PlayerVision = state.visions.get(owner_id)
	var corners := HexView.corners()
	var visible_rect := _visible_hex_rect()
	for hex in hexes:
		var center := HexView.axial_to_pixel(hex)
		if not visible_rect.has_point(center):
			continue
		if pv != null and pv.is_visible(hex):
			continue
		var explored := pv != null and pv.is_explored(hex)
		var color: Color = EXPLORED_COLOR if explored else UNEXPLORED_COLOR
		var points := PackedVector2Array()
		for corner in corners:
			points.append(center + corner)
		draw_colored_polygon(points, color)
