## Fog-of-war overlay: hides hexes the local player hasn't explored yet, and
## dims hexes that are explored but not currently visible (the "explored but
## not currently visible" fade from 01-map-and-terrain.md's Fog of War
## section). Reads state.visions, already computed every tick by
## VisionSystem.resolve_tick (sim_orchestrator.gd) — this is only the
## missing visual for output that already exists, per the build order's
## deferred item-2 list. Read-only, like every other client/ node: never
## calls VisionSystem.vision_for (which lazily creates entries), just reads.
##
## Two layers, both 3D (this file went through a Node2D draw_colored_polygon
## phase, a pure-shader phase, and a per-cell Node3D-prop phase before landing
## here — see git history if any is relevant):
## - _mesh_instance: a single continuous plane (fog_cloud.gdshader) spanning
##   the whole map, doing the actual occlusion — always fully opaque over
##   unexplored, alpha-only over explored-but-not-visible. GPU frustum-culled
##   for free since it's one mesh; this is the reliable, no-gaps guarantee
##   regardless of what's decorated on top of it.
## - the prop layer: scattered, overlapping cloud_big/cloud_small instances
##   (the actual visual — the shader plane renders flat neutral grey, see
##   fog_cloud.gdshader, so it doesn't visually compete)
##   for a Civilization-style cloud-bank look instead of a flat haze. Drawn
##   as one MultiMesh per cloud mesh (NOT one Node3D scene instance per grid
##   cell — the earlier per-node version was the dominant frame cost: ~1k+
##   scene instantiations with per-instance duplicated materials, ~1k+ draw
##   calls, and instantiate/free churn on every pan). Per-prop fade alpha
##   rides in the MultiMesh instance COLOR. Bounded to camera view + margin,
##   refreshed only when the camera moves far enough or vision actually
##   changed.
##
## Perf shape (this rewrite exists because the first shader-plane version
## lagged badly at the 10Hz sim tick):
## - The fog_state texture is diffed per HEX, not rewritten per texel: setup
##   precomputes each map hex's key + the texel indices it covers, then a
##   tick only compares each hex's visible/explored code against last time
##   and rewrites the few texels of hexes that changed. The old version ran
##   pixel_to_axial + to_key for all ~65k texels every single tick.
## - Prop placement/fade targets recompute only when vision CHANGED (the
##   texture diff says so for free) or the camera moved PROP_CAM_REFRESH
##   pixels — not every tick.
## - The per-frame alpha animation walks flat packed arrays with cached
##   hex-neighborhood keys; zero string building, zero HexCoord allocation,
##   and it writes an instance color only while an alpha is actually moving.
##
## The shader plane is kept near ground level (FOG_SHEET_HEIGHT) rather than
## floating at "cloud height": any content above y=0 parallax-shifts on
## screen under the tilted camera (the same height*tan(tilt) effect main.gd's
## _sync_camera_3d doc comment covers for buildings) — a floating sheet would
## drift its vision boundary away from the true hex-aligned boundary
## underneath it. The cloud PROPS don't have this constraint (their exact
## silhouette isn't gameplay-critical the way the occlusion boundary is), so
## they sit higher for visual depth.
class_name FogOfWar
extends Node2D

var state: MatchState
var hexes: Array[HexCoord] = []
var owner_id: String
var camera_controller: CameraController

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _fog_image: Image
var _fog_texture: ImageTexture
var _bounds_min: Vector2 ## HexView pixel space
var _bounds_max: Vector2
var _tex_width: int
var _tex_height: int
var _last_drawn_tick: int = -1

## Per-map-hex precompute (all aligned with `hexes` by index, built once in
## setup): the hex's to_key() string, the fog code (0/128/255) it had when
## last written into the texture (-1 = never), and the fog_state texel
## indices its area covers. This is what turns the per-tick texture rebuild
## into a cheap diff — see the class doc comment.
var _hex_keys: PackedStringArray = PackedStringArray()
var _hex_codes: PackedInt32Array = PackedInt32Array()
var _hex_texels: Array = [] ## Array[PackedInt32Array]
var _fog_bytes: PackedByteArray = PackedByteArray() ## live R8 texture backing store

## Prop layer state. _parts_by_variant[v] = Array of {mm: MultiMesh, xform:
## Transform3D} — one MultiMesh per MeshInstance3D found inside cloud scene
## v, sharing one slot numbering per variant. The _act_* arrays are the
## currently-active prop set (rebuilt wholesale by _update_props), walked
## flat every frame by _update_prop_alphas.
var _prop_root: Node3D
var _parts_by_variant: Array = []
var _act_cells: Array[Vector2i] = []
var _act_variant: PackedInt32Array = PackedInt32Array()
var _act_slot: PackedInt32Array = PackedInt32Array()
var _act_target: PackedFloat32Array = PackedFloat32Array()
var _act_alpha: PackedFloat32Array = PackedFloat32Array()
var _alpha_by_cell: Dictionary = {} ## Vector2i -> float, survives _update_props rebuilds so fades don't restart when the buffer is repacked
var _cell_disk_cache: Dictionary = {} ## Vector2i -> [PackedStringArray keys, PackedInt32Array dists] of every hex within CLOUD_ERODE_HEXES of the cell hex + its ring distance (deterministic, so cached forever) — see _cloud_alpha_target
var _prop_last_cam_pos: Vector2 = Vector2.INF
var _prop_last_cam_zoom: Vector2 = Vector2.INF

const SHADER_PATH := "res://client/fog_cloud.gdshader"
const PROP_SHADER_PATH := "res://client/fog_cloud_prop.gdshader"
const FOG_SHEET_HEIGHT := 0.05 ## see class doc comment — kept near ground to avoid tilt parallax drift
const MARGIN_HEXES := 2.0 ## sheet extends this far past the outermost hex so panning slightly past the map edge doesn't show a hard cutoff
## World-pixel size per fog-state texel. GPU bilinear sampling of this
## low-res texture (not the noise pattern itself) is what produces the
## smooth vision-boundary transition — a coarser texel spreads that blend
## over a wider stretch of world space, which is what actually rounds a hex
## boundary's corners into a blobby, cloud-like line instead of a tight strip
## that still traces the hex outline. (A previous, much finer 6px value
## tracked the true hex boundary closely — closer to the vision radius, but
## the reported "rigid ending, hex borders" complaint.) Bigger also means
## fewer texels, so this is a perf win too, not just a look change.
const FOG_TEXEL_SIZE_PIXELS := 18.0
const FOG_TEXTURE_MAX_DIM := 256 ## cost cap for very large multiplayer maps — texel size grows past FOG_TEXEL_SIZE_PIXELS rather than the texture growing unbounded

const CLOUD_DIR := "res://assets/decoration/nature/"
const PROP_CLOUD_MESHES := [CLOUD_DIR + "cloud_big.gltf", CLOUD_DIR + "cloud_small.gltf"]
const PROP_CELL_SIZE_PIXELS := 40.0 ## smaller than a typical scaled cloud mesh footprint, so neighboring cells' props overlap generously
const PROP_SKIP_CHANCE := 0.15 ## small per-cell chance to skip entirely — neighbor overlap still covers it, breaks up any residual grid regularity
const PROP_SCALE_MIN := 1.3
const PROP_SCALE_MAX := 2.6
const PROP_ALPHA := 0.82 ## each cloud stays slightly translucent rather than fully opaque, so overlapping instances visually MERGE — overlap regions build up toward solid while a single layer's own outer silhouette reads as a soft fringe rather than a hard cutout edge against its neighbors
const EXPLORED_PROP_ALPHA := 0.1 ## flat, low target for explored-but-not-visible cells (see _cloud_alpha_target) — sparse drifting cloud puffs over remembered terrain instead of leaving that whole layer to the shader plane alone, and because prop cells sit on their own world-space grid (unrelated to the hex grid, unlike the flat shader plane's per-hex texture), scattering some here is what breaks the visible/explored boundary out of a hex-aligned line. Cut from 0.22 alongside fog_cloud.gdshader's haze_alpha — overlapping instances near a scouted base were stacking into something opaque enough to bury it, not read as a light veil.
## Cloud height ABOVE the ground beneath the prop (see _cell_world_xform's
## _terrain_height_at_pixel offset), not an absolute world Y. Has to clear the
## tallest thing that can stand on a tile — currently a peak-tier mountain
## cluster, ~2.5 units after TerrainView3D.PEAK_DECOR_SCALE — or hilltops
## render straight through the fog that's supposed to be hiding them. Kept only
## just above that: the camera's tilt turns height into horizontal
## displacement, so every extra unit slides a cloud further from the hex it's
## covering.
const PROP_HEIGHT_MIN := 2.8
const PROP_HEIGHT_MAX := 3.4
const SALT_PROP_MESH := 201
const SALT_PROP_JITTER_X := 202
const SALT_PROP_JITTER_Y := 203
const SALT_PROP_SCALE := 204
const SALT_PROP_ROTATION := 205
const SALT_PROP_HEIGHT := 206
const SALT_PROP_SKIP := 207
const PROP_MARGIN_HEXES := 4.0 ## wider than the fog sheet's own MARGIN_HEXES since large, scaled-up cloud props can visually extend well past their cell center
## Camera must move at least this many HexView pixels (unzoomed) before props
## are recomputed — avoids thrashing the buffer every frame while panning.
##
## MUST stay well under PROP_MARGIN_HEXES's own pixel budget, which is why this
## is derived from it rather than an independent constant: the margin exists so
## props just off-screen already exist before they scroll into view, but that
## only holds if a repack is guaranteed to fire before the camera has moved far
## enough to eat through the margin. A fixed 150px threshold against a 96px
## margin (3 hexes) violated that outright — a fast continuous drag pans well
## past 150px between input-processed frames, so the newly-revealed screen edge
## was showing bare, prop-less ground for the several frames it took the
## threshold to trip (reported as "I can see the tiles on the edge of my screen"
## when panning quickly). Sized to a fraction of the margin instead, so however
## PROP_MARGIN_HEXES gets tuned later, there's always real cushion left over
## the moment a repack triggers, not a race against it.
const PROP_CAM_REFRESH_MARGIN_FRACTION := 0.4
const PROP_CAM_REFRESH_PIXELS := PROP_MARGIN_HEXES * HexView.HEX_SIZE * PROP_CAM_REFRESH_MARGIN_FRACTION
const PROP_RENDER_PRIORITY := 10 ## must beat _material's -10 (see _build_mesh's doc comment) so props draw after — i.e. on top of — the fog plane instead of being painted over by it
## A cloud prop's mesh is roughly this many hexes in horizontal radius once
## scaled (cloud_big AABB ~1.8 world units half-extent * ~2x PROP_SCALE ≈ 100
## px ≈ 3 hexes). _cloud_alpha_target erodes placement inward by this much so
## a full-opacity cloud's CENTER sits this far into unexplored territory and
## its EDGE lands on the vision boundary — rather than a cloud centered on a
## boundary cell bulging its whole radius back over visible hexes (clouds
## appearing right next to the player's own troops).
const CLOUD_ERODE_HEXES := 3.0
const FADE_TIME := 0.35 ## exponential time constant for prop alpha chasing its target — quick but not an instant pop when a hex is explored/loses vision
const ALPHA_PRUNE_THRESHOLD := 0.02 ## once a faded-out prop's alpha drops below this AND it's no longer needed near the vision boundary, its slot is dropped at the next _update_props repack rather than kept around at ~0 alpha forever
const ALPHA_SNAP_EPSILON := 0.002 ## once within this of the target, alpha snaps to it exactly so the per-frame loop stops touching that instance's color entirely

func setup(p_state: MatchState, p_hexes: Array[HexCoord], p_owner_id: String, p_camera_controller: CameraController) -> void:
	state = p_state
	hexes = p_hexes
	owner_id = p_owner_id
	camera_controller = p_camera_controller
	_compute_bounds()
	_build_mesh()
	_build_fog_texture_tables()
	if _prop_root == null:
		_prop_root = Node3D.new()
		add_child(_prop_root)
		_build_prop_multimeshes()
	_alpha_by_cell.clear()
	_cell_disk_cache.clear()
	_act_cells.clear()
	_act_variant = PackedInt32Array()
	_act_slot = PackedInt32Array()
	_act_target = PackedFloat32Array()
	_act_alpha = PackedFloat32Array()
	_last_drawn_tick = -1 ## force a texture diff pass on the next _process, even if state.tick happens to already equal 0
	_prop_last_cam_pos = Vector2.INF ## force an immediate prop population rather than waiting for the camera to move

func _compute_bounds() -> void:
	var bmin := Vector2(INF, INF)
	var bmax := Vector2(-INF, -INF)
	for hex in hexes:
		var p := HexView.axial_to_pixel(hex)
		bmin = Vector2(minf(bmin.x, p.x), minf(bmin.y, p.y))
		bmax = Vector2(maxf(bmax.x, p.x), maxf(bmax.y, p.y))
	var margin := Vector2.ONE * MARGIN_HEXES * HexView.HEX_SIZE
	_bounds_min = bmin - margin
	_bounds_max = bmax + margin
	var span := _bounds_max - _bounds_min
	_tex_width = clampi(int(ceil(span.x / FOG_TEXEL_SIZE_PIXELS)), 4, FOG_TEXTURE_MAX_DIM)
	_tex_height = clampi(int(ceil(span.y / FOG_TEXEL_SIZE_PIXELS)), 4, FOG_TEXTURE_MAX_DIM)

## Builds a single quad spanning _bounds_min..bounds_max with UVs tied
## directly to that same bounding box (not PlaneMesh's own implicit UV
## convention, to guarantee this matches the texel indexing in
## _build_fog_texture_tables exactly rather than relying on two separate
## systems agreeing by luck).
func _build_mesh() -> void:
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		# Pure overlay: never participates in the shadow pass (it's also what
		# tripped "Parameter material is null" spam in material_casts_shadows —
		# a SurfaceTool mesh with no surface material being considered for
		# shadows).
		_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_mesh_instance)
		_material = ShaderMaterial.new()
		_material.shader = load(SHADER_PATH)
		# Draw first among transparent-queue objects (see PROP_RENDER_PRIORITY's
		# doc comment) — depth_test_disabled means this plane paints over the
		# ENTIRE opaque-pass buffer regardless of depth, including our own cloud
		# props if they happen to draw before it. Explicit render_priority
		# forces this to always go first, so props (given a higher priority)
		# always land on top by draw order rather than relying on depth, which
		# is exactly what doesn't work here.
		_material.render_priority = -10
		_mesh_instance.material_override = _material
	var wupp := TerrainView3D.WORLD_UNITS_PER_PIXEL
	var min_x := _bounds_min.x * wupp
	var min_z := _bounds_min.y * wupp
	var max_x := _bounds_max.x * wupp
	var max_z := _bounds_max.y * wupp
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(min_x, FOG_SHEET_HEIGHT, min_z))
	st.set_uv(Vector2(1, 0))
	st.add_vertex(Vector3(max_x, FOG_SHEET_HEIGHT, min_z))
	st.set_uv(Vector2(1, 1))
	st.add_vertex(Vector3(max_x, FOG_SHEET_HEIGHT, max_z))
	st.set_uv(Vector2(0, 0))
	st.add_vertex(Vector3(min_x, FOG_SHEET_HEIGHT, min_z))
	st.set_uv(Vector2(1, 1))
	st.add_vertex(Vector3(max_x, FOG_SHEET_HEIGHT, max_z))
	st.set_uv(Vector2(0, 1))
	st.add_vertex(Vector3(min_x, FOG_SHEET_HEIGHT, max_z))
	_mesh_instance.mesh = st.commit()

## One-time inverse mapping for the fog_state texture: which texels does each
## map hex cover. Runs the expensive pixel_to_axial-per-texel pass exactly
## once per match instead of every tick, and seeds the backing byte array
## fully unexplored (255) — texels whose hex is outside the map keep that
## value forever, which is also what the old per-tick rebuild computed for
## them every time.
func _build_fog_texture_tables() -> void:
	_hex_keys = PackedStringArray()
	_hex_texels = []
	var key_to_index: Dictionary = {}
	for idx in range(hexes.size()):
		var key := hexes[idx].to_key()
		_hex_keys.append(key)
		_hex_texels.append(PackedInt32Array())
		key_to_index[key] = idx
	_hex_codes = PackedInt32Array()
	_hex_codes.resize(hexes.size())
	_hex_codes.fill(-1)
	_fog_bytes = PackedByteArray()
	_fog_bytes.resize(_tex_width * _tex_height)
	_fog_bytes.fill(255)
	var span := _bounds_max - _bounds_min
	for j in range(_tex_height):
		var v := (float(j) + 0.5) / float(_tex_height)
		var py := _bounds_min.y + v * span.y
		for i in range(_tex_width):
			var u := (float(i) + 0.5) / float(_tex_width)
			var px := _bounds_min.x + u * span.x
			var hex := HexView.pixel_to_axial(Vector2(px, py))
			var idx: int = key_to_index.get(hex.to_key(), -1)
			if idx >= 0:
				_hex_texels[idx].append(j * _tex_width + i)
	_fog_image = Image.create_from_data(_tex_width, _tex_height, false, Image.FORMAT_R8, _fog_bytes)
	_fog_texture = ImageTexture.create_from_image(_fog_image)
	_material.set_shader_parameter("fog_state", _fog_texture)

## One MultiMesh per MeshInstance3D inside each cloud scene (both packs'
## clouds are a single mesh/surface today; the loop tolerates more). Each
## surface gets ONE ShaderMaterial (fog_cloud_prop.gdshader, shared Shader
## resource, per-part uniforms) instead of a duplicated BaseMaterial3D — the
## shader reads per-instance fade alpha straight off the MultiMesh COLOR
## (like vertex_color_use_as_albedo did) AND fades ALPHA toward each mesh's
## own AABB edge, which is what actually fixes overlapping instances reading
## as separate hard-edged clouds instead of one soft bank (see that shader's
## doc comment).
func _build_prop_multimeshes() -> void:
	_parts_by_variant = []
	var prop_shader: Shader = load(PROP_SHADER_PATH)
	for path in PROP_CLOUD_MESHES:
		var parts: Array = []
		var scene: PackedScene = load(path)
		if scene != null:
			var node := scene.instantiate()
			_collect_prop_parts(node, Transform3D.IDENTITY, prop_shader, parts)
			node.free()
		_parts_by_variant.append(parts)

func _collect_prop_parts(node: Node, parent_xform: Transform3D, prop_shader: Shader, out_parts: Array) -> void:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mi := node as MeshInstance3D
		var mesh: Mesh = mi.mesh.duplicate()
		var aabb := mesh.get_aabb()
		for i in range(mesh.get_surface_count()):
			var mat := mi.get_active_material(i)
			var dup := ShaderMaterial.new()
			dup.shader = prop_shader
			dup.render_priority = PROP_RENDER_PRIORITY
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				dup.set_shader_parameter("albedo_texture", (mat as BaseMaterial3D).albedo_texture)
			dup.set_shader_parameter("aabb_center", aabb.get_center())
			dup.set_shader_parameter("aabb_radius", maxf(aabb.size.length() * 0.5, 0.001))
			if mesh is ArrayMesh:
				(mesh as ArrayMesh).surface_set_material(i, dup)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_prop_root.add_child(mmi)
		out_parts.append({"mm": mm, "xform": xform})
	for child in node.get_children():
		_collect_prop_parts(child, xform, prop_shader, out_parts)

func _process(delta: float) -> void:
	if state == null:
		return
	var fog_changed := false
	if state.tick != _last_drawn_tick:
		_last_drawn_tick = state.tick
		fog_changed = _refresh_fog_texture()
	var cam_pos := camera_controller.position
	var cam_zoom := camera_controller.zoom
	var cam_moved := cam_pos.distance_to(_prop_last_cam_pos) * cam_zoom.x > PROP_CAM_REFRESH_PIXELS or cam_zoom != _prop_last_cam_zoom
	# Unlike the pre-optimization version this does NOT run on every tick —
	# only when the vision diff actually found a change (or the camera moved).
	# A tick where nobody's vision boundary moved costs just the diff itself.
	if fog_changed or cam_moved:
		_prop_last_cam_pos = cam_pos
		_prop_last_cam_zoom = cam_zoom
		_update_props()
	# Runs every frame, independent of the gate above, so alpha keeps
	# animating smoothly toward its target between vision recomputes — flat
	# packed-array walk that skips (and stops writing colors for) every
	# instance already at its target.
	_update_prop_alphas(delta)

## Camera's current visible world rect in HexView pixel space, +PROP_MARGIN_HEXES
## so props just off-screen exist before they'd scroll into view — same
## approach fog_of_war.gd's very first (per-hex) version used for exactly
## this reason.
func _prop_visible_rect() -> Rect2:
	var vp_size := get_viewport().get_visible_rect().size
	var half_extent := vp_size / (2.0 * camera_controller.zoom)
	var margin := Vector2.ONE * PROP_MARGIN_HEXES * HexView.HEX_SIZE / camera_controller.zoom
	return Rect2(camera_controller.position - half_extent - margin, (half_extent + margin) * 2.0)

## Diffs each map hex's fog code against what the texture last held and
## rewrites only changed hexes' texels (precomputed in
## _build_fog_texture_tables). Returns whether anything changed, which
## _process reuses as the "vision actually moved" signal gating prop
## placement — the diff makes that signal free. GPU upload only happens on
## a real change.
func _refresh_fog_texture() -> bool:
	var pv: PlayerVision = state.visions.get(owner_id)
	var changed := false
	for idx in range(_hex_keys.size()):
		var code := 255
		if pv != null:
			var key := _hex_keys[idx]
			if pv.visible_hexes.has(key):
				code = 0
			elif pv.explored_hexes.has(key):
				code = 128
		if _hex_codes[idx] == code:
			continue
		_hex_codes[idx] = code
		changed = true
		var texels: PackedInt32Array = _hex_texels[idx]
		for t in texels:
			_fog_bytes[t] = code
	if not changed:
		return false
	_fog_image.set_data(_tex_width, _tex_height, false, Image.FORMAT_R8, _fog_bytes)
	_fog_texture.update(_fog_image)
	return true

## Repacks the full MultiMesh buffers with the props needed inside the
## current camera view (+ margin). Cell indices are computed against the
## fixed map-wide _bounds_min origin (not relative to the viewport), so a
## given world position always maps to the same jitter/mesh-pick regardless
## of which subset is currently in range — panning away and back reproduces
## the exact same placement rather than re-rolling it. Runs only on real
## vision change or a big-enough camera move (see _process), so a wholesale
## repack (a few thousand set_instance_* calls worst case) is fine —
## dramatically cheaper than the per-node instantiate/free it replaced.
##
## A cell only gets a cloud when it sits far enough INTO unexplored territory
## that a full-size cloud's edge lands on the vision boundary rather than
## bulging back over visible/explored hexes (see _cloud_alpha_target and
## CLOUD_ERODE_HEXES). Cells over visible OR explored land get target 0 — so
## explored terrain shows through the shader plane's translucent haze instead
## of being buried under opaque clouds. In-flight fade alphas survive the
## repack via _alpha_by_cell.
func _update_props() -> void:
	if _parts_by_variant.is_empty():
		return
	var span := _bounds_max - _bounds_min
	var total_cols := int(ceil(span.x / PROP_CELL_SIZE_PIXELS))
	var total_rows := int(ceil(span.y / PROP_CELL_SIZE_PIXELS))
	var rect := _prop_visible_rect()
	var col_start := clampi(int(floor((rect.position.x - _bounds_min.x) / PROP_CELL_SIZE_PIXELS)), 0, total_cols - 1)
	var col_end := clampi(int(ceil((rect.end.x - _bounds_min.x) / PROP_CELL_SIZE_PIXELS)), 0, total_cols - 1)
	var row_start := clampi(int(floor((rect.position.y - _bounds_min.y) / PROP_CELL_SIZE_PIXELS)), 0, total_rows - 1)
	var row_end := clampi(int(ceil((rect.end.y - _bounds_min.y) / PROP_CELL_SIZE_PIXELS)), 0, total_rows - 1)
	var variant_count := _parts_by_variant.size()
	_act_cells.clear()
	_act_variant = PackedInt32Array()
	_act_target = PackedFloat32Array()
	_act_alpha = PackedFloat32Array()
	var counts := PackedInt32Array()
	counts.resize(variant_count)
	var kept_alpha: Dictionary = {}
	for cx in range(col_start, col_end + 1):
		for cy in range(row_start, row_end + 1):
			if RenderUtil.roll2d(cx, cy, SALT_PROP_SKIP) < PROP_SKIP_CHANCE:
				continue
			var cell := Vector2i(cx, cy)
			var target := _cloud_alpha_target(cell)
			var alpha: float = _alpha_by_cell.get(cell, 0.0)
			# Not needed near the boundary and (as good as) faded out — drop.
			if target <= 0.0 and alpha < ALPHA_PRUNE_THRESHOLD:
				continue
			var variant := RenderUtil.spatial_hash(cx, cy, SALT_PROP_MESH) % variant_count
			_act_cells.append(cell)
			_act_variant.append(variant)
			_act_target.append(target)
			_act_alpha.append(alpha)
			kept_alpha[cell] = alpha
			counts[variant] += 1
	_alpha_by_cell = kept_alpha ## cells that scrolled out of range or finished fading drop their fade state here
	for v in range(variant_count):
		for part in _parts_by_variant[v]:
			part["mm"].instance_count = counts[v]
	_act_slot = PackedInt32Array()
	_act_slot.resize(_act_cells.size())
	var next_slot := PackedInt32Array()
	next_slot.resize(variant_count)
	for i in range(_act_cells.size()):
		var cell := _act_cells[i]
		var variant := _act_variant[i]
		var slot := next_slot[variant]
		next_slot[variant] = slot + 1
		_act_slot[i] = slot
		var cell_xform := _cell_world_xform(cell.x, cell.y)
		var color := Color(1, 1, 1, _act_alpha[i])
		for part in _parts_by_variant[variant]:
			var mm: MultiMesh = part["mm"]
			mm.set_instance_transform(slot, cell_xform * part["xform"])
			mm.set_instance_color(slot, color)

## Deterministic world transform for a cell's cloud prop — jittered position
## on the placement grid, random-but-stable yaw/scale/height, identical on
## every client (all RenderUtil.spatial_hash-derived, no shared RNG).
func _cell_world_xform(cx: int, cy: int) -> Transform3D:
	var jitter_x := RenderUtil.roll2d(cx, cy, SALT_PROP_JITTER_X) - 0.5
	var jitter_y := RenderUtil.roll2d(cx, cy, SALT_PROP_JITTER_Y) - 0.5
	var px := _bounds_min.x + (float(cx) + 0.5 + jitter_x) * PROP_CELL_SIZE_PIXELS
	var py := _bounds_min.y + (float(cy) + 0.5 + jitter_y) * PROP_CELL_SIZE_PIXELS
	var scale := lerpf(PROP_SCALE_MIN, PROP_SCALE_MAX, RenderUtil.roll2d(cx, cy, SALT_PROP_SCALE))
	var height := lerpf(PROP_HEIGHT_MIN, PROP_HEIGHT_MAX, RenderUtil.roll2d(cx, cy, SALT_PROP_HEIGHT))
	# Clouds ride the terrain rather than sitting on one global plane: a fixed
	# height low enough to hug lowland would let hilltops (and the mountain
	# clusters on them) poke straight through the fog, but lifting the whole
	# layer to clear the highest peak instead pushes every cloud far off the
	# hex it's meant to hide — under the camera's tilt, height reads as
	# horizontal displacement (main.gd's _sync_camera_3d covers that math).
	# Offsetting per-cell by the ground beneath keeps the parallax error as
	# small as it was on the old flat map, everywhere on the map.
	height += _terrain_height_at_pixel(px, py)
	var basis := Basis(Vector3.UP, RenderUtil.angle2d(cx, cy, SALT_PROP_ROTATION)).scaled(Vector3.ONE * scale)
	var wupp := TerrainView3D.WORLD_UNITS_PER_PIXEL
	return Transform3D(basis, Vector3(px * wupp, height, py * wupp))

## Ground height under a point in HexView pixel space — a cloud prop sits on
## the placement grid, not on a hex, so it has to resolve its own hex first.
func _terrain_height_at_pixel(px: float, py: float) -> float:
	if state == null or state.grid == null:
		return 0.0
	return TerrainView3D.surface_height(state.grid, HexView.pixel_to_axial(Vector2(px, py)))

## Target alpha (0..PROP_ALPHA) for a cell's cloud prop.
## - Currently VISIBLE own hex: always 0 — never obscure live vision.
## - UNEXPLORED own hex: ramps with distance (in hexes) to the nearest
##   visible/explored hex, 0 right at the boundary to full PROP_ALPHA once
##   CLOUD_ERODE_HEXES deep. Since a scaled cloud mesh is ~CLOUD_ERODE_HEXES
##   in radius, a full-opacity cloud's CENTER sits that far into unexplored
##   land and its visible EDGE lands on the boundary — instead of a cloud
##   centered on a boundary cell overhanging its whole radius back over the
##   player's own territory.
## - EXPLORED-but-not-visible own hex: flat EXPLORED_PROP_ALPHA regardless of
##   distance to anything — sparse, mostly-transparent puffs drifting over
##   remembered terrain (not zero, not the full unexplored ramp) so that band
##   reads as actual cloud rather than being left to the flat shader plane
##   alone, and so its edge — unlike the shader plane's per-hex texture — is
##   shaped by the props' own world-space placement grid and soft-edged
##   silhouettes (fog_cloud_prop.gdshader), not the hex grid.
##
## The scanned disk of (hex key, ring distance) pairs is deterministic per
## cell and cached forever (_cell_disk_cache); the per-repack hot path is
## pure Dictionary.has, no HexCoord or String allocation.
func _cloud_alpha_target(cell: Vector2i) -> float:
	var pv: PlayerVision = state.visions.get(owner_id)
	if pv == null:
		return PROP_ALPHA ## no vision computed yet — everything is unexplored
	var disk: Array = _cell_disk_cache.get(cell, [])
	if disk.is_empty():
		disk = _build_cell_disk(cell)
		_cell_disk_cache[cell] = disk
	var keys: PackedStringArray = disk[0]
	var dists: PackedInt32Array = disk[1]
	var own_key: String = disk[2]
	if pv.visible_hexes.has(own_key):
		return 0.0
	var nearest_clear := CLOUD_ERODE_HEXES + 1.0
	for i in range(keys.size()):
		var key := keys[i]
		if pv.visible_hexes.has(key) or pv.explored_hexes.has(key):
			var d := float(dists[i])
			if d < nearest_clear:
				nearest_clear = d
				if d == 0.0:
					break ## cell's own hex is explored — the ramp bottoms out at 0, see explored check below
	var ramped := clampf(nearest_clear / CLOUD_ERODE_HEXES, 0.0, 1.0) * PROP_ALPHA
	if pv.explored_hexes.has(own_key):
		return maxf(ramped, EXPLORED_PROP_ALPHA)
	return ramped

## Every hex within ceil(CLOUD_ERODE_HEXES) of the cell's (jittered) center
## hex, paired with its ring distance, plus the center hex's own key — the
## disk _cloud_alpha_target scans for the nearest visible/explored hex, and
## own_key is checked directly for the visible/explored special cases.
## Deterministic, so computed once per cell and cached.
func _build_cell_disk(cell: Vector2i) -> Array:
	var jitter_x := RenderUtil.roll2d(cell.x, cell.y, SALT_PROP_JITTER_X) - 0.5
	var jitter_y := RenderUtil.roll2d(cell.x, cell.y, SALT_PROP_JITTER_Y) - 0.5
	var px := _bounds_min.x + (float(cell.x) + 0.5 + jitter_x) * PROP_CELL_SIZE_PIXELS
	var py := _bounds_min.y + (float(cell.y) + 0.5 + jitter_y) * PROP_CELL_SIZE_PIXELS
	var center := HexView.pixel_to_axial(Vector2(px, py))
	var keys := PackedStringArray()
	var dists := PackedInt32Array()
	for coord in HexCoord.range_within(center, int(ceil(CLOUD_ERODE_HEXES))):
		keys.append(coord.to_key())
		dists.append(HexCoord.distance(center, coord))
	return [keys, dists, center.to_key()]

## Every frame (see _process), chases each active prop's alpha toward its
## target (fixed since the last _update_props — targets can only change when
## vision changes, which triggers a repack anyway) at an exponential rate
## (FADE_TIME). Snaps to the target once within ALPHA_SNAP_EPSILON, after
## which that instance costs one float compare per frame and zero writes —
## in the steady state (nothing fading) this whole pass does no rendering
## work at all.
func _update_prop_alphas(delta: float) -> void:
	var count := _act_alpha.size()
	if count == 0:
		return
	var rate := 1.0 - exp(-delta / FADE_TIME)
	for i in range(count):
		var target := _act_target[i]
		var alpha := _act_alpha[i]
		if alpha == target:
			continue
		alpha = lerpf(alpha, target, rate)
		if absf(alpha - target) < ALPHA_SNAP_EPSILON:
			alpha = target
		_act_alpha[i] = alpha
		_alpha_by_cell[_act_cells[i]] = alpha
		var color := Color(1, 1, 1, alpha)
		var slot := _act_slot[i]
		for part in _parts_by_variant[_act_variant[i]]:
			part["mm"].set_instance_color(slot, color)
