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
## build-order.md. `auras`: AuraSystem.resolve_tick()'s output, feeding each
## squad's speed_boost/slow-derived speed multiplier (same caller-computed-
## once convention as CombatResolver's `detections`/`auras`).
static func resolve_tick(dt: float, squads: Array[SquadInstance], grid: HexGrid, troop_defs: Dictionary, auras: Dictionary = {}) -> void:
	for squad in squads:
		_advance_squad(squad, dt, grid, troop_defs, auras)

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

static func _advance_squad(squad: SquadInstance, dt: float, grid: HexGrid, troop_defs: Dictionary, auras: Dictionary = {}) -> void:
	if squad.member_ids.is_empty():
		return
	if squad.boarded_on_squad_id != "":
		return
	if squad.path.is_empty():
		return
	# Regiment lock-step squads are driven by resolve_regiment_tick() instead —
	# see the Regiment section below — so the generic per-squad loop skips them
	# to avoid double-advancing the same squad.
	if squad.order.get("type", "") == "regiment_move":
		return
	# freeze/stun (full lockout) and emp's Land-domain partial lockout both
	# block movement (05-troop-stat-schema.md's Status Effects section).
	if StatusEffectSystem.is_locked_out(squad) or StatusEffectSystem.is_move_locked(squad):
		return

	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var speed := float(def.get("speed", 0.0)) * StatusEffectSystem.move_speed_mult(squad) * AuraSystem.speed_mult(auras, squad.id)
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
	var order_type := String(squad.order.get("type", ""))
	if order_type == "move" or order_type == "regiment_move":
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

## --- Regiment lock-step (04-combat.md's Commanders section /
## 07-data-architecture.md section 4b "Regiment movement is lock-step") -------
##
## A regiment moves as one block on a single shared path computed from the
## Commander's hex, at a flat speed cap (the slowest member's speed stat) —
## not each squad re-deriving its own terrain cost, since every squad occupies
## the identical hex at every step. The Commander's own domain/terrainOverrides
## resolve the shared path's terrain cost (it's the anchor the path is computed
## from); member squads simply mirror its current_hex/path/edge_progress each
## tick rather than pathing independently. A member given a temporary ad hoc
## order (`{type:"move"}`, issued by clicking that squad directly per
## 09-ui-and-controls.md) is left out of lock-step — advanced instead by the
## ordinary per-squad resolve_tick() above — until it goes idle (empty path),
## at which point it's converted back to `{type:"regiment_move"}` and rejoins
## the shared path on the next tick.

## Issues a regiment-wide move order: computes one shared path from
## `commander_squad`'s current hex and mirrors it onto every squad in
## `member_squads`, clearing any ad hoc split. Returns false (no-op, mirroring
## issue_move's failure behavior) if the goal is unreachable for the
## Commander's domain.
static func issue_regiment_move(commander_squad: SquadInstance, member_squads: Array[SquadInstance], grid: HexGrid, goal: HexCoord, troop_defs: Dictionary) -> bool:
	var def: Dictionary = troop_defs.get(commander_squad.troop_type, {})
	var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
	var overrides: Dictionary = def.get("terrainOverrides", {})

	var full := grid.find_path(commander_squad.current_hex, goal, domain, overrides)
	if full.size() <= 1:
		commander_squad.path = []
		return false

	full.remove_at(0)
	commander_squad.path = full
	commander_squad.edge_progress = 0.0
	commander_squad.order = {"type": "regiment_move", "goal": goal.to_key()}

	for squad in member_squads:
		squad.path = full.duplicate()
		squad.edge_progress = 0.0
		squad.order = {"type": "regiment_move", "goal": goal.to_key()}
	return true

## Advances a regiment one tick: rejoins any ad hoc squad that's gone idle,
## advances the Commander along the shared path at the regiment's capped
## (slowest-member) speed, then mirrors the result onto every lock-step member.
static func resolve_regiment_tick(dt: float, commander_squad: SquadInstance, member_squads: Array[SquadInstance], grid: HexGrid, troop_defs: Dictionary, auras: Dictionary = {}) -> void:
	for squad in member_squads:
		if squad.order.get("type", "") == "move" and squad.path.is_empty():
			squad.order = {"type": "regiment_move", "goal": commander_squad.order.get("goal", "")}

	if commander_squad.boarded_on_squad_id != "" or commander_squad.path.is_empty():
		return
	# A locked-out Commander (freeze/stun/emp) halts the whole regiment — its
	# path is the shared anchor, so nothing can advance without it.
	if StatusEffectSystem.is_locked_out(commander_squad) or StatusEffectSystem.is_move_locked(commander_squad):
		return

	var lockstep: Array[SquadInstance] = [commander_squad]
	for squad in member_squads:
		if squad.boarded_on_squad_id != "" or squad.order.get("type", "") != "regiment_move":
			continue
		# A member that's individually locked out just doesn't advance/mirror
		# this tick (temporarily falling out of sync) rather than halting the
		# whole regiment — it rejoins on its own once its lockout ends, same
		# path as an ad hoc split above.
		if StatusEffectSystem.is_locked_out(squad) or StatusEffectSystem.is_move_locked(squad):
			continue
		lockstep.append(squad)

	var speed := INF
	for squad in lockstep:
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		speed = min(speed, float(def.get("speed", 0.0)) * StatusEffectSystem.move_speed_mult(squad) * AuraSystem.speed_mult(auras, squad.id))
	if speed <= 0.0 or speed == INF:
		return

	var commander_def: Dictionary = troop_defs.get(commander_squad.troop_type, {})
	var domain := Terrain.domain_from_string(String(commander_def.get("domain", "Infantry")))
	var overrides: Dictionary = commander_def.get("terrainOverrides", {})

	var remaining_time := dt
	var replanned_this_tick := false
	while remaining_time > 0.0 and not commander_squad.path.is_empty():
		var next_hex: HexCoord = commander_squad.path[0]
		var cost := grid.edge_cost(commander_squad.current_hex, next_hex, domain, overrides)
		if cost == Terrain.INF:
			if replanned_this_tick or not _replan(commander_squad, grid, domain, overrides):
				break
			replanned_this_tick = true
			continue

		var speed_eff := speed / cost
		var time_to_edge := (1.0 - commander_squad.edge_progress) / speed_eff
		if time_to_edge <= remaining_time:
			remaining_time -= time_to_edge
			commander_squad.current_hex = next_hex
			commander_squad.path.remove_at(0)
			commander_squad.edge_progress = 0.0
		else:
			commander_squad.edge_progress += speed_eff * remaining_time
			remaining_time = 0.0

	for squad in lockstep:
		if squad == commander_squad:
			continue
		squad.current_hex = commander_squad.current_hex
		squad.path = commander_squad.path.duplicate()
		squad.edge_progress = commander_squad.edge_progress
