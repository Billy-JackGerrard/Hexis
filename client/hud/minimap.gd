## Minimap (build order item 7, 09-ui-and-controls.md's Minimap requirement
## — "needed given multi-base, multi-front play across a large hex map"):
## corner-docked overview of every generated hex (Board.TERRAIN_COLORS reused
## so the palette matches the main board exactly), every base (owner-tinted,
## slightly larger), and every squad (owner-tinted dot). Click or
## click-drag recenters the camera on the corresponding world position —
## unlike every other client/ node this one is a real interactive Control
## (default mouse_filter = STOP), so it naturally consumes clicks in its own
## rect before they'd otherwise reach InputController's world-space
## _unhandled_input.
##
## Same fog-of-war the main board applies (client/fog_of_war.gd) instead of
## a full-information overview: an unexplored hex is left blank, an explored-
## but-not-currently-visible one draws darkened, and enemy bases/squads only
## ever appear once (bases) or while (squads) the local player's own
## PlayerVision (state.visions) actually covers them — mirrors
## squad_view.gd's _is_renderable stealth/detection gate exactly, since a
## minimap dot would otherwise leak a stealthed enemy squad's position.
class_name Minimap
extends Control

var state: MatchState
var owner_colors: Dictionary = {}
var camera_controller: CameraController
var hexes: Array[HexCoord] = []
var local_owner_id: String = ""

var _bounds_min: Vector2
var _bounds_extent: Vector2 ## bounds_max - bounds_min, precomputed once

## Redraw throttle: the terrain/base/squad layers only change on a sim tick
## (10Hz), and the "you are here" viewport rect only changes while the camera
## is actually panning/zooming — so redrawing this whole map-sized overlay
## unconditionally every render frame (60fps+) was wasted cost the vast
## majority of the time nothing moved. See fog_of_war.gd for the same fix.
var _last_drawn_tick: int = -1
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: Vector2 = Vector2.INF

const SIZE := Vector2(220.0, 220.0)
const MARGIN := 12.0
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.6)
const BASE_RADIUS := 4.0
const SQUAD_RADIUS := 2.0
const VIEWPORT_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const EXPLORED_DARKEN := 0.5

func setup(p_state: MatchState, p_owner_colors: Dictionary, p_camera_controller: CameraController, p_hexes: Array[HexCoord], bounds_min: Vector2, bounds_max: Vector2, p_local_owner_id: String) -> void:
	state = p_state
	owner_colors = p_owner_colors
	camera_controller = p_camera_controller
	hexes = p_hexes
	local_owner_id = p_local_owner_id
	_bounds_min = bounds_min
	_bounds_extent = bounds_max - bounds_min

	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -SIZE.x - MARGIN
	offset_right = -MARGIN
	offset_top = -SIZE.y - MARGIN
	offset_bottom = -MARGIN

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

## World position -> local minimap-space position (non-uniform stretch to
## fit SIZE; a placeholder-scale minimap doesn't need aspect-correct scaling
## to be useful).
func _world_to_local(world_pos: Vector2) -> Vector2:
	var t := (world_pos - _bounds_min) / _bounds_extent
	return t * SIZE

func _local_to_world(local_pos: Vector2) -> Vector2:
	var t := local_pos / SIZE
	return _bounds_min + t * _bounds_extent

func _gui_input(event: InputEvent) -> void:
	var pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pos = event.position
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pos = event.position
	else:
		return
	camera_controller.center_on(_local_to_world(pos))
	accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), BG_COLOR, true)
	if state != null and state.grid != null:
		var pv: PlayerVision = state.visions.get(local_owner_id)
		for hex in hexes:
			if pv == null or not pv.is_explored(hex):
				continue
			var color: Color = Board.TERRAIN_COLORS.get(state.grid.get_terrain(hex), Color.MAGENTA)
			if not pv.is_visible(hex):
				color = color.darkened(EXPLORED_DARKEN)
			draw_rect(Rect2(_world_to_local(HexView.axial_to_pixel(hex)), Vector2(2.0, 2.0)), color, true)
		for base in state.bases:
			if pv == null or not pv.is_explored(base.hex_coord):
				continue
			var color: Color = owner_colors.get(base.owner_id, Color.WHITE)
			draw_circle(_world_to_local(HexView.axial_to_pixel(base.hex_coord)), BASE_RADIUS, color)
		for squad in state.squads:
			if not _is_squad_visible(squad, pv):
				continue
			var color: Color = owner_colors.get(squad.owner_id, Color.WHITE)
			draw_circle(_world_to_local(HexView.axial_to_pixel(squad.current_hex)), SQUAD_RADIUS, color)
	_draw_viewport_rect()
	draw_rect(Rect2(Vector2.ZERO, SIZE), BORDER_COLOR, false, 1.5)

## Mirrors squad_view.gd's _is_renderable exactly (own squads always shown;
## an enemy one only while currently visible and not hidden by stealth/
## detection) so the minimap can't leak anything the main board wouldn't.
func _is_squad_visible(squad: SquadInstance, pv: PlayerVision) -> bool:
	if squad.member_ids.is_empty() or squad.is_docked():
		return false
	if squad.owner_id == local_owner_id:
		return true
	if pv == null or not pv.is_visible(squad.current_hex):
		return false
	var def: Dictionary = state.troop_defs.get(squad.troop_type, {})
	if not DetectionSystem.is_squad_hidden(squad, def, state.grid):
		return true
	return DetectionSystem.detected_hexes_for(state.detections, local_owner_id).has(squad.current_hex.to_key())

## The camera's current visible world extent, outlined on the minimap — the
## standard "you are here" minimap rectangle.
func _draw_viewport_rect() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var half_extent := vp_size / (2.0 * camera_controller.zoom)
	var top_left := _world_to_local(camera_controller.position - half_extent)
	var bottom_right := _world_to_local(camera_controller.position + half_extent)
	draw_rect(Rect2(top_left, bottom_right - top_left), VIEWPORT_COLOR, false, 1.0)
