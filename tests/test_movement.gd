## Headless assertion suite for the movement slice (sim/movement/movement_resolver.gd,
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
	print("Attack-move (resolve_attack_move)")
	_test_attack_move()
	print("Buildings block Land vehicles")
	_test_building_blocking()

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
	var rifleman_speed: float = float(_troop_defs["rifleman"]["speed"])
	var quad_bike_speed: float = float(_troop_defs["quad_bike"]["speed"])
	# Hills' Infantry movement-cost multiplier is a sim/-side placeholder
	# constant (Terrain.HILLS_INFANTRY_COST), not authored in data/troops/ —
	# out of this file's data-driven-ification scope, but named here so the
	# speed-derived math below stays legible.
	var hills_infantry_cost := 2.0

	# 1. Single-hex partial advance: rifleman on plains.
	var grid1 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s1 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(s1, grid1, HexCoord.new(3, 0), _troop_defs), "issue_move succeeds toward a reachable goal")
	MovementResolver.resolve_tick(0.5, [s1], grid1, _troop_defs)
	_check(s1.current_hex.equals(HexCoord.new(0, 0)), "0.5s @ rifleman's speed: still on the starting hex")
	_check(_approx(s1.edge_progress, rifleman_speed * 0.5), "0.5s @ rifleman's speed (%s): edge_progress = %s" % [rifleman_speed, rifleman_speed * 0.5])
	MovementResolver.resolve_tick(0.5, [s1], grid1, _troop_defs)
	_check(s1.current_hex.equals(HexCoord.new(1, 0)), "second 0.5s tick crosses the first hex boundary")
	_check(_approx(s1.edge_progress, rifleman_speed * 1.0 - 1.0), "leftover time carried onto the new edge (%s)" % (rifleman_speed * 1.0 - 1.0))

	# 2. Multi-hex advance in one big-dt tick: quad_bike on plains.
	var grid2 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var s2 := _make_squad("p1", "quad_bike", HexCoord.new(0, 0))
	MovementResolver.issue_move(s2, grid2, HexCoord.new(4, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s2], grid2, _troop_defs)
	var quad_hexes_crossed: int = int(floor(quad_bike_speed))
	var quad_leftover: float = quad_bike_speed - float(quad_hexes_crossed)
	_check(s2.current_hex.equals(HexCoord.new(quad_hexes_crossed, 0)), "1.0s @ quad_bike's speed (%s) on plains crosses %d whole hexes" % [quad_bike_speed, quad_hexes_crossed])
	_check(_approx(s2.edge_progress, quad_leftover), "leftover progress after the tick (%s)" % quad_leftover)

	# 3. Terrain-cost slowdown: rifleman on hills moves at speed/cost.
	var grid3 := _line_grid([Terrain.Type.HILLS, Terrain.Type.HILLS])
	var s3 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s3, grid3, HexCoord.new(1, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s3], grid3, _troop_defs)
	var hills_effective_speed: float = rifleman_speed / hills_infantry_cost
	_check(s3.current_hex.equals(HexCoord.new(0, 0)), "hills: 1.0s @ effective speed %s doesn't finish the hex" % hills_effective_speed)
	_check(_approx(s3.edge_progress, hills_effective_speed), "hills: edge_progress = speed/cost * dt = %s" % hills_effective_speed)

	# 4. Differing-cost remainder correctness: plains -> plains -> hills.
	# Crossing hex0->hex1 (plains, cost 1) takes 1/speed seconds, leaving the
	# remainder of the 1.0s tick for hex1->hex2 (hills, effective speed
	# speed/cost). A naive fraction-carry (instead of a time-carry) would
	# instead give a different, wrong remainder.
	var grid4 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.HILLS])
	var s4 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.issue_move(s4, grid4, HexCoord.new(2, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [s4], grid4, _troop_defs)
	var leftover_time: float = 1.0 - 1.0 / rifleman_speed
	var expected_progress4: float = leftover_time * hills_effective_speed
	_check(s4.current_hex.equals(HexCoord.new(1, 0)), "crosses exactly the first (plains) edge in 1.0s")
	_check(_approx(s4.edge_progress, expected_progress4), "leftover time correctly re-applied at the hills edge's own speed (%s, via time-carry not fraction-carry)" % expected_progress4)

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

	# 2. Regiment speed is capped by its slowest member (sniper), not the
	# faster Commander or rifleman.
	var sniper_speed: float = float(_troop_defs["sniper"]["speed"])
	var commander_speed: float = float(_troop_defs["commander_vanguard"]["speed"])
	MovementResolver.resolve_regiment_tick(1.0, cmd1, [m1a, m1b], grid1, _troop_defs)
	var sniper_hexes_crossed: int = int(floor(sniper_speed))
	var sniper_leftover: float = sniper_speed - float(sniper_hexes_crossed)
	_check(cmd1.current_hex.equals(HexCoord.new(sniper_hexes_crossed, 0)), "1.0s @ capped speed (sniper's, %s) crosses %d plains hex(es)" % [sniper_speed, sniper_hexes_crossed])
	_check(_approx(cmd1.edge_progress, sniper_leftover), "leftover progress after the capped tick (%s)" % sniper_leftover)
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
	_check(_approx(cmd2.edge_progress, commander_speed * 0.1), "Commander still advances alone at its own capped speed (%s, no other lock-step members)" % commander_speed)
	_check(m2.current_hex.equals(HexCoord.new(0, 0)), "ad hoc-split member is untouched by resolve_regiment_tick")

	# 4. Once the ad hoc-split member goes idle (arrives / path drains), it
	# automatically rejoins the shared path on the next regiment tick.
	MovementResolver.resolve_tick(2.0, [m2], grid2, _troop_defs)
	_check(m2.path.is_empty(), "ad hoc order (sniper's speed %s, 2 hexes) fully resolved in 2.0s -> idle" % sniper_speed)
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

	# 6. A regiment member boarded as cargo mid-regiment: excluded from
	# lock-step mirroring while boarded (CargoSystem.board clears its
	# regiment_move order, and it has no independent position anyway — see
	# MovementResolver._mirror_boarded_squads), then automatically rejoins
	# regiment_move on the next regiment tick once CargoSystem.unload()
	# releases it, per resolve_regiment_tick's broadened idle-rejoin check.
	var grid6 := _line_grid([
		Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS,
		Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS,
	])
	var cmd6 := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0))
	var m6 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var truck6 := _make_squad("p1", "transport_truck", HexCoord.new(0, 0))
	m6.commander_id = cmd6.id
	MovementResolver.issue_regiment_move(cmd6, [m6], grid6, HexCoord.new(5, 0), _troop_defs)
	CargoSystem.board(truck6, m6, _troop_defs)
	_check(m6.boarded_on_squad_id == truck6.id, "member squad boards the carrier")
	_check(m6.order.is_empty(), "boarding clears the member's regiment_move order")
	_check(m6.commander_id == cmd6.id, "boarding does not touch commander_id — still a member throughout")

	MovementResolver.resolve_regiment_tick(1.0, cmd6, [m6], grid6, _troop_defs)
	_check(not cmd6.path.is_empty(), "Commander is still en route (not yet at goal) after this tick")
	_check(m6.current_hex.equals(HexCoord.new(0, 0)), "boarded member does not mirror the Commander while still cargo")

	CargoSystem.unload(truck6, m6, HexCoord.new(0, 0), grid6, _troop_defs)
	_check(m6.boarded_on_squad_id == "", "member unloaded, no longer cargo")
	_check(m6.order.is_empty(), "CargoSystem.unload leaves the member idle ({}), not regiment_move")

	MovementResolver.resolve_regiment_tick(1.0, cmd6, [m6], grid6, _troop_defs)
	_check(m6.order.get("type") == "regiment_move", "unloaded member automatically rejoins regiment_move on the next regiment tick")
	_check(m6.current_hex.equals(cmd6.current_hex), "rejoined member mirrors the Commander's hex again")

## --- Attack-move (resolve_attack_move) --------------------------------------

func _make_target(owner: String, troop_type: String, hex: HexCoord) -> CombatTarget:
	_next_id += 1
	var squad := SquadInstance.new("tsq%d" % _next_id, owner, troop_type, hex)
	var tid := "ttr%d" % _next_id
	squad.add_member(tid)
	var troops: Dictionary = {tid: TroopInstance.new(tid, troop_type, owner, squad.id, 100.0)}
	return CombatTarget.for_squad(squad, _troop_defs.get(troop_type, {}), troops)

func _test_attack_move() -> void:
	var rifleman_range: float = float(_troop_defs["rifleman"]["range"])
	var grid := _line_grid([
		Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS,
		Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS,
		Terrain.Type.PLAINS,
	])

	# 1. Target out of range, attacker idle -> chases (issues a fresh path)
	# toward the target's current hex, WITHOUT clobbering the attack_target
	# order the way issue_move's own {type:"move"} order would.
	var attacker := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var far_target := _make_target("p2", "rifleman", HexCoord.new(8, 0))
	attacker.order = {"type": "attack_target", "targetId": far_target.target_id()}
	MovementResolver.resolve_attack_move([attacker], _troop_defs, grid, [far_target])
	_check(not attacker.path.is_empty(), "attacker out of range (dist 8 > rifleman's range %s) chases toward the target" % rifleman_range)
	_check(attacker.order.get("type") == "attack_target", "chasing does not overwrite the attack_target order")
	_check(attacker.order.get("targetId") == far_target.target_id(), "attack_target's targetId is preserved while chasing")

	# 2. Once already mid-chase (non-empty path), a further call doesn't
	# recompute/reissue the path every tick.
	var path_before := attacker.path.duplicate()
	MovementResolver.resolve_attack_move([attacker], _troop_defs, grid, [far_target])
	_check(attacker.path == path_before, "an in-progress chase path is left alone, not recomputed each call")

	# 3. Once the target is in range, any in-progress chase path is cleared
	# so the squad holds position and fights instead of overshooting.
	var near_attacker := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var near_target := _make_target("p2", "rifleman", HexCoord.new(3, 0))
	near_attacker.order = {"type": "attack_target", "targetId": near_target.target_id()}
	near_attacker.path = [HexCoord.new(1, 0), HexCoord.new(2, 0)]
	MovementResolver.resolve_attack_move([near_attacker], _troop_defs, grid, [near_target])
	_check(near_attacker.path.is_empty(), "target already in range (dist 3 <= rifleman's range %s) clears any in-progress chase path" % rifleman_range)

	# 4. A squad with no attack_target order is left completely alone.
	var idle_squad := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	MovementResolver.resolve_attack_move([idle_squad], _troop_defs, grid, [far_target])
	_check(idle_squad.path.is_empty(), "a squad with no attack_target order is untouched by resolve_attack_move")

	# 5. A dead/vanished target is a no-op (order is left for CombatTargeting's
	# own dead-target cleanup, per select_target's existing behavior).
	var orphan := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	orphan.order = {"type": "attack_target", "targetId": "nonexistent"}
	MovementResolver.resolve_attack_move([orphan], _troop_defs, grid, [far_target])
	_check(orphan.path.is_empty(), "a directed order pointing at an untracked/dead target triggers no chase")

## --- Buildings block Land vehicles (BuildingPlacement.land_blocking_hexes) --

func _test_building_blocking() -> void:
	# 1. A standing (base-attached) building on the only route blocks a Land
	# vehicle from pathing through it...
	var grid1 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var base1 := BaseInstance.new("b1", "capital", "p2", 1, HexCoord.new(1, 0))
	base1.buildings.append(BuildingInstance.new("bld1", "b1", "barracks", 1, "", HexCoord.new(1, 0)))
	var land1 := _make_squad("p1", "basekiller", HexCoord.new(0, 0))
	_check(not MovementResolver.issue_move(land1, grid1, HexCoord.new(2, 0), _troop_defs, [base1]), "a Land vehicle cannot path through a standing building")

	# 2. ...but Infantry passes through the same hex freely (only Domain.LAND
	# consults blocked_land_hexes).
	var infantry1 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(infantry1, grid1, HexCoord.new(2, 0), _troop_defs, [base1]), "Infantry ignores building occupancy")

	# 3. A Road hex stays passable for Land vehicles (infrastructure exception).
	var grid2 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var road := BuildingInstance.new("bld2", "", "road", 1, "", HexCoord.new(1, 0))
	var land2 := _make_squad("p1", "basekiller", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(land2, grid2, HexCoord.new(2, 0), _troop_defs, [], [road]), "a Road hex stays passable for Land vehicles")

	# 4. A ruined building (destroyed, not yet rebuilt) no longer blocks.
	var grid3 := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var base3 := BaseInstance.new("b3", "capital", "p2", 1, HexCoord.new(1, 0))
	var ruin := BuildingInstance.new("bld3", "b3", "barracks", 1, "", HexCoord.new(1, 0))
	ruin.is_ruin = true
	base3.buildings.append(ruin)
	var land3 := _make_squad("p1", "basekiller", HexCoord.new(0, 0))
	_check(MovementResolver.issue_move(land3, grid3, HexCoord.new(2, 0), _troop_defs, [base3]), "a ruin no longer blocks Land movement")
