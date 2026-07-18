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
const COAST_DIR := "res://assets/tiles/coast/"
const NATURE_DIR := "res://assets/decoration/nature/"
const PROPS_DIR := "res://assets/decoration/props/"
const BRIDGE_MESH := "res://assets/buildings/neutral/building_bridge_A.gltf"

## World-space height of one HexGrid elevation level, in units where the hex
## apothem is 1.0. Freely tunable: the pack's filler and slope meshes are
## natively exactly 1.0 tall, and the placement code scales them on Y to
## whatever this is (see _place_elevation_skirt), so they stay flush at any
## step height rather than being pinned to the authored geometry.
##
## Deliberately well above 1.0. The camera looks almost straight down (only
## CAMERA_TILT_DEGREES off vertical), which compresses vertical relief hard on
## screen — at a 1.0 step, a full two-level plateau was nearly indistinguishable
## from flat ground in practice. Raising it is the whole reason hills read as
## height rather than as a texture change. The cost is that the flat 2D overlay
## layer (grid outlines, selection rings) is anchored at y=0 and drifts further
## from raised tiles the taller this gets, so it can't grow without limit.
const WORLD_UNITS_PER_ELEVATION: float = 1.5

## Stackable filler block placed under a raised plate, one per level below it,
## so an elevated hex reads as a solid column of earth rather than a slab
## hovering over a hole. The pack's plates only model their own top ~1 unit;
## without this you see straight under a hill from a low camera angle.
const GROUND_BOTTOM_MESH := BASE_DIR + "hex_grass_bottom.gltf"

## Ramp surface for a raised hex that has a neighbour exactly one level below
## it (see _ramp_low_direction). Its high edge is the mesh's local direction 0,
## which — per TerrainTileResolver's calibration — points toward
## HexCoord.DIRECTIONS[rotation_steps] once placed. So rotating by the
## direction OPPOSITE the low neighbour tilts the surface down toward that
## neighbour, physically connecting the two levels.
const GROUND_SLOPE_MESH := BASE_DIR + "hex_grass_sloped_high.gltf"

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
## Split by height, on top of the ground plate already being physically raised
## (see WORLD_UNITS_PER_ELEVATION): the rim ring keeps the modest hills_*
## mounds, while the interior plateau gets the pack's much larger mountain_*
## meshes. The raised plate alone reads as a flat mesa — putting genuinely
## bigger geometry on the high tiles is what makes a hill range look like it
## climbs rather than just steps up once.
const HILLS_MESHES := [
	NATURE_DIR + "hills_A.gltf", NATURE_DIR + "hills_B.gltf", NATURE_DIR + "hills_C.gltf",
	NATURE_DIR + "hills_A_trees.gltf", NATURE_DIR + "hills_B_trees.gltf", NATURE_DIR + "hills_C_trees.gltf",
]
const PEAK_MESHES := [
	NATURE_DIR + "mountain_A.gltf", NATURE_DIR + "mountain_B.gltf", NATURE_DIR + "mountain_C.gltf",
	NATURE_DIR + "mountain_A_grass.gltf", NATURE_DIR + "mountain_B_grass.gltf", NATURE_DIR + "mountain_C_grass.gltf",
	NATURE_DIR + "mountain_A_grass_trees.gltf", NATURE_DIR + "mountain_B_grass_trees.gltf",
	NATURE_DIR + "mountain_C_grass_trees.gltf",
]

## Extra uniform scale for hill/mountain clusters, on top of the elevation the
## plate underneath already provides. The pack authors these as props sized to
## sit unobtrusively on a flat tile; at 1.0 they read as pebbles once the tile
## itself is a level or two up. Kept modest — much past this a cluster starts
## visibly overhanging its own hex's edges onto the neighbour.
## The mountain_* meshes are already ~1.5x the height of the hills_* mounds
## before any scaling, so the peak tier needs far less help than the rim does.
## Both are capped by FogOfWar.PROP_HEIGHT_MIN, which has to stay above the
## tallest thing on the map or hilltops poke through the fog.
const HILLS_DECOR_SCALE := 1.35
const PEAK_DECOR_SCALE := 1.15

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
## Plains is the majority terrain, so an empty grass plate is what the player
## stares at most of the match. Every Plains hex now gets scatter rather than
## the old sparse 8% single-rock roll, which left the map reading as a bare
## board with an occasional pebble.
##
## Three things make that survivable at full coverage instead of cluttered:
## the props are drawn from a genuinely mixed table (lone trees, cut stumps,
## grassy mounds, boulders — not five near-identical rocks); each one is
## pushed out toward the hex's rim rather than sitting on the center, which is
## where troop/building sprites and selection rings live; and the per-hex count
## is itself rolled, so hexes vary between one prop and a small cluster.
## hill_single_A/B/C are deliberately NOT in this table despite being the
## obvious "small nature prop" candidates: the pack models them as miniature
## hexagonal mounds with their own dirt-colored side walls, so scattered across
## Plains they read as broken/half-sunk terrain tiles rather than as scenery —
## verified on screen, they were indistinguishable from a tile-placement bug.
## They belong on Hills, where HILLS_MESHES already covers that shape.
const PLAINS_DECOR := [
	NATURE_DIR + "rock_single_A.gltf", NATURE_DIR + "rock_single_B.gltf", NATURE_DIR + "rock_single_C.gltf",
	NATURE_DIR + "rock_single_D.gltf", NATURE_DIR + "rock_single_E.gltf",
	NATURE_DIR + "tree_single_A.gltf", NATURE_DIR + "tree_single_B.gltf",
	NATURE_DIR + "tree_single_A_cut.gltf", NATURE_DIR + "tree_single_B_cut.gltf",
	NATURE_DIR + "trees_A_small.gltf", NATURE_DIR + "trees_B_small.gltf",
]

## Ocean/River keep a sparse roll — open water wants to stay readable, and
## these tables are small and repetitive enough that full coverage would
## obviously tile.
const OCEAN_DECOR_CHANCE := 0.12
const RIVER_DECOR_CHANCE := 0.20

## Props per Plains hex, picked per-hex from this inclusive range.
const PLAINS_DECOR_MIN_COUNT := 1
const PLAINS_DECOR_MAX_COUNT := 3

## Where a scattered prop sits, as a fraction of the hex apothem (~1.0 world
## unit) from the center. The floor is what keeps decor off the middle of the
## tile — the ceiling keeps it from straddling the boundary onto a neighbour.
const PLAINS_DECOR_MIN_RADIUS := 0.42
const PLAINS_DECOR_MAX_RADIUS := 0.78

## Per-prop scale jitter, so a cluster doesn't read as the same asset stamped
## twice at the same size.
const PLAINS_DECOR_MIN_SCALE := 0.7
const PLAINS_DECOR_MAX_SCALE := 1.15

## A river hex with only one (or zero) live neighbor connections is a
## dead end (source/mouth). The pack has no dedicated spring/waterfall mesh,
## so TerrainTileResolver falls back to the straight-through 2-connection
## mesh — the channel then visibly runs off the edge OPPOSITE the real
## connection, into a land neighbor, reading as an abrupt cut. Rather than
## the normal RIVER_DECOR_CHANCE roll, force a cluster of shore props aimed
## squarely at that dead-end edge to plug the channel mouth, so it reads as a
## marshy spring/pond instead of a mechanical stop.
const RIVER_END_DECOR_COUNT := 3
const RIVER_END_EDGE_OFFSET := 0.8 ## world units from hex center toward the dead-end edge (hex apothem is ~1.0 world unit) — puts the props over the channel mouth
const RIVER_END_EDGE_SPREAD := 0.55 ## world units the cluster fans out ALONG the edge, so it covers the full channel width rather than a single point

## River banks. Every edge where a River hex meets land is a hard seam between
## the channel mesh and a grass plate — the pack has no land/water transition
## tile, so previously a river just butted straight up against the grass. These
## props are laid ALONG that seam (on the river side of it, fanned across the
## edge the way _place_river_end_decoration lays out a channel mouth) to read
## as a reedy, silted bank. Placed per river-to-land edge rather than per hex,
## so a river running between two land hexes gets banks on both sides and a
## river flowing into open ocean correctly gets none.
##
## Deliberately not rolled against a chance: a bank that appears on only some
## edges reads as an error rather than as variety. The variation comes from
## which props are picked and how they're jittered along the seam.
const RIVER_BANK_DECOR := [
	NATURE_DIR + "waterplant_A.gltf", NATURE_DIR + "waterplant_B.gltf", NATURE_DIR + "waterplant_C.gltf",
	NATURE_DIR + "rock_single_A.gltf", NATURE_DIR + "rock_single_D.gltf",
]
const RIVER_BANK_PROPS_PER_EDGE := 2
const RIVER_BANK_EDGE_OFFSET := 0.62 ## world units from hex center toward the land edge — inside the hex, hugging the seam
const RIVER_BANK_EDGE_SPREAD := 0.7 ## world units the props fan out along the seam
const RIVER_BANK_JITTER := 0.12 ## world units of per-prop wobble, so the bank isn't a ruler-straight line of props
const RIVER_BANK_SCALE := 0.8 ## bank props read as undergrowth, not as full-size features

## A ramp's visible surface runs from the low neighbour's height at one edge up
## to this hex's own at the other, so anything standing on it belongs at the
## midpoint rather than at either end — half a level below the flat height
## surface_height reports for the hex.
const RAMP_DECOR_DROP := WORLD_UNITS_PER_ELEVATION * 0.5

## Coastal beaches. Any lowland land hex touching Ocean swaps its flat grass
## plate for one of the pack's coast tiles (assets/tiles/coast/), which model
## a sand shelf running down into the water on whichever edges face the sea —
## resolved from an Ocean-neighbour connection mask through the same
## TerrainTileResolver the river/road tiles use (see TerrainTileDefs.
## COAST_MASKS for why the sparse mesh set is fine).
##
## Gated on elevation 0: a raised hex meeting the sea is a headland dropping
## into the water, and flattening it to a beach plate would both lose the
## height and leave the cliff column underneath poking through the sand. Those
## keep their normal raised plate, which is exactly the "unless there are hills
## there" carve-out.
const COAST_MESH_PREFIX := COAST_DIR + "hex_coast_"

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
## SALT_RIVER_END_* are each used as `+i` over RIVER_END_DECOR_COUNT
## iterations, so 12-14 and 13-15 are all effectively consumed. New salts
## start at 20 to stay clear of that, and the per-prop scatter salts below
## are spaced 100 apart for the same reason (each is used as `+i` over up to
## PLAINS_DECOR_MAX_COUNT iterations).
const SALT_PLAINS_COUNT := 20
const SALT_PLAINS_SCATTER_MESH := 100
const SALT_PLAINS_SCATTER_ANGLE := 200
const SALT_PLAINS_SCATTER_RADIUS := 300
const SALT_PLAINS_SCATTER_SCALE := 400
const SALT_BANK_MESH := 500
const SALT_BANK_JITTER := 600

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
## hex key -> world Y that decoration on that hex should sit at. Cached during
## _place_static rather than recomputed, because a ramp's decor height isn't
## derivable from elevation alone (see RAMP_DECOR_DROP) — it depends on which
## mesh the placement pass actually chose for the plate.
var _decor_y: Dictionary = {}
var _ground_noise: FastNoiseLite ## see GROUND_TEXTURE_VARIANTS' doc comment

func setup(p_grid: HexGrid, p_hexes: Array[HexCoord], p_world_seed: int = 0) -> void:
	for child in get_children():
		child.queue_free()
	_known_infrastructure.clear()
	_road_nodes.clear()
	_decor_y.clear()
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

## World Y of the top surface of the ground plate at `hex` — the height every
## decoration, building and overlay on that hex has to sit at. Static so
## BuildingView3D/InputController can ask the same question without needing a
## TerrainView3D instance; `p_grid` rather than the member so it's callable
## before setup() has run.
static func surface_height(p_grid: HexGrid, hex: HexCoord) -> float:
	if p_grid == null:
		return 0.0
	return float(p_grid.get_elevation(hex)) * WORLD_UNITS_PER_ELEVATION

## Full world position of a hex's ground surface — the one place the
## pixel->world conversion and the elevation lookup are combined, so callers
## can't accidentally place something at the right XZ and the wrong height.
static func hex_to_world(p_grid: HexGrid, hex: HexCoord) -> Vector3:
	var pixel := HexView.axial_to_pixel(hex)
	return Vector3(pixel.x * WORLD_UNITS_PER_PIXEL, surface_height(p_grid, hex), pixel.y * WORLD_UNITS_PER_PIXEL)

## Direction index (into HexCoord.DIRECTIONS) of a neighbour exactly one
## elevation level below `hex`, or -1 if there is none. That's what makes this
## hex a ramp: it's the edge the ground actually slopes down across, and the
## edge ground troops are able to climb (a two-level drop is a cliff, which
## stays a sheer column — see Terrain.CLIFF_ELEVATION_DELTA).
##
## When several neighbours qualify, the lowest direction index wins rather than
## a random pick: a hex can only tilt one way, and choosing deterministically
## by index keeps the choice stable across clients without burning a salt.
func _ramp_low_direction(hex: HexCoord) -> int:
	var elevation := grid.get_elevation(hex)
	if elevation <= 0:
		return -1
	for i in range(HexCoord.DIRECTIONS.size()):
		var n := HexCoord.neighbor(hex, i)
		if grid.has_hex(n) and grid.get_elevation(n) == elevation - 1:
			return i
	return -1

## True iff this hex is lowland land directly touching Ocean — the beach case.
## River is excluded (it gets banks instead, see RIVER_BANK_DECOR) and so is
## anything raised, per COAST_MESH_PREFIX's doc comment.
func _is_beach(hex: HexCoord, terrain: Terrain.Type) -> bool:
	if grid.get_elevation(hex) != 0:
		return false
	if terrain != Terrain.Type.PLAINS and terrain != Terrain.Type.FOREST and terrain != Terrain.Type.HILLS:
		return false
	return _ocean_connection_mask(hex) != 0

func _ocean_connection_mask(hex: HexCoord) -> int:
	return grid.connection_mask(hex, func(n: HexCoord) -> bool: return grid.has_hex(n) and grid.get_terrain(n) == Terrain.Type.OCEAN)

func _place_static(hex: HexCoord) -> void:
	var terrain := grid.get_terrain(hex)
	var elevation := grid.get_elevation(hex)
	var mesh_path: String
	var rotation_steps := 0
	var river_mask := 0
	var plate_y := float(elevation) * WORLD_UNITS_PER_ELEVATION
	if terrain == Terrain.Type.RIVER:
		river_mask = grid.river_connection_mask(hex)
		var result := TerrainTileResolver.resolve(river_mask, TerrainTileDefs.RIVER_MASKS)
		mesh_path = RIVER_DIR + result.mesh_name + ".gltf"
		rotation_steps = result.rotation_steps
	elif _is_beach(hex, terrain):
		var coast := TerrainTileResolver.resolve(_ocean_connection_mask(hex), TerrainTileDefs.COAST_MASKS)
		mesh_path = COAST_DIR + coast.mesh_name + ".gltf"
		rotation_steps = coast.rotation_steps
	else:
		var low_dir := _ramp_low_direction(hex)
		if low_dir >= 0:
			# A ramp bridges two levels: the slope mesh spans from the low
			# neighbour's height up to this hex's own, so it's seated one level
			# down and rotated so its high edge points away from that neighbour.
			mesh_path = GROUND_SLOPE_MESH
			rotation_steps = (low_dir + 3) % 6
			plate_y -= WORLD_UNITS_PER_ELEVATION
		else:
			mesh_path = BASE_MESH_BY_TERRAIN.get(terrain, BASE_MESH_BY_TERRAIN[Terrain.Type.PLAINS])
	var node := _instance_mesh(mesh_path, hex, rotation_steps, plate_y)
	if node == null:
		return
	var is_ramp := mesh_path == GROUND_SLOPE_MESH
	if is_ramp:
		# Authored to rise exactly 1.0 above its own flat top; scaling on Y
		# makes it bridge one WORLD_UNITS_PER_ELEVATION step instead.
		node.scale.y = WORLD_UNITS_PER_ELEVATION
	if terrain != Terrain.Type.OCEAN and terrain != Terrain.Type.RIVER:
		_maybe_swap_ground_texture(node, hex)
	add_child(node)
	# Underside of what was just placed: a flat plate's body is 1.0 tall, a
	# scaled ramp's reaches a full step below its seat.
	_place_elevation_skirt(hex, plate_y - (WORLD_UNITS_PER_ELEVATION if is_ramp else 1.0))
	# On a ramp the plate was seated a level down and slopes back up across the
	# hex, so decor belongs at the mid-surface, not at either end of the slope.
	var decor_y := surface_height(grid, hex)
	if mesh_path == GROUND_SLOPE_MESH:
		decor_y -= RAMP_DECOR_DROP
	_decor_y[hex.to_key()] = decor_y
	_place_decoration(hex, terrain, river_mask)
	if terrain == Terrain.Type.RIVER:
		_place_river_banks(hex)

## Fills the column between `fill_top` (the underside of whatever plate was
## just placed) and the sea floor with GROUND_BOTTOM_MESH blocks. Each plate
## models only its own top slice of earth, so without this you see clean
## through a hill from a low camera angle and a cliff face has nothing to
## actually be the face of.
##
## Blocks are stacked downward from `fill_top` and scaled on Y to
## WORLD_UNITS_PER_ELEVATION (they're authored 1.0 tall), so the column stays
## seamless at any step height. The last one usually overshoots below sea
## level, which is invisible and cheaper than special-casing a partial block.
func _place_elevation_skirt(hex: HexCoord, fill_top: float) -> void:
	var depth := fill_top + 1.0 ## sea floor is at local -1.0, matching every plate's own base
	if depth <= 0.0:
		return
	var count := int(ceil(depth / WORLD_UNITS_PER_ELEVATION))
	for i in range(count):
		var block := _instance_mesh(GROUND_BOTTOM_MESH, hex, 0, fill_top - float(i) * WORLD_UNITS_PER_ELEVATION)
		if block == null:
			return
		block.scale.y = WORLD_UNITS_PER_ELEVATION
		# Deliberately NOT run through _maybe_swap_ground_texture: this is the
		# exposed rock face of a cliff/hillside, not a grass surface. Tinting it
		# to an autumn or summer *grass* swatch made cliff walls read as pale
		# painted bands rather than as earth, and made one hill's face differ in
		# colour from its neighbour's for no readable reason.
		add_child(block)

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
	var scale := 1.0
	match terrain:
		Terrain.Type.FOREST:
			var depth: int = _forest_depth.get(hex.to_key(), 0)
			var tier := FOREST_MESHES_EDGE if depth <= 0 else (FOREST_MESHES_MID if depth == 1 else FOREST_MESHES_DEEP)
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_FOREST_MESH, tier)
		Terrain.Type.HILLS:
			# Rim hexes keep the modest mounds; the raised interior gets the
			# pack's mountain meshes, so a range visibly climbs toward its
			# middle instead of being a uniform ring of identical bumps.
			if grid.get_elevation(hex) >= Tuning.HILLS_PEAK_ELEVATION:
				mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_HILLS_MESH, PEAK_MESHES)
				scale = PEAK_DECOR_SCALE
			else:
				mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_HILLS_MESH, HILLS_MESHES)
				scale = HILLS_DECOR_SCALE
		Terrain.Type.OCEAN:
			if RenderUtil.roll2d(hex.q, hex.r, SALT_OCEAN_ROLL) >= OCEAN_DECOR_CHANCE:
				return
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_OCEAN_MESH, OCEAN_DECOR)
		Terrain.Type.RIVER:
			if TerrainTileResolver._popcount(river_mask) <= 1:
				_place_river_end_decoration(hex, river_mask)
				return
			if RenderUtil.roll2d(hex.q, hex.r, SALT_RIVER_ROLL) >= RIVER_DECOR_CHANCE:
				return
			mesh_path = RenderUtil.pick2d(hex.q, hex.r, SALT_RIVER_MESH, RIVER_DECOR)
		Terrain.Type.PLAINS:
			_place_plains_scatter(hex)
			return
		_:
			return
	var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_DECOR_ROTATION), _hex_decor_y(hex))
	if node == null:
		return
	if scale != 1.0:
		node.scale = Vector3.ONE * scale
	add_child(node)

## World Y decoration on this hex should sit at — see _decor_y. Falls back to
## the flat elevation height for a hex _place_static hasn't reached yet.
func _hex_decor_y(hex: HexCoord) -> float:
	return _decor_y.get(hex.to_key(), surface_height(grid, hex))

## Scatters PLAINS_DECOR_MIN_COUNT..MAX_COUNT props around the rim of a Plains
## hex — see PLAINS_DECOR for why Plains gets full coverage rather than the
## sparse roll every other terrain uses.
##
## Every per-prop property (which mesh, angle, distance from center, scale)
## draws from its own RenderUtil salt offset by the prop index, so two props on
## the same hex don't land on top of each other and two hexes with the same
## prop count don't produce the same arrangement. Angles are spread by an even
## share of the circle plus a per-prop jitter rather than being fully random:
## three independent random angles clump into one corner of the hex often
## enough to look like a bug.
func _place_plains_scatter(hex: HexCoord) -> void:
	var span := PLAINS_DECOR_MAX_COUNT - PLAINS_DECOR_MIN_COUNT + 1
	var count := PLAINS_DECOR_MIN_COUNT + int(RenderUtil.roll2d(hex.q, hex.r, SALT_PLAINS_COUNT) * span)
	count = mini(count, PLAINS_DECOR_MAX_COUNT)
	var base_angle := RenderUtil.angle2d(hex.q, hex.r, SALT_PLAINS_ROLL)
	for i in range(count):
		var mesh_path: String = RenderUtil.pick2d(hex.q, hex.r, SALT_PLAINS_SCATTER_MESH + i, PLAINS_DECOR)
		var jitter := RenderUtil.roll2d(hex.q, hex.r, SALT_PLAINS_SCATTER_ANGLE + i) - 0.5
		var angle := base_angle + TAU * (float(i) / float(count) + jitter / float(count))
		var radius: float = lerp(PLAINS_DECOR_MIN_RADIUS, PLAINS_DECOR_MAX_RADIUS, RenderUtil.roll2d(hex.q, hex.r, SALT_PLAINS_SCATTER_RADIUS + i))
		var offset := Vector2.RIGHT.rotated(angle) * radius
		var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_DECOR_ROTATION + i), _hex_decor_y(hex))
		if node == null:
			continue
		node.position += Vector3(offset.x, 0.0, offset.y)
		node.scale = Vector3.ONE * lerp(PLAINS_DECOR_MIN_SCALE, PLAINS_DECOR_MAX_SCALE, RenderUtil.roll2d(hex.q, hex.r, SALT_PLAINS_SCATTER_SCALE + i))
		add_child(node)

## Lays RIVER_BANK_PROPS_PER_EDGE shore props along each edge where this River
## hex meets land — see RIVER_BANK_DECOR for why. Props sit inside the river
## hex, hugging the seam, fanned across it so the whole edge is covered rather
## than a single point of it.
func _place_river_banks(hex: HexCoord) -> void:
	var center := HexView.axial_to_pixel(hex)
	var y := _hex_decor_y(hex)
	for dir in range(HexCoord.DIRECTIONS.size()):
		var n := HexCoord.neighbor(hex, dir)
		if not grid.has_hex(n):
			continue
		var neighbor_terrain := grid.get_terrain(n)
		if neighbor_terrain == Terrain.Type.RIVER or neighbor_terrain == Terrain.Type.OCEAN:
			continue
		var edge_dir := (HexView.axial_to_pixel(n) - center).normalized()
		var along := Vector2(-edge_dir.y, edge_dir.x)
		for i in range(RIVER_BANK_PROPS_PER_EDGE):
			var salt := dir * RIVER_BANK_PROPS_PER_EDGE + i
			var mesh_path: String = RenderUtil.pick2d(hex.q, hex.r, SALT_BANK_MESH + salt, RIVER_BANK_DECOR)
			var t := float(i) / float(maxi(RIVER_BANK_PROPS_PER_EDGE - 1, 1)) - 0.5 ## -0.5..0.5 across the edge
			var wobble := (RenderUtil.roll2d(hex.q, hex.r, SALT_BANK_JITTER + salt) - 0.5) * 2.0 * RIVER_BANK_JITTER
			var offset := edge_dir * (RIVER_BANK_EDGE_OFFSET + wobble) + along * t * RIVER_BANK_EDGE_SPREAD
			var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_BANK_JITTER + salt), y)
			if node == null:
				continue
			node.position += Vector3(offset.x, 0.0, offset.y)
			node.scale = Vector3.ONE * RIVER_BANK_SCALE
			add_child(node)

## Plugs the abrupt channel mouth of a dead-end river hex (see
## RIVER_END_DECOR_COUNT). The dead-end edge is the one OPPOSITE the hex's
## single real connection — that's where the straight fallback mesh's channel
## runs off into land. Props are laid across that edge (offset toward it +
## fanned along it) rather than scattered randomly, so they actually cover the
## visible cut. An isolated river hex (0 connections — no direction to aim at)
## falls back to a centered scatter, the old behavior.
func _place_river_end_decoration(hex: HexCoord, river_mask: int) -> void:
	var dead_dir := _river_dead_end_dir(river_mask)
	var edge_dir := Vector2.ZERO
	var along := Vector2.ZERO
	if dead_dir >= 0:
		var nb := HexCoord.neighbor(hex, dead_dir)
		edge_dir = (HexView.axial_to_pixel(nb) - HexView.axial_to_pixel(hex)).normalized()
		along = Vector2(-edge_dir.y, edge_dir.x)
	for i in range(RIVER_END_DECOR_COUNT):
		var mesh_path: String = RenderUtil.pick2d(hex.q, hex.r, SALT_RIVER_END_MESH + i, RIVER_DECOR)
		var offset: Vector2
		if dead_dir >= 0:
			var t := float(i) / float(maxi(RIVER_END_DECOR_COUNT - 1, 1)) - 0.5 ## -0.5..0.5 across the edge
			offset = edge_dir * RIVER_END_EDGE_OFFSET + along * t * RIVER_END_EDGE_SPREAD
		else:
			offset = Vector2.RIGHT.rotated(RenderUtil.angle2d(hex.q, hex.r, SALT_RIVER_END_OFFSET + i)) * 0.35
		var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_DECOR_ROTATION + i), _hex_decor_y(hex))
		if node == null:
			continue
		node.position += Vector3(offset.x, 0.0, offset.y)
		add_child(node)

## The dead-end edge direction (index into HexCoord.DIRECTIONS) of a river hex
## whose fallback mesh is a straight channel: the edge OPPOSITE its single
## real connection. Returns -1 for a 0-connection (isolated) hex, which has no
## meaningful direction to aim at.
func _river_dead_end_dir(river_mask: int) -> int:
	if TerrainTileResolver._popcount(river_mask) != 1:
		return -1
	for i in range(6):
		if river_mask & (1 << i) != 0:
			return (i + 3) % 6
	return -1

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
	# Road/Bridge sit on top of whatever plate is already at this hex, so they
	# take the hex's own surface height rather than sea level.
	var infra_y := _hex_decor_y(hex)
	if infra == Terrain.Infrastructure.ROAD:
		var mask := grid.road_connection_mask(hex)
		var result := TerrainTileResolver.resolve(mask, TerrainTileDefs.ROAD_MASKS)
		node = _instance_mesh(ROAD_DIR + result.mesh_name + ".gltf", hex, result.rotation_steps, infra_y)
	elif infra == Terrain.Infrastructure.BRIDGE:
		# Single non-directional mesh — known v1 cosmetic limitation (a
		# Bridge on a river corner/crossing hex won't visually match that
		# shape), see game-design/01-map-and-terrain.md. Placed at the base
		# calibration rotation only (rotation_steps=0), on top of the River
		# mesh already placed underneath by _place_static.
		node = _instance_mesh(BRIDGE_MESH, hex, 0, infra_y)

	if node:
		add_child(node)
		_road_nodes[key] = node

## `world_y` is the height to seat the mesh at — 0.0 for a lowland tile, one
## WORLD_UNITS_PER_ELEVATION per level for a raised one, and one level lower
## again for a ramp (whose mesh spans two levels). Callers pass it explicitly
## rather than having it derived here, because the skirt blocks under a raised
## plate deliberately sit at heights that aren't the hex's own surface.
func _instance_mesh(path: String, hex: HexCoord, rotation_steps: int, world_y: float = 0.0) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("TerrainView3D: failed to load %s" % path)
		return null
	var node: Node3D = scene.instantiate()
	var pixel := HexView.axial_to_pixel(hex)
	node.position = Vector3(pixel.x * WORLD_UNITS_PER_PIXEL, world_y, pixel.y * WORLD_UNITS_PER_PIXEL)
	node.rotation.y = deg_to_rad(TerrainTileResolver.ROTATION_BASE_DEGREES + 60.0 * rotation_steps)
	return node

## Same placement as _instance_mesh, but with a free (non-60°-stepped)
## Y-rotation in radians — decoration props don't need connection-mask edge
## alignment the way river/road tiles do, so a continuous random angle reads
## more natural than snapping to 6 positions.
func _instance_decor(path: String, hex: HexCoord, rotation_rad: float, world_y: float = 0.0) -> Node3D:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("TerrainView3D: failed to load %s" % path)
		return null
	var node: Node3D = scene.instantiate()
	var pixel := HexView.axial_to_pixel(hex)
	node.position = Vector3(pixel.x * WORLD_UNITS_PER_PIXEL, world_y, pixel.y * WORLD_UNITS_PER_PIXEL)
	node.rotation.y = rotation_rad
	return node
