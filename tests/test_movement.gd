## Headless assertion suite for the movement slice (sim/units/movement_resolver.gd,
## the terrainOverrides plumbing in sim/hex/terrain_types.gd + sim/hex/hex_grid.gd).
## Run with:
##   godot --headless --script res://tests/test_movement.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _next_id: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")

	print("Terrain overrides")
	_test_terrain_overrides()
	print("MovementResolver")
	_test_movement_resolver()
	print("Regiment lock-step")
	_test_regiment_lockstep()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers -------------------------------------------------------------

func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.001

## A straight +q line of hexes at (0,0),(1,0),(2,0),... with the given terrain
## per index; every other hex defaults to OCEAN (has_hex false, effectively
## off-map for anything that doesn't already treat OCEAN as impassable).
func _line_grid(terrains: Array) -> HexGrid:
	var grid := HexGrid.new()
	for i in range(terrains.size()):
		grid.set_terrain(HexCoord.new(i, 0), terrains[i])
	return grid

func _make_squad(owner: String, troop_type: String, hex: HexCoord) -> SquadInstance:
	_next_id += 1
	var squad := SquadInstance.new("sq%d" % _next_id, owner, troop_type, hex)
	squad.add_member("tr%d" % _next_id)
	return squad

## --- Terrain overrides ----------------------------------------------------

func _test_terrain_overrides() -> void:
	# ignoresForestBlock clears Forest's Land block, same as a Road would.
	_check(Terrain.effective_cost(Terrain.Type.FOREST, Terrain.Domain.LAND) == Terrain.INF, "Forest blocks Land by default")
	_check(Terrain.effective_cost(Terrain.Type.FOREST, Terrain.Domain.LAND, Terrain.Infrastructure.NONE, {"ignoresForestBlock": true}) == 1.0, "ignoresForestBlock clears Forest's Land block")
	_check(Terrain.effective_cost(Terrain.Type.FOREST, Terrain.Domain.LAND, Terrain.Infrastructure.NONE, {}) == Terrain.INF, "missing override -> still blocked")

	# ignoresRiverBlock clears River's Infantry/Land block, same as a Bridge would.
	_check(Terrain.effective_cost(Terrain.Type.RIVER, Terrain.Domain.INFANTRY, Terrain.Infrastructure.NONE, {"ignoresRiverBlock": true}) == 1.0, "ignoresRiverBlock clears River's Infantry block")

	# overrides never clear a Wall (a separate edge-level check in HexGrid).
	var grid := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	grid.set_wall(HexCoord.new(0, 0), HexCoord.new(1, 0), true)
	_check(grid.edge_cost(HexCoord.new(0, 0), HexCoord.new(1, 0), Terrain.Domain.LAND, {"ignoresForestBlock": true, "ignoresRiverBlock": true}) == Terrain.INF, "terrainOverrides do not clear a Wall")

	# domain_from_string maps the schema's four domain strings 1:1.
	_check(Terrain.domain_from_string("Infantry") == Terrain.Domain.INFANTRY, "domain_from_string Infantry")
	_check(Terrain.domain_from_string("Land") == Terrain.Domain.LAND, "domain_from_string Land")
	_check(Terrain.domain_from_string("Air") == Terrain.Domain.AIR, "domain_from_string Air")
	_check(Terrain.domain_from_string("Naval") == Terrain.Domain.NAVAL, "domain_from_string Naval")

## --- MovementResolver ------------------------------------------------------

func _test_movement_resolver() -> void:
	# 1. Single-hex partial advance: rifleman (speed 1.2) on plains.
	var grid1 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s1 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(s1, grid1, HexCoord.new(3, 0), _troop_defs), "issue_move succeeds toward a reachable goal")
	MovementResolver.resolve_tick(0.5, [s1], grid1, _troop_defs)
	_check(s1.current_hex.equals(HexCoord.new(0, 0)), "0.5s @ speed 1.2: still on the starting hex")
	_check(_approx(s1.edge_progress, 0.6), "0.5s @ speed 1.2: edge_progress = 0.6")
	MovementResolver.resolve_tick(0.5, [s1], grid1, _troop_defs)
	_check(s1.current_hex.equals(HexCoord.new(1, 0)), "second 0.5s tick crosses the first hex boundary")
	_check(_approx(s1.edge_progress, 0.2), "leftover time carried onto the new edge (0.2)")

	# 2. Multi-hex advance in one big-dt tick: quad_bike (speed 3.0) on plains.
	var grid2 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s2 := _make_squad("p1", "quad_bike", HexCoord.new(0, 0))
	MovementResolver.issue_move(s2, grid2, HexCoord.new(4, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s2], grid2, _troop_defs)
	_check(s2.current_hex.equals(HexCoord.new(3, 0)), "1.0s @ speed 3.0 on plains crosses 3 whole hexes")
	_check(_approx(s2.edge_progress, 0.0), "no leftover progress after an exact 3-hex tick")

	# 3. Terrain-cost slowdown: rifleman on hills (cost 2.0) moves half as fast.
	var grid3 := _line_grid([Terrain.Type.HILLS, Terrain.Type.HILLS])
	var s3 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s3, grid3, HexCoord.new(1, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s3], grid3, _troop_defs)
	_check(s3.current_hex.equals(HexCoord.new(0, 0)), "hills: 1.0s @ effective speed 0.6 doesn't finish the hex")
	_check(_approx(s3.edge_progress, 0.6), "hills: edge_progress = speed/cost * dt = 0.6")

	# 4. Differing-cost remainder correctness: plains -> plains -> hills.
	# Crossing hex0->hex1 (plains, cost 1) takes 1/1.2 = 0.8333s, leaving
	# 0.1667s for hex1->hex2 (hills, cost 2, effective speed 0.6): 0.1667*0.6 = 0.1.
	# A naive fraction-carry (instead of a time-carry) would instead give ~0.2.
	var grid4 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.HILLS])
	var s4 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s4, grid4, HexCoord.new(2, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s4], grid4, _troop_defs)
	_check(s4.current_hex.equals(HexCoord.new(1, 0)), "crosses exactly the first (plains) edge in 1.0s")
	_check(_approx(s4.edge_progress, 0.1), "leftover time correctly re-applied at the hills edge's own speed (0.1, not 0.2)")

	# 5. Unreachable goal -> issue_move fails, no movement.
	var grid5 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.FOREST])
	var s5 := _make_squad("p1", "basekiller", HexCoord.new(0, 0))
	_check(not MovementResolver.issue_move(s5, grid5, HexCoord.new(1, 0), _troop_defs), "Land unit can't path through Forest -> issue_move returns false")
	_check(s5.path.is_empty(), "path stays empty on a failed issue_move")
	MovementResolver.resolve_tick(1.0, [s5], grid5, _troop_defs)
	_check(s5.current_hex.equals(HexCoord.new(0, 0)), "no path -> ticking is a no-op")

	# 6. Arrive-and-stop: adjacent goal, tick until arrival, then a no-op tick.
	var grid6 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s6 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s6, grid6, HexCoord.new(1, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s6], grid6, _troop_defs)
	_check(s6.current_hex.equals(HexCoord.new(1, 0)), "arrives at the adjacent goal")
	_check(s6.path.is_empty(), "path drained on arrival")
	_check(_approx(s6.edge_progress, 0.0), "edge_progress reset to 0 on arrival")
	MovementResolver.resolve_tick(1.0, [s6], grid6, _troop_defs)
	_check(s6.current_hex.equals(HexCoord.new(1, 0)), "further ticking after arrival is a no-op")

	# 7. Boarded squad is skipped entirely (cargo position-driving deferred).
	var grid7 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s7 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s7, grid7, HexCoord.new(1, 0), _troop_defs)
	s7.boarded_on_squad_id = "carrier1"
	MovementResolver.resolve_tick(1.0, [s7], grid7, _troop_defs)
	_check(s7.current_hex.equals(HexCoord.new(0, 0)), "a boarded squad does not advance")
	_check(_approx(s7.edge_progress, 0.0), "a boarded squad's edge_progress is untouched")

	# 8. Air ignores walls; a Land unit does not.
	var grid8 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	grid8.set_wall(HexCoord.new(0, 0), HexCoord.new(1, 0), true)
	var s8_air := _make_squad("p1", "glider", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(s8_air, grid8, HexCoord.new(2, 0), _troop_defs), "Air paths straight through a walled edge")
	MovementResolver.resolve_tick(1.0, [s8_air], grid8, _troop_defs)
	_check(not s8_air.current_hex.equals(HexCoord.new(0, 0)), "Air actually crosses the walled edge when ticked")
	var s8_land := _make_squad("p2", "basekiller", HexCoord.new(0, 0))
	_check(not MovementResolver.issue_move(s8_land, grid8, HexCoord.new(2, 0), _troop_defs), "a Land unit cannot path across the same walled edge (no detour exists on this line)")

	# 9. terrainOverrides honored: basekiller (Land, no override) is blocked by
	# Forest; quad_bike (ignoresForestBlock) traverses it at cost 1.0.
	var grid9 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.PLAINS])
	var s9_blocked := _make_squad("p1", "basekiller", HexCoord.new(0, 0))
	_check(not MovementResolver.issue_move(s9_blocked, grid9, HexCoord.new(2, 0), _troop_defs), "basekiller (no override) can't path through Forest")
	var s9_ok := _make_squad("p1", "quad_bike", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(s9_ok, grid9, HexCoord.new(2, 0), _troop_defs), "quad_bike (ignoresForestBlock) paths through Forest")
	MovementResolver.resolve_tick(1.0, [s9_ok], grid9, _troop_defs)
	_check(not s9_ok.current_hex.equals(HexCoord.new(0, 0)), "quad_bike actually advances into/through the Forest hex")

	# 10. Mid-move replan: a wall raised on the next edge after the order was
	# issued forces a reroute (or a clean halt if no detour exists).
	var grid10 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s10 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s10, grid10, HexCoord.new(2, 0), _troop_defs)
	grid10.set_wall(HexCoord.new(0, 0), HexCoord.new(1, 0), true)
	MovementResolver.resolve_tick(1.0, [s10], grid10, _troop_defs)
	_check(s10.current_hex.equals(HexCoord.new(0, 0)), "no detour exists on this line -> squad halts at its current hex, doesn't teleport/error")
	_check(s10.path.is_empty(), "a blocked route with no detour clears the path (idle) rather than looping forever")

## --- Regiment lock-step ----------------------------------------------------

func _test_regiment_lockstep() -> void:
	# 1. issue_regiment_move mirrors the Commander's shared path onto every
	# member squad (all starting from the Commander's own hex).
	var grid1 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var cmd1 := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0))
	var m1a := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var m1b := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	_check(MovementResolver.issue_regiment_move(cmd1, [m1a, m1b], grid1, HexCoord.new(3, 0), _troop_defs), "issue_regiment_move succeeds toward a reachable goal")
	_check(m1a.path.size() == cmd1.path.size(), "member path mirrors the Commander's shared path")
	_check(m1a.order.get("type") == "regiment_move", "member order flips to regiment_move")
	_check(m1b.order.get("type") == "regiment_move", "second member order flips to regiment_move")

	# 2. Regiment speed is capped by its slowest member (sniper, speed 1.0),
	# not the faster Commander (3.2) or rifleman (1.2).
	MovementResolver.resolve_regiment_tick(1.0, cmd1, [m1a, m1b], grid1, _troop_defs)
	_check(cmd1.current_hex.equals(HexCoord.new(1, 0)), "1.0s @ capped speed 1.0 crosses exactly one plains hex")
	_check(_approx(cmd1.edge_progress, 0.0), "no leftover progress after an exact 1-hex tick")
	_check(m1a.current_hex.equals(cmd1.current_hex), "rifleman mirrors the Commander's new hex")
	_check(m1b.current_hex.equals(cmd1.current_hex), "sniper mirrors the Commander's new hex")
	_check(m1a.path.size() == cmd1.path.size(), "rifleman's remaining path still mirrors the Commander's")

	# 3. An ad hoc order splits a member off; it advances independently via the
	# ordinary per-squad resolve_tick (not resolve_regiment_tick), and is left
	# behind by the lock-step block.
	var grid2 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var cmd2 := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0))
	var m2 := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	MovementResolver.issue_regiment_move(cmd2, [m2], grid2, HexCoord.new(3, 0), _troop_defs)
	MovementResolver.issue_move(m2, grid2, HexCoord.new(2, 0), _troop_defs)
	_check(m2.order.get("type") == "move", "ad hoc order on a member overrides its regiment_move order")
	MovementResolver.resolve_regiment_tick(0.1, cmd2, [m2], grid2, _troop_defs)
	_check(_approx(cmd2.edge_progress, 0.32), "Commander still advances alone at its own capped speed 3.2 (no other lock-step members)")
	_check(m2.current_hex.equals(HexCoord.new(0, 0)), "ad hoc-split member is untouched by resolve_regiment_tick")

	# 4. Once the ad hoc-split member goes idle (arrives / path drains), it
	# automatically rejoins the shared path on the next regiment tick.
	MovementResolver.resolve_tick(2.0, [m2], grid2, _troop_defs)
	_check(m2.path.is_empty(), "ad hoc order (speed 1.0, 2 hexes) fully resolved in 2.0s -> idle")
	MovementResolver.resolve_regiment_tick(1.0, cmd2, [m2], grid2, _troop_defs)
	_check(m2.order.get("type") == "regiment_move", "idle member converts back to regiment_move")
	_check(m2.current_hex.equals(cmd2.current_hex), "rejoined member mirrors the Commander's hex again")

	# 5. Unreachable goal for the Commander's domain -> issue_regiment_move
	# fails, no member is mutated.
	var grid3 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.FOREST])
	var cmd3 := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0))
	var m3 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	_check(not MovementResolver.issue_regiment_move(cmd3, [m3], grid3, HexCoord.new(1, 0), _troop_defs), "Land Commander can't path through Forest -> issue_regiment_move returns false")
	_check(m3.path.is_empty(), "member path untouched (still empty) on a failed issue_regiment_move")
	_check(m3.order.is_empty(), "member order untouched on a failed issue_regiment_move")
