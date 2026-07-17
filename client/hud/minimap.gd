## Minimap (build order item 7, 09-ui-and-controls.md's Minimap requirement
## — "needed given multi-base, multi-front play across a large hex map"):
## corner-docked overview of every generated hex (flat per-terrain-type
## colors — the minimap is a schematic overview, not a scaled-down render of
## the 3D terrain view), every base (owner-tinted,
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
##
## Combat involving the local player also blinks a red dot at the fight's
## hex (see _draw_combat_flashes) — gated on current visibility, same as
## squads, so it can't reveal a fight happening somewhere still fogged.
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
## (10Hz, already sparse so left unthrottled), and the "you are here"
## viewport rect only changes while the camera is actually panning/zooming —
## so redrawing this whole map-sized overlay unconditionally every render
## frame (60fps+) was wasted cost the vast majority of the time nothing
## moved. Camera position fires a change every single rendered frame while
## panning though (see fog_of_war.gd's own version of this same fix), and
## this redraw always re-iterates the full (unculled — this is a whole-map
## overview by design) hex list, so the cam-triggered path also needs a
## real-time cooldown, not just a value-changed check, or a fast drag still
## redraws (and re-walks every hex) every single frame.
var _last_drawn_tick: int = -1
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: Vector2 = Vector2.INF
var _cam_redraw_cooldown: float = 0.0

const CAM_REDRAW_COOLDOWN_SECONDS := 0.1
const SIZE := Vector2(220.0, 220.0)
const MARGIN := 12.0
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const BORDER_COLOR := UITheme.PANEL_BORDER
const BORDER_WIDTH := 4.0
const BASE_RADIUS := 4.0
const SQUAD_RADIUS := 2.0
const VIEWPORT_COLOR := Color(1.0, 1.0, 1.0, 0.5)
const EXPLORED_DARKEN := 0.5
const TERRAIN_COLORS := {
	Terrain.Type.PLAINS: Color(0.55, 0.75, 0.35),
	Terrain.Type.FOREST: Color(0.20, 0.45, 0.20),
	Terrain.Type.HILLS: Color(0.65, 0.55, 0.35),
	Terrain.Type.RIVER: Color(0.35, 0.60, 0.85),
	Terrain.Type.OCEAN: Color(0.15, 0.35, 0.65),
}
## How long (seconds) after a hit the combat-flash dot stays lit — mirrors
## SquadInstance/BuildingInstance.time_since_damage's own reset-to-0-on-hit
## semantics, just read from the client side instead of driving a system.
const COMBAT_FLASH_SECONDS := 0.6
const COMBAT_FLASH_RADIUS := 5.0
const COMBAT_FLASH_COLOR := Color(1.0, 0.15, 0.1, 1.0)

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

func _process(delta: float) -> void:
	if state == null:
		return
	_cam_redraw_cooldown = maxf(0.0, _cam_redraw_cooldown - delta)
	var tick_changed := state.tick != _last_drawn_tick
	var cam_pos := camera_controller.position
	var cam_zoom := camera_controller.zoom
	var cam_changed := cam_pos != _last_cam_pos or cam_zoom != _last_cam_zoom
	if not tick_changed and not (cam_changed and _cam_redraw_cooldown <= 0.0):
		return
	_last_drawn_tick = state.tick
	_last_cam_pos = cam_pos
	_last_cam_zoom = cam_zoom
	_cam_redraw_cooldown = CAM_REDRAW_COOLDOWN_SECONDS
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
			var color: Color = TERRAIN_COLORS.get(state.grid.get_terrain(hex), Color.MAGENTA)
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
		_draw_combat_flashes(pv)
	_draw_viewport_rect()
	draw_rect(Rect2(Vector2.ZERO, SIZE), BORDER_COLOR, false, BORDER_WIDTH)

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

## Combat-flash dot: a hex the local player can currently see (not just
## remembered fog) where a squad or building on either side of the fight is
## owned by the local player — mirrors last_damaged_by/time_since_damage
## being reset on every hit (CombatResolver._damage_target) so this needs no
## dedicated event system, just a read of state already being written.
## Blinks (rather than fading) via a tick-parity toggle so it stays legible
## at minimap scale; COMBAT_FLASH_SECONDS keeps it lit briefly after the last
## hit rather than a single-tick strobe.
func _draw_combat_flashes(pv: PlayerVision) -> void:
	if state.tick % 4 >= 2:
		return
	for squad in state.squads:
		if squad.member_ids.is_empty() or squad.is_docked():
			continue
		if not _is_combat_flash(squad.owner_id, squad.last_damaged_by, squad.time_since_damage):
			continue
		if pv == null or not pv.is_visible(squad.current_hex):
			continue
		draw_circle(_world_to_local(HexView.axial_to_pixel(squad.current_hex)), COMBAT_FLASH_RADIUS, COMBAT_FLASH_COLOR)
	for base in state.bases:
		for building in base.buildings:
			if building.hex == null or not _is_combat_flash(base.owner_id, building.last_damaged_by, building.time_since_damage):
				continue
			if pv == null or not pv.is_visible(building.hex):
				continue
			draw_circle(_world_to_local(HexView.axial_to_pixel(building.hex)), COMBAT_FLASH_RADIUS, COMBAT_FLASH_COLOR)
	for building in state.standalone_buildings:
		if building.hex == null or not _is_combat_flash(building.owner_id, building.last_damaged_by, building.time_since_damage):
			continue
		if pv == null or not pv.is_visible(building.hex):
			continue
		draw_circle(_world_to_local(HexView.axial_to_pixel(building.hex)), COMBAT_FLASH_RADIUS, COMBAT_FLASH_COLOR)

func _is_combat_flash(owner_id: String, last_damaged_by: String, time_since_damage: float) -> bool:
	# last_damaged_by == "" means "never actually hit" (its default, and what
	# combat_resolver/command_processor reset it back to on capture/rebuild) —
	# required explicitly so a target that's simply sitting at low
	# time_since_damage (fresh spawn, or any future stalled-accumulator bug)
	# can't read as "in combat" without a real recorded hit backing it.
	if last_damaged_by == "":
		return false
	if time_since_damage >= COMBAT_FLASH_SECONDS:
		return false
	return owner_id == local_owner_id or last_damaged_by == local_owner_id

## The camera's current visible world extent, outlined on the minimap — the
## standard "you are here" minimap rectangle.
func _draw_viewport_rect() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var half_extent := vp_size / (2.0 * camera_controller.zoom)
	var top_left := _world_to_local(camera_controller.position - half_extent)
	var bottom_right := _world_to_local(camera_controller.position + half_extent)
	draw_rect(Rect2(top_left, bottom_right - top_left), VIEWPORT_COLOR, false, 1.0)
