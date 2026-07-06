## Validates whether a building may be placed at a given hex for a base, per
## 02-bases-and-buildings.md's "Expansion Rule (Hex Adjacency)" and
## "Population" sections. Stateless, mirrors SquadCap/CommanderProgression:
## nothing here is stored, every check reads live BaseInstance/HexGrid state.
##
## Walls are deliberately out of scope for this slice — they're edge-keyed
## (not hex-keyed), need only ONE adjacent building instead of two, and don't
## consume population. They land with the combat/line-of-sight slice where
## their edge-blocking behavior actually matters. The bridge-foothold
## adjacency exception is deferred alongside them.
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
}

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

	var adjacent_building_count := 0
	for neighbor in HexCoord.neighbors(hex):
		if occupied.has(neighbor.to_key()):
			adjacent_building_count += 1
	if adjacent_building_count < MIN_ADJACENT_BUILDINGS:
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
## hex set) to base.buildings. Returns the Result either way; mutates nothing
## on failure.
static func place_building(base: BaseInstance, base_def: Dictionary, building_type: String, hex: HexCoord, grid: HexGrid, building_defs: Dictionary, id: String, material: String = "", occupied_unit_hexes: Dictionary = {}) -> Result:
	var result := can_place(base, base_def, building_type, hex, grid, building_defs, occupied_unit_hexes)
	if result != Result.OK:
		return result
	base.buildings.append(BuildingInstance.new(id, base.id, building_type, 1, material, hex))
	return Result.OK
