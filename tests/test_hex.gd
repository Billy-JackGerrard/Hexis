## Headless assertion suite for sim/hex/*. Run with:
##   godot --headless --script res://tests/test_hex.gd
extends SceneTree

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	print("HexCoord")
	_test_coord()
	print("HexGrid")
	_test_grid()
	print("Infrastructure (Road/Bridge)")
	_test_infrastructure()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _test_coord() -> void:
	var origin := HexCoord.new(0, 0)
	_check(origin.s() == 0, "origin cube s() == 0")

	var n := HexCoord.neighbors(origin)
	_check(n.size() == 6, "6 neighbors")
	for neighbor in n:
		_check(HexCoord.distance(origin, neighbor) == 1, "neighbor is distance 1: %s" % neighbor)

	_check(HexCoord.distance(HexCoord.new(0, 0), HexCoord.new(3, -1)) == 3, "distance(0,0 -> 3,-1) == 3")
	_check(HexCoord.distance(HexCoord.new(-2, 1), HexCoord.new(2, -1)) == 4, "distance(-2,1 -> 2,-1) == 4")

	var ring1 := HexCoord.range_within(origin, 1)
	_check(ring1.size() == 7, "range_within radius 1 has 7 hexes (center + 6)")

	_check(HexCoord.ring(origin, 0).size() == 1, "ring radius 0 is just the center")
	var ring_r1 := HexCoord.ring(origin, 1)
	_check(ring_r1.size() == 6, "ring radius 1 has 6 hexes")
	var neighbor_keys := {}
	for nb in HexCoord.neighbors(origin):
		neighbor_keys[nb.to_key()] = true
	var ring_r1_matches_neighbors := true
	for hex in ring_r1:
		if not neighbor_keys.has(hex.to_key()):
			ring_r1_matches_neighbors = false
	_check(ring_r1_matches_neighbors, "ring radius 1 set-equals neighbors(origin)")
	var ring_r2 := HexCoord.ring(origin, 2)
	_check(ring_r2.size() == 12, "ring radius 2 has 6*radius hexes")
	var ring_r2_all_distance_2 := true
	for hex in ring_r2:
		if HexCoord.distance(origin, hex) != 2:
			ring_r2_all_distance_2 = false
	_check(ring_r2_all_distance_2, "every ring radius 2 hex is distance 2 from center")

	var key := HexCoord.new(5, -3).to_key()
	var restored := HexCoord.from_key(key)
	_check(restored.q == 5 and restored.r == -3, "to_key/from_key round-trip")

func _test_grid() -> void:
	var grid := HexGrid.new()
	# 3x3-ish plains patch with one hill and one forest tile, per
	# game-design/01-map-and-terrain.md's terrain table.
	for coord in HexCoord.range_within(HexCoord.new(0, 0), 2):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.HILLS)
	grid.set_terrain(HexCoord.new(2, 0), Terrain.Type.FOREST)
	grid.set_terrain(HexCoord.new(0, 2), Terrain.Type.RIVER)

	_check(grid.get_terrain(HexCoord.new(0, 0)) == Terrain.Type.PLAINS, "center is Plains")
	_check(not grid.has_hex(HexCoord.new(99, 99)), "unset hex reports has_hex() == false")

	_check(Terrain.is_passable(Terrain.Type.HILLS, Terrain.Domain.INFANTRY), "Hills passable for Infantry (slowed, not blocked)")
	_check(Terrain.cost(Terrain.Type.HILLS, Terrain.Domain.INFANTRY) > 1.0, "Hills cost > 1.0 for Infantry")
	_check(Terrain.cost(Terrain.Type.HILLS, Terrain.Domain.LAND) == 1.0, "Hills normal cost for Land vehicles")
	_check(not Terrain.is_passable(Terrain.Type.FOREST, Terrain.Domain.LAND), "Forest blocked for Land vehicles")
	_check(Terrain.is_passable(Terrain.Type.FOREST, Terrain.Domain.INFANTRY), "Forest passable for Infantry")
	_check(not Terrain.is_passable(Terrain.Type.RIVER, Terrain.Domain.INFANTRY), "River blocked for Infantry without a Bridge")
	_check(Terrain.is_passable(Terrain.Type.RIVER, Terrain.Domain.NAVAL), "River fully passable for Naval")
	_check(Terrain.is_passable(Terrain.Type.OCEAN, Terrain.Domain.AIR), "Air ignores terrain restrictions entirely (Ocean)")

	# Walls block a specific edge, both directions, except for Air.
	var a := HexCoord.new(0, 0)
	var b := HexCoord.new(1, 0)
	grid.set_terrain(b, Terrain.Type.PLAINS)
	_check(grid.edge_cost(a, b, Terrain.Domain.LAND) != Terrain.INF, "edge open before wall")
	grid.set_wall(a, b, true)
	_check(grid.edge_cost(a, b, Terrain.Domain.LAND) == Terrain.INF, "wall blocks Land in the a->b direction")
	_check(grid.edge_cost(b, a, Terrain.Domain.LAND) == Terrain.INF, "wall blocks Land in the b->a direction too")
	_check(grid.edge_cost(a, b, Terrain.Domain.AIR) != Terrain.INF, "Air ignores walls entirely")
	grid.set_wall(a, b, false)
	_check(grid.edge_cost(a, b, Terrain.Domain.LAND) != Terrain.INF, "unset wall reopens the edge")

	# Pathfinding around an impassable Forest tile (goal is a Plains hex past
	# it, not the Forest tile itself, which would be an unreachable goal).
	var goal := HexCoord.new(2, -2)
	var path := grid.find_path(HexCoord.new(0, 0), goal, Terrain.Domain.LAND)
	_check(not path.is_empty(), "path found around blocked Forest tile")
	if not path.is_empty():
		_check(path[0].equals(HexCoord.new(0, 0)), "path starts at start hex")
		_check(path[-1].equals(goal), "path ends at goal hex")
		for step in path:
			_check(Terrain.is_passable(grid.get_terrain(step), Terrain.Domain.LAND), "no path step lands on impassable terrain: %s" % step)

	var no_path := grid.find_path(HexCoord.new(0, 0), HexCoord.new(99, 99), Terrain.Domain.LAND)
	_check(no_path.is_empty(), "no path to an off-grid hex")

func _test_infrastructure() -> void:
	# Bare terrain rules, no infrastructure — sanity check the baseline.
	_check(not Terrain.is_passable_with(Terrain.Type.FOREST, Terrain.Domain.LAND, Terrain.Infrastructure.NONE), "Forest still blocks Land with no infrastructure")
	_check(not Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.NONE), "River still blocks Land with no infrastructure")

	# Road clears Forest's Land block.
	_check(Terrain.is_passable_with(Terrain.Type.FOREST, Terrain.Domain.LAND, Terrain.Infrastructure.ROAD), "Road clears Forest block for Land")
	_check(Terrain.effective_cost(Terrain.Type.FOREST, Terrain.Domain.LAND, Terrain.Infrastructure.ROAD) == 1.0, "Road makes Forest normal-cost for Land")
	_check(not Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.ROAD), "Road on a River hex does not clear the River block (wrong infrastructure)")

	# Bridge clears River's Infantry/Land block.
	_check(Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.INFANTRY, Terrain.Infrastructure.BRIDGE), "Bridge clears River block for Infantry")
	_check(Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.BRIDGE), "Bridge clears River block for Land")
	_check(Terrain.effective_cost(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.BRIDGE) == 1.0, "Bridge makes River normal-cost for Land")
	_check(not Terrain.is_passable_with(Terrain.Type.FOREST, Terrain.Domain.LAND, Terrain.Infrastructure.BRIDGE), "Bridge on a Forest hex does not clear the Forest block (wrong infrastructure)")

	# Naval was already fully passable on River regardless of infrastructure.
	_check(Terrain.effective_cost(Terrain.Type.RIVER, Terrain.Domain.NAVAL, Terrain.Infrastructure.NONE) == 1.0, "Naval unaffected by infrastructure on River (already passable)")

	# Heavy land vehicles are too heavy for a Wood Bridge -- Stone is fine, and
	# neither Infantry nor a Light vehicle cares about the material.
	_check(not Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.BRIDGE, "wood", true), "Heavy Land vehicle cannot cross a Wood Bridge")
	_check(Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.BRIDGE, "stone", true), "Heavy Land vehicle can cross a Stone Bridge")
	_check(Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.LAND, Terrain.Infrastructure.BRIDGE, "wood", false), "Light Land vehicle can cross a Wood Bridge")
	_check(Terrain.is_passable_with(Terrain.Type.RIVER, Terrain.Domain.INFANTRY, Terrain.Infrastructure.BRIDGE, "wood", true), "Infantry ignores the Heavy-vehicle Wood Bridge gate entirely (not a Land vehicle)")

	# HexGrid wiring: a Road on a specific Forest hex opens a path through it
	# for Land, without affecting a different, un-Road'd Forest hex.
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), 2):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	var forest_hex := HexCoord.new(1, 0)
	var other_forest_hex := HexCoord.new(-1, 0)
	grid.set_terrain(forest_hex, Terrain.Type.FOREST)
	grid.set_terrain(other_forest_hex, Terrain.Type.FOREST)

	_check(grid.get_infrastructure(forest_hex) == Terrain.Infrastructure.NONE, "no infrastructure by default")
	_check(grid.edge_cost(HexCoord.new(0, 0), forest_hex, Terrain.Domain.LAND) == Terrain.INF, "Land blocked entering Forest hex before Road")
	grid.set_infrastructure(forest_hex, Terrain.Infrastructure.ROAD)
	_check(grid.get_infrastructure(forest_hex) == Terrain.Infrastructure.ROAD, "get_infrastructure reflects the Road just set")
	_check(grid.edge_cost(HexCoord.new(0, 0), forest_hex, Terrain.Domain.LAND) != Terrain.INF, "Land can enter the Forest hex once a Road is built there")
	_check(grid.edge_cost(HexCoord.new(0, 0), other_forest_hex, Terrain.Domain.LAND) == Terrain.INF, "the other, un-Road'd Forest hex is still blocked for Land")

	grid.set_infrastructure(forest_hex, Terrain.Infrastructure.NONE)
	_check(grid.edge_cost(HexCoord.new(0, 0), forest_hex, Terrain.Domain.LAND) == Terrain.INF, "removing the Road re-blocks the hex for Land")

	# HexGrid wiring: a Wood Bridge's own material blocks a Heavy Land vehicle's
	# edge_cost but not a Stone Bridge's, and get_infrastructure_material tracks
	# it alongside the Infrastructure enum, clearing together on demolish.
	var river_hex := HexCoord.new(1, 0)
	grid.set_terrain(river_hex, Terrain.Type.RIVER)
	_check(grid.get_infrastructure_material(river_hex) == "", "no infrastructure material by default")
	grid.set_infrastructure(river_hex, Terrain.Infrastructure.BRIDGE, "wood")
	_check(grid.get_infrastructure_material(river_hex) == "wood", "get_infrastructure_material reflects the Wood Bridge just set")
	_check(grid.edge_cost(HexCoord.new(0, 0), river_hex, Terrain.Domain.LAND, {}, {}, true) == Terrain.INF, "Heavy Land vehicle blocked crossing the Wood Bridge")
	_check(grid.edge_cost(HexCoord.new(0, 0), river_hex, Terrain.Domain.LAND, {}, {}, false) != Terrain.INF, "Light Land vehicle crosses the Wood Bridge fine")

	grid.set_infrastructure(river_hex, Terrain.Infrastructure.BRIDGE, "stone")
	_check(grid.edge_cost(HexCoord.new(0, 0), river_hex, Terrain.Domain.LAND, {}, {}, true) != Terrain.INF, "Heavy Land vehicle crosses a Stone Bridge fine")

	grid.set_infrastructure(river_hex, Terrain.Infrastructure.NONE)
	_check(grid.get_infrastructure_material(river_hex) == "", "demolishing the Bridge clears its material alongside the Infrastructure enum")
