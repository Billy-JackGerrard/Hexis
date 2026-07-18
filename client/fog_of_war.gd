## Fog-of-war overlay: hides hexes the local player hasn't explored yet, and
## dims hexes that are explored but not currently visible (the "explored but
## not currently visible" fade from 01-map-and-terrain.md's Fog of War
## section). Reads state.visions, already computed every tick by
## VisionSystem.resolve_tick (sim_orchestrator.gd) — this is only the
## missing visual for output that already exists, per the build order's
## deferred item-2 list. Read-only, like every other client/ node: never
## calls VisionSystem.vision_for (which lazily creates entries), just reads.
##
## Everything here is 3D (MeshInstance3D under _fog_root), not a Node2D
## draw_colored_polygon overlay like the original version of this file used.
## main.tscn's single Window always renders World3D first and the 2D canvas
## layer on top of it (see main.gd's own doc comment on that same ordering) —
## a flat 2D polygon is therefore ALWAYS drawn over any 3D content, including
## the cloud decoration meshes added for atmosphere: they'd render into the
## 3D pass and then get fully painted over by the 2D fog polygon on the next
## pass, only visible at all where they happened to stick out past the
## polygon's screen-space edge. Doing the occlusion itself in 3D lets normal
## depth-sorting composite the clouds against it correctly instead.
##
## Two per-hex layers, each a wrapper Node3D holding up to two children:
## - Unexplored: an opaque black prism (_fog_prism_mesh scaled to
##   FOG_FLOOR_HEIGHT_UNEXPLORED) tall enough to hide typical terrain/
##   building/decoration content, topped with an opaque cloud cluster
##   (cloud_big/cloud_small) floating above it for the "under thick cloud"
##   look. A flat cap alone (no side walls) would leave a gap under the
##   tilted camera — see _build_fog_prism_mesh's doc comment.
## - Explored-but-not-visible: a thin translucent grey prism (unlike
##   unexplored, this deliberately does NOT need to fully occlude — the
##   whole point is dimmed-but-visible remembered terrain) topped with a
##   translucent haze cloud, both alpha-blended so terrain/buildings show
##   through faintly. Distinct from the unexplored look rather than reusing
##   it, so "remembered" reads differently from "never seen."
class_name FogOfWar
extends Node2D

var state: MatchState
var hexes: Array[HexCoord] = []
var owner_id: String
var camera_controller: CameraController

var _fog_root: Node3D
var _fog_prism_mesh: ArrayMesh ## unit-height (Y=1) hex prism, shared by every instance below via per-node Y scale — see _build_fog_prism_mesh
var _floor_material: StandardMaterial3D
var _haze_floor_material: StandardMaterial3D
var _unexplored_instances: Dictionary = {} ## hex key -> Node3D wrapper (floor + cloud)
var _haze_instances: Dictionary = {} ## hex key -> Node3D wrapper (floor + cloud)

## Redraw throttle: tick change (vision only changes on a fine tick, 10Hz,
## already sparse so left unthrottled) OR camera pos/zoom change (the drawn
## set is culled to the on-screen viewport via _visible_hex_rect, so
## panning/zooming must requalify it — same "you are here" reasoning
## minimap.gd's own throttle uses). The camera check alone isn't enough
## though: position changes every single rendered frame while panning
## (right-drag fires a mouse-motion event ~every frame), so without a
## real-time cooldown this recomputed — and re-iterated the full hex list —
## up to 100+ times/sec while dragging, worse the more of the map a
## zoomed-out camera put on screen. CAM_REDRAW_COOLDOWN caps that to the same
## ~10Hz the tick-driven update already runs at, independent of pan speed/
## frame rate.
var _last_drawn_tick: int = -1
var _last_cam_pos: Vector2 = Vector2.INF
var _last_cam_zoom: Vector2 = Vector2.INF
var _cam_redraw_cooldown: float = 0.0

const CAM_REDRAW_COOLDOWN_SECONDS := 0.1
const MARGIN_HEXES := 2.0

const UNEXPLORED_COLOR := Color(0.0, 0.0, 0.0, 1.0)
const EXPLORED_COLOR := Color(0.0, 0.0, 0.0, 0.55)

## Both drawn from the pack's nature/ decoration set (see terrain_view_3d.gd
## for the other consumer of that same directory). CLOUD_HAZE uses only the
## small mesh — thinner per-hex coverage reads as a light haze rather than
## the solid blanket the big+small mix gives unexplored hexes.
const CLOUD_DIR := "res://assets/decoration/nature/"
const CLOUD_UNEXPLORED_MESHES := [CLOUD_DIR + "cloud_big.gltf", CLOUD_DIR + "cloud_small.gltf"]
const CLOUD_HAZE_MESHES := [CLOUD_DIR + "cloud_small.gltf"]
const CLOUD_HEIGHT_UNEXPLORED := 2.2 ## world units above ground; above FOG_FLOOR_HEIGHT_UNEXPLORED so it visibly caps the block
const CLOUD_HEIGHT_HAZE := 1.8
const CLOUD_HAZE_ALPHA := 0.32
const SALT_CLOUD_MESH := 101
const SALT_CLOUD_ROTATION := 102

## Prism heights (world units, before the tilt's own height*tan(tilt)
## parallax — same effect that makes tall buildings "lean" on screen, see
## main.gd's _sync_camera_3d doc comment). FOG_FLOOR_HEIGHT_UNEXPLORED is a
## practical guess at "taller than typical terrain/building/decoration
## content at this hex", not a hard guarantee for every possible tall asset
## in the pack (a very tall mountain decoration could still poke above the
## rim) — tune upward if that's visibly an issue. FOG_HAZE_HEIGHT_EXPLORED
## is deliberately thin: the explored layer only needs to tint, not occlude.
const FOG_FLOOR_HEIGHT_UNEXPLORED := 1.6
const FOG_HAZE_HEIGHT_EXPLORED := 0.05

func setup(p_state: MatchState, p_hexes: Array[HexCoord], p_owner_id: String, p_camera_controller: CameraController) -> void:
	state = p_state
	hexes = p_hexes
	owner_id = p_owner_id
	camera_controller = p_camera_controller
	if _fog_root == null:
		_fog_root = Node3D.new()
		add_child(_fog_root)
		_fog_prism_mesh = _build_fog_prism_mesh()
		_floor_material = _build_floor_material(UNEXPLORED_COLOR, false)
		_haze_floor_material = _build_floor_material(EXPLORED_COLOR, true)
	else:
		for child in _fog_root.get_children():
			child.queue_free()
	_unexplored_instances.clear()
	_haze_instances.clear()

## A solid hex prism (side walls, no bottom cap since the camera never looks
## from below, plus a top cap) rather than a single flat quad at height —
## a flat cap alone parallax-shifts on screen under the tilted camera the
## same way a building does (see main.gd's tilt doc comment), which would
## leave the near edge of the actual ground hex uncovered. The solid walls
## fill that gap: whatever screen ray enters this hex's footprint at any
## height up to the prism's top is blocked by a wall or the cap, regardless
## of tilt. Built once at unit height (Y=1) in local space and reused by
## every instance via per-node Y scale, since the shape is identical
## everywhere — only the height (unexplored vs. haze) and per-hex XZ
## position differ.
func _build_fog_prism_mesh() -> ArrayMesh:
	var corners := HexView.corners()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(corners.size()):
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var a0 := Vector3(a.x, 0.0, a.y) * TerrainView3D.WORLD_UNITS_PER_PIXEL
		var b0 := Vector3(b.x, 0.0, b.y) * TerrainView3D.WORLD_UNITS_PER_PIXEL
		var a1 := Vector3(a.x, 1.0, a.y) * TerrainView3D.WORLD_UNITS_PER_PIXEL
		var b1 := Vector3(b.x, 1.0, b.y) * TerrainView3D.WORLD_UNITS_PER_PIXEL
		st.add_vertex(a0)
		st.add_vertex(b0)
		st.add_vertex(b1)
		st.add_vertex(a0)
		st.add_vertex(b1)
		st.add_vertex(a1)
	var top_center := Vector3.UP
	for i in range(corners.size()):
		var a := corners[i]
		var b := corners[(i + 1) % corners.size()]
		var a1 := Vector3(a.x, 1.0, a.y) * TerrainView3D.WORLD_UNITS_PER_PIXEL
		var b1 := Vector3(b.x, 1.0, b.y) * TerrainView3D.WORLD_UNITS_PER_PIXEL
		st.add_vertex(top_center)
		st.add_vertex(a1)
		st.add_vertex(b1)
	return st.commit()

## Unshaded (flat color regardless of DirectionalLight3D, matching the flat
## look the original 2D polygon had) and double-sided (cull disabled — the
## winding direction of the two layers built above isn't guaranteed to face
## the camera from every angle, cheaper to just disable culling than to
## chase winding order for content that's opaque/translucent regardless).
func _build_floor_material(color: Color, translucent: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	if translucent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _process(delta: float) -> void:
	if state == null:
		return
	_cam_redraw_cooldown = maxf(0.0, _cam_redraw_cooldown - delta)
	var tick_changed := state.tick != _last_drawn_tick
	var cam_pos := camera_controller.position
	var cam_zoom := camera_controller.zoom
	var cam_changed := cam_pos != _last_cam_pos or cam_zoom != _last_cam_zoom
	# Cooldown alone leaves a gap: a fast drag can cross the margin in under
	# 100ms, exposing hexes with no fog instance placed yet (a visible flash
	# of unfogged map). Once the pan has eaten the margin, force the update
	# regardless of cooldown so the buffer never runs dry. A zoom step is
	# worse: it's a single discrete jump that exposes a whole new ring of
	# hexes at once (bigger on zoom-out, since the viewport suddenly covers
	# far more world), so any zoom change always forces an immediate update.
	var cam_zoom_changed := cam_zoom != _last_cam_zoom
	# Triggering at the full margin (zero slack) flashes: the update's result
	# doesn't land until next frame, so the exact-margin trigger point has no
	# room for that one frame of latency. Need a cushion — but a small one
	# (frequent, eager updates) is only "free" where each update is cheap,
	# i.e. at normal zoom and zoomed in, where the culled pass covers little
	# of the map. Zoomed out, the same eager cushion was the earlier lag:
	# every one of those extra updates is pricier because far more hexes fall
	# inside a zoomed-out visible_rect. So only relax the cushion below
	# default zoom, where the up-front margin is already at its screen-space
	# widest and can afford to be spent further before forcing a catch-up
	# update.
	var cushion_fraction := 1.0 if cam_zoom.x < 1.1 else 0.5
	var cam_outran_margin := cam_pos.distance_to(_last_cam_pos) >= MARGIN_HEXES * HexView.HEX_SIZE / cam_zoom.x * cushion_fraction
	if not tick_changed and not cam_changed:
		return
	if not tick_changed and not cam_zoom_changed and _cam_redraw_cooldown > 0.0 and not cam_outran_margin:
		return
	_last_drawn_tick = state.tick
	_last_cam_pos = cam_pos
	_last_cam_zoom = cam_zoom
	_cam_redraw_cooldown = CAM_REDRAW_COOLDOWN_SECONDS
	_update_fog(_visible_hex_rect())

## The camera's current visible world rect, +2 hexes of margin so hexes just
## off-screen are already placed before they scroll into view (avoids a
## visible pop-in strip at the viewport edge during a pan).
func _visible_hex_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	var half_extent := vp_size / (2.0 * camera_controller.zoom)
	# Fixed world-unit margin would shrink to a thin sliver on screen once
	# zoomed out (screen size = world size * zoom); scale by 1/zoom so the
	# buffer stays a constant thickness in screen space at any zoom level.
	var margin := Vector2.ONE * MARGIN_HEXES * HexView.HEX_SIZE / camera_controller.zoom
	return Rect2(camera_controller.position - half_extent - margin, (half_extent + margin) * 2.0)

## Adds/removes fog instances to match the current visible-rect-culled,
## explored/unexplored split — same per-hex loop cost as the old _draw()
## (bounded by the viewport, not the whole map), run at the same cadence
## since both are gated by the same _process() decision above. Visible hexes
## (pv.is_visible) get neither layer.
func _update_fog(visible_rect: Rect2) -> void:
	if state.grid == null or camera_controller == null:
		return
	var pv: PlayerVision = state.visions.get(owner_id)
	var touched_unexplored: Dictionary = {}
	var touched_haze: Dictionary = {}
	for hex in hexes:
		var center := HexView.axial_to_pixel(hex)
		if not visible_rect.has_point(center):
			continue
		if pv != null and pv.is_visible(hex):
			continue
		var key := hex.to_key()
		if pv != null and pv.is_explored(hex):
			touched_haze[key] = true
			_ensure_instance(hex, _haze_instances, _haze_floor_material, FOG_HAZE_HEIGHT_EXPLORED, CLOUD_HAZE_MESHES, CLOUD_HEIGHT_HAZE, true)
		else:
			touched_unexplored[key] = true
			_ensure_instance(hex, _unexplored_instances, _floor_material, FOG_FLOOR_HEIGHT_UNEXPLORED, CLOUD_UNEXPLORED_MESHES, CLOUD_HEIGHT_UNEXPLORED, false)
	_prune_instances(_unexplored_instances, touched_unexplored)
	_prune_instances(_haze_instances, touched_haze)

func _ensure_instance(hex: HexCoord, instances: Dictionary, floor_material: StandardMaterial3D, floor_height: float, cloud_options: Array, cloud_height: float, hazy_cloud: bool) -> void:
	var key := hex.to_key()
	if instances.has(key):
		return
	var pixel := HexView.axial_to_pixel(hex)
	var wrapper := Node3D.new()
	wrapper.position = Vector3(pixel.x * TerrainView3D.WORLD_UNITS_PER_PIXEL, 0.0, pixel.y * TerrainView3D.WORLD_UNITS_PER_PIXEL)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = _fog_prism_mesh
	floor_instance.material_override = floor_material
	floor_instance.scale.y = floor_height
	wrapper.add_child(floor_instance)
	var cloud_path: String = RenderUtil.pick2d(hex.q, hex.r, SALT_CLOUD_MESH, cloud_options)
	var cloud_scene: PackedScene = load(cloud_path)
	if cloud_scene != null:
		var cloud_node: Node3D = cloud_scene.instantiate()
		cloud_node.position.y = cloud_height
		cloud_node.rotation.y = RenderUtil.angle2d(hex.q, hex.r, SALT_CLOUD_ROTATION)
		if hazy_cloud:
			RenderUtil.apply_alpha(cloud_node, CLOUD_HAZE_ALPHA)
		wrapper.add_child(cloud_node)
	_fog_root.add_child(wrapper)
	instances[key] = wrapper

## Frees any instance whose hex wasn't touched this pass — it either scrolled
## out of visible_rect, became visible (vision source moved in), or (haze
## only) regressed from explored to unexplored, which can't actually happen
## (PlayerVision.is_explored is monotonic — once true, always true) but is
## handled the same way regardless since this is just "not in the touched
## set" bookkeeping, no special case needed.
func _prune_instances(instances: Dictionary, touched: Dictionary) -> void:
	for key in instances.keys():
		if touched.has(key):
			continue
		var node: Node3D = instances[key]
		node.queue_free()
		instances.erase(key)
