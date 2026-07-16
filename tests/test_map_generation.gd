## Headless assertion suite for sim/worldgen/* and sim/map_generator.gd. Run with:
##   godot --headless --script res://tests/test_map_generation.gd
extends SceneTree

var _failures: int = 0
var _base_defs: Dictionary
var _building_defs: Dictionary
var _troop_defs: Dictionary
var _outpost_defs: Dictionary

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_base_defs = DataLoader.load_dir("res://data/bases")
	_building_defs = DataLoader.load_dir("res://data/buildings")
	_troop_defs = DataLoader.load_dir("res://data/troops")
	_outpost_defs = DataLoader.load_dir("res://data/outposts")

	print("Hexagon + ocean fringe")
	_test_hexagon_and_fringe()
	print("Biome coverage")
	_test_biomes()
	print("Rivers")
	_test_rivers()
	print("Super river")
	_test_super_river()
	print("Base spacing")
	_test_base_spacing()
	print("Expansion viability")
	_test_expansion_viability()
	print("Unique base def assignment")
	_test_unique_def_assignment()
	print("Kraken Point ocean-edge site")
	_test_kraken_point_site()
	print("Treehouse deep-forest site")
	_test_treehouse_site()
	print("Windy Peaks Hills site")
	_test_windy_peaks_site()
	print("Sky Fortress moat + water connectivity")
	_test_sky_fortress_site()
	print("Rivergate river-adjacent site")
	_test_rivergate_site()
	print("Seeded building placement (collisions, adjacency, walls)")
	_test_seeded_building_placement()
	print("MapGenerator end-to-end")
	_test_map_generator_end_to_end()
	print("MapGenerator garrisons")
	_test_map_generator_garrisons()
	print("MapGenerator player_count guard")
	_test_player_count_guard()
	print("Barbarian outpost placement")
	_test_barbarian_outpost_placement()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _test_hexagon_and_fringe() -> void:
	var radius := 10
	var fringe := 2
	var grid := TerrainGenerator.generate_base_terrain(radius, fringe)
	var origin := HexCoord.new(0, 0)

	var interior_ok := true
	for hex in HexCoord.range_within(origin, radius):
		if grid.get_terrain(hex) != Terrain.Type.PLAINS:
			interior_ok = false
	_check(interior_ok, "every hex within radius is Plains")

	var fringe_ok := true
	for hex in HexCoord.range_within(origin, radius + fringe):
		if HexCoord.distance(origin, hex) > radius and grid.get_terrain(hex) != Terrain.Type.OCEAN:
			fringe_ok = false
	_check(fringe_ok, "fringe ring is Ocean")

	var beyond_ok := true
	for hex in HexCoord.ring(origin, radius + fringe + 1):
		if grid.has_hex(hex):
			beyond_ok = false
	_check(beyond_ok, "hexes beyond radius+fringe report has_hex() == false")

func _test_biomes() -> void:
	var radius := 15
	var grid := TerrainGenerator.generate_base_terrain(radius, 0)
	TerrainGenerator.generate_biomes(grid, radius, 42)
	var origin := HexCoord.new(0, 0)

	var plains := 0
	var forest := 0
	var hills := 0
	var total := 0
	for hex in HexCoord.range_within(origin, radius):
		total += 1
		match grid.get_terrain(hex):
			Terrain.Type.PLAINS:
				plains += 1
			Terrain.Type.FOREST:
				forest += 1
			Terrain.Type.HILLS:
				hills += 1

	_check(plains > forest and plains > hills, "Plains stays the majority terrain")
	var forest_fraction := float(forest) / float(total)
	var hills_fraction := float(hills) / float(total)
	_check(forest_fraction > 0.0 and forest_fraction < Tuning.FOREST_COVERAGE_FRACTION * 1.6, "Forest coverage in a loose band around its budget")
	_check(hills_fraction > 0.0 and hills_fraction < Tuning.HILLS_COVERAGE_FRACTION * 1.6, "Hills coverage in a loose band around its budget")

func _test_rivers() -> void:
	var radius := 20
	var grid := TerrainGenerator.generate_base_terrain(radius, 0)
	var paths := TerrainGenerator.generate_rivers(grid, radius, 42, 4)
	var origin := HexCoord.new(0, 0)

	_check(paths.size() == TerrainGenerator.num_rivers(4), "generated the expected number of rivers")

	var all_contiguous := true
	var all_start_inland := true
	var all_end_at_coast := true
	for path in paths:
		for i in range(path.size() - 1):
			if HexCoord.distance(path[i], path[i + 1]) != 1:
				all_contiguous = false
		if not path.is_empty():
			if HexCoord.distance(origin, path[0]) > radius - Tuning.RIVER_MIN_LENGTH:
				all_start_inland = false
			if HexCoord.distance(origin, path[-1]) < radius:
				all_end_at_coast = false
	_check(all_contiguous, "every river path is an unbroken chain of adjacent hexes")
	_check(all_start_inland, "every river starts well inland")
	_check(all_end_at_coast, "every river reaches the coastline")

	var river_tiles_match := true
	for path in paths:
		for hex in path:
			if grid.get_terrain(hex) != Terrain.Type.RIVER:
				river_tiles_match = false
	_check(river_tiles_match, "every path hex is actually River terrain on the grid")

## Covers TerrainGenerator.generate_super_river's chance roll, full-map-
## crossing shape, and 2-wide sections, across enough seeds to see both a
## hit and a miss (Tuning.SUPER_RIVER_CHANCE is 0.5).
func _test_super_river() -> void:
	var radius := 24
	var origin := HexCoord.new(0, 0)
	var saw_hit := false
	var saw_miss := false
	var all_contiguous := true
	var all_cross_center := true
	var all_span_full_diameter := true
	var all_tiles_are_river := true
	var any_widened := true

	for world_seed in range(40):
		var grid := TerrainGenerator.generate_base_terrain(radius, 0)
		var path := TerrainGenerator.generate_super_river(grid, radius, world_seed)
		if path.is_empty():
			saw_miss = true
			continue
		saw_hit = true

		var touches_center := false
		for i in range(path.size()):
			if HexCoord.distance(origin, path[i]) <= 1:
				touches_center = true
			if i > 0 and HexCoord.distance(path[i - 1], path[i]) != 1:
				all_contiguous = false
			if grid.get_terrain(path[i]) != Terrain.Type.RIVER:
				all_tiles_are_river = false
		if not touches_center:
			all_cross_center = false
		if path.size() != radius * 2 + 1:
			all_span_full_diameter = false

		var path_keys: Dictionary = {}
		for hex in path:
			path_keys[hex.to_key()] = true
		var widened := false
		for hex in path:
			for n in HexCoord.neighbors(hex):
				if grid.get_terrain(n) == Terrain.Type.RIVER and not path_keys.has(n.to_key()):
					widened = true
		if not widened:
			any_widened = false

	_check(saw_hit, "the chance roll hits at least once across 40 seeds (fixture sanity check)")
	_check(saw_miss, "the chance roll also misses at least once across 40 seeds (it's a 50% roll, not guaranteed)")
	_check(all_contiguous, "every rolled super river is an unbroken chain of adjacent hexes")
	_check(all_cross_center, "every rolled super river passes through/adjacent to the origin")
	_check(all_span_full_diameter, "every rolled super river spans the full map diameter (edge to opposite edge)")
	_check(all_tiles_are_river, "every super river path hex is actually River terrain on the grid")
	_check(any_widened, "every rolled super river has at least one 2-hex-wide section")

func _test_base_spacing() -> void:
	var player_count := 2
	var world_seed := 42
	var grid := TerrainGenerator.generate_all(player_count, world_seed)
	var counter := {"n": 0}
	var next_id := func() -> String:
		counter["n"] += 1
		return "base_%d" % counter["n"]
	var placement := BaseSiteSelector.place_bases(grid, player_count, world_seed, _base_defs, _building_defs, next_id)
	_check(placement["bases"] is Array and not (placement["bases"] as Array).is_empty(), "placement succeeded: %s" % placement.get("failure_reason", ""))

	var bases: Array = placement["bases"]
	var min_spacing_ok := true
	var capital_spacing_ok := true
	for i in range(bases.size()):
		for j in range(i + 1, bases.size()):
			var a: BaseInstance = bases[i]
			var b: BaseInstance = bases[j]
			var d := HexCoord.distance(a.hex_coord, b.hex_coord)
			if d < Tuning.MIN_BASE_SPACING:
				min_spacing_ok = false
			var a_is_capital: bool = _base_defs.get(a.base_def_id, {}).get("isCapital", false)
			var b_is_capital: bool = _base_defs.get(b.base_def_id, {}).get("isCapital", false)
			if a_is_capital and b_is_capital and d < Tuning.CAPITAL_MIN_SPACING:
				capital_spacing_ok = false
	_check(min_spacing_ok, "every base pair respects MIN_BASE_SPACING")
	_check(capital_spacing_ok, "every Capital pair respects the stricter CAPITAL_MIN_SPACING")

func _test_expansion_viability() -> void:
	var origin := HexCoord.new(0, 0)

	var open_grid := HexGrid.new()
	for hex in HexCoord.range_within(origin, 12):
		open_grid.set_terrain(hex, Terrain.Type.PLAINS)
	_check(BaseSiteSelector.has_viable_expansion(origin, open_grid), "open Plains disk has viable expansion")

	var walled_grid := HexGrid.new()
	for hex in HexCoord.range_within(origin, 12):
		walled_grid.set_terrain(hex, Terrain.Type.PLAINS)
	for hex in HexCoord.ring(origin, 3):
		walled_grid.set_terrain(hex, Terrain.Type.RIVER)
	_check(not BaseSiteSelector.has_viable_expansion(origin, walled_grid), "a closed River ring walls off expansion")

func _test_unique_def_assignment() -> void:
	var unique_defs: Array = []
	for def in _base_defs.values():
		if not def.get("isCapital", false):
			unique_defs.append(def)

	for player_count in [2, 4, 6]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var deal: Array = BaseSiteSelector._assign_unique_defs(unique_defs, player_count, rng, [])
		_check(deal.size() == player_count * 2, "player_count=%d draws exactly player_count*2 defs" % player_count)

		var seen_ids: Dictionary = {}
		var no_repeats := true
		for entry in deal:
			var id: String = entry["def"].get("id", "")
			if seen_ids.has(id):
				no_repeats = false
			seen_ids[id] = true
		_check(no_repeats, "player_count=%d has no repeated Unique base type" % player_count)

		var per_player_counts: Dictionary = {}
		for entry in deal:
			var p: int = entry["player_index"]
			per_player_counts[p] = per_player_counts.get(p, 0) + 1
		var every_player_gets_two := true
		for p in range(player_count):
			if per_player_counts.get(p, 0) != 2:
				every_player_gets_two = false
		_check(every_player_gets_two, "player_count=%d deals exactly 2 Uniques per player" % player_count)

	var rng_a := RandomNumberGenerator.new()
	rng_a.seed = 555
	var rng_b := RandomNumberGenerator.new()
	rng_b.seed = 555
	var deal_a: Array = BaseSiteSelector._assign_unique_defs(unique_defs, 4, rng_a, [])
	var deal_b: Array = BaseSiteSelector._assign_unique_defs(unique_defs, 4, rng_b, [])
	var deterministic := deal_a.size() == deal_b.size()
	for i in range(deal_a.size()):
		if deal_a[i]["def"].get("id", "") != deal_b[i]["def"].get("id", "") or deal_a[i]["player_index"] != deal_b[i]["player_index"]:
			deterministic = false
	_check(deterministic, "same seed produces the same deal")

## Small deterministic seed sweep so a single unlucky terrain roll can't make
## these forced-inclusion tests flaky — mirrors MapGenerator's own retry
## philosophy, just scoped to the test.
func _generate_forcing(player_count: int, forced_ids: Array[String]) -> MapGenerationResult:
	for world_seed in [7, 13, 42, 101, 2024, 99999]:
		var result := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs, forced_ids, _troop_defs)
		if result != null:
			return result
	return null

func _find_base(result: MapGenerationResult, base_def_id: String) -> BaseInstance:
	for b in result.bases:
		if b.base_def_id == base_def_id:
			return b
	return null

func _test_kraken_point_site() -> void:
	var result := _generate_forcing(2, ["kraken_point"])
	_check(result != null, "generation succeeds with Kraken Point forced")
	if result == null:
		return
	var base := _find_base(result, "kraken_point")
	_check(base != null, "Kraken Point was actually placed")
	if base == null:
		return
	var has_ocean_neighbor := false
	for h in HexCoord.ring(base.hex_coord, 2):
		if result.grid.get_terrain(h) == Terrain.Type.OCEAN:
			has_ocean_neighbor = true
	_check(has_ocean_neighbor, "Kraken Point's site has Ocean at ring-distance 2")

	# Regression coverage for the "water turrets/shipyard land on dry Plains"
	# bug: every seeded building requiring Water adjacency must actually have
	# a qualifying neighbor, not just sit somewhere inside the (guaranteed
	# all-Plains) flower.
	var water_buildings_ok := true
	var any_water_building := false
	for building in base.buildings:
		var required := String(_building_defs.get(building.building_type, {}).get("placementRequirement", {}).get("adjacentTerrainRequired", ""))
		if required != "Water" or building.hex == null:
			continue
		any_water_building = true
		var satisfied := false
		for n in HexCoord.neighbors(building.hex):
			var t := result.grid.get_terrain(n)
			if t == Terrain.Type.OCEAN or t == Terrain.Type.RIVER:
				satisfied = true
				break
		if not satisfied:
			water_buildings_ok = false
	_check(any_water_building, "Kraken Point's initialBuildings include at least one Water-adjacency building (fixture sanity check)")
	_check(water_buildings_ok, "every seeded Water-adjacency building (Water Turret/Shipyard) actually has an adjacent Water tile")

	# Regression coverage for the "ships spawn on land" bug: every seeded
	# garrison squad whose troop is Naval-domain must stand on actual water.
	var ships_on_water := true
	var any_naval_squad := false
	for squad in result.squads:
		var domain := Terrain.domain_from_string(String(_troop_defs.get(squad.troop_type, {}).get("domain", "Infantry")))
		if domain != Terrain.Domain.NAVAL:
			continue
		any_naval_squad = true
		if not Terrain.is_passable(result.grid.get_terrain(squad.current_hex), Terrain.Domain.NAVAL):
			ships_on_water = false
	_check(any_naval_squad, "Kraken Point's initialGarrison includes at least one Naval troop (fixture sanity check)")
	_check(ships_on_water, "every seeded Naval garrison squad (Kraken Point's ships) stands on actual water, not land")

## Rivergate's notes say its specialty defense "must sit next to the river to
## actually cover the crossing", but (unlike Kraken Point) had no site
## predicate at all guaranteeing River adjacency — it could roll anywhere on
## Plains. _is_river_adjacent_site fixes that; this covers the same "does the
## seeded Water Turret/Ford Yard actually have a qualifying neighbor" ground
## as the Kraken Point test above.
func _test_rivergate_site() -> void:
	var result := _generate_forcing(2, ["rivergate"])
	_check(result != null, "generation succeeds with Rivergate forced")
	if result == null:
		return
	var base := _find_base(result, "rivergate")
	_check(base != null, "Rivergate was actually placed")
	if base == null:
		return
	var has_river_neighbor := false
	for h in HexCoord.ring(base.hex_coord, 2):
		if result.grid.get_terrain(h) == Terrain.Type.RIVER:
			has_river_neighbor = true
	_check(has_river_neighbor, "Rivergate's site has River at ring-distance 2")

	var water_buildings_ok := true
	var any_water_building := false
	for building in base.buildings:
		var required := String(_building_defs.get(building.building_type, {}).get("placementRequirement", {}).get("adjacentTerrainRequired", ""))
		if required != "Water" or building.hex == null:
			continue
		any_water_building = true
		var satisfied := false
		for n in HexCoord.neighbors(building.hex):
			var t := result.grid.get_terrain(n)
			if t == Terrain.Type.OCEAN or t == Terrain.Type.RIVER:
				satisfied = true
				break
		if not satisfied:
			water_buildings_ok = false
	_check(any_water_building, "Rivergate's initialBuildings include at least one Water-adjacency building (fixture sanity check)")
	_check(water_buildings_ok, "every seeded Water-adjacency building (Water Turret/Ford Yard) actually has an adjacent Water tile")

func _test_treehouse_site() -> void:
	var result := _generate_forcing(2, ["treehouse"])
	_check(result != null, "generation succeeds with Treehouse forced")
	if result == null:
		return
	var base := _find_base(result, "treehouse")
	_check(base != null, "Treehouse was actually placed")
	if base == null:
		return
	_check(result.grid.get_terrain(base.hex_coord) == Terrain.Type.FOREST, "Treehouse's HQ hex is Forest")
	var flower_forest := true
	for n in HexCoord.neighbors(base.hex_coord):
		if result.grid.get_terrain(n) != Terrain.Type.FOREST:
			flower_forest = false
	_check(flower_forest, "Treehouse's flower (HQ + 6 neighbors) is entirely Forest")

func _test_windy_peaks_site() -> void:
	var result := _generate_forcing(2, ["windy_peaks"])
	_check(result != null, "generation succeeds with Windy Peaks forced")
	if result == null:
		return
	var base := _find_base(result, "windy_peaks")
	_check(base != null, "Windy Peaks was actually placed")
	if base == null:
		return
	_check(result.grid.get_terrain(base.hex_coord) == Terrain.Type.HILLS, "Windy Peaks' HQ hex is Hills")
	var flower_hills := true
	for n in HexCoord.neighbors(base.hex_coord):
		if result.grid.get_terrain(n) != Terrain.Type.HILLS:
			flower_hills = false
	_check(flower_hills, "Windy Peaks' flower (HQ + 6 neighbors) is entirely Hills")

func _test_sky_fortress_site() -> void:
	var result := _generate_forcing(2, ["sky_fortress"])
	_check(result != null, "generation succeeds with Sky Fortress forced")
	if result == null:
		return
	var base := _find_base(result, "sky_fortress")
	_check(base != null, "Sky Fortress was actually placed")
	if base == null:
		return

	var flower_untouched := true
	for n in HexCoord.neighbors(base.hex_coord):
		if result.grid.get_terrain(n) != Terrain.Type.PLAINS:
			flower_untouched = false
	_check(flower_untouched, "Sky Fortress's own flower stays Plains (moat sits outside it)")

	var ring := HexCoord.ring(base.hex_coord, Tuning.MOAT_INNER_RADIUS)
	var water_count := 0
	for h in ring:
		var t := result.grid.get_terrain(h)
		if t == Terrain.Type.OCEAN or t == Terrain.Type.RIVER:
			water_count += 1
	_check(float(water_count) / float(ring.size()) >= Tuning.MOAT_MIN_COVERAGE_FRACTION, "moat ring is mostly water")

	# Connectivity: BFS outward from the moat ring, through water tiles only,
	# must reach a water tile that existed independent of the moat/channel
	# carve — i.e. the moat isn't an isolated pond. We approximate this by
	# confirming the connected water region touching the ring extends well
	# beyond the moat ring itself (a bare, unconnected moat's water region
	# would be bounded by the ring's own footprint).
	var visited: Dictionary = {}
	var frontier: Array = []
	for h in ring:
		if result.grid.get_terrain(h) == Terrain.Type.OCEAN or result.grid.get_terrain(h) == Terrain.Type.RIVER:
			visited[h.to_key()] = true
			frontier.append(h)
	var region_size := 0
	while not frontier.is_empty():
		var next_frontier: Array = []
		for hex in frontier:
			region_size += 1
			for n in HexCoord.neighbors(hex):
				var key: String = n.to_key()
				if visited.has(key) or not result.grid.has_hex(n):
					continue
				var t := result.grid.get_terrain(n)
				if t == Terrain.Type.OCEAN or t == Terrain.Type.RIVER:
					visited[key] = true
					next_frontier.append(n)
		frontier = next_frontier
	_check(region_size > ring.size(), "moat's connected water region extends beyond the ring itself (connected to real water)")

## Regression coverage for BaseFactory.seed_base's old fixed 6-direction fan:
## every base def with more than 6 non-Wall initialBuildings (nearly all
## Unique bases) wrapped past direction 5 back onto direction 0, silently
## stacking two buildings on the same hex, and every seeded Wall was given a
## single `hex` instead of a hex_a/hex_b edge (invisible to base_view.gd,
## inert to grid.is_walled_edge). Runs across player counts so a good spread
## of Unique base types gets exercised.
func _test_seeded_building_placement() -> void:
	for player_count in [2, 4, 6]:
		var result := MapGenerator.generate(player_count, 42, _base_defs, _building_defs, [], _troop_defs)
		if result == null:
			_check(false, "player_count=%d generation succeeds for seeded-building checks" % player_count)
			continue

		var no_hex_collisions := true
		var adjacency_ok := true
		for base in result.bases:
			var seen_hexes: Dictionary = {}
			for building in base.buildings:
				if building.hex == null:
					continue ## Wall: edge-keyed, no single hex of its own.
				if seen_hexes.has(building.hex.to_key()):
					no_hex_collisions = false
				seen_hexes[building.hex.to_key()] = true

				var required := String(_building_defs.get(building.building_type, {}).get("placementRequirement", {}).get("adjacentTerrainRequired", ""))
				if required == "":
					continue
				var satisfied := false
				for n in HexCoord.neighbors(building.hex):
					if BuildingPlacement._matches_adjacent_terrain_required(required, result.grid.get_terrain(n)):
						satisfied = true
						break
				if not satisfied:
					adjacency_ok = false
		_check(no_hex_collisions, "player_count=%d no two seeded buildings share a hex" % player_count)
		_check(adjacency_ok, "player_count=%d every seeded building with an adjacentTerrainRequired actually has it" % player_count)

		var every_wall_registered := true
		var any_wall := false
		for base in result.bases:
			for building in base.buildings:
				if building.building_type != "wall":
					continue
				any_wall = true
				if building.hex_a == null or building.hex_b == null or not result.grid.is_walled_edge(building.hex_a, building.hex_b):
					every_wall_registered = false
		_check(any_wall, "player_count=%d seeded at least one Wall (fixture sanity check)" % player_count)
		_check(every_wall_registered, "player_count=%d every seeded Wall is a real hex_a/hex_b edge registered on the grid" % player_count)

func _test_map_generator_end_to_end() -> void:
	for player_count in [2, 4, 6]:
		var world_seed := 42
		var r1 := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs)
		var r2 := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs)
		_check(r1 != null and r2 != null, "player_count=%d generation succeeds" % player_count)
		if r1 == null or r2 == null:
			continue

		var deterministic := r1.bases.size() == r2.bases.size()
		for i in range(r1.bases.size()):
			if not r1.bases[i].hex_coord.equals(r2.bases[i].hex_coord) or r1.bases[i].base_def_id != r2.bases[i].base_def_id:
				deterministic = false
		_check(deterministic, "player_count=%d is deterministic given the same seed" % player_count)

		_check(r1.bases.size() == player_count * 3, "player_count=%d produces player_count*3 bases" % player_count)

		var capitals := 0
		for b in r1.bases:
			if _base_defs.get(b.base_def_id, {}).get("isCapital", false):
				capitals += 1
		_check(capitals == player_count, "player_count=%d produces exactly player_count Capitals" % player_count)

		var every_hq_terrain_ok := true
		for b in r1.bases:
			var required: Terrain.Type = BaseSiteSelector._hq_site_terrain(_base_defs.get(b.base_def_id, {}))
			if r1.grid.get_terrain(b.hex_coord) != required:
				every_hq_terrain_ok = false
		_check(every_hq_terrain_ok, "player_count=%d every HQ hex matches its base's required terrain" % player_count)

		var seen_unique_ids: Dictionary = {}
		var no_unique_repeats := true
		for b in r1.bases:
			if _base_defs.get(b.base_def_id, {}).get("isCapital", false):
				continue
			if seen_unique_ids.has(b.base_def_id):
				no_unique_repeats = false
			seen_unique_ids[b.base_def_id] = true
		_check(no_unique_repeats, "player_count=%d has no repeated Unique base type" % player_count)

		var every_capital_viable := true
		for b in r1.bases:
			if _base_defs.get(b.base_def_id, {}).get("isCapital", false) and not BaseSiteSelector.has_viable_expansion(b.hex_coord, r1.grid):
				every_capital_viable = false
		_check(every_capital_viable, "player_count=%d every Capital passes has_viable_expansion" % player_count)

		var radius := TerrainGenerator.map_radius(player_count)
		var fringe := radius + Tuning.OCEAN_FRINGE_WIDTH
		var origin := HexCoord.new(0, 0)
		var coverage_ok := true
		for hex in HexCoord.ring(origin, fringe):
			if not r1.grid.has_hex(hex):
				coverage_ok = false
		for hex in HexCoord.ring(origin, fringe + 1):
			if r1.grid.has_hex(hex):
				coverage_ok = false
		_check(coverage_ok, "player_count=%d grid covers exactly the intended hexagon+fringe" % player_count)

func _test_map_generator_garrisons() -> void:
	var player_count := 2
	var world_seed := 42

	var without_troop_defs := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs)
	_check(without_troop_defs != null and without_troop_defs.squads.is_empty(), "omitting troop_defs seeds no garrisons (optional, backward-compatible)")

	var result := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs, [], _troop_defs)
	_check(result != null, "generation with troop_defs succeeds")
	if result == null:
		return

	var expected_troop_count := 0
	for base in result.bases:
		var garrison: Array = _base_defs.get(base.base_def_id, {}).get("initialGarrison", [])
		for entry in garrison:
			expected_troop_count += int(entry.get("count", 0))
	_check(expected_troop_count > 0, "at least one placed base has an initialGarrison to seed (sanity check on fixture data)")

	var actual_troop_count := 0
	for squad in result.squads:
		actual_troop_count += squad.member_ids.size()
	_check(actual_troop_count == expected_troop_count, "total seeded garrison troops (%d) matches the sum of every placed base's initialGarrison counts (%d)" % [actual_troop_count, expected_troop_count])
	_check(result.troops_by_id.size() == actual_troop_count, "every seeded troop is registered in troops_by_id")

	var owner_by_base_id: Dictionary = {}
	for base in result.bases:
		owner_by_base_id[base.id] = base.owner_id
	var hex_by_base_id: Dictionary = {}
	for base in result.bases:
		hex_by_base_id[base.id] = base.hex_coord

	var every_squad_near_a_base := true
	for squad in result.squads:
		var found_nearby_base := false
		for base in result.bases:
			if base.owner_id == squad.owner_id and HexCoord.distance(base.hex_coord, squad.current_hex) >= Tuning.GARRISON_RING_RADIUS:
				found_nearby_base = true
				break
		if not found_nearby_base:
			every_squad_near_a_base = false
	_check(every_squad_near_a_base, "every seeded garrison squad stands at or beyond its own owner's garrison ring")

	# Domain-correction regression: a squad's seeded hex must actually be
	# terrain its own troop type can stand on (a Naval garrison — e.g. Kraken
	# Point's Destroyers/Submarine — used to land on the ring hex verbatim
	# even when that hex was dry Plains; see GarrisonFactory.seed_garrison).
	var every_squad_domain_ok := true
	for squad in result.squads:
		var domain := Terrain.domain_from_string(String(_troop_defs.get(squad.troop_type, {}).get("domain", "Infantry")))
		if not Terrain.is_passable(result.grid.get_terrain(squad.current_hex), domain):
			every_squad_domain_ok = false
	_check(every_squad_domain_ok, "every seeded garrison squad stands on terrain its own domain can occupy")

func _test_player_count_guard() -> void:
	var result := MapGenerator.generate(MapGenerator.MAX_SUPPORTED_PLAYER_COUNT + 1, 1, _base_defs, _building_defs)
	_check(result == null, "player_count beyond MAX_SUPPORTED_PLAYER_COUNT fails loudly (returns null)")

## Covers BarbarianOutpostPlacer end-to-end via MapGenerator.generate(): camp
## count/spacing/ownership, distance-scaled tier assignment, and determinism.
## See sim/outposts/barbarian_outpost_placer.gd; loot-on-death logic itself is
## covered separately in tests/test_barbarian_outposts.gd.
func _test_barbarian_outpost_placement() -> void:
	var player_count := 2
	var world_seed := 42
	var result := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs, [], _troop_defs, _outpost_defs)
	_check(result != null, "generation with outpost_defs succeeds")
	if result == null:
		return

	var expected_count := Tuning.BARBARIAN_OUTPOST_BASE_COUNT + player_count * Tuning.BARBARIAN_OUTPOST_COUNT_PER_PLAYER
	_check(result.barbarian_outposts.size() > 0 and result.barbarian_outposts.size() <= expected_count, "placed at least one and at most the expected %d outposts (best-effort)" % expected_count)
	_check(result.standalone_buildings.size() == result.barbarian_outposts.size(), "one standalone tower per outpost record")

	var building_by_id: Dictionary = {}
	for b in result.standalone_buildings:
		building_by_id[b.id] = b

	var every_tower_is_tower_type := true
	var every_tower_neutral := true
	var every_material_valid := true
	for outpost in result.barbarian_outposts:
		var building: BuildingInstance = building_by_id.get(outpost.building_id)
		if building == null or building.building_type != "tower":
			every_tower_is_tower_type = false
			continue
		if building.owner_id != BaseSiteSelector.NEUTRAL_OWNER_ID:
			every_tower_neutral = false
		if not ["wood", "stone", "steel"].has(building.material):
			every_material_valid = false
	_check(every_tower_is_tower_type, "every outpost's building_id resolves to an actual standalone tower")
	_check(every_tower_neutral, "every outpost tower is owned by BaseSiteSelector.NEUTRAL_OWNER_ID")
	_check(every_material_valid, "every outpost tower has a valid material")

	var squads_by_id: Dictionary = {}
	for squad in result.squads:
		squads_by_id[squad.id] = squad
	var every_guard_neutral := true
	var any_guard := false
	for outpost in result.barbarian_outposts:
		for guard_id in outpost.guard_squad_ids:
			any_guard = true
			var squad: SquadInstance = squads_by_id.get(guard_id)
			if squad == null or squad.owner_id != BaseSiteSelector.NEUTRAL_OWNER_ID:
				every_guard_neutral = false
	_check(any_guard, "at least one outpost has guard squads (fixture sanity check)")
	_check(every_guard_neutral, "every outpost guard squad is owned by BaseSiteSelector.NEUTRAL_OWNER_ID")

	var spacing_from_base_ok := true
	var spacing_from_outpost_ok := true
	for i in range(result.barbarian_outposts.size()):
		var a: BuildingInstance = building_by_id.get(result.barbarian_outposts[i].building_id)
		if a == null:
			continue
		for base in result.bases:
			if HexCoord.distance(a.hex, base.hex_coord) < Tuning.BARBARIAN_OUTPOST_MIN_SPACING_FROM_BASE:
				spacing_from_base_ok = false
		for j in range(i + 1, result.barbarian_outposts.size()):
			var b: BuildingInstance = building_by_id.get(result.barbarian_outposts[j].building_id)
			if b != null and HexCoord.distance(a.hex, b.hex) < Tuning.BARBARIAN_OUTPOST_MIN_SPACING_FROM_OUTPOST:
				spacing_from_outpost_ok = false
	_check(spacing_from_base_ok, "every outpost respects BARBARIAN_OUTPOST_MIN_SPACING_FROM_BASE")
	_check(spacing_from_outpost_ok, "every outpost pair respects BARBARIAN_OUTPOST_MIN_SPACING_FROM_OUTPOST")

	var capital_hexes: Array[HexCoord] = []
	for base in result.bases:
		if _base_defs.get(base.base_def_id, {}).get("isCapital", false):
			capital_hexes.append(base.hex_coord)
	var map_radius := TerrainGenerator.map_radius(player_count)
	var tier_matches_distance := true
	for outpost in result.barbarian_outposts:
		var building: BuildingInstance = building_by_id.get(outpost.building_id)
		if building == null or capital_hexes.is_empty():
			continue
		var closest: int = HexCoord.distance(building.hex, capital_hexes[0])
		for k in range(1, capital_hexes.size()):
			closest = min(closest, HexCoord.distance(building.hex, capital_hexes[k]))
		var fraction := float(closest) / float(map_radius)
		var expected_material := "steel"
		if fraction < Tuning.BARBARIAN_TIER_NEAR_FRACTION:
			expected_material = "wood"
		elif fraction < Tuning.BARBARIAN_TIER_FAR_FRACTION:
			expected_material = "stone"
		if building.material != expected_material:
			tier_matches_distance = false
	_check(tier_matches_distance, "every outpost's tier matches its distance-from-nearest-Capital bucket")

	var result2 := MapGenerator.generate(player_count, world_seed, _base_defs, _building_defs, [], _troop_defs, _outpost_defs)
	var deterministic := result2 != null and result2.barbarian_outposts.size() == result.barbarian_outposts.size()
	if deterministic:
		var building_by_id2: Dictionary = {}
		for b in result2.standalone_buildings:
			building_by_id2[b.id] = b
		for i in range(result.barbarian_outposts.size()):
			var b1: BuildingInstance = building_by_id.get(result.barbarian_outposts[i].building_id)
			var b2: BuildingInstance = building_by_id2.get(result2.barbarian_outposts[i].building_id)
			if b1 == null or b2 == null or not b1.hex.equals(b2.hex) or b1.material != b2.material:
				deterministic = false
	_check(deterministic, "same seed produces the same outpost placement")
