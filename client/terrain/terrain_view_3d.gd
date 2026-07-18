## 3D terrain renderer — the Node3D counterpart to the old client/board.gd
## (deleted; see game-design/01-map-and-terrain.md for the rendering
## approach this replaces). Lives inside the SubViewport main.tscn sets up;
## positions/rotates real GLTF meshes from assets/tiles/ instead of drawing
## flat 2D polygons.
##
## Two lifecycles:
## - Static (setup(), called once): base Terrain.Type + River meshes.
##   Terrain.Type never changes after MapGenerator.generate() runs.
## - Dynamic (polled every _process, not hooked to placement call sites):
##   Road/Bridge. Infrastructure CAN change mid-match
##   (sim/bases/building_placement.gd), and in multiplayer a remote peer's
##   build arrives via LockstepDriver/CommandProcessor, never touching local
##   InputController — a call-site hook would miss every other player's
##   builds. Polls `grid.get_infrastructure` directly (the same HexGrid
##   `place_standalone_building` already wires Road/Bridge into
##   synchronously, so there's no extra indirection through
##   state.standalone_buildings needed) rather than reacting to command call
##   sites, matching how BaseView/SquadView/FogOfWar already poll off
##   MatchState.
class_name TerrainView3D
extends Node3D

const RIVER_DIR := "res://assets/tiles/rivers/"
const ROAD_DIR := "res://assets/tiles/roads/"
const BASE_DIR := "res://assets/tiles/base/"
const NATURE_DIR := "res://assets/decoration/nature/"
const PROPS_DIR := "res://assets/decoration/props/"
const BRIDGE_MESH := "res://assets/buildings/neutral/building_bridge_A.gltf"

## Terrain.Type -> base mesh, for every hex that isn't River (River always
## replaces the base tile with a river_* mesh instead — see _static_mesh_for).
## Forest/Hills sit on top of this same grass ground plate (see
## FOREST_MESHES/HILLS_MESHES below) rather than getting a dedicated ground
## mesh — this pack doesn't ship one, and stacking a decoration cluster on
## grass is how the pack's own hill/tree meshes are authored to be used.
const BASE_MESH_BY_TERRAIN := {
	Terrain.Type.PLAINS: BASE_DIR + "hex_grass.gltf",
	Terrain.Type.FOREST: BASE_DIR + "hex_grass.gltf",
	Terrain.Type.HILLS: BASE_DIR + "hex_grass.gltf",
	Terrain.Type.OCEAN: BASE_DIR + "hex_water.gltf",
}

## Forest tree clusters instanced on top of the grass ground plate, tiered
## by how deep into a contiguous forest patch a hex sits (see
## _compute_forest_depth): edge hexes (any non-Forest neighbor) get sparse
## large trees, one-hex-deep get medium, two-or-more-deep get dense small
## trees. Picking purely per-hex at random (the original approach) put a
## dense/small hex right next to a sparse/large one constantly — reads as
## noise, not a forest. Tiering by depth instead makes each contiguous
## forest patch read as one coherent stand that thickens toward its center,
## while the A/B pick within a tier still keeps neighbors from being
## textbook-identical.
const FOREST_MESHES_EDGE := [NATURE_DIR + "trees_A_large.gltf", NATURE_DIR + "trees_B_large.gltf"]
const FOREST_MESHES_MID := [NATURE_DIR + "trees_A_medium.gltf", NATURE_DIR + "trees_B_medium.gltf"]
const FOREST_MESHES_DEEP := [NATURE_DIR + "trees_A_small.gltf", NATURE_DIR + "trees_B_small.gltf"]

## Hills decoration clusters instanced on top of the grass ground plate,
## one per hex, chosen deterministically per-hex (RenderUtil.pick2d) so the
## same map always looks the same but neighboring hexes don't all render
## the identical rock cluster. Pre-built multi-rock clusters (not single
## props), so one instance per hex is enough.
const HILLS_MESHES := [
	NATURE_DIR + "hills_A.gltf", NATURE_DIR + "hills_B.gltf", NATURE_DIR + "hills_C.gltf",
	NATURE_DIR + "hills_A_trees.gltf", NATURE_DIR + "hills_B_trees.gltf", NATURE_DIR + "hills_C_trees.gltf",
]

## Sparse decoration for the remaining terrain types — rolled per-hex
## (RenderUtil.roll) against *_DECOR_CHANCE, so only a minority of hexes get
## a prop (avoids a cluttered look on the majority-Plains/Ocean map). River's
## entry is also the pragmatic fix for river hexes visually dead-ending at a
## Hills neighbor with no bank/shoreline transition: this pack has no
## land/water transition mesh (hex_transition.gltf's blend behavior is
## unconfirmed, tiles/coast/ is a separate land-vs-ocean system — both
## out of scope here, see game-design/01-map-and-terrain.md), so scattering
## shore plants along the river's edge softens the hard boundary cheaply
## rather than solving it geometrically.
const OCEAN_DECOR := [
	NATURE_DIR + "waterlily_A.gltf", NATURE_DIR + "waterlily_B.gltf",
	NATURE_DIR + "waterplant_A.gltf", NATURE_DIR + "waterplant_B.gltf", NATURE_DIR + "waterplant_C.gltf",
	PROPS_DIR + "boat.gltf",
]
const RIVER_DECOR := [
	NATURE_DIR + "waterlily_A.gltf", NATURE_DIR + "waterlily_B.gltf",
	NATURE_DIR + "waterplant_A.gltf", NATURE_DIR + "waterplant_B.gltf", NATURE_DIR + "waterplant_C.gltf",
]
const PLAINS_DECOR := [
	NATURE_DIR + "rock_single_A.gltf", NATURE_DIR + "rock_single_B.gltf", NATURE_DIR + "rock_single_C.gltf",
	NATURE_DIR + "rock_single_D.gltf", NATURE_DIR + "rock_single_E.gltf",
]
const OCEAN_DECOR_CHANCE := 0.12
const RIVER_DECOR_CHANCE := 0.20
const PLAINS_DECOR_CHANCE := 0.08

## A river hex with only one (or zero) live neighbor connections is a
## dead end (source/mouth) — the pack has no dedicated spring/waterfall
## mesh for that, so the channel just stops flat against the hex edge and
## reads as an abrupt cut. Forcing (not rolling) 2 shore props right there,
## rather than the normal RIVER_DECOR_CHANCE roll, dresses it up as a
## marshy spring/pond instead of a mechanical dead end.
const RIVER_END_DECOR_COUNT := 2

## Ground texture variety: the base atlas (hexagons_medieval.png) is a flat
## color-swatch sheet, not a detailed grass texture — there's no visible
## "grain" to add regardless of mesh choice. But the pack ships full
## seasonal recolors of that same atlas (same UV layout, different color
## grading), so swapping a hex's ground material to one of these for a
## region of hexes gives real (not just tinted) color variation — patches
## of golden/richer-green grass among the default yellow-green, instead of
## one uniform flat color. Winter's swatch is a pale near-white/blue
## (literal snow) — excluded, would read as random snow patches rather than
## natural variety. Applies to Plains/Forest/Hills (all share the hex_grass
## ground plate); not Ocean/River (separate mesh/atlas region, don't want
## autumn-tinted water).
##
## Picked from one continuous FastNoiseLite field (see _ground_noise, sampled
## in world pixel space so blobs are round rather than skewed by axial q/r)
## instead of an independent per-hex roll: a per-hex roll (the original
## approach, RenderUtil.roll2d/pick2d against these same salts) scattered
## single Fall/Summer hexes at random across the map with no relation to
## neighbors — reads as noise, and had no reason to line up with the forest/
## hills decoration clusters next to it (different RNG entirely). Sampling
## one low-frequency field instead gives contiguous biome-like patches:
## the high tail of the field (> GROUND_NOISE_FALL_THRESHOLD) is one Fall
## region, the low tail (< GROUND_NOISE_SUMMER_THRESHOLD) is one Summer
## region, everything in between (the bulk of the field) stays default —
## thresholds picked to keep roughly the same ~20%/20%/60% split the old
## per-hex chance produced, just clustered instead of scattered.
const GROUND_TEXTURE_VARIANTS := ["Fall", "Summer"]
const GROUND_NOISE_FREQUENCY := 0.0012 ## period ~830px, ~26 hexes across — large regional patches, not per-cluster speckle
const GROUND_NOISE_FALL_THRESHOLD := 0.35
const GROUND_NOISE_SUMMER_THRESHOLD := -0.35

## Independent RenderUtil.*2d salts (see RenderUtil.spatial_hash) — each
## decision below (which mesh, whether to roll at all, rotation, ground
## variant) must be decorrelated from the others for the same hex, or
## they'd all move together and still look patterned.
const SALT_FOREST_MESH := 1
const SALT_HILLS_MESH := 2
const SALT_OCEAN_ROLL := 3
const SALT_OCEAN_MESH := 4
const SALT_RIVER_ROLL := 5
const SALT_RIVER_MESH := 6
const SALT_PLAINS_ROLL := 7
const SALT_PLAINS_MESH := 8
const SALT_DECOR_ROTATION := 9
const SALT_RIVER_END_MESH := 12
const SALT_RIVER_END_OFFSET := 13

## World units per HexView pixel, and the fixed placement rotation every
## instanced mesh gets before its own per-hex rotation_steps*60 — see
## TerrainTileResolver's header for the full derivation. WORLD_HEX_CIRCUMRADIUS
## is this asset pack's own native circumradius (matches hex_grass.gltf's
## measured Z-axis extent exactly), so meshes need no rescale — placing a
## mesh unscaled already matches HexView.HEX_SIZE-driven spacing once
## positions are run through WORLD_UNITS_PER_PIXEL.
const WORLD_HEX_CIRCUMRADIUS: float = 2.0 / 1.7320508075688772 ## 2/sqrt(3), matches HexView.SQRT3
const WORLD_UNITS_PER_PIXEL: float = WORLD_HEX_CIRCUMRADIUS / 32.0 ## HexView.HEX_SIZE

## Single source of truth for the 3D camera's fixed pitch — main.gd reads
## this rather than defining its own copy (main.gd's _sync_camera_3d doc
## comment covers the ground-plane compensation this angle drives, which
## keeps the flat 2D overlay layer — grid outlines, labels, selectors —
## locked to the 3D ground at y=0). Decoration meshes need NO per-instance
## compensation: they're real 3D objects sitting on real 3D ground tiles,
## so the camera renders each cluster correctly over its own tile the same
## way it does buildings. A tall tree's crown reading higher on screen is
## honest perspective, not a misplacement.
const CAMERA_TILT_DEGREES := 18.0

var grid: HexGrid
var hexes: Array[HexCoord] = []

var _known_infrastructure: Dictionary = {} ## hex key -> Terrain.Infrastructure
var _road_nodes: Dictionary = {} ## hex key -> Node3D (the dynamic Road/Bridge instance at that hex, if any)
var _forest_depth: Dictionary = {} ## hex key -> int, see _compute_forest_depth
var _ground_noise: FastNoiseLite ## see GROUND_TEXTURE_VARIANTS' doc comment

func setup(p_grid: HexGrid, p_hexes: Array[HexCoord], p_world_seed: int = 0) -> void:
	for child in get_children():
		child.queue_free()
	_known_infrastructure.clear()
	_road_nodes.clear()
	grid = p_grid
	hexes = p_hexes
	_ground_noise = FastNoiseLite.new()
	_ground_noise.seed = p_world_seed
	_ground_noise.frequency = GROUND_NOISE_FREQUENCY
	# Default fractal (FBM, 5 octaves) layers high-frequency detail on top of
	# the base frequency — exactly the small-blob speckle GROUND_NOISE_FREQUENCY
	# alone doesn't fix, since each extra octave adds its own fine variation
	# regardless of how low the base frequency is. A single octave (no fractal
	# layering) keeps only the smooth large-scale shape.
	_ground_noise.fractal_octaves = 1
	_compute_forest_depth()
	for hex in hexes:
		_place_static(hex)
		_known_infrastructure[hex.to_key()] = Terrain.Infrastructure.NONE
		_refresh_infrastructure(hex)

## Multi-source BFS distance transform: every Forest hex with at least one
## non-Forest (or off-grid) neighbor is depth 0; everything else is 1 +
## the minimum depth of its Forest neighbors. Terrain.Type never changes
## after MapGenerator.generate() runs (same invariant _place_static's own
## header comment relies on), so this only needs computing once in setup().
func _compute_forest_depth() -> void:
	_forest_depth.clear()
	var frontier: Array[HexCoord] = []
	for hex in hexes:
		if grid.get_terrain(hex) != Terrain.Type.FOREST:
			continue
		var is_edge := false
		for n in HexCoord.neighbors(hex):
			if not grid.has_hex(n) or grid.get_terrain(n) != Terrain.Type.FOREST:
				is_edge = true
				break
		if is_edge:
			_forest_depth[hex.to_key()] = 0
			frontier.append(hex)
	var depth := 0
	while not frontier.is_empty():
		var next_frontier: Array[HexCoord] = []
		for hex in frontier:
			for n in HexCoord.neighbors(hex):
				if grid.has_hex(n) and grid.get_terrain(n) == Terrain.Type.FOREST and not _forest_depth.has(n.to_key()):
					_forest_depth[n.to_key()] = depth + 1
					next_frontier.append(n)
		frontier = next_frontier
		depth += 1

func _process(_delta: float) -> void:
	if grid == null:
		return
	for hex in hexes:
		var key := hex.to_key()
		var current := grid.get_infrastructure(hex)
		if _known_infrastructure.get(key, Terrain.Infrastructure.NONE) != current:
			_known_infrastructure[key] = current
			_refresh_infrastructure(hex)
			# This hex's own connection mask changed, but so did every Road
			# neighbor's — a neighbor's road_connection_mask reads this
			# hex's infrastructure too.
			for n in HexCoord.neighbors(hex):
				if grid.has_hex(n) and grid.get_infrastructure(n) == Terrain.Infrastructure.ROAD:
					_refresh_infrastructure(n)

func _place_static(hex: HexCoord) -> void:
	var terrain := grid.get_terrain(hex)
	var mesh_path: String
	var rotation_steps := 0
	var river_mask := 0
	if terrain == Terrain.Type.RIVER:
		river_mask = grid.river_connection_mask(hex)
		var result := TerrainTileResolver.resolve(river_mask, TerrainTileDefs.RIVER_MASKS)
		mesh_path = RIVER_DIR + result.mesh_name + ".gltf"
		rotation_steps = result.rotation_steps
	else:
		mesh_path = BASE_MESH_BY_TERRAIN.get(terrain, BASE_MESH_BY_TERRAIN[Terrain.Type.PLAINS])
	var node := _instance_mesh(mesh_path, hex, rotation_steps)
	if node == null:
		return
	if terrain == Terrain.Type.PLAINS or terrain == Terrain.Type.FOREST or terrain == Terrain.Type.HILLS:
		_maybe_swap_ground_texture(node, hex)
	add_child(node)
	_place_decoration(hex, terrain, river_mask)

## Swaps this hex's ground material to a seasonal atlas variant (see
## GROUND_TEXTURE_VARIANTS) if it falls in the Fall or Summer tail of
## _ground_noise — real color variation via a different source image, not a
## multiply-tint. Sampled in world pixel space (not raw q/r) so patches read
## as round biome blobs rather than being skewed by axial coordinates.
func _maybe_swap_ground_texture(node: Node, hex: HexCoord) -> void:
	var pixel := HexView.axial_to_pixel(hex)
	var n := _ground_noise.get_noise_2d(pixel.x, pixel.y)
	var variant: String
	if n > GROUND_NOISE_FALL_THRESHOLD:
		variant = "Fall"
	elif n < GROUND_NOISE_SUMMER_THRESHOLD:
		variant = "Summer"
	else:
		return
	var tex: Texture2D = load(BASE_DIR + "hexagons_medieval_" + variant + ".png")
	if tex == null:
		return
	_apply_ground_texture(node, tex)

func _apply_ground_texture(node: Node, tex: Texture2D) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for i in range(mesh_instance.mesh.get_surface_count()):
			var mat := mesh_instance.mesh.surface_get_material(i)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			var dup: BaseMaterial3D = mat.duplicate()
			dup.albedo_texture = tex
			mesh_instance.set_surface_override_material(i, dup)
	for child in node.get_children():
		_apply_ground_texture(child, tex)

## Adds a deterministic (per-hex, RenderUtil.*2d spatial hash — NOT a
## formatted-string hash, which visibly clustered same-variant patches
## across neighboring hexes) decoration prop on top of the base tile just
## placed, or does nothing for terrain types with no decoration table.
## Forest/Hills always get one (their base mesh alone would otherwise be
## indistinguishable flat grass); Ocean/Plains get one only on a per-hex
## probability roll, to keep the map from looking cluttered. River hexes
## get the same sparse roll UNLESS they're a dead end (river_mask popcount
## <= 1 — a source/mouth with no proper spring/waterfall mesh in this pack),
## in which case they're always heavily decorated instead, so the abrupt
## channel-just-stops look reads as a marshy spring/pond.
func _place_decoration(hex: HexCoord, terrain: Terrain.Type, river_mask: int) -> void:
	var mesh_path: String
	match terrain:
		Terrain.Type.FOREST:
			var depth: int = _forest_depth.get(hex.to_key(), 0)
			var tier := FOREST_MESHES_EDGE if depth <= 0 else (FOREST_MESHES_MID if depth == 1 else FOREST_MESHES_DEEP)
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_FOREST_MESH, tier)
		Terrain.Type.HILLS:
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_HILLS_MESH, HILLS_MESHES)
		Terrain.Type.OCEAN:
			if RenderUtil.roll2d(hex.q, hex.r, SALT_OCEAN_ROLL) >= OCEAN_DECOR_CHANCE:
				return
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_OCEAN_MESH, OCEAN_DECOR)
		Terrain.Type.RIVER:
			if TerrainTileResolver._popcount(river_mask) <= 1:
				_place_river_end_decoration(hex)
				return
			if RenderUtil.roll2d(hex.q, hex.r, SALT_RIVER_ROLL) >= RIVER_DECOR_CHANCE:
				return
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_RIVER_MESH, RIVER_DECOR)
		Terrain.Type.PLAINS:
			if RenderUtil.roll2d(hex.q, hex.r, SALT_PLAINS_ROLL) >= PLAINS_DECOR_CHANCE:
				return
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_PLAINS_MESH, PLAINS_DECOR)
		_:
			return
	var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_DECOR_ROTATION))
	if node != null:
		add_child(node)

func _place_river_end_decoration(hex: HexCoord) -> void:
	for i in range(RIVER_END_DECOR_COUNT):
		var mesh_path: String = RenderUtil.pick2d(hex.q, hex.r, SALT_RIVER_END_MESH + i, RIVER_DECOR)
		var offset := Vector2.RIGHT.rotated(RenderUtil.angle2d(hex.q, hex.r, SALT_RIVER_END_OFFSET + i)) * 0.35
		var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_DECOR_ROTATION + i))
		if node == null:
			continue
		node.position += Vector3(offset.x, 0.0, offset.y)
		add_child(node)

## Rebuilds the dynamic Road/Bridge mesh at `hex` to match its current
## Infrastructure (freeing any previous one first) — called both from
## setup() (for infrastructure already present on a freshly generated map)
## and from _process's poll loop (for infrastructure placed mid-match).
func _refresh_infrastructure(hex: HexCoord) -> void:
	var key := hex.to_key()
	var existing: Node3D = _road_nodes.get(key)
	if existing:
		existing.queue_free()
		_road_nodes.erase(key)

	var infra := grid.get_infrastructure(hex)
	var node: Node3D = null
	if infra == Terrain.Infrastructure.ROAD:
		var mask := grid.road_connection_mask(hex)
		var result := TerrainTileResolver.resolve(mask, TerrainTileDefs.ROAD_MASKS)
		node = _instance_mesh(ROAD_DIR + result.mesh_name + ".gltf", hex, result.rotation_steps)
	elif infra == Terrain.Infrastructure.BRIDGE:
		# Single non-directional mesh — known v1 cosmetic limitation (a
		# Bridge on a river corner/crossing hex won't visually match that
		# shape), see game-design/01-map-and-terrain.md. Placed at the base
		# calibration rotation only (rotation_steps=0), on top of the River
		# mesh already placed underneath by _place_static.
		node = _instance_mesh(BRIDGE_MESH, hex, 0)

	if node:
		add_child(node)
		_road_nodes[key] = node

func _instance_mesh(path: String, hex: HexCoord, rotation_steps: int) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("TerrainView3D: failed to load %s" % path)
		return null
	var node: Node3D = scene.instantiate()
	var pixel := HexView.axial_to_pixel(hex)
	node.position = Vector3(pixel.x * WORLD_UNITS_PER_PIXEL, 0.0, pixel.y * WORLD_UNITS_PER_PIXEL)
	node.rotation.y = deg_to_rad(TerrainTileResolver.ROTATION_BASE_DEGREES + 60.0 * rotation_steps)
	return node

## Same placement as _instance_mesh, but with a free (non-60°-stepped)
## Y-rotation in radians — decoration props don't need connection-mask edge
## alignment the way river/road tiles do, so a continuous random angle reads
## more natural than snapping to 6 positions.
func _instance_decor(path: String, hex: HexCoord, rotation_rad: float) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("TerrainView3D: failed to load %s" % path)
		return null
	var node: Node3D = scene.instantiate()
	var pixel := HexView.axial_to_pixel(hex)
	node.position = Vector3(pixel.x * WORLD_UNITS_PER_PIXEL, 0.0, pixel.y * WORLD_UNITS_PER_PIXEL)
	node.rotation.y = rotation_rad
	return node
