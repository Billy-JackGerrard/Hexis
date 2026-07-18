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

## Extra depth Ocean/River plates are seated at, below lowland ground. The pack
## already models its water surface slightly recessed (the water mesh's top face
## sits at -0.2 where a grass plate's is at 0.0), which is enough to stop them
## z-fighting but not enough to read as water sitting *in* the land — the
## coastline looked like a colour change rather than an edge. Dropping the plate
## further makes the shoreline and river banks into visible lips you look down
## over, which is also what makes the beach tiles' sand shelf read as sloping
## into something.
##
## Deliberately small. Land plates only model their own top 1.0 unit, so past
## roughly that the water surface would clear the bottom of the land beside it
## and you would see under the coast at grazing angles. This is a purely visual
## offset — HexGrid elevation for water stays 0, so no movement cost, cliff
## check, or vision sightline is affected by it.
const WATER_SURFACE_DROP := 0.3

## Procedural surface-detail shader applied to every land ground plate — see
## the shader file's own header for what it does and why the noise is evaluated
## in world space. This is what replaced the Plains prop scatter.
const GROUND_DETAIL_SHADER := "res://client/terrain/ground_detail.gdshader"

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
## forest patch read as one coherent stand that thickens toward its center.
##
## SPECIES (the A/B axis) is chosen per *patch*, not per hex — see
## _compute_forest_patches. A real wood is one kind of tree; mixing A and B
## hex-by-hex within a single stand made it read as two different forests
## overlapping rather than one, which is exactly the noise the depth tiering
## was introduced to remove. Neighbouring but separate patches still differ,
## since they get their own independent pick.
const FOREST_SPECIES := ["A", "B"]
const FOREST_MESH_BY_DEPTH := ["large", "medium", "small"] ## index = depth tier, see _compute_forest_depth

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
## River props are reeds only — no waterlilies and no rocks. Anything sitting
## in open channel reads as something in the water's way, and a River hex is a
## movement decision (Naval highway, ground block unless bridged), so that
## reading is actively misleading. Reeds along the edge say "bank"; a boulder
## mid-channel says "obstacle".
const RIVER_DECOR := [
	NATURE_DIR + "waterplant_A.gltf", NATURE_DIR + "waterplant_B.gltf", NATURE_DIR + "waterplant_C.gltf",
]
## Plains carries NO scattered props at all. An earlier pass gave every Plains
## hex one-to-three rocks/trees/stumps to fix "the majority terrain is a bare
## plate" — and it did fix that, but the result read as clutter: Plains is most
## of the map, so per-hex props strewed the whole board with small objects that
## competed with the things the player actually has to read (squads, buildings,
## selection rings, order feedback) and made real, meaningful obstacles harder
## to pick out at a glance.
##
## The boredom that scatter was solving is a *surface* problem, so it's solved
## on the surface instead — see GROUND_DETAIL_SHADER, which gives the plate
## visible grain and colour break-up without putting anything on the board.
##
## Ocean/River keep their sparse rolls: those are a small minority of hexes, so
## a lily pad or a moored boat every few tiles reads as detail, not litter.
const OCEAN_DECOR_CHANCE := 0.12

## A river hex with only one (or zero) live neighbor connections is a
## dead end (source/mouth). The pack has no dedicated spring/waterfall mesh,
## so TerrainTileResolver falls back to the straight-through 2-connection
## mesh — the channel then visibly runs off the edge OPPOSITE the real
## connection, into a land neighbor, reading as an abrupt cut. Rather than
## any per-hex roll, force a cluster of shore props aimed
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
## Reeds only, same reasoning as RIVER_DECOR: the rock_single_* props that used
## to be in this table were the single biggest source of "the river is full of
## obstacles" — scattered boulders along both banks of every river on the map
## read as debris strewn through the channel rather than as a shoreline.
const RIVER_BANK_DECOR := [
	NATURE_DIR + "waterplant_A.gltf", NATURE_DIR + "waterplant_B.gltf", NATURE_DIR + "waterplant_C.gltf",
]
## Cut back after "not liking the reeds on the riverbanks" — at 2-per-edge and
## offset 0.72 (close to the land-facing edge) every river-to-land seam grew a
## near-continuous hedge that read as its own feature rather than as a light
## fringe. Fewer props, and moved back toward the water (down from 0.72): they
## were sitting close enough to the land edge to visually blend into the
## neighbouring grass hex's own decor instead of reading as part of the river.
const RIVER_BANK_PROPS_PER_EDGE := 1
const RIVER_BANK_EDGE_OFFSET := 0.5 ## world units from hex center toward the land edge
const RIVER_BANK_EDGE_SPREAD := 0.7 ## world units the props fan out along the seam
const RIVER_BANK_JITTER := 0.12 ## world units of per-prop wobble, so the bank isn't a ruler-straight line of props
const RIVER_BANK_SCALE := 0.55 ## smaller too, on top of fewer — a light fringe, not a hedge

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

## An earlier version blended the OCEAN side of a shoreline too, via the
## pack's hex_transition.gltf seated on the water hex facing the land it
## touched. Removed: every land hex touching Ocean at elevation 0 already
## qualifies as a beach (_is_beach's ocean-connection check is unconditional),
## so it already gets a COAST_MESH_PREFIX shelf mesh dipping toward the water
## on that exact edge — the ocean-side piece was drawing a SECOND, separately
## authored dip right against the first, and the two shapes don't share a
## profile, so the seam between them showed as a visible crack/step at any
## oblique tilt (reported as "the hex transition thing looks bad on the
## ocean because it doesn't sync up") even after an earlier pass fixed the
## literal Z-fight from placing it alongside the plain water plate. The only
## land-Ocean edges with no coast mesh on the land side are raised (cliff)
## hexes, per COAST_MESH_PREFIX's elevation-0 gate — and a sheer cliff base
## meeting flush open water needs no sand blend; that's just what a rocky
## coastline looks like. So every case is already covered by one mesh or the
## other, and Ocean hexes now always render the plain BASE_MESH_BY_TERRAIN
## water plate.

## Ground texture variety: the base atlas (hexagons_medieval.png) is a flat
## color-swatch sheet, not a detailed grass texture — there's no visible
## "grain" to add regardless of mesh choice — GROUND_DETAIL_SHADER supplies
## that grain procedurally on top of whichever atlas this picks. But the pack
## ships full seasonal recolors of that same atlas (same UV layout, different
## color grading), so swapping a hex's ground material to one of these for a
## region of hexes gives real (not just tinted) color variation. Applies to
## Plains/Forest/Hills (all share the hex_grass ground plate; Forest/Hills'
## own decoration meshes take the same swap — see _compute_forest_patches/
## _compute_hills_atlas) and, guarded, to River/coast (see _maybe_swap_ground_
## texture's preserve_water); not Ocean, which has no land to match.
##
## Regions are FIXED compass quadrants, not randomly placed: North is always
## Winter, South always Summer, East always Fall, West stays the default
## atlas (there is no "Spring" swatch in the pack — default already reads as
## the fresh/green option, so it fills that slot for free). This is a
## deliberate reversal of an earlier version that placed regions from noise
## alone with Winter excluded outright (a literal snow-white recolor read as
## a random patch of snow in the middle of nowhere with no reason to be
## there). Pinning Winter to one fixed edge of the map is what makes it read
## as "the cold end of the world" instead — expected, not random — which is
## exactly what makes it safe to bring back in. Purely cosmetic either way:
## nothing here is gameplay-visible (no stat, vision, or cost hook reads
## season), and capitals are sited by random search
## (worldgen/base_site_selector.gd's _shuffled_candidates) with no fixed
## angular slot per player, so no player is systematically closer to one
## quadrant than another.
##
## Quadrant boundaries are still organic, not pie-slice straight: the classify
## angle is computed from the hex's position *plus* an offset drawn from
## _ground_noise (a second, decorrelated sample of the same field — see
## _region_angle), so the boundary meanders across the noise field's ~26-hex
## period instead of cutting a straight line through the map center.
const GROUND_ATLAS_DEFAULT := BASE_DIR + "hexagons_medieval.png"
const GROUND_ATLAS_WINTER := BASE_DIR + "hexagons_medieval_Winter.png" ## North
const GROUND_ATLAS_SUMMER := BASE_DIR + "hexagons_medieval_Summer.png" ## South
const GROUND_ATLAS_FALL := BASE_DIR + "hexagons_medieval_Fall.png" ## East
## GROUND_ATLAS_DEFAULT doubles as West/"Spring".
const GROUND_NOISE_FREQUENCY := 0.0012 ## period ~830px, ~26 hexes across — how far the quadrant boundary wanders, not a patch size anymore
## Pixel-space offset (same space as HexView.axial_to_pixel) applied to the
## angle sample's position before computing direction — see _region_angle.
## A few hexes' worth (HexView.HEX_SIZE is 32px), so the boundary curves over
## a human-noticeable stretch of ground without being large enough to flip a
## hex all the way into the opposite quadrant near the map's own center.
const GROUND_REGION_WARP_STRENGTH := 220.0

## Independent RenderUtil.*2d salts (see RenderUtil.spatial_hash) — each
## decision below (which mesh, whether to roll at all, rotation, ground
## variant) must be decorrelated from the others for the same hex, or
## they'd all move together and still look patterned.
const SALT_FOREST_MESH := 1
const SALT_HILLS_MESH := 2
const SALT_OCEAN_ROLL := 3
const SALT_OCEAN_MESH := 4
const SALT_PLAINS_ROLL := 7
const SALT_PLAINS_MESH := 8
const SALT_DECOR_ROTATION := 9
const SALT_RIVER_END_MESH := 12
const SALT_RIVER_END_OFFSET := 13
## SALT_RIVER_END_* are each used as `+i` over RIVER_END_DECOR_COUNT
## iterations, so 12-14 and 13-15 are all effectively consumed. New salts start
## at 500 to stay clear of that, spaced 100 apart because each is used as `+i`
## over several iterations.
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

## Starting value for the 3D camera's pitch — CameraController.tilt_degrees
## is seeded from this constant, then live-adjustable at runtime via
## shift-drag (see camera_controller.gd's doc comment), so this is a tuned
## default rather than the fixed value it once was. main.gd's _sync_camera_3d
## doc comment covers the ground-plane compensation the CURRENT tilt drives,
## which keeps the flat 2D overlay layer — grid outlines, labels, selectors —
## locked to the 3D ground at y=0 regardless of what the live angle is.
## Decoration meshes need NO per-instance compensation at any tilt: they're
## real 3D objects sitting on real 3D ground tiles, so the camera renders each
## cluster correctly over its own tile the same way it does buildings. A tall
## tree's crown reading higher on screen is honest perspective, not a
## misplacement.
const CAMERA_TILT_DEGREES := 18.0

var grid: HexGrid
var hexes: Array[HexCoord] = []

var _known_infrastructure: Dictionary = {} ## hex key -> Terrain.Infrastructure
var _road_nodes: Dictionary = {} ## hex key -> Node3D (the dynamic Road/Bridge instance at that hex, if any)
var _forest_depth: Dictionary = {} ## hex key -> int, see _compute_forest_depth
var _forest_species: Dictionary = {} ## hex key -> "A"/"B", see _compute_forest_patches
var _biome_atlas: Dictionary = {} ## hex key -> atlas path, Forest/Hills only, see _compute_forest_patches/_compute_hills_atlas
var _ground_shader: Shader ## GROUND_DETAIL_SHADER, loaded once
var _ground_materials: Dictionary = {} ## "<atlas path>|<tint>" -> ShaderMaterial, see _ground_material
## hex key -> world Y that decoration on that hex should sit at. Cached during
## _place_static rather than recomputed, because a ramp's decor height isn't
## derivable from elevation alone (see RAMP_DECOR_DROP) — it depends on which
## mesh the placement pass actually chose for the plate.
var _decor_y: Dictionary = {}
var _ground_noise: FastNoiseLite ## see GROUND_NOISE_FREQUENCY's doc comment

func setup(p_grid: HexGrid, p_hexes: Array[HexCoord], p_world_seed: int = 0) -> void:
	for child in get_children():
		child.queue_free()
	_known_infrastructure.clear()
	_road_nodes.clear()
	_decor_y.clear()
	_ground_materials.clear()
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
	# Shared by both: Forest and Hills patches write into the same _biome_atlas
	# map (each hex belongs to at most one terrain type, so there's no
	# collision), reset once here rather than by whichever call happens to run
	# first.
	_biome_atlas.clear()
	_compute_forest_patches()
	_compute_hills_atlas()
	_extend_biome_atlas_to_fringe()
	for hex in hexes:
		_place_static(hex)
		_known_infrastructure[hex.to_key()] = Terrain.Infrastructure.NONE
		_refresh_infrastructure(hex)

## Flood-fills the contiguous same-terrain patch containing `start` (BFS/DFS
## order doesn't matter here — nothing downstream cares), marking every member
## in the shared `seen` dictionary as it goes so a caller scanning `hexes` in
## order never re-walks a patch it already collected. Shared by
## _compute_forest_patches and _compute_hills_atlas, which both need "every
## hex belonging to the same contiguous blob of this terrain type".
func _flood_fill_patch(start: HexCoord, terrain: Terrain.Type, seen: Dictionary) -> Array[HexCoord]:
	var patch: Array[HexCoord] = []
	var frontier: Array[HexCoord] = [start]
	seen[start.to_key()] = true
	while not frontier.is_empty():
		var current: HexCoord = frontier.pop_back()
		patch.append(current)
		for n in HexCoord.neighbors(current):
			var nk := n.to_key()
			if seen.has(nk) or not grid.has_hex(n) or grid.get_terrain(n) != terrain:
				continue
			seen[nk] = true
			frontier.append(n)
	return patch

## Pixel-space centroid of `patch` — the point _atlas_for_position samples to
## pin every hex in it to one shared seasonal atlas. See _compute_hills_atlas
## for why a patch needs ONE shared sample instead of one per hex.
func _patch_centroid(patch: Array[HexCoord]) -> Vector2:
	var centroid := Vector2.ZERO
	for coord in patch:
		centroid += HexView.axial_to_pixel(coord)
	return centroid / float(patch.size())

## Assigns every Forest hex the tree species of the contiguous patch it belongs
## to (see FOREST_SPECIES), picked once from the patch's own canonical hex —
## the lowest to_key() in it. Using a canonical member rather than whichever hex
## the fill happened to start from makes the choice independent of iteration
## order, so every client derives the same species for the same patch with
## nothing synced over the network, exactly like every other RenderUtil.*2d
## cosmetic decision.
##
## Also assigns the patch's seasonal atlas (see _compute_hills_atlas for why a
## patch needs one shared sample) in the same pass, since both need the same
## flood fill — trees are drawn from the same atlas as the ground plate (see
## FOREST_SPECIES's mesh materials), so left unswapped a wood stayed uniformly
## default-green across an autumn or winter region the same way Hills did.
func _compute_forest_patches() -> void:
	_forest_species.clear()
	var seen: Dictionary = {}
	for hex in hexes:
		if seen.has(hex.to_key()) or grid.get_terrain(hex) != Terrain.Type.FOREST:
			continue
		var patch := _flood_fill_patch(hex, Terrain.Type.FOREST, seen)
		var canonical := hex
		for coord in patch:
			if coord.to_key() < canonical.to_key():
				canonical = coord
		var species: String = RenderUtil.pick2d(canonical.q, canonical.r, SALT_FOREST_MESH, FOREST_SPECIES)
		var atlas := _atlas_for_position(_patch_centroid(patch))
		for coord in patch:
			_forest_species[coord.to_key()] = species
			_biome_atlas[coord.to_key()] = atlas

## Pins every hex of a Hills patch to ONE seasonal atlas, sampled once at the
## patch's pixel centroid instead of per hex.
##
## Flat land can afford a per-hex sample: the region boundary wanders between
## two swatches of ground and reads as a soft edge. A hill range can't. Its
## plates are physically raised with lit side walls, so a boundary running
## through the middle of one massif reads as two different massifs jammed
## together — half the range green, half yellow, with a hard seam along a
## silhouette the eye is already tracking. Sampling at the centroid also keeps
## the range in the SAME region as the land around it, which is the point:
## GROUND_NOISE_FREQUENCY's period (~26 hexes) is wider than a typical patch
## (see Tuning.HILLS_PATCH_SIZE_WEIGHTS), so the centroid's region is almost
## always the one the patch's neighbours are in too.
func _compute_hills_atlas() -> void:
	var seen: Dictionary = {}
	for hex in hexes:
		if seen.has(hex.to_key()) or grid.get_terrain(hex) != Terrain.Type.HILLS:
			continue
		var patch := _flood_fill_patch(hex, Terrain.Type.HILLS, seen)
		var atlas := _atlas_for_position(_patch_centroid(patch))
		for coord in patch:
			_biome_atlas[coord.to_key()] = atlas

## Copies each Forest/Hills patch's own pinned atlas onto its immediate
## non-Forest/Hills neighbours (Plains, River, beach-Coast — anything that
## would otherwise fall back to _maybe_swap_ground_texture's per-hex
## _atlas_for_position sample). A patch is deliberately pinned to ONE atlas
## sampled at its centroid (see _compute_hills_atlas) rather than per hex, so
## it can't show a seam through its own middle — but that same centroid can
## land in a different compass quadrant than a lowland hex sampling its OWN
## position right at the patch's rim, especially for a large/elongated patch
## whose edge sits well away from its centroid. The mismatch is exactly what
## it sounds like from ground level: a ramp or cliff face in one season
## butting straight up against flat ground in another, one hex over — the
## rim patch's OWN colour is internally consistent, but the seam just moved
## to the hills/lowland boundary instead of being inside the hills. Letting
## the immediate lowland fringe borrow the patch's atlas removes that seam at
## the cost of the outermost ring of lowland around a patch occasionally not
## matching the compass quadrant its own position would otherwise pick —
## a far smaller, far less visible tradeoff, since flat ground has none of
## the raised geometry that makes a colour seam read as "wrong place."
func _extend_biome_atlas_to_fringe() -> void:
	var fringe: Dictionary = {}
	for hex in hexes:
		var key := hex.to_key()
		var atlas: String = _biome_atlas.get(key, "")
		if atlas.is_empty():
			continue
		for n in HexCoord.neighbors(hex):
			var nk := n.to_key()
			if _biome_atlas.has(nk) or fringe.has(nk):
				continue
			if not grid.has_hex(n):
				continue
			var nt := grid.get_terrain(n)
			if nt == Terrain.Type.HILLS or nt == Terrain.Type.FOREST:
				continue ## has (or will get) its own patch-pinned entry
			fringe[nk] = atlas
	for k in fringe:
		_biome_atlas[k] = fringe[k]

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

## Direction index (into HexCoord.DIRECTIONS) of the lowland neighbour this hex
## ramps down to, or -1 if it isn't a ramp.
##
## ONLY the first step up from lowland is a ramp. Every step above that renders
## as a flat plate with a vertical face — a terrace. The obvious rule ("any hex
## with a neighbour one level below slopes toward it") was tried first and was
## wrong: on a real map it made 525 of 544 raised hexes slopes and left only 19
## flat, so an entire hill range was one continuous incline with no readable
## step anywhere in it, and the decoration clusters ended up sitting on tilted
## ground where they hid the very slope they were standing on. Restricting
## ramps to the rim gives the shape hills actually need — a walk-up edge, then
## stepped ground above it.
##
## Purely a rendering decision: the sim's cost model is unchanged either way, a
## one-level step is climbable whether it's drawn as an incline or a low ledge
## (see Terrain.elevation_step_cost).
##
## When several lowland neighbours qualify, the lowest direction index wins
## rather than a random pick: a hex can only tilt one way, and choosing
## deterministically by index keeps the choice stable across clients without
## burning a salt.
func _ramp_low_direction(hex: HexCoord) -> int:
	if grid.get_elevation(hex) != Tuning.HILLS_RIM_ELEVATION:
		return -1
	for i in range(HexCoord.DIRECTIONS.size()):
		var n := HexCoord.neighbor(hex, i)
		if grid.has_hex(n) and grid.get_elevation(n) == 0:
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
	var is_water := terrain == Terrain.Type.OCEAN or terrain == Terrain.Type.RIVER
	if is_water:
		plate_y -= WATER_SURFACE_DROP
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
	if terrain != Terrain.Type.OCEAN:
		# River and beach plates carry grass/sand AND water on one surface, so
		# they need the shader's water guard; plain Ocean is skipped outright,
		# since it's all water and there's nothing on it to match to the land.
		var has_water_uv := terrain == Terrain.Type.RIVER or mesh_path.begins_with(COAST_MESH_PREFIX)
		_maybe_swap_ground_texture(node, hex, has_water_uv)
	add_child(node)
	# Underside of what was just placed: a flat plate's body is 1.0 tall, a
	# scaled ramp's reaches a full step below its seat.
	_place_elevation_skirt(hex, plate_y - (WORLD_UNITS_PER_ELEVATION if is_ramp else 1.0))
	# On a ramp the plate was seated a level down and slopes back up across the
	# hex, so decor belongs at the mid-surface, not at either end of the slope.
	var decor_y := surface_height(grid, hex)
	if is_ramp:
		decor_y -= RAMP_DECOR_DROP
	elif is_water:
		# Lilies, reeds and bank props belong ON the water surface, which is now
		# recessed — without this they hover at old sea level above their own hex.
		decor_y -= WATER_SURFACE_DROP
	_decor_y[hex.to_key()] = decor_y
	# A ramp is the one hex whose SHAPE is the thing worth looking at — it's how
	# the player reads "you can walk up here". A hill/mountain cluster planted on
	# it sits square across the incline and hides it completely, so the slope is
	# left bare. The rim reading as open grassy approach into rocky high ground
	# is also just what a hill range looks like.
	if not is_ramp:
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

## Applies the ground surface treatment to a land plate: the procedural detail
## shader (GROUND_DETAIL_SHADER), pointed at either the default atlas or a
## seasonal variant of it.
##
## The seasonal swap is real colour variation from a different source image,
## not a multiply-tint, and comes from a fixed compass quadrant (see
## GROUND_ATLAS_DEFAULT's doc comment) rather than a random patch. The detail
## shader then runs on whichever atlas was chosen, so the two compose: broad
## seasonal regions with per-surface grain inside them.
##
## `preserve_water` forwards to the shader's water guard — set it for any mesh
## whose UVs reach into the atlas's water swatches (river channels, coast
## tiles), so the seasonal region colours the land without recolouring the
## water running through it. See the shader's water_guard_texture comment.
func _maybe_swap_ground_texture(node: Node, hex: HexCoord, preserve_water: bool = false) -> void:
	# Forest/Hills are pinned per patch rather than per hex — see
	# _compute_hills_atlas for why a lone hex sample isn't good enough for them.
	var atlas: String = _biome_atlas.get(hex.to_key(), "")
	if atlas.is_empty():
		atlas = _atlas_for_position(HexView.axial_to_pixel(hex))
	var tex: Texture2D = load(atlas)
	if tex == null:
		return
	_apply_ground_texture(node, tex, preserve_water)

## The compass-quadrant angle to classify `pixel` into a season — see
## GROUND_ATLAS_DEFAULT's doc comment for the fixed N/E/S/W assignment.
##
## `pixel` is nudged by an offset drawn from _ground_noise before the angle is
## taken, so the quadrant boundary is an organic curve wandering across the
## noise field's period rather than a straight line through the map's own
## center. The offset is built from two samples of the SAME field at very
## different sample points (not two independent noise fields) — cheap, and
## the two samples are already effectively decorrelated since they land in
## unrelated cells of the field.
func _region_angle(pixel: Vector2) -> float:
	var warp_x := _ground_noise.get_noise_2d(pixel.x, pixel.y)
	var warp_y := _ground_noise.get_noise_2d(pixel.y + 4096.0, pixel.x - 4096.0)
	var warped := pixel + Vector2(warp_x, warp_y) * GROUND_REGION_WARP_STRENGTH
	return warped.angle()

## Which fixed seasonal atlas `pixel` falls into. Pixel space is HexView's
## (same space as HexView.axial_to_pixel and this file's hex_to_world), where
## +X is East/-X is West (matches the world X axis unchanged) and +Y is
## South/-Y is North (world Z, per main.tscn's Camera3D basis: local up maps
## to world -Z, i.e. "up on screen" is -Z, so +Y-pixel/+Z-world is down-screen/
## South). Vector2.angle() is atan2(y, x), so East sits at 0, South at +PI/2,
## West at ±PI, North at -PI/2 — each quadrant a PI/2 wedge centered on its
## own cardinal.
func _atlas_for_position(pixel: Vector2) -> String:
	var angle := _region_angle(pixel)
	if absf(angle) <= PI / 4.0:
		return GROUND_ATLAS_FALL # East
	if angle > PI / 4.0 and angle < 3.0 * PI / 4.0:
		return GROUND_ATLAS_SUMMER # South
	if angle < -PI / 4.0 and angle > -3.0 * PI / 4.0:
		return GROUND_ATLAS_WINTER # North
	return GROUND_ATLAS_DEFAULT # West ("Spring")

## Replaces every surface's imported BaseMaterial3D with a ShaderMaterial
## running GROUND_DETAIL_SHADER over `tex`, carrying the original material's
## albedo_color across as a tint so per-surface colouring survives the swap.
##
## The ShaderMaterial is cached per texture (_ground_materials) rather than
## built per surface: there are only ever three of them (default/Fall/Summer),
## every plate on the map shares one, and the previous duplicate-per-surface
## approach allocated a fresh material for thousands of tiles.
func _apply_ground_texture(node: Node, tex: Texture2D, preserve_water: bool = false) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for i in range(mesh_instance.mesh.get_surface_count()):
			var mat := mesh_instance.mesh.surface_get_material(i)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			var tint: Color = (mat as BaseMaterial3D).albedo_color
			mesh_instance.set_surface_override_material(i, _ground_material(tex, tint, preserve_water))
	for child in node.get_children():
		_apply_ground_texture(child, tex, preserve_water)

func _ground_material(tex: Texture2D, tint: Color, preserve_water: bool) -> ShaderMaterial:
	var key := "%s|%s|%s" % [tex.resource_path, tint, preserve_water]
	if _ground_materials.has(key):
		return _ground_materials[key]
	if _ground_shader == null:
		_ground_shader = load(GROUND_DETAIL_SHADER)
	var mat := ShaderMaterial.new()
	mat.shader = _ground_shader
	mat.set_shader_parameter("albedo_texture", tex)
	mat.set_shader_parameter("albedo_tint", tint)
	mat.set_shader_parameter("preserve_water", preserve_water)
	if preserve_water:
		mat.set_shader_parameter("water_guard_texture", load(GROUND_ATLAS_DEFAULT))
	_ground_materials[key] = mat
	return mat

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
			# Size from this hex's depth into the stand, species from the whole
			# patch — one wood is one kind of tree, thickening toward its middle.
			var depth: int = _forest_depth.get(hex.to_key(), 0)
			var tier: String = FOREST_MESH_BY_DEPTH[mini(depth, FOREST_MESH_BY_DEPTH.size() - 1)]
			var species: String = _forest_species.get(hex.to_key(), FOREST_SPECIES[0])
			mesh_path = "%strees_%s_%s.gltf" % [NATURE_DIR, species, tier]
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
			# Dead ends still get their channel-mouth plug (see
			# _place_river_end_decoration — it hides a real mesh artifact, not a
			# decoration choice). Otherwise a flowing river gets NOTHING in the
			# channel: the old per-hex roll dropped a prop on the hex centre,
			# i.e. squarely mid-stream, which is exactly what read as the river
			# being full of obstacles. All river dressing now lives on the banks
			# instead — see _place_river_banks.
			if TerrainTileResolver._popcount(river_mask) <= 1:
				_place_river_end_decoration(hex, river_mask)
			return
		_:
			# Plains included: it deliberately carries no props at all, only the
			# ground detail shader. See OCEAN_DECOR_CHANCE's doc comment.
			return
	var node := _instance_decor(mesh_path, hex, RenderUtil.angle2d(hex.q, hex.r, SALT_DECOR_ROTATION), _hex_decor_y(hex))
	if node == null:
		return
	if scale != 1.0:
		node.scale = Vector3.ONE * scale
	if terrain == Terrain.Type.HILLS or terrain == Terrain.Type.FOREST:
		# Both the hill/mountain clusters and the tree meshes are drawn from the
		# same atlas as the ground plate under them and cover most of their hex —
		# so left unswapped they stay default green while the plate goes autumn/
		# winter, and the whole patch reads as belonging to a different map than
		# the land around it (a uniformly green wood sitting in a snowy region).
		# Swapping them is what actually makes a patch sit inside its region.
		# No water guard: nothing on these meshes is water.
		_maybe_swap_ground_texture(node, hex)
	add_child(node)

## World Y decoration on this hex should sit at — see _decor_y. Falls back to
## the flat elevation height for a hex _place_static hasn't reached yet.
func _hex_decor_y(hex: HexCoord) -> float:
	return _decor_y.get(hex.to_key(), surface_height(grid, hex))

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
			# -0.5..0.5 across the edge, centered regardless of count: at
			# RIVER_BANK_PROPS_PER_EDGE == 1 the old `i / max(count-1,1) - 0.5`
			# always evaluated to -0.5 (i is always 0), pinning the single prop
			# to one end of the edge instead of its middle.
			var t := (float(i) - float(RIVER_BANK_PROPS_PER_EDGE - 1) * 0.5) / float(maxi(RIVER_BANK_PROPS_PER_EDGE - 1, 1))
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
