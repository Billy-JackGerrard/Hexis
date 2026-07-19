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
	print("Connection mask (River/Road tile-adjacency)")
	_test_connection_mask()
	print("Elevation (slopes and cliffs)")
	_test_elevation()

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

func _test_connection_mask() -> void:
	var grid := HexGrid.new()
	var origin := HexCoord.new(0, 0)
	for coord in HexCoord.range_within(origin, 2):
		grid.set_terrain(coord, Terrain.Type.PLAINS)

	_check(grid.river_connection_mask(origin) == 0, "no River neighbors, mask is 0")

	# A straight 3-hex river through the origin: origin has exactly 2 River
	# neighbors, on opposite sides (bits i and i+3, per HexCoord.DIRECTIONS'
	# fixed winding order).
	var upstream := HexCoord.neighbor(origin, 0)
	var downstream := HexCoord.neighbor(origin, 3)
	grid.set_terrain(upstream, Terrain.Type.RIVER)
	grid.set_terrain(downstream, Terrain.Type.RIVER)
	grid.set_terrain(origin, Terrain.Type.RIVER)
	var mask := grid.river_connection_mask(origin)
	_check(mask == (1 << 0 | 1 << 3), "straight river through origin sets bits 0 and 3")

	# A river source (only one River neighbor) reads as a single set bit —
	# this is the mask a renderer uses to tell a source (river-start, edge
	# points away from an upstream neighbor that doesn't exist) apart from a
	# river continuing further: same popcount as any other lone edge, the
	# bit position is what a caller inspects.
	var source_mask := grid.river_connection_mask(upstream)
	_check(source_mask == (1 << 3), "river source hex has exactly one set bit, pointing back at its only River neighbor")

	# Roads are tracked independently of terrain and use the same mask shape.
	_check(grid.road_connection_mask(origin) == 0, "no Road neighbors yet, mask is 0")
	var road_neighbor := HexCoord.neighbor(origin, 1)
	grid.set_infrastructure(origin, Terrain.Infrastructure.ROAD)
	grid.set_infrastructure(road_neighbor, Terrain.Infrastructure.ROAD)
	_check(grid.road_connection_mask(origin) == (1 << 1), "Road placed on a neighbor connects live, no separate wiring step")
	_check(grid.road_connection_mask(road_neighbor) == (1 << 4), "the other hex's mask reflects the same connection from its own side (opposite bit, same edge)")

	# A third Road neighbor makes origin a 3-way junction. It's also adjacent
	# to road_neighbor (hexes 60 degrees apart around a shared center are
	# always mutually adjacent), so road_neighbor's own mask picks up that
	# new edge too, live, with no separate "connect these two" step — this
	# is the cascading behavior a player building a new Road tile next to
	# two existing ones needs: every affected hex's mask is just recomputed
	# from current neighbor state, whichever hex asks.
	var third := HexCoord.neighbor(origin, 2)
	grid.set_infrastructure(third, Terrain.Infrastructure.ROAD)
	_check(grid.road_connection_mask(origin) == (1 << 1 | 1 << 2), "a third Road neighbor extends origin's mask into a 3-way junction")
	_check(grid.road_connection_mask(road_neighbor) == (1 << 3 | 1 << 4), "road_neighbor's own mask also picks up the new edge to third, since it's adjacent to it too")

	# A hex with no shared neighbors at all is genuinely unaffected.
	var unrelated := HexCoord.neighbor(HexCoord.neighbor(origin, 3), 3)
	_check(grid.road_connection_mask(unrelated) == 0, "a hex sharing no neighbors with the junction is untouched")

## Elevation is a separate axis from Terrain.Type: the *difference* between two
## adjacent hexes decides whether an edge is a free descent, a slower climb, or
## an unclimbable cliff. Crucially it's directional — the defining property of a
## cliff is that you can drop off it but not scale it, so the way up a plateau
## is a different edge somewhere else on its rim.
func _test_elevation() -> void:
	var grid := HexGrid.new()
	var low := HexCoord.new(0, 0)
	var slope := HexCoord.new(1, 0)
	var peak := HexCoord.new(2, 0)
	for hex in [low, slope, peak]:
		grid.set_terrain(hex, Terrain.Type.PLAINS)
	_check(grid.get_elevation(low) == 0, "a hex with no elevation set reads as lowland 0, so pre-elevation grids behave exactly as they did when the map was flat")

	grid.set_elevation(slope, Tuning.HILLS_RIM_ELEVATION)
	grid.set_elevation(peak, Tuning.HILLS_PEAK_ELEVATION)

	var flat_cost := Terrain.cost(Terrain.Type.PLAINS, Terrain.Domain.INFANTRY)

	# One level up is a slope: passable, but slower by
	# SLOPE_ASCENT_COST_PER_LEVEL on top of the terrain's own cost.
	_check(grid.edge_cost(low, slope, Terrain.Domain.INFANTRY) == flat_cost + Terrain.SLOPE_ASCENT_COST_PER_LEVEL, "climbing one elevation level costs the terrain cost plus SLOPE_ASCENT_COST_PER_LEVEL")
	# Land vehicles only ever climb via a rendered ramp — lowland straight up
	# to HILLS_RIM_ELEVATION, the one edge TerrainView3D slopes — so they pay
	# the same ascent cost as Infantry there...
	_check(grid.edge_cost(low, slope, Terrain.Domain.LAND) == flat_cost + Terrain.SLOPE_ASCENT_COST_PER_LEVEL, "Land vehicles can climb the lowland-to-rim slope, same cost as Infantry")
	# ...but rim-to-peak is a single elevation level too (climbable on foot,
	# under CLIFF_ELEVATION_DELTA), with no ramp mesh rendered on it — a
	# vehicle simply has no way to drive up it, unlike Infantry.
	_check(grid.edge_cost(slope, peak, Terrain.Domain.INFANTRY) == flat_cost + Terrain.SLOPE_ASCENT_COST_PER_LEVEL, "Infantry can still climb rim-to-peak on foot, one level")
	_check(grid.edge_cost(slope, peak, Terrain.Domain.LAND) == Terrain.INF, "Land vehicles cannot climb rim-to-peak — no ramp there, even though it's only one level")

	# Descending is free — never a discount, since find_path's heuristic assumes
	# a minimum step cost of 1.0 and would stop being admissible below it.
	_check(grid.edge_cost(slope, low, Terrain.Domain.INFANTRY) == flat_cost, "descending a slope costs the plain terrain cost — no ascent penalty")
	_check(grid.edge_cost(peak, slope, Terrain.Domain.INFANTRY) == flat_cost, "descending is never cheaper than flat ground, so the A* heuristic stays admissible")
	_check(grid.edge_cost(peak, slope, Terrain.Domain.LAND) == flat_cost, "Land vehicles descend freely too — the ramp restriction only ever blocks climbing")

	# Two levels up is a cliff: blocked for ground domains, one way only.
	_check(grid.edge_cost(low, peak, Terrain.Domain.INFANTRY) == Terrain.INF, "a two-level step up is a cliff face — Infantry cannot scale it")
	_check(grid.edge_cost(low, peak, Terrain.Domain.LAND) == Terrain.INF, "a Land vehicle cannot scale a cliff either")
	_check(grid.edge_cost(peak, low, Terrain.Domain.INFANTRY) == flat_cost, "the SAME edge is legal in the other direction — a cliff blocks the climb, not the drop")
	_check(grid.is_cliff_edge(low, peak) and not grid.is_cliff_edge(peak, low), "is_cliff_edge is directional, matching that asymmetry")

	# Air ignores elevation entirely, same as it ignores walls and buildings.
	_check(grid.edge_cost(low, peak, Terrain.Domain.AIR) == Terrain.cost(Terrain.Type.PLAINS, Terrain.Domain.AIR), "Air flies over a cliff at its normal cost")

	# A cliff is routed around, not through: pathing from the lowland to the
	# peak has to detour via the one-level slope, which is exactly the
	# "go up from a different direction" property cliffs exist to create.
	var path := grid.find_path(low, peak, Terrain.Domain.INFANTRY)
	_check(path.size() == 3 and path[1].equals(slope), "A* routes around the cliff face and up the slope instead, reaching the peak the long way")

	# A Land vehicle can reach the rim (via the ramp) but this fixture's peak
	# has no ramp edge onto it at all, so it's genuinely unreachable for Land —
	# unlike Infantry, which gets there via the same detour above.
	_check(grid.find_path(low, peak, Terrain.Domain.LAND).is_empty(), "with no ramp onto the peak, a Land vehicle can't reach it even by detour")
	var land_path := grid.find_path(low, slope, Terrain.Domain.LAND)
	_check(land_path.size() == 2 and land_path[1].equals(slope), "a Land vehicle can still reach the rim directly, over its one ramp edge")

	# With no ramp at all, the peak is genuinely unreachable on foot.
	var sealed_grid := HexGrid.new()
	for hex in [low, slope, peak]:
		sealed_grid.set_terrain(hex, Terrain.Type.PLAINS)
	sealed_grid.set_elevation(slope, 2)
	sealed_grid.set_elevation(peak, 2)
	_check(sealed_grid.find_path(low, peak, Terrain.Domain.INFANTRY).is_empty(), "a plateau cliff-faced on every edge is unreachable on foot — which is why worldgen's repair pass guarantees a ramp")
	_check(not sealed_grid.find_path(low, peak, Terrain.Domain.AIR).is_empty(), "...but Air still gets there, which is the point of cliffs existing")
