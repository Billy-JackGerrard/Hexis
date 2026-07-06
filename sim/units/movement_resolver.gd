## Advances squads along their assigned path, per 01-map-and-terrain.md's
## Movement & Positioning section: position is `current_hex` (integer axial)
## plus `edge_progress` (0-1, animation-only — all game logic reads
## current_hex). Stateless/static, same split as CombatResolver (data on
## SquadInstance, timing/rules here). Runs before CombatResolver each tick so
## combat re-derives targets/ranges from post-move positions; movement never
## halts for combat — units advance their path and auto-fire independently
## (04-combat.md's "hold position and fight" describes the idle/no-order
## state, not an override of an explicit move order).
##
## `path` holds only the upcoming hexes to enter (current_hex is not in it);
## an empty path means idle/arrived. Per-tick motion is converted to elapsed
## TIME, not carried as a raw progress fraction, because consecutive edges can
## have different terrain cost (e.g. plains 1.0 -> hills 2.0) — a fraction of
## one edge isn't the same fraction of another, so overflow must be converted
## back to seconds before applying it to the next edge.
class_name MovementResolver
extends RefCounted

## squads: every player's live squads (mutated: current_hex/path/edge_progress
## advanced). Boarded squads (cargo) and squads with no path/zero speed are
## no-ops here — cargo position-driving is deferred, see 10-tech-stack-and-
## build-order.md.
static func resolve_tick(dt: float, squads: Array[SquadInstance], grid: HexGrid, troop_defs: Dictionary) -> void:
	for squad in squads:
		_advance_squad(squad, dt, grid, troop_defs)

## Issues a move order: paths `squad` from its current hex to `goal` and
## starts it moving. Returns false (leaving the squad idle, path cleared) if
## already at `goal` or no route exists for this troop type's domain/
## terrainOverrides. `order` is set alongside `path` so a blocked mid-route
## edge (see _replan) has a stable destination to replan toward, and so this
## stays symmetric with the existing `{type:"attack_target", targetId}`
## convention — CombatTargeting only reacts to "attack_target", so a move
## order never interferes with auto-targeting.
static func issue_move(squad: SquadInstance, grid: HexGrid, goal: HexCoord, troop_defs: Dictionary) -> bool:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
	var overrides: Dictionary = def.get("terrainOverrides", {})

	var full := grid.find_path(squad.current_hex, goal, domain, overrides)
	if full.size() <= 1:
		squad.path = []
		return false

	full.remove_at(0)
	squad.path = full
	squad.edge_progress = 0.0
	squad.order = {"type": "move", "goal": goal.to_key()}
	return true

static func _advance_squad(squad: SquadInstance, dt: float, grid: HexGrid, troop_defs: Dictionary) -> void:
	if squad.member_ids.is_empty():
		return
	if squad.boarded_on_squad_id != "":
		return
	if squad.path.is_empty():
		return

	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var speed := float(def.get("speed", 0.0))
	if speed <= 0.0:
		return
	var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
	var overrides: Dictionary = def.get("terrainOverrides", {})

	var remaining_time := dt
	var replanned_this_tick := false
	while remaining_time > 0.0 and not squad.path.is_empty():
		var next_hex: HexCoord = squad.path[0]
		var cost := grid.edge_cost(squad.current_hex, next_hex, domain, overrides)
		if cost == Terrain.INF:
			if replanned_this_tick or not _replan(squad, grid, domain, overrides):
				break
			replanned_this_tick = true
			continue

		var speed_eff := speed / cost
		var time_to_edge := (1.0 - squad.edge_progress) / speed_eff
		if time_to_edge <= remaining_time:
			remaining_time -= time_to_edge
			squad.current_hex = next_hex
			squad.path.remove_at(0)
			squad.edge_progress = 0.0
		else:
			squad.edge_progress += speed_eff * remaining_time
			remaining_time = 0.0

## Re-paths toward the squad's move-order goal (or the last hex of its
## current path, if the order was somehow lost) after finding the next stored
## edge blocked — e.g. a wall raised mid-route. Clears path (halts in place)
## if no route exists. find_path never returns a blocked first edge, so the
## caller's post-replan retry cannot hit Terrain.INF again on the same edge.
static func _replan(squad: SquadInstance, grid: HexGrid, domain: Terrain.Domain, overrides: Dictionary) -> bool:
	var goal: HexCoord
	if squad.order.get("type", "") == "move":
		goal = HexCoord.from_key(String(squad.order["goal"]))
	else:
		goal = squad.path.back()

	var new_path := grid.find_path(squad.current_hex, goal, domain, overrides)
	if new_path.size() <= 1:
		squad.path = []
		return false

	new_path.remove_at(0)
	squad.path = new_path
	return true
