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

## Redraw throttle: tick change (vision only changes on a fine tick, 10Hz,
## already sparse so left unthrottled) OR camera pos/zoom change (the drawn
## set is culled to the on-screen viewport via _visible_hex_rect, so
## panning/zooming must requalify it — same "you are here" reasoning
## minimap.gd's own throttle uses). The camera check alone isn't enough
## though: position changes every single rendered frame while panning
## (right-drag fires a mouse-motion event ~every frame), so without a
## real-time cooldown this redrew — and re-iterated the full hex list — up
## to 100+ times/sec while dragging, worse the more of the map a zoomed-out
## camera put on screen. CAM_REDRAW_COOLDOWN caps that to the same ~10Hz the
## tick-driven redraw already runs at, independent of pan speed/frame rate.
var _last_drawn_tick: int = -1
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: Vector2 = Vector2.INF
var _cam_redraw_cooldown: float = 0.0

const CAM_REDRAW_COOLDOWN_SECONDS := 0.1
const MARGIN_HEXES := 2.0
const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.55)

func setup(p_state: MatchState, p_hexes: Array[HexCoord], p_owner_id: String, p_camera_controller: CameraController) -> void:
	state = p_state
	hexes = p_hexes
	owner_id = p_owner_id
	camera_controller = p_camera_controller

func _process(delta: float) -> void:
	if state == null:
		return
	_cam_redraw_cooldown = maxf(0.0, _cam_redraw_cooldown - delta)
	var tick_changed := state.tick != _last_drawn_tick
	var cam_pos := camera_controller.position
	var cam_zoom := camera_controller.zoom
	var cam_changed := cam_pos != _last_cam_pos or cam_zoom != _last_cam_zoom
	# Cooldown alone leaves a gap: a fast drag can cross the margin in under
	# 100ms, exposing hexes with no fog polygon drawn yet (a visible flash of
	# unfogged map). Once the pan has eaten the margin, force the redraw
	# regardless of cooldown so the buffer never runs dry. A zoom step is
	# worse: it's a single discrete jump that exposes a whole new ring of
	# hexes at once (bigger on zoom-out, since the viewport suddenly covers
	# far more world), so any zoom change always forces an immediate redraw.
	var cam_zoom_changed := cam_zoom != _last_cam_zoom
	# Trigger at half the margin, not the full margin — leaves a cushion
	# instead of forcing the redraw exactly as the buffer runs out.
	var cam_outran_margin := cam_pos.distance_to(_last_cam_pos) >= MARGIN_HEXES * HexView.HEX_SIZE / cam_zoom.x * 0.5
	if not tick_changed and not cam_changed:
		return
	if not tick_changed and not cam_zoom_changed and _cam_redraw_cooldown > 0.0 and not cam_outran_margin:
		return
	_last_drawn_tick = state.tick
	_last_cam_pos = cam_pos
	_last_cam_zoom = cam_zoom
	_cam_redraw_cooldown = CAM_REDRAW_COOLDOWN_SECONDS
	queue_redraw()

## The camera's current visible world rect, +2 hexes of margin so hexes just
## off-screen are already drawn before they scroll into view (avoids a
## visible pop-in strip at the viewport edge during a pan).
func _visible_hex_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	var half_extent := vp_size / (2.0 * camera_controller.zoom)
	# Fixed world-unit margin would shrink to a thin sliver on screen once
	# zoomed out (screen size = world size * zoom); scale by 1/zoom so the
	# buffer stays a constant thickness in screen space at any zoom level.
	var margin := Vector2.ONE * MARGIN_HEXES * HexView.HEX_SIZE / camera_controller.zoom
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
