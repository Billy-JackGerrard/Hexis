## Headless assertion suite for sim/bases placement/population logic. Run with:
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
	print("GarrisonFactory seeding")
	_test_garrison_seeding()
	print("BuildingPlacement eligibility/fixed/standalone")
	_test_eligibility()
	print("BuildingPlacement hex occupancy")
	_test_hex_occupancy()
	print("BuildingPlacement terrain requirements")
	_test_terrain()
	print("BuildingPlacement adjacency")
	_test_adjacency()
	print("BuildingPlacement Bridge-foothold adjacency exception")
	_test_bridge_foothold_exemption()
	print("BuildingPlacement HQ radius")
	_test_hq_radius()
	print("BuildingPlacement population gate (integration)")
	_test_population_gate()
	print("BuildingPlacement standalone placement")
	_test_standalone_placement()
	print("BuildingPlacement Wall placement")
	_test_wall_placement()

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
	# At hq_level 1 no statGrowth is applied yet, so HQ's contribution is just
	# hq.json's authored baseStats.populationCapacity.
	var hq_cap: int = int(_building_defs["hq"]["nonProductionUpgrade"]["baseStats"]["populationCapacity"])
	_check(Population.population_cap(fresh_base, _building_defs) == hq_cap, "hq level %d, no houses -> population cap %d" % [fresh_base.hq_level, hq_cap])
	_check(Population.population_used(fresh_base, _building_defs) == 0, "no buildings -> population used 0")
	_check(Population.has_capacity_for(fresh_base, "farm", _building_defs), "fresh base has room for a non-house building")

	fresh_base.buildings.append(BuildingInstance.new("h1", "pb1", "house", 1))
	var house_capacity_l1: int = int(_building_defs["house"]["nonProductionUpgrade"]["baseStats"]["populationCapacity"])
	_check(Population.population_cap(fresh_base, _building_defs) == hq_cap + house_capacity_l1, "one level-1 House adds its authored populationCapacity (%d) -> cap %d+%d=%d" % [house_capacity_l1, hq_cap, house_capacity_l1, hq_cap + house_capacity_l1])

	fresh_base.buildings.append(BuildingInstance.new("f1", "pb1", "farm", 1))
	fresh_base.buildings.append(BuildingInstance.new("q1", "pb1", "quarry", 1))
	# population_used counts each building with populationCost > 0 as exactly
	# 1 (a threshold check, not a sum of the cost magnitudes -- see
	# Population.population_used) -- so what's data-driven here is WHICH
	# building types count, not the specific cost number.
	var farm_pop_cost: float = float(_building_defs["farm"].get("populationCost", 1))
	var quarry_pop_cost: float = float(_building_defs["quarry"].get("populationCost", 1))
	var used_after_farm_quarry: int = (1 if farm_pop_cost > 0 else 0) + (1 if quarry_pop_cost > 0 else 0)
	_check(Population.population_used(fresh_base, _building_defs) == used_after_farm_quarry, "House doesn't count; Farm+Quarry (populationCost > 0) do")
	_check(Population.has_capacity_for(fresh_base, "mine", _building_defs), "%d used < %d cap -> room for another building" % [used_after_farm_quarry, hq_cap + house_capacity_l1])

	var turret_pop_cost: float = float(_building_defs["turret"].get("populationCost", 1))
	var full_cap: int = hq_cap + house_capacity_l1
	var turrets_to_fill: int = full_cap - used_after_farm_quarry
	for i in range(turrets_to_fill):
		fresh_base.buildings.append(BuildingInstance.new("t%d" % i, "pb1", "turret", 1))
	var used_after_turrets: int = used_after_farm_quarry + (turrets_to_fill if turret_pop_cost > 0 else 0)
	_check(Population.population_used(fresh_base, _building_defs) == used_after_turrets, "%d population-costing buildings placed" % used_after_turrets)
	_check(not Population.has_capacity_for(fresh_base, "mine", _building_defs), "used == cap -> no room for a non-house building")
	_check(Population.has_capacity_for(fresh_base, "house", _building_defs), "House is always placeable regardless of capacity")
	_check(Population.has_capacity_for(fresh_base, "hq", _building_defs), "HQ is always placeable regardless of capacity")

func _test_seeding() -> void:
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := BaseFactory.seed_base("b2", capital_def, "p1", HexCoord.new(0, 0), grid)

	_check(seeded.buildings.size() == 4, "capital seeds exactly 4 buildings (HQ/Farm/Quarry/Command Centre)")
	var hq := seeded.buildings_of_type("hq")[0]
	var farm := seeded.buildings_of_type("farm")[0]
	var quarry := seeded.buildings_of_type("quarry")[0]
	var command_centre := seeded.buildings_of_type("command_centre")[0]
	_check(hq.hex.equals(HexCoord.new(0, 0)), "HQ seeded at the given hq_hex")
	_check(HexCoord.distance(hq.hex, farm.hex) == 1, "Farm seeded adjacent to HQ")
	_check(HexCoord.distance(hq.hex, quarry.hex) == 1, "Quarry seeded adjacent to HQ")
	_check(HexCoord.distance(farm.hex, quarry.hex) == 1, "Farm and Quarry are mutually adjacent")
	_check(HexCoord.distance(hq.hex, command_centre.hex) == 1, "Command Centre seeded adjacent to HQ")
	for b in seeded.buildings:
		_check(grid.get_terrain(b.hex) == Terrain.Type.PLAINS, "%s seeded on Plains" % b.building_type)

func _test_garrison_seeding() -> void:
	var hq_hex := HexCoord.new(0, 0)
	var camp_kaboom_def: Dictionary = _base_defs["camp_kaboom"]
	var squads: Array[SquadInstance] = []
	var troops_by_id: Dictionary = {}
	var troop_id_counter := {"n": 0}
	var next_troop_id := func() -> String:
		troop_id_counter["n"] += 1
		return "gt_%d" % troop_id_counter["n"]
	var squad_id_counter := {"n": 0}
	var next_squad_id := func() -> String:
		squad_id_counter["n"] += 1
		return "gs_%d" % squad_id_counter["n"]

	GarrisonFactory.seed_garrison(camp_kaboom_def, "p1", hq_hex, _troop_defs, squads, troops_by_id, next_troop_id, next_squad_id)

	# earthshaker (count 2, maxSquadSize 2) and tank_obliterator (count 2,
	# maxSquadSize 4) each fit within a single squad.
	_check(squads.size() == 2, "camp_kaboom's initialGarrison seeds 2 squads (one per troop type, both fit their maxSquadSize)")
	var total_troops := 0
	for squad in squads:
		total_troops += squad.member_ids.size()
		_check(squad.owner_id == "p1", "seeded squad carries the given owner_id")
		_check(HexCoord.distance(hq_hex, squad.current_hex) == Tuning.GARRISON_RING_RADIUS, "seeded squad stands on the garrison ring, clear of the building flower")
		for member_id in squad.member_ids:
			var troop: TroopInstance = troops_by_id[member_id]
			_check(troop.owner_id == "p1", "seeded troop carries the given owner_id")
			_check(troop.squad_id == squad.id, "seeded troop's squad_id points back at its squad")
			var expected_hp: float = float(_troop_defs[troop.unit_type]["hp"])
			_check(troop.current_hp == expected_hp, "seeded troop's HP comes from its troop def")
	_check(total_troops == 4, "4 total garrison troops seeded (2 earthshaker + 2 tank_obliterator)")
	_check(troops_by_id.size() == 4, "every seeded troop registered in troops_by_id")

	var capital_squads: Array[SquadInstance] = []
	var capital_troops_by_id: Dictionary = {}
	GarrisonFactory.seed_garrison(_base_defs["capital"], "p1", hq_hex, _troop_defs, capital_squads, capital_troops_by_id, next_troop_id, next_squad_id)
	_check(capital_squads.is_empty(), "Capital has no initialGarrison -> seeds no squads")

func _fresh_seeded_base(id: String, grid: HexGrid, hq_level: int) -> BaseInstance:
	var base := BaseFactory.seed_base(id, _base_defs["capital"], "p1", HexCoord.new(0, 0), grid)
	base.hq_level = hq_level
	return base

func _test_eligibility() -> void:
	# (0,-1) included so seed_base's Command Centre (direction 2) lands there
	# on-grid instead of spilling over onto (0,1), which this test needs free.
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1), HexCoord.new(0, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b3", grid, 2)

	_check(BuildingPlacement.can_place(seeded, capital_def, "barracks", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"Barracks placeable at Capital, adjacent to HQ+Farm, within population/radius")

	_check(BuildingPlacement.can_place(seeded, capital_def, "hq", HexCoord.new(99, 99), grid, _building_defs) == BuildingPlacement.Result.IS_FIXED,
		"HQ can never be freshly built (isFixed)")

	_check(BuildingPlacement.can_place(seeded, capital_def, "command_centre", HexCoord.new(99, 99), grid, _building_defs) == BuildingPlacement.Result.IS_FIXED,
		"Command Centre can never be freshly built (isFixed)")

	_check(BuildingPlacement.can_place(seeded, capital_def, "stone_works", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.NOT_BUILDABLE_AT_BASE,
		"Stone Works is Foundry Reach-exclusive, not buildable at Capital")

	var standalone_test_def := {"id": "test_base", "buildableBuildings": ["road"]}
	_check(BuildingPlacement.can_place(seeded, standalone_test_def, "road", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.IS_STANDALONE,
		"standalone buildings (Road) are rejected by the base-tied validator")

func _test_hex_occupancy() -> void:
	# (0,-1) included so seed_base's Command Centre (direction 2) lands there
	# on-grid instead of spilling over onto (0,1), which this test needs free.
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1), HexCoord.new(0, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b4", grid, 1)

	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(0, 0), grid, _building_defs) == BuildingPlacement.Result.HEX_OCCUPIED,
		"can't place on a hex already occupied by another building (HQ)")

	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(500, 500), grid, _building_defs) == BuildingPlacement.Result.OUT_OF_HEX_BOUNDS,
		"hex not present in the grid at all")

	var infantry_squad := SquadInstance.new("s1", "p2", "rifleman", HexCoord.new(0, 1))
	var ground_occupied := BuildingPlacement.ground_unit_hexes([infantry_squad], _troop_defs)
	_check(ground_occupied.has(HexCoord.new(0, 1).to_key()), "Infantry squad blocks its hex for placement")
	_check(BuildingPlacement.can_place(seeded, capital_def, "barracks", HexCoord.new(0, 1), grid, _building_defs, ground_occupied) == BuildingPlacement.Result.HEX_OCCUPIED_BY_UNIT,
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
	grid.set_terrain(HexCoord.new(0, 1), Terrain.Type.PLAINS)
	grid.set_terrain(HexCoord.new(0, 2), Terrain.Type.OCEAN)

	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b5", grid, 2)
	# Seeded at (0,0)=hq, (1,0)=farm, (1,-1)=quarry, (0,-1)=command_centre.

	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(5, 5), grid, _building_defs) == BuildingPlacement.Result.WRONG_SITE_TERRAIN,
		"Farm (siteTerrain Plains) rejected on a Forest hex")

	_check(BuildingPlacement.can_place(seeded, capital_def, "harbour", HexCoord.new(4, 4), grid, _building_defs) == BuildingPlacement.Result.MISSING_ADJACENT_TERRAIN,
		"Harbour rejected when no neighboring hex is Water")

	_check(BuildingPlacement.can_place(seeded, capital_def, "harbour", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"Harbour placeable on Plains adjacent to Water, with 2 adjacent buildings (HQ+Farm)")

	## Treehouse's terrainException ("Forest") is a base-level, not per-building,
	## exception -- per data/bases/treehouse.json's notes, ALL of its buildable
	## buildings get Forest as an additional allowed site terrain alongside the
	## Plains default, not a replacement for it.
	var treehouse_def: Dictionary = _base_defs["treehouse"]
	var treehouse_grid := HexGrid.new()
	treehouse_grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	treehouse_grid.set_terrain(HexCoord.new(-1, 0), Terrain.Type.PLAINS)
	treehouse_grid.set_terrain(HexCoord.new(0, -1), Terrain.Type.FOREST)
	var treehouse_base := BaseInstance.new("th1", "treehouse", "p1", 1, HexCoord.new(0, 0))
	treehouse_base.buildings.append(BuildingInstance.new("th_hq", "th1", "hq", 1, "", HexCoord.new(0, 0)))
	treehouse_base.buildings.append(BuildingInstance.new("th_q", "th1", "quarry", 1, "", HexCoord.new(-1, 0)))

	_check(BuildingPlacement.can_place(treehouse_base, treehouse_def, "farm", HexCoord.new(0, -1), treehouse_grid, _building_defs) == BuildingPlacement.Result.OK,
		"Treehouse: Farm (default siteTerrain Plains) also placeable directly on Forest via terrainException")
	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(5, 5), grid, _building_defs) == BuildingPlacement.Result.WRONG_SITE_TERRAIN,
		"Capital (no terrainException): Farm still rejected on Forest")

	## Lumber Mill's own generic requirement is Plains + adjacent Forest; at
	## Treehouse it should also be placeable directly on Forest with no
	## adjacent-Forest requirement, since sitting on Forest IS the exception.
	_check(BuildingPlacement.can_place(treehouse_base, treehouse_def, "lumber_mill", HexCoord.new(0, -1), treehouse_grid, _building_defs) == BuildingPlacement.Result.OK,
		"Treehouse: Lumber Mill placeable directly on Forest, bypassing its generic adjacentTerrainRequired")

	## Windy Peaks reuses the exact same generic terrainException mechanism,
	## just with "Hill" as the base_def value -- nothing building-specific was
	## needed for this to work, confirming the mechanism generalizes.
	var windy_peaks_def: Dictionary = _base_defs["windy_peaks"]
	var windy_peaks_grid := HexGrid.new()
	windy_peaks_grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	windy_peaks_grid.set_terrain(HexCoord.new(-1, 0), Terrain.Type.PLAINS)
	windy_peaks_grid.set_terrain(HexCoord.new(0, -1), Terrain.Type.HILLS)
	windy_peaks_grid.set_terrain(HexCoord.new(-10, -10), Terrain.Type.HILLS)
	var windy_peaks_base := BaseInstance.new("wp1", "windy_peaks", "p1", 1, HexCoord.new(0, 0))
	windy_peaks_base.buildings.append(BuildingInstance.new("wp_hq", "wp1", "hq", 1, "", HexCoord.new(0, 0)))
	windy_peaks_base.buildings.append(BuildingInstance.new("wp_q", "wp1", "quarry", 1, "", HexCoord.new(-1, 0)))

	_check(BuildingPlacement.can_place(windy_peaks_base, windy_peaks_def, "farm", HexCoord.new(0, -1), windy_peaks_grid, _building_defs) == BuildingPlacement.Result.OK,
		"Windy Peaks: Farm (default siteTerrain Plains) also placeable directly on Hill via terrainException")
	_check(BuildingPlacement.can_place(seeded, capital_def, "farm", HexCoord.new(-10, -10), windy_peaks_grid, _building_defs) == BuildingPlacement.Result.WRONG_SITE_TERRAIN,
		"Capital (no terrainException): Farm still rejected on Hill")

func _test_adjacency() -> void:
	# (0,-1) included so seed_base's Command Centre (direction 2) lands there
	# on-grid instead of spilling over onto (-1,1), which this test needs free.
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1), HexCoord.new(-1, 1), HexCoord.new(0, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("b6", grid, 2)
	# Seeded at (0,0)=hq, (1,0)=farm, (1,-1)=quarry, (0,-1)=command_centre.
	# (-1,1) touches only HQ among these five.

	_check(BuildingPlacement.can_place(seeded, capital_def, "turret", HexCoord.new(-1, 1), grid, _building_defs) == BuildingPlacement.Result.NOT_ENOUGH_ADJACENT_BUILDINGS,
		"hex touching only 1 existing building (HQ) is rejected")

	_check(BuildingPlacement.can_place(seeded, capital_def, "turret", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"hex touching 2 existing buildings (HQ+Farm) is accepted")

## Per 02-bases-and-buildings.md's Bridge exception: near_bank(0,0) --
## bridge(1,0, River+Bridge infrastructure) -- far_bank(2,0). far_bank has
## zero adjacent buildings of its own (the Bridge hex isn't a "building" for
## adjacency-counting), so it would normally fail the 2-adjacent-buildings
## rule -- unless the Bridge's OTHER side (near_bank) already has a building,
## which stands in as the missing adjacency.
func _test_bridge_foothold_exemption() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.RIVER)
	grid.set_terrain(HexCoord.new(2, 0), Terrain.Type.PLAINS)
	grid.set_infrastructure(HexCoord.new(1, 0), Terrain.Infrastructure.BRIDGE)
	var capital_def: Dictionary = _base_defs["capital"]

	var base_with_foothold := BaseInstance.new("bb1", "capital", "p1", 1, HexCoord.new(0, 0))
	base_with_foothold.buildings.append(BuildingInstance.new("near1", "bb1", "hq", 1, "", HexCoord.new(0, 0)))
	_check(BuildingPlacement.can_place(base_with_foothold, capital_def, "farm", HexCoord.new(2, 0), grid, _building_defs) == BuildingPlacement.Result.OK,
		"far-bank hex adjacent to a Bridge is exempt from the 2-adjacent-buildings rule once the near bank has a foothold")

	var base_without_foothold := BaseInstance.new("bb2", "capital", "p1", 1, HexCoord.new(0, 0))
	_check(BuildingPlacement.can_place(base_without_foothold, capital_def, "farm", HexCoord.new(2, 0), grid, _building_defs) == BuildingPlacement.Result.NOT_ENOUGH_ADJACENT_BUILDINGS,
		"the Bridge alone doesn't seed a foothold from nothing -- no near-bank building means no exemption")

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

	var farm_pop_cost: float = float(_building_defs["farm"].get("populationCost", 1))
	var quarry_pop_cost: float = float(_building_defs["quarry"].get("populationCost", 1))
	var expected_used: int = (1 if farm_pop_cost > 0 else 0) + (1 if quarry_pop_cost > 0 else 0)
	# hq_level 1's populationCap is hq.json's authored baseStats.populationCapacity;
	# top up with extra population-costing buildings (off-grid, only population
	# math cares about base.buildings, not placement/adjacency) to reach it exactly.
	var hq_cap: int = int(_building_defs["hq"]["nonProductionUpgrade"]["baseStats"]["populationCapacity"])
	var i := 0
	while expected_used < hq_cap:
		base.buildings.append(BuildingInstance.new("filler%d" % i, "b8", "turret", 1, "", HexCoord.new(50 + i, 50)))
		expected_used += 1
		i += 1
	_check(Population.population_used(base, _building_defs) == expected_used and Population.population_cap(base, _building_defs) == hq_cap,
		"fixture is already at population cap (Farm+Quarry+filler turrets == HQ's authored populationCapacity)")
	_check(BuildingPlacement.can_place(base, capital_def, "turret", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.POPULATION_FULL,
		"non-House placement rejected once population is full")
	_check(BuildingPlacement.can_place(base, capital_def, "house", HexCoord.new(0, 1), grid, _building_defs) == BuildingPlacement.Result.OK,
		"House placement still allowed once population is full")

func _test_standalone_placement() -> void:
	# Tower/Landmine have no placementRequirement at all -> buildable on any
	# terrain, unlike can_place's implicit Plains default.
	var mixed_grid := HexGrid.new()
	mixed_grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	mixed_grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.FOREST)
	mixed_grid.set_terrain(HexCoord.new(2, 0), Terrain.Type.HILLS)

	_check(BuildingPlacement.can_place_standalone("tower", HexCoord.new(0, 0), mixed_grid, _building_defs, {}) == BuildingPlacement.Result.OK,
		"Tower placeable on Plains (no siteTerrain restriction)")
	_check(BuildingPlacement.can_place_standalone("tower", HexCoord.new(1, 0), mixed_grid, _building_defs, {}) == BuildingPlacement.Result.OK,
		"Tower placeable on Forest (no siteTerrain restriction)")
	_check(BuildingPlacement.can_place_standalone("landmine", HexCoord.new(2, 0), mixed_grid, _building_defs, {}) == BuildingPlacement.Result.OK,
		"Landmine placeable on Hills (no siteTerrain restriction)")

	# Road requires Forest.
	var forest_grid := HexGrid.new()
	forest_grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	forest_grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.FOREST)
	_check(BuildingPlacement.can_place_standalone("road", HexCoord.new(0, 0), forest_grid, _building_defs, {}) == BuildingPlacement.Result.WRONG_SITE_TERRAIN,
		"Road rejected on a Plains hex (siteTerrain Forest)")
	_check(BuildingPlacement.can_place_standalone("road", HexCoord.new(1, 0), forest_grid, _building_defs, {}) == BuildingPlacement.Result.OK,
		"Road placeable on a Forest hex")

	# Bridge requires River.
	var river_grid := HexGrid.new()
	river_grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	river_grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.RIVER)
	_check(BuildingPlacement.can_place_standalone("bridge", HexCoord.new(0, 0), river_grid, _building_defs, {}) == BuildingPlacement.Result.WRONG_SITE_TERRAIN,
		"Bridge rejected on a Plains hex (siteTerrain River)")
	_check(BuildingPlacement.can_place_standalone("bridge", HexCoord.new(1, 0), river_grid, _building_defs, {}) == BuildingPlacement.Result.OK,
		"Bridge placeable on a River hex")

	# Dock requires Plains + an adjacent Water (Ocean/River) hex. Note:
	# HexGrid.get_terrain() defaults an untracked hex to OCEAN, so every
	# neighbor here must be explicitly set to a non-Water terrain to actually
	# exercise the rejection path.
	var dock_grid := HexGrid.new()
	dock_grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	for neighbor in HexCoord.neighbors(HexCoord.new(0, 0)):
		dock_grid.set_terrain(neighbor, Terrain.Type.PLAINS)
	dock_grid.set_terrain(HexCoord.new(5, 5), Terrain.Type.PLAINS)
	dock_grid.set_terrain(HexCoord.new(6, 5), Terrain.Type.OCEAN)
	_check(BuildingPlacement.can_place_standalone("dock", HexCoord.new(0, 0), dock_grid, _building_defs, {}) == BuildingPlacement.Result.MISSING_ADJACENT_TERRAIN,
		"Dock rejected on Plains with no adjacent Water")
	_check(BuildingPlacement.can_place_standalone("dock", HexCoord.new(5, 5), dock_grid, _building_defs, {}) == BuildingPlacement.Result.OK,
		"Dock placeable on Plains adjacent to Ocean")

	# A non-standalone type is rejected by the standalone path.
	_check(BuildingPlacement.can_place_standalone("farm", HexCoord.new(0, 0), mixed_grid, _building_defs, {}) == BuildingPlacement.Result.NOT_STANDALONE,
		"a base-tied type (Farm) is rejected by the standalone validator")

	# Hex occupancy against base buildings.
	var occ_grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1)])
	var occ_base := _fresh_seeded_base("sb1", occ_grid, 1)
	var hq_hex: HexCoord = occ_base.buildings_of_type("hq")[0].hex
	var occupied_with_base := BuildingPlacement.standalone_occupied_hexes([occ_base], [])
	_check(BuildingPlacement.can_place_standalone("tower", hq_hex, occ_grid, _building_defs, occupied_with_base) == BuildingPlacement.Result.HEX_OCCUPIED,
		"standalone placement rejected on a hex already occupied by a base building")

	# Hex occupancy against another standalone building.
	var standalone_hex := HexCoord.new(20, 20)
	var lone_grid := HexGrid.new()
	lone_grid.set_terrain(standalone_hex, Terrain.Type.PLAINS)
	var existing_tower := BuildingInstance.new("t1", "", "tower", 1, "stone", standalone_hex, "p1")
	var occupied_with_standalone := BuildingPlacement.standalone_occupied_hexes([], [existing_tower])
	_check(BuildingPlacement.can_place_standalone("landmine", standalone_hex, lone_grid, _building_defs, occupied_with_standalone) == BuildingPlacement.Result.HEX_OCCUPIED,
		"standalone placement rejected on a hex already occupied by another standalone building")

	# Ground-unit occupancy blocks standalone placement too.
	var unit_hex := HexCoord.new(30, 30)
	var unit_grid := HexGrid.new()
	unit_grid.set_terrain(unit_hex, Terrain.Type.PLAINS)
	var infantry_squad := SquadInstance.new("su1", "p2", "rifleman", unit_hex)
	var ground_occupied := BuildingPlacement.ground_unit_hexes([infantry_squad], _troop_defs)
	_check(BuildingPlacement.can_place_standalone("tower", unit_hex, unit_grid, _building_defs, {}, ground_occupied) == BuildingPlacement.Result.HEX_OCCUPIED_BY_UNIT,
		"standalone placement rejected on a hex occupied by a ground troop")

	# place_standalone_building end-to-end: appends with owner_id/base_id set,
	# and Road/Bridge placement wires grid infrastructure.
	var build_hex := HexCoord.new(40, 40)
	var build_grid := HexGrid.new()
	build_grid.set_terrain(build_hex, Terrain.Type.FOREST)
	var standalone_buildings: Array[BuildingInstance] = []
	var place_result := BuildingPlacement.place_standalone_building([], standalone_buildings, "road", build_hex, build_grid, _building_defs, "road1", "p1")
	_check(place_result == BuildingPlacement.Result.OK, "place_standalone_building succeeds for a valid Road placement")
	_check(standalone_buildings.size() == 1, "the new standalone building was appended")
	_check(standalone_buildings[0].owner_id == "p1", "the new standalone building carries the given owner_id")
	_check(standalone_buildings[0].base_id == "", "the new standalone building has no base_id")
	_check(build_grid.get_infrastructure(build_hex) == Terrain.Infrastructure.ROAD, "placing a Road wires grid infrastructure so pathfinding picks it up")

	var second_place_result := BuildingPlacement.place_standalone_building([], standalone_buildings, "tower", build_hex, build_grid, _building_defs, "tower1", "p1")
	_check(second_place_result == BuildingPlacement.Result.HEX_OCCUPIED, "a second standalone building can't be placed on the same hex as the first")

func _test_wall_placement() -> void:
	# (0,-1) included alongside HQ's other ring-1 neighbors so seed_base's
	# Command Centre (direction 2) lands on-grid at its normal spot instead of
	# spilling over onto (-1,0) — real sites always have a complete flower
	# (BaseSiteSelector._flower_terrain_ok), this fixture just mirrors that.
	var grid := _plains_grid([HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(1, -1), HexCoord.new(0, -1), HexCoord.new(-1, 0), HexCoord.new(0, 1), HexCoord.new(-1, 1)])
	var capital_def: Dictionary = _base_defs["capital"]
	var seeded := _fresh_seeded_base("w1", grid, 2)
	# Seeded at (0,0)=hq, (1,0)=farm, (1,-1)=quarry, (0,-1)=command centre.

	# A Wall needs only ONE adjacent existing building, unlike a normal
	# building's two — the edge between HQ (0,0) and the empty (-1,0) hex
	# qualifies (HQ alone is enough).
	_check(BuildingPlacement.can_place_wall(seeded, capital_def, HexCoord.new(0, 0), HexCoord.new(-1, 0), grid, _building_defs) == BuildingPlacement.Result.OK,
		"a Wall edge touching just 1 existing building (HQ) is accepted, unlike a normal building's 2-adjacency rule")

	# Neither endpoint of this edge ((-1,0) and its neighbor (-1,1), both
	# unoccupied) is an occupied hex -> rejected.
	_check(BuildingPlacement.can_place_wall(seeded, capital_def, HexCoord.new(-1, 0), HexCoord.new(-1, 1), grid, _building_defs) == BuildingPlacement.Result.NOT_ENOUGH_ADJACENT_BUILDINGS_FOR_WALL,
		"a Wall edge touching zero existing buildings is rejected")

	# The two hexes must actually be neighbors — (1,0) and (-1,0) are both
	# on the grid but 2 hexes apart, not adjacent.
	_check(BuildingPlacement.can_place_wall(seeded, capital_def, HexCoord.new(1, 0), HexCoord.new(-1, 0), grid, _building_defs) == BuildingPlacement.Result.EDGE_NOT_ADJACENT_HEXES,
		"a Wall edge between two non-adjacent hexes is rejected")

	# place_wall end-to-end: appends a hex-less BuildingInstance to
	# base.buildings and wires grid.set_wall() so pathing picks it up.
	var place_result := BuildingPlacement.place_wall(seeded, capital_def, HexCoord.new(0, 0), HexCoord.new(-1, 0), grid, _building_defs, "wall1", "stone")
	_check(place_result == BuildingPlacement.Result.OK, "place_wall succeeds for a valid edge")
	var placed_wall: BuildingInstance = seeded.buildings[seeded.buildings.size() - 1]
	_check(placed_wall.building_type == "wall", "the new building is a wall")
	_check(placed_wall.hex == null, "a Wall has no single hex")
	_check(placed_wall.hex_a.equals(HexCoord.new(0, 0)) and placed_wall.hex_b.equals(HexCoord.new(-1, 0)), "the Wall's hex_a/hex_b record its edge")
	_check(placed_wall.max_hp > 0.0, "the Wall's max_hp is resolved from its material (stone)")
	_check(grid.is_walled_edge(HexCoord.new(0, 0), HexCoord.new(-1, 0)), "place_wall wires grid.set_wall so movement/pathing picks it up immediately")
	_check(not seeded.occupied_hexes().has(HexCoord.new(-1, 0).to_key()), "a Wall doesn't occupy a hex-adjacency slot")

	# The same edge can't be walled twice.
	_check(BuildingPlacement.can_place_wall(seeded, capital_def, HexCoord.new(0, 0), HexCoord.new(-1, 0), grid, _building_defs) == BuildingPlacement.Result.EDGE_ALREADY_WALLED,
		"an already-walled edge is rejected")

	# A Wall doesn't consume population.
	var farm_pop_cost: float = float(_building_defs["farm"].get("populationCost", 1))
	var quarry_pop_cost: float = float(_building_defs["quarry"].get("populationCost", 1))
	var command_centre_pop_cost: float = float(_building_defs["command_centre"].get("populationCost", 1))
	var expected_used: int = (1 if farm_pop_cost > 0 else 0) + (1 if quarry_pop_cost > 0 else 0) + (1 if command_centre_pop_cost > 0 else 0)
	_check(Population.population_used(seeded, _building_defs) == expected_used, "the placed Wall does not count against population (still just Farm+Quarry+Command Centre, populationCost > 0 each)")
