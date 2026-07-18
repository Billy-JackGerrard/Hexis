## 3D building renderer — the Node3D counterpart to base_view.gd's flat 2D
## shapes, for building_types that have a real mesh (see
## BuildingMeshDefs.mesh_path_for). base_view.gd keeps ownership of hover
## tooltips/base titles/labels (still useful floating over a 3D mesh) and
## keeps drawing its own flat shape for the few types intentionally left 2D
## here — Wall (needs its own corner/straight connection-mask resolver, a
## follow-up) and Landmine (stealthed; a visible 3D prop would leak that a
## hex holds a hidden mine to anyone who can merely see the hex, not just
## detect it). Road/Bridge are already real 3D via TerrainView3D's
## infrastructure poll — rendering them again here would double them up.
##
## Poll-based (matching TerrainView3D/BaseView's own "poll MatchState every
## _process rather than hook call sites" convention): a remote peer's build/
## upgrade/demolish arrives via LockstepDriver/CommandProcessor, never
## through local InputController, so a call-site hook would miss every
## other player's changes. Diffs a per-building signature (level/ruin/hex)
## against what's currently instanced, and separately drops any tracked
## building id no longer present at all (a destroyed standalone building —
## e.g. Tower, Dock — is removed outright from
## MatchState.standalone_buildings, unlike a base-attached building which
## just flips is_ruin and stays in base.buildings).
class_name BuildingView3D
extends Node3D

var state: MatchState
var grid: HexGrid
var bases: Array[BaseInstance] = []
var standalone_buildings: Array[BuildingInstance] = []
var building_defs: Dictionary = {}
var detections: Dictionary = {}
var local_owner_id: String = ""

var _nodes: Dictionary = {} ## building.id -> Node3D
var _signatures: Dictionary = {} ## building.id -> String

const SKIP_TYPES := ["road", "bridge", "landmine", "wall"]
const PIER_TYPES := ["dock", "harbour", "port", "shipyard"]
const PIER_OFFSET_FRACTION := 0.35
const BOAT_MESH := BuildingMeshDefs.PROPS_DIR + "boat.gltf"
const BOAT_SPACING := 0.6
const RUIN_MESH := BuildingMeshDefs.BUILDINGS_DIR + "neutral/building_destroyed.gltf"
const DECOR_RING_RADIUS := 0.55
const DECOR_RING_STEP := 0.15

func setup(p_state: MatchState, p_grid: HexGrid, p_bases: Array[BaseInstance], p_standalone_buildings: Array[BuildingInstance], p_building_defs: Dictionary, p_detections: Dictionary, p_local_owner_id: String) -> void:
	state = p_state
	grid = p_grid
	bases = p_bases
	standalone_buildings = p_standalone_buildings
	building_defs = p_building_defs
	detections = p_detections
	local_owner_id = p_local_owner_id

func _process(_delta: float) -> void:
	if grid == null:
		return
	var seen: Dictionary = {} ## building.id -> true
	for base in bases:
		for building in base.buildings:
			_poll_one(building, base.owner_id, seen)
	for building in standalone_buildings:
		_poll_one(building, building.owner_id, seen)
	for id in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
			_signatures.erase(id)

func _poll_one(building: BuildingInstance, owner_id: String, seen: Dictionary) -> void:
	if building.hex == null or SKIP_TYPES.has(building.building_type):
		return
	if not _is_visible_to_local(building, owner_id):
		return
	seen[building.id] = true
	# owner_id is part of the signature so a base capture (HQ flip changes
	# base.owner_id but not the BuildingInstance's own level/hex/material)
	# still triggers a mesh rebuild in the new owner's color.
	var sig := "%d:%s:%s:%s:%s" % [building.level, building.is_ruin, building.hex.to_key(), building.material, owner_id]
	if _signatures.get(building.id) == sig:
		return
	_signatures[building.id] = sig
	var old: Node3D = _nodes.get(building.id)
	if old:
		old.queue_free()
	var node := _build_node(building, owner_id)
	if node == null:
		_nodes.erase(building.id)
		return
	add_child(node)
	_nodes[building.id] = node

## See base_view.gd's identical-named function for why this checks live
## vision (state.visions), not just stealth, for anyone else's buildings —
## same fog-of-war rule ("base composition requires live vision" per
## 01-map-and-terrain.md), same regression risk now that fog occlusion is
## 3D-only rather than a 2D polygon every Node2D draw call used to sit under.
## This gate currently only matters as defense-in-depth (the fog shader's
## depth_test_disabled already visually hides an unexplored building's mesh
## regardless of this check), but skipping mesh creation entirely for
## not-currently-visible foreign buildings is strictly cheaper too.
func _is_visible_to_local(building: BuildingInstance, owner_id: String) -> bool:
	if owner_id == local_owner_id:
		return true
	if BuildingStats.stealth(building_defs.get(building.building_type, {}), building_defs):
		return DetectionSystem.detected_hexes_for(detections, local_owner_id).has(building.hex.to_key())
	var pv: PlayerVision = state.visions.get(local_owner_id)
	return pv != null and pv.is_visible(building.hex)

func _build_node(building: BuildingInstance, owner_id: String) -> Node3D:
	# Seated on the hex's actual ground surface, not sea level — Windy Peaks
	# builds onto raised Hills, and any building on a hill-adjacent tile would
	# otherwise sink into (or float over) the terrain now that it has height.
	var center := TerrainView3D.hex_to_world(state.grid, building.hex)

	# Every ruined building — regardless of original type — renders as the
	# same neutral rubble heap. "What it used to be" stopped mattering the
	# moment it was destroyed; a uniform ruin also reads at a glance without
	# needing per-type destroyed variants this pack doesn't ship anyway.
	if building.is_ruin:
		var ruin_scene: PackedScene = load(RUIN_MESH)
		if ruin_scene == null:
			push_error("BuildingView3D: failed to load %s" % RUIN_MESH)
			return null
		var ruin_root := Node3D.new()
		ruin_root.add_child(ruin_scene.instantiate())
		ruin_root.position = center
		return ruin_root

	var mesh_path := BuildingMeshDefs.mesh_path_for(building.building_type, building.level, building.material, owner_id)
	if mesh_path.is_empty():
		return null
	var scene: PackedScene = load(mesh_path)
	if scene == null:
		push_error("BuildingView3D: failed to load %s" % mesh_path)
		return null

	var root := Node3D.new()
	var mesh_node: Node3D = scene.instantiate()
	mesh_node.scale = Vector3.ONE * BuildingMeshDefs.level_scale(building.level)
	root.add_child(mesh_node)

	var element_tint: Color = BuildingMeshDefs.ELEMENT_TINTS.get(building.building_type, Color.WHITE)
	if element_tint != Color.WHITE:
		RenderUtil.apply_tint(mesh_node, element_tint)
	elif BuildingMeshDefs.needs_neutral_tint(building.building_type, owner_id):
		RenderUtil.apply_tint(mesh_node, BuildingMeshDefs.NEUTRAL_TINT)

	var pos := center
	var facing := 0.0

	if PIER_TYPES.has(building.building_type):
		var water_hex := _water_neighbor(building.hex)
		if water_hex != null:
			var wpos := TerrainView3D.hex_to_world(state.grid, water_hex)
			var dir := wpos - center
			facing = atan2(dir.x, dir.z)
			pos = center.lerp(wpos, PIER_OFFSET_FRACTION)

	root.position = pos
	root.rotation.y = facing

	if building.building_type == "harbour":
		_add_harbour_boats(root, building.level, facing)
	else:
		_add_level_decor(root, building, owner_id)

	return root

## "Fishing boats" are purely a visual per game-design/02-bases-and-buildings.md:235
## — count == level (level 1 = 1 boat, doubling food output per level without a
## matching doubling of visible boats would undersell the growth, but a literal
## 1:1 count is what the doc specifies), fanned out along the building's
## water-facing axis so they read as moored offshore rather than stacked.
func _add_harbour_boats(root: Node3D, level: int, facing: float) -> void:
	var count := clampi(level, 1, 6)
	for i in range(count):
		var scene: PackedScene = load(BOAT_MESH)
		if scene == null:
			continue
		var boat: Node3D = scene.instantiate()
		var lateral := (i - (count - 1) / 2.0) * BOAT_SPACING
		var offset := Vector3(lateral, 0.0, 0.4).rotated(Vector3.UP, facing)
		boat.position = offset
		boat.rotation.y = facing
		root.add_child(boat)

## "As buildings level up, add more decor" — one extra thematic prop per
## level above 1 (capped), scattered on a small ring around the building.
## See BuildingMeshDefs.LEVEL_DECOR_BY_TYPE for the per-type prop choice.
func _add_level_decor(root: Node3D, building: BuildingInstance, owner_id: String) -> void:
	var decor_path := BuildingMeshDefs.level_decor_mesh_for(building.building_type, owner_id)
	if decor_path.is_empty():
		return
	var count := BuildingMeshDefs.level_decor_count(building.building_type, building.level)
	for i in range(count):
		var scene: PackedScene = load(decor_path)
		if scene == null:
			continue
		var decor: Node3D = scene.instantiate()
		var seed_key := "%s:decor:%d" % [building.id, i]
		var ring_angle := RenderUtil.angle(seed_key)
		var radius := DECOR_RING_RADIUS + DECOR_RING_STEP * (i % 3)
		decor.position = Vector3(cos(ring_angle) * radius, 0.0, sin(ring_angle) * radius)
		decor.rotation.y = RenderUtil.angle(seed_key + ":rot")
		root.add_child(decor)

## First neighbor hex that's Ocean or River, or null — used to orient/offset
## Dock/Harbour/Port/Shipyard toward the water they're required to be built
## adjacent to (placementRequirement.adjacentTerrainRequired: Water).
func _water_neighbor(hex: HexCoord) -> HexCoord:
	for n in HexCoord.neighbors(hex):
		if grid.has_hex(n):
			var t := grid.get_terrain(n)
			if t == Terrain.Type.OCEAN or t == Terrain.Type.RIVER:
				return n
	return null

