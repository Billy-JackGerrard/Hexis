## Headless assertion suite for sim/instances placement/population logic. Run with:
##   godot --headless --script res://tests/test_placement.gd
extends SceneTree

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

var _building_defs: Dictionary
var _base_defs: Dictionary
var _troop_defs: Dictionary

func _init() -> void:
	_building_defs = DataLoader.load_dir("res://data/buildings")
	_base_defs = DataLoader.load_dir("res://data/bases")
	_troop_defs = DataLoader.load_dir("res://data/troops")

	print("Population")
	_test_population()
	print("BaseFactory seeding")
	_test_seeding()
	print("BuildingPlacement eligibility/fixed/standalone")
	_test_eligibility()
	print("BuildingPlacement hex occupancy")
	_test_hex_occupancy()
	print("BuildingPlacement terrain requirements")
	_test_terrain()
	print("BuildingPlacement adjacency")
	_test_adjacency()
	print("BuildingPlacement HQ radius")
	_test_hq_radius()
	print("BuildingPlacement population gate (integration)")
	_test_population_gate()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _plains_grid(hexes: Array) -> HexGrid:
	var grid := HexGrid.new()
	for h in hexes:
		grid.set_terrain(h, Terrain.Type.PLAINS)
	return grid

func _test_population() -> void:
	var fresh_base := BaseInstance.new("pb1", "capital", "p1", 1)
	_check(Population.population_cap(fresh_base, _building_defs) == 2, "hq level 1, no houses -> population cap 2")
	_check(Population.population_used(fresh_base, _building_defs) == 0, "no buildings -> population used 0")
	_check(Population.has_capacity_for(fresh_base, "farm", _building_defs), "fresh base has room for a non-house building")

	fresh_base.buildings.append(BuildingInstance.new("h1", "pb1", "house", 1))
	_check(Population.population_cap(fresh_base, _building_defs) == 6, "one level-1 House adds 4 capacity -> cap 2+4=6")

	fresh_base.buildings.append(BuildingInstance.new("f1", "pb1", "farm", 1))
	fresh_base.buildings.append(BuildingInstance.new("q1", "pb1", "quarry", 1))
	_check(Population.population_used(fresh_base, _building_defs) == 2, "House doesn't count; Farm+Quarry (populationCost 1 each) do")
	_check(Population.has_capacity_for(fresh_base, "mine", _building_defs), "2 used < 6 cap -> room for another building")

	for i in range(4):
		fresh_base.buildings.append(BuildingInstance.new("t%d" % i, "pb1", "turret", 1))
	_check(Population.population_used(fresh_base, _building_defs) == 6, "6 population-costing buildings placed")
	_check(not Population.has_capacity_for(fresh_base, "mine", _building_defs), "used == cap -> no room for a non-house building")
	_check(Population.has_capacity_for(fresh_base, "house", _building_defs), "House is always placeable regardless of capacity")
	_check(Population.has_capacity_for(fresh_base, "hq", _building_defs), "HQ is always placeable regardless of capacity")

func _test_seeding() -> void:
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := BaseFactory.seed_base("b2", capital_def, "p1", HexCoord.new(0, 0), grid)

	_check(seeded.buildings.size() == 3, "capital seeds exactly 3 buildings (HQ/Farm/Quarry)")
	var hq := seeded.buildings_of_type("hq")[0]
	var farm := seeded.buildings_of_type("farm")[0]
	var quarry := seeded.buildings_of_type("quarry")[0]
	_check(hq.hex.equals(HexCoord.new(0, 0)), "HQ seeded at the given hq_hex")
	_check(HexCoord.distance(hq.hex, farm.hex) == 1, "Farm seeded adjacent to HQ")
	_check(HexCoord.distance(hq.hex, quarry.hex) == 1, "Quarry seeded adjacent to HQ")
	_check(HexCoord.distance(farm.hex, quarry.hex) == 1, "Farm and Quarry are mutually adjacent")
	for b in seeded.buildings:
		_check(grid.get_terrain(b.hex) == Terrain.Type.PLAINS, "%s seeded on Plains" % b.building_type)

func _fresh_seeded_base(id: String, grid: HexGrid, hq_level: int) -> BaseInstance:
	var base := BaseFactory.seed_base(id, _base_defs["capital"], "p1", HexCoord.new(0, 0), grid)
	base.hq_level = hq_level
	return base

func _test_eligibility() -> void:
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b3", grid, 2)

	_check(BuildingPlacement.can_place(seeded, capital_def, "command_centre", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"Command Centre placeable at Capital, adjacent to HQ+Farm, within population/radius")

	_check(BuildingPlacement.can_place(seeded, capital_def, "hq", HexCoord.new(99, 99), grid, _building_defs) == BuildingPlacement.Result.IS_FIXED,
		"HQ can never be freshly built (isFixed)")

	_check(BuildingPlacement.can_place(seeded, capital_def, "stone_works", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.NOT_BUILDABLE_AT_BASE,
		"Stone Works is Foundry Reach-exclusive, not buildable at Capital")

	var standalone_test_def := {"id": "test_base", "buildableBuildings": ["road"]}
	_check(BuildingPlacement.can_place(seeded, standalone_test_def, "road", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.IS_STANDALONE,
		"standalone buildings (Road) are rejected by the base-tied validator")

func _test_hex_occupancy() -> void:
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b4", grid, 1)

	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(0, 0), grid, _building_defs) == BuildingPlacement.Result.HEX_OCCUPIED,
		"can't place on a hex already occupied by another building (HQ)")

	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(500, 500), grid, _building_defs) == BuildingPlacement.Result.OUT_OF_HEX_BOUNDS,
		"hex not present in the grid at all")

	var infantry_squad := SquadInstance.new("s1", "p2", "rifleman", HexCoord.new(0, 1))
	var ground_occupied := BuildingPlacement.ground_unit_hexes([infantry_squad], _troop_defs)
	_check(ground_occupied.has(HexCoord.new(0, 1).to_key()), "Infantry squad blocks its hex for placement")
	_check(BuildingPlacement.can_place(seeded, capital_def, "command_centre", HexCoord.new(0, 1), grid, _building_defs, ground_occupied) == BuildingPlacement.Result.HEX_OCCUPIED_BY_UNIT,
		"can't build on a hex occupied by a ground troop")

	var air_squad := SquadInstance.new("s2", "p2", "flamecopter", HexCoord.new(0, 1))
	var air_occupied := BuildingPlacement.ground_unit_hexes([air_squad], _troop_defs)
	_check(not air_occupied.has(HexCoord.new(0, 1).to_key()), "Air squads don't block building placement")

func _test_terrain() -> void:
	var grid := HexGrid.new()
	for h in [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1)]:
		grid.set_terrain(h, Terrain.Type.PLAINS)
	grid.set_terrain(HexCoord.new(5, 5), Terrain.Type.FOREST)
	for h in [HexCoord.new(4, 4), HexCoord.new(5, 4), HexCoord.new(5, 3), HexCoord.new(4, 3), HexCoord.new(3, 4), HexCoord.new(3, 5), HexCoord.new(4, 5)]:
		grid.set_terrain(h, Terrain.Type.PLAINS)
	grid.set_terrain(HexCoord.new(0, -2), Terrain.Type.OCEAN)

	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b5", grid, 2)

	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(5, 5), grid, _building_defs) == BuildingPlacement.Result.WRONG_SITE_TERRAIN,
		"Farm (siteTerrain Plains) rejected on a Forest hex")

	_check(BuildingPlacement.can_place(seeded, capital_def, "harbour", HexCoord.new(4, 4), grid, _building_defs) == BuildingPlacement.Result.MISSING_ADJACENT_TERRAIN,
		"Harbour rejected when no neighboring hex is Water")

	_check(BuildingPlacement.can_place(seeded, capital_def, "harbour", HexCoord.new(0, -1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"Harbour placeable on Plains adjacent to Water, with 2 adjacent buildings (HQ+Quarry)")

func _test_adjacency() -> void:
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(-1, 0), HexCoord.new(0, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b6", grid, 2)

	_check(BuildingPlacement.can_place(seeded, capital_def, "turret", HexCoord.new(-1, 0), grid, _building_defs) == BuildingPlacement.Result.NOT_ENOUGH_ADJACENT_BUILDINGS,
		"hex touching only 1 existing building (HQ) is rejected")

	_check(BuildingPlacement.can_place(seeded, capital_def, "turret", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"hex touching 2 existing buildings (HQ+Farm) is accepted")

func _test_hq_radius() -> void:
	var grid := _plains_grid([HexCoord.new(10, 0), HexCoord.new(11, 0), HexCoord.new(10, 1)])
	var far_base := BaseInstance.new("b7", "capital", "p1", 1, HexCoord.new(0, 0))
	far_base.buildings.append(BuildingInstance.new("far1", "b7", "turret", 1, "", HexCoord.new(10, 0)))
	far_base.buildings.append(BuildingInstance.new("far2", "b7", "turret", 1, "", HexCoord.new(11, 0)))
	var capital_def: Dictionary = _base_defs["capital"]

	_check(BuildingPlacement.hq_build_radius(1) == 4, "hq_build_radius placeholder formula: level*2+2")
	_check(BuildingPlacement.can_place(far_base, capital_def, "turret", HexCoord.new(10, 1), grid, _building_defs) == BuildingPlacement.Result.OUTSIDE_HQ_RADIUS,
		"hex has 2 adjacent buildings but is far outside HQ's build radius")

func _test_population_gate() -> void:
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, 1)])
	var base := BaseInstance.new("b8", "capital", "p1", 1, HexCoord.new(0, 0))
	base.buildings.append(BuildingInstance.new("hq1", "b8", "hq", 1, "", HexCoord.new(0, 0)))
	base.buildings.append(BuildingInstance.new("f1", "b8", "farm", 1, "", HexCoord.new(1, 0)))
	base.buildings.append(BuildingInstance.new("q1", "b8", "quarry", 1, "", HexCoord.new(1, -1)))
	var capital_def: Dictionary = _base_defs["capital"]

	_check(Population.population_used(base, _building_defs) == 2 and Population.population_cap(base, _building_defs) == 2,
		"fixture is already at population cap (Farm+Quarry == hq_level*2)")
	_check(BuildingPlacement.can_place(base, capital_def, "turret", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.POPULATION_FULL,
		"non-House placement rejected once population is full")
	_check(BuildingPlacement.can_place(base, capital_def, "house", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"House placement still allowed once population is full")
