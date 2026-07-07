## Validates whether a building may be placed at a given hex for a base, per
## 02-bases-and-buildings.md's "Expansion Rule (Hex Adjacency)" and
## "Population" sections. Stateless, mirrors SquadCap/CommanderProgression:
## nothing here is stored, every check reads live BaseInstance/HexGrid state.
##
## Walls (see can_place_wall/place_wall below) are edge-keyed, not hex-keyed
## — sitting on the border between two hexes rather than on one — so they get
## their own validator rather than reusing can_place: no HEX_OCCUPIED/
## HEX_OCCUPIED_BY_UNIT/siteTerrain/population checks (a Wall doesn't occupy a
## hex or cost population), and only ONE adjacent building is required
## instead of MIN_ADJACENT_BUILDINGS.
class_name BuildingPlacement
extends RefCounted

enum Result {
	OK,
	NOT_BUILDABLE_AT_BASE,
	IS_FIXED,
	IS_STANDALONE,
	HEX_OCCUPIED,
	HEX_OCCUPIED_BY_UNIT,
	OUT_OF_HEX_BOUNDS,
	WRONG_SITE_TERRAIN,
	MISSING_ADJACENT_TERRAIN,
	NOT_ENOUGH_ADJACENT_BUILDINGS,
	OUTSIDE_HQ_RADIUS,
	POPULATION_FULL,
	NOT_STANDALONE,
	EDGE_NOT_ADJACENT_HEXES,
	EDGE_ALREADY_WALLED,
	NOT_ENOUGH_ADJACENT_BUILDINGS_FOR_WALL,
	## The following five are command-layer (CommandProcessor) rejection
	## reasons, not placement-geometry ones — grouped into this same enum so
	## every place_*/rebuild caller gets one Result type back rather than two.
	BASE_NOT_FOUND,
	NOT_OWNER,
	CANNOT_BUILD_INFRASTRUCTURE, ## no valid owned squad with canBuildInfrastructure
	INSUFFICIENT_RESOURCES, ## owner's pool can't cover the build cost
	OUT_OF_ENGINEER_RANGE, ## target hex is further than STANDALONE_BUILD_RANGE from the building Engineer
}

## Max hex-distance between the building Engineer and a standalone build site
## (Road/Bridge/Dock/Tower/Landmine) — an Engineer must travel next to a site
## rather than dropping infrastructure anywhere on the map. 1 = adjacent-only,
## since the Engineer's own hex is already excluded (ground units block
## placement — see ground_unit_hexes/HEX_OCCUPIED_BY_UNIT).
const STANDALONE_BUILD_RANGE := 1

## Minimum adjacent existing buildings required for a normal (non-Wall)
## placement, per the Expansion Rule. Walls need only 1 — deferred, see above.
const MIN_ADJACENT_BUILDINGS := 2

## Placeholder build-radius formula (tunable, same spirit as
## Terrain.HILLS_INFANTRY_COST): a base may only build within this many hexes
## of its HQ, scaling with hqLevel. Design doc pins the scaling relationship
## but not the exact number.
static func hq_build_radius(hq_level: int) -> int:
	return hq_level * 2 + 2

static func _site_terrain(name: String) -> Terrain.Type:
	match name:
		"Forest": return Terrain.Type.FOREST
		"Hill": return Terrain.Type.HILLS
		"River": return Terrain.Type.RIVER
		_: return Terrain.Type.PLAINS

static func _matches_adjacent_terrain_required(name: String, terrain: Terrain.Type) -> bool:
	match name:
		"Water": return terrain == Terrain.Type.RIVER or terrain == Terrain.Type.OCEAN
		"Forest": return terrain == Terrain.Type.FOREST
		_: return true

## Bridge exception to the 2-adjacent-buildings rule, per
## 02-bases-and-buildings.md: without it, a base could never expand across a
## River, since the far bank starts with zero adjacent buildings. `hex` is
## exempt if it's adjacent to a Bridge hex (`grid.get_infrastructure() ==
## BRIDGE` — Bridge is a hex-based standalone building, tracked on the grid
## regardless of which array its BuildingInstance lives in, so no
## standalone_buildings param is needed here) AND that Bridge already has an
## existing building on its OPPOSITE side from `hex` — the "foothold on the
## near bank" the Bridge stands in for. If `bridge_hex` is `hex`'s neighbor in
## direction `d` (`bridge_hex = neighbor(hex, d)`), the far side of that same
## Bridge — continuing straight across, away from `hex` — is
## `neighbor(bridge_hex, d)` (the SAME direction again, not its opposite:
## `neighbor(bridge_hex, (d+3)%6)` would just walk back to `hex` itself).
## With no foothold on the near-bank end, the far bank still can't be reached
## this way (the Bridge alone doesn't seed a foothold from nothing).
static func _has_bridge_foothold_exemption(hex: HexCoord, occupied: Dictionary, grid: HexGrid) -> bool:
	for d in range(6):
		var bridge_hex := HexCoord.neighbor(hex, d)
		if grid.get_infrastructure(bridge_hex) != Terrain.Infrastructure.BRIDGE:
			continue
		var other_side := HexCoord.neighbor(bridge_hex, d)
		if occupied.has(other_side.to_key()):
			return true
	return false

static func _hq_hex(base: BaseInstance) -> HexCoord:
	var hq_buildings := base.buildings_of_type("hq")
	if not hq_buildings.is_empty() and hq_buildings[0].hex != null:
		return hq_buildings[0].hex
	return base.hex_coord

## `occupied_unit_hexes` is a caller-supplied {hex_key: true} set of hexes
## currently occupied by ground (Infantry/Land) troops — see
## ground_unit_hexes(). Air/Naval units never block building placement.
static func can_place(base: BaseInstance, base_def: Dictionary, building_type: String, hex: HexCoord, grid: HexGrid, building_defs: Dictionary, occupied_unit_hexes: Dictionary = {}) -> Result:
	var buildable: Array = base_def.get("buildableBuildings", [])
	if not buildable.has(building_type):
		return Result.NOT_BUILDABLE_AT_BASE

	var building_def: Dictionary = building_defs.get(building_type, {})
	if building_def.get("isFixed", false):
		return Result.IS_FIXED
	if building_def.get("isStandalone", false):
		return Result.IS_STANDALONE

	if not grid.has_hex(hex):
		return Result.OUT_OF_HEX_BOUNDS

	var hex_key := hex.to_key()
	var occupied := base.occupied_hexes()
	if occupied.has(hex_key):
		return Result.HEX_OCCUPIED
	if occupied_unit_hexes.has(hex_key):
		return Result.HEX_OCCUPIED_BY_UNIT

	var placement_requirement: Dictionary = building_def.get("placementRequirement", {})
	var required_site_terrain := _site_terrain(placement_requirement.get("siteTerrain", "Plains"))
	var hex_terrain := grid.get_terrain(hex)
	var used_terrain_exception := false
	if hex_terrain != required_site_terrain:
		var terrain_exception: String = base_def.get("terrainException", "")
		if terrain_exception == "" or hex_terrain != _site_terrain(terrain_exception):
			return Result.WRONG_SITE_TERRAIN
		used_terrain_exception = true

	var adjacent_terrain_required: String = placement_requirement.get("adjacentTerrainRequired", "")
	if adjacent_terrain_required != "" and not used_terrain_exception:
		var satisfied := false
		for neighbor in HexCoord.neighbors(hex):
			if _matches_adjacent_terrain_required(adjacent_terrain_required, grid.get_terrain(neighbor)):
				satisfied = true
				break
		if not satisfied:
			return Result.MISSING_ADJACENT_TERRAIN

	var adjacent_building_count := 0
	for neighbor in HexCoord.neighbors(hex):
		if occupied.has(neighbor.to_key()):
			adjacent_building_count += 1
	if adjacent_building_count < MIN_ADJACENT_BUILDINGS and not _has_bridge_foothold_exemption(hex, occupied, grid):
		return Result.NOT_ENOUGH_ADJACENT_BUILDINGS

	var hq_hex := _hq_hex(base)
	if hq_hex != null and HexCoord.distance(hex, hq_hex) > hq_build_radius(base.hq_level):
		return Result.OUTSIDE_HQ_RADIUS

	if not Population.has_capacity_for(base, building_type, building_defs):
		return Result.POPULATION_FULL

	return Result.OK

## Builds the {hex_key: true} occupancy set for ground_unit_hexes: any squad
## whose troop_type's domain is Infantry or Land blocks a build there; Air/
## Naval don't.
static func ground_unit_hexes(squads: Array[SquadInstance], troop_defs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for squad in squads:
		var troop_def: Dictionary = troop_defs.get(squad.troop_type, {})
		var domain: String = troop_def.get("domain", "")
		if domain == "Infantry" or domain == "Land":
			result[squad.current_hex.to_key()] = true
	return result

## Validates via can_place and, on OK, appends a new BuildingInstance (with
## hex set, combat HP and total_resources_spent initialized from its def) to
## base.buildings. Returns the Result either way; mutates nothing on failure.
static func place_building(base: BaseInstance, base_def: Dictionary, building_type: String, hex: HexCoord, grid: HexGrid, building_defs: Dictionary, id: String, material: String = "", occupied_unit_hexes: Dictionary = {}) -> Result:
	var result := can_place(base, base_def, building_type, hex, grid, building_defs, occupied_unit_hexes)
	if result != Result.OK:
		return result
	var building := BuildingInstance.new(id, base.id, building_type, 1, material, hex)
	var building_def: Dictionary = building_defs.get(building_type, {})
	building.init_hp(building_def, building_defs)
	building.init_cost(building_def, building_defs)
	base.buildings.append(building)
	return Result.OK

## Validates placement of a standalone building (Tower/Landmine/Road/Bridge/
## Dock) at a hex. Unlike can_place, there's no owning BaseInstance: no
## buildableBuildings/population/2-adjacency/HQ-radius checks — those are
## base-menu concepts that don't apply here. occupied_hexes is the union of
## every base's occupied_hexes() plus every existing standalone building's
## hex, built by standalone_occupied_hexes() below.
##
## Unlike can_place's implicit Plains default, a standalone building with no
## placementRequirement at all (Tower, Landmine) is buildable on any terrain
## per their notes — so siteTerrain is only enforced when the def names one.
static func can_place_standalone(building_type: String, hex: HexCoord, grid: HexGrid, building_defs: Dictionary, occupied_hexes: Dictionary, occupied_unit_hexes: Dictionary = {}) -> Result:
	var building_def: Dictionary = building_defs.get(building_type, {})
	if not building_def.get("isStandalone", false):
		return Result.NOT_STANDALONE

	if not grid.has_hex(hex):
		return Result.OUT_OF_HEX_BOUNDS

	var hex_key := hex.to_key()
	if occupied_hexes.has(hex_key):
		return Result.HEX_OCCUPIED
	if occupied_unit_hexes.has(hex_key):
		return Result.HEX_OCCUPIED_BY_UNIT

	var placement_requirement: Dictionary = building_def.get("placementRequirement", {})
	if placement_requirement.has("siteTerrain"):
		var required_site_terrain := _site_terrain(placement_requirement["siteTerrain"])
		if grid.get_terrain(hex) != required_site_terrain:
			return Result.WRONG_SITE_TERRAIN

	var adjacent_terrain_required: String = placement_requirement.get("adjacentTerrainRequired", "")
	if adjacent_terrain_required != "":
		var satisfied := false
		for neighbor in HexCoord.neighbors(hex):
			if _matches_adjacent_terrain_required(adjacent_terrain_required, grid.get_terrain(neighbor)):
				satisfied = true
				break
		if not satisfied:
			return Result.MISSING_ADJACENT_TERRAIN

	return Result.OK

## Minimum adjacent existing buildings required for a Wall — per
## 02-bases-and-buildings.md, only ONE (not MIN_ADJACENT_BUILDINGS's two).
const MIN_ADJACENT_BUILDINGS_FOR_WALL := 1

## Validates placement of a Wall on the edge between `hex_a` and `hex_b`, per
## 02-bases-and-buildings.md ("sits on the border between two hexes... Wall
## blocks movement and line-of-sight... Placement only requires one existing
## adjacent building, not the usual two... Doesn't consume a population
## slot"). Unlike can_place, a Wall has no hex of its own, so there's no
## HEX_OCCUPIED/HEX_OCCUPIED_BY_UNIT/siteTerrain/population check — instead:
## both hexes must be on the grid and mutually adjacent, the edge mustn't
## already be walled, and — since a Wall's "1 adjacent building" has no hex of
## its own to count neighbors around — this reads as "the edge runs along a
## hex this base has already built on" (at least one of hex_a/hex_b is in
## base.occupied_hexes()), a placeholder interpretation in the same spirit as
## hq_build_radius/HILLS_INFANTRY_COST: the design doc pins the *count* (1,
## not 2) but not the exact adjacency shape for an edge-based building.
static func can_place_wall(base: BaseInstance, base_def: Dictionary, hex_a: HexCoord, hex_b: HexCoord, grid: HexGrid, building_defs: Dictionary) -> Result:
	var buildable: Array = base_def.get("buildableBuildings", [])
	if not buildable.has("wall"):
		return Result.NOT_BUILDABLE_AT_BASE

	if not grid.has_hex(hex_a) or not grid.has_hex(hex_b):
		return Result.OUT_OF_HEX_BOUNDS
	if HexCoord.distance(hex_a, hex_b) != 1:
		return Result.EDGE_NOT_ADJACENT_HEXES
	if grid.is_walled_edge(hex_a, hex_b):
		return Result.EDGE_ALREADY_WALLED

	var occupied := base.occupied_hexes()
	var adjacent_building_count := 0
	if occupied.has(hex_a.to_key()):
		adjacent_building_count += 1
	if occupied.has(hex_b.to_key()):
		adjacent_building_count += 1
	if adjacent_building_count < MIN_ADJACENT_BUILDINGS_FOR_WALL:
		return Result.NOT_ENOUGH_ADJACENT_BUILDINGS_FOR_WALL

	var hq_hex := _hq_hex(base)
	if hq_hex != null and min(HexCoord.distance(hex_a, hq_hex), HexCoord.distance(hex_b, hq_hex)) > hq_build_radius(base.hq_level):
		return Result.OUTSIDE_HQ_RADIUS

	return Result.OK

## Validates via can_place_wall and, on OK, appends a new Wall BuildingInstance
## (hex null, hex_a/hex_b set instead — see BuildingInstance) to base.buildings
## and wires it into grid.set_wall() so movement/pathing picks it up
## immediately. Reuses base.buildings/BuildingRegenSystem/CombatResolver's
## existing base-building loops wholesale (they already iterate
## base.buildings generically) rather than a parallel Wall registry — a Wall
## is just a BuildingInstance whose position is an edge instead of a hex.
static func place_wall(base: BaseInstance, base_def: Dictionary, hex_a: HexCoord, hex_b: HexCoord, grid: HexGrid, building_defs: Dictionary, id: String, material: String = "") -> Result:
	var result := can_place_wall(base, base_def, hex_a, hex_b, grid, building_defs)
	if result != Result.OK:
		return result
	var wall := BuildingInstance.new(id, base.id, "wall", 1, material)
	wall.hex_a = hex_a
	wall.hex_b = hex_b
	wall.init_hp(building_defs.get("wall", {}), building_defs)
	wall.init_cost(building_defs.get("wall", {}), building_defs)
	base.buildings.append(wall)
	grid.set_wall(hex_a, hex_b, true)
	return Result.OK

## Union of every base's occupied_hexes() plus every standalone building's
## hex, as {hex_key: BuildingInstance} — the standalone-path equivalent of
## BaseInstance.occupied_hexes(), since standalone buildings have no owning
## base to ask.
static func standalone_occupied_hexes(bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance]) -> Dictionary:
	var result: Dictionary = {}
	for base in bases:
		for key in base.occupied_hexes():
			result[key] = base.occupied_hexes()[key]
	for building in standalone_buildings:
		if building.hex != null:
			result[building.hex.to_key()] = building
	return result

## Building types exempt from the Land-vehicle building-block rule below —
## infrastructure meant to be driven over, not an obstacle (01-map-and-terrain.md).
const LAND_PASSABLE_BUILDING_TYPES := ["road", "bridge"]

## {hex_key: true} for every hex a `Land`-domain unit cannot enter: any
## standing (non-ruin, non-destroyed) building's hex, base-attached or
## standalone, except Road/Bridge (see LAND_PASSABLE_BUILDING_TYPES) and Wall
## (edge-keyed, `hex == null`, already excluded by base.occupied_hexes()).
## Infantry/Air/Naval never consult this — HexGrid.edge_cost only applies it
## for Domain.LAND, same as every other Domain-specific terrain rule.
static func land_blocking_hexes(bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance]) -> Dictionary:
	var result: Dictionary = {}
	for base in bases:
		var occupied := base.occupied_hexes()
		for key in occupied:
			if _blocks_land(occupied[key]):
				result[key] = true
	for building in standalone_buildings:
		if building.hex != null and _blocks_land(building):
			result[building.hex.to_key()] = true
	return result

static func _blocks_land(building: BuildingInstance) -> bool:
	if LAND_PASSABLE_BUILDING_TYPES.has(building.building_type):
		return false
	if building.is_ruin or (building.max_hp > 0.0 and building.current_hp <= 0.0):
		return false
	return true

## Building types a Naval carrier may disembark land cargo onto (or pick
## boarding cargo up from) per 01-map-and-terrain.md's Naval/Coastline Rules
## ("Naval troops can only disembark onto land at a Dock, a Port/Shipyard, or
## a Harbour") — consumed by CargoSystem.unload()/can_board(), not grid
## pathing (none of these touch grid infrastructure; a docked ship's cargo
## disembarks via the Cargo system, it doesn't path there as a Naval-domain
## move).
const NAVAL_LANDING_BUILDING_TYPES := ["dock", "port", "shipyard", "harbour"]

## True if `hex` carries a Dock, Port, Shipyard, or Harbour — base-attached or
## standalone, per NAVAL_LANDING_BUILDING_TYPES.
static func is_naval_landing_hex(hex: HexCoord, bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance]) -> bool:
	var occupied := standalone_occupied_hexes(bases, standalone_buildings)
	var building: BuildingInstance = occupied.get(hex.to_key())
	return building != null and NAVAL_LANDING_BUILDING_TYPES.has(building.building_type)

## Validates via can_place_standalone and, on OK, appends a new
## BuildingInstance (base_id "", owner_id set) to standalone_buildings.
## Road/Bridge additionally get wired into grid infrastructure so pathfinding
## picks them up immediately (Terrain.effective_cost/edge_cost already
## consume get_infrastructure). Dock/Tower/Landmine don't touch
## infrastructure — Dock's disembark-gating (see is_naval_landing_hex above,
## consumed by CargoSystem.unload) and Tower/Landmine's combat role are
## separate systems.
static func place_standalone_building(bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], building_type: String, hex: HexCoord, grid: HexGrid, building_defs: Dictionary, id: String, owner_id: String, material: String = "", occupied_unit_hexes: Dictionary = {}) -> Result:
	var occupied := standalone_occupied_hexes(bases, standalone_buildings)
	var result := can_place_standalone(building_type, hex, grid, building_defs, occupied, occupied_unit_hexes)
	if result != Result.OK:
		return result
	var building := BuildingInstance.new(id, "", building_type, 1, material, hex, owner_id)
	building.init_hp(building_defs.get(building_type, {}), building_defs)
	building.init_cost(building_defs.get(building_type, {}), building_defs)
	standalone_buildings.append(building)
	if building_type == "road":
		grid.set_infrastructure(hex, Terrain.Infrastructure.ROAD)
	elif building_type == "bridge":
		grid.set_infrastructure(hex, Terrain.Infrastructure.BRIDGE)
	return Result.OK
