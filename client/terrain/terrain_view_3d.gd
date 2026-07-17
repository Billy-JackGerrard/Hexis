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
const BRIDGE_MESH := "res://assets/buildings/neutral/building_bridge_A.gltf"

## Terrain.Type -> base mesh, for every hex that isn't River (River always
## replaces the base tile with a river_* mesh instead — see _static_mesh_for).
## Forest/Hills render as flat grass in v1 (this pack has no dedicated
## ground mesh for either — see game-design/01-map-and-terrain.md's
## Rendering Notes for why, and the decoration/nature/ prop-scatter this
## intentionally leaves as a follow-up rather than doing now).
const BASE_MESH_BY_TERRAIN := {
	Terrain.Type.PLAINS: BASE_DIR + "hex_grass.gltf",
	Terrain.Type.FOREST: BASE_DIR + "hex_grass.gltf",
	Terrain.Type.HILLS: BASE_DIR + "hex_grass.gltf",
	Terrain.Type.OCEAN: BASE_DIR + "hex_water.gltf",
}

## World units per HexView pixel, and the fixed placement rotation every
## instanced mesh gets before its own per-hex rotation_steps*60 — see
## TerrainTileResolver's header for the full derivation. WORLD_HEX_CIRCUMRADIUS
## is this asset pack's own native circumradius (matches hex_grass.gltf's
## measured Z-axis extent exactly), so meshes need no rescale — placing a
## mesh unscaled already matches HexView.HEX_SIZE-driven spacing once
## positions are run through WORLD_UNITS_PER_PIXEL.
const WORLD_HEX_CIRCUMRADIUS: float = 2.0 / 1.7320508075688772 ## 2/sqrt(3), matches HexView.SQRT3
const WORLD_UNITS_PER_PIXEL: float = WORLD_HEX_CIRCUMRADIUS / 32.0 ## HexView.HEX_SIZE

var grid: HexGrid
var hexes: Array[HexCoord] = []

var _known_infrastructure: Dictionary = {} ## hex key -> Terrain.Infrastructure
var _road_nodes: Dictionary = {} ## hex key -> Node3D (the dynamic Road/Bridge instance at that hex, if any)

func setup(p_grid: HexGrid, p_hexes: Array[HexCoord]) -> void:
	for child in get_children():
		child.queue_free()
	_known_infrastructure.clear()
	_road_nodes.clear()
	grid = p_grid
	hexes = p_hexes
	for hex in hexes:
		_place_static(hex)
		_known_infrastructure[hex.to_key()] = Terrain.Infrastructure.NONE
		_refresh_infrastructure(hex)

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
	if terrain == Terrain.Type.RIVER:
		var mask := grid.river_connection_mask(hex)
		var result := TerrainTileResolver.resolve(mask, TerrainTileDefs.RIVER_MASKS)
		mesh_path = RIVER_DIR + result.mesh_name + ".gltf"
		rotation_steps = result.rotation_steps
	else:
		mesh_path = BASE_MESH_BY_TERRAIN.get(terrain, BASE_MESH_BY_TERRAIN[Terrain.Type.PLAINS])
	var node := _instance_mesh(mesh_path, hex, rotation_steps)
	if node:
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
