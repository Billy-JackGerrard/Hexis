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
	NOT_STANDALONE,
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

## Validates via can_place_standalone and, on OK, appends a new
## BuildingInstance (base_id "", owner_id set) to standalone_buildings.
## Road/Bridge additionally get wired into grid infrastructure so pathfinding
## picks them up immediately (Terrain.effective_cost/edge_cost already
## consume get_infrastructure). Dock/Tower/Landmine don't touch
## infrastructure — Dock's disembark-gating and Tower/Landmine's combat role
## are separate systems.
static func place_standalone_building(bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], building_type: String, hex: HexCoord, grid: HexGrid, building_defs: Dictionary, id: String, owner_id: String, material: String = "", occupied_unit_hexes: Dictionary = {}) -> Result:
	var occupied := standalone_occupied_hexes(bases, standalone_buildings)
	var result := can_place_standalone(building_type, hex, grid, building_defs, occupied, occupied_unit_hexes)
	if result != Result.OK:
		return result
	var building := BuildingInstance.new(id, "", building_type, 1, material, hex, owner_id)
	building.init_hp(building_defs.get(building_type, {}), building_defs)
	standalone_buildings.append(building)
	if building_type == "road":
		grid.set_infrastructure(hex, Terrain.Infrastructure.ROAD)
	elif building_type == "bridge":
		grid.set_infrastructure(hex, Terrain.Infrastructure.BRIDGE)
	return Result.OK
