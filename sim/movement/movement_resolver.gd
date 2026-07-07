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
## advanced). Squads with no path/zero speed are no-ops here. A boarded/docked
## squad (cargo, `boarded_on_squad_id`/`docked_building_id` set — see
## SquadInstance.is_docked(), CargoSystem, 04-combat.md's Cargo section) never
## paths on its own; instead its position is mirrored onto its carrier
## squad's or host building's each tick by `_mirror_boarded_squads`, the same
## "position becomes the host's" treatment regiment lock-step gives escorted
## squads. `auras`: AuraSystem.resolve_tick()'s output, feeding each squad's
## speed_boost/slow-derived speed multiplier (same caller-computed-once
## convention as CombatResolver's `detections`/`auras`). `bases`/
## `standalone_buildings` resolve a docked squad's host building by id, and
## also feed BuildingPlacement.land_blocking_hexes() (01-map-and-terrain.md:
## a standing building blocks Land-domain movement, Road/Bridge/ruins excepted)
## — default to empty so existing callers with no buildings on their grid at
## all don't need to pass them.
static func resolve_tick(dt: float, squads: Array[SquadInstance], grid: HexGrid, troop_defs: Dictionary, auras: Dictionary = {}, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> void:
	var blocked_land_hexes := BuildingPlacement.land_blocking_hexes(bases, standalone_buildings)
	for squad in squads:
		_advance_squad(squad, dt, grid, troop_defs, auras, blocked_land_hexes)
	_mirror_boarded_squads(squads, bases, standalone_buildings)

## Boarded/docked squads don't path/act independently — their current_hex/
## path/edge_progress just track whatever carrier squad or host building
## they're aboard, so the host's own movement (advanced above, since a
## carrier is not itself boarded in the one-level-deep cargo model; a
## building never moves at all) silently drags its cargo along. A no-op for
## any squad whose carrier/building isn't found this tick (already pruned, or
## a stale id) — CombatResolver's carrier/building-death-kills-cargo handles
## that case by removing the boarded/docked squad outright instead.
static func _mirror_boarded_squads(squads: Array[SquadInstance], bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> void:
	var by_id: Dictionary = {}
	for squad in squads:
		by_id[squad.id] = squad
	var buildings_by_id: Dictionary = {}
	for base in bases:
		for building in base.buildings:
			buildings_by_id[building.id] = building
	for building in standalone_buildings:
		buildings_by_id[building.id] = building

	for squad in squads:
		if squad.boarded_on_squad_id != "":
			var carrier: SquadInstance = by_id.get(squad.boarded_on_squad_id)
			if carrier == null:
				continue
			squad.current_hex = carrier.current_hex
			squad.path = []
			squad.edge_progress = 0.0
		elif squad.docked_building_id != "":
			var building: BuildingInstance = buildings_by_id.get(squad.docked_building_id)
			if building == null or building.hex == null:
				continue
			squad.current_hex = building.hex
			squad.path = []
			squad.edge_progress = 0.0

## Issues a move order: paths `squad` from its current hex to `goal` and
## starts it moving. Returns false (leaving the squad idle, path cleared) if
## already at `goal` or no route exists for this troop type's domain/
## terrainOverrides. `order` is set alongside `path` so a blocked mid-route
## edge (see _replan) has a stable destination to replan toward, and so this
## stays symmetric with the existing `{type:"attack_target", targetId}`
## convention — CombatTargeting only reacts to "attack_target", so a move
## order never interferes with auto-targeting.
static func issue_move(squad: SquadInstance, grid: HexGrid, goal: HexCoord, troop_defs: Dictionary, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> bool:
	if not _path_toward(squad, grid, goal, troop_defs, bases, standalone_buildings):
		return false
	squad.order = {"type": "move", "goal": goal.to_key()}
	return true

## Shared pathing core for issue_move and resolve_attack_move: computes a
## fresh path/edge_progress toward `goal` for this troop type's Domain/
## terrainOverrides. Unlike issue_move, this never touches `squad.order` —
## resolve_attack_move needs the squad to keep its `attack_target` order
## while it chases, not have it silently overwritten with `{type:"move"}`.
static func _path_toward(squad: SquadInstance, grid: HexGrid, goal: HexCoord, troop_defs: Dictionary, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> bool:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
	var overrides: Dictionary = def.get("terrainOverrides", {})
	var blocked_land_hexes := BuildingPlacement.land_blocking_hexes(bases, standalone_buildings)

	var full := grid.find_path(squad.current_hex, goal, domain, overrides, blocked_land_hexes)
	if full.size() <= 1:
		squad.path = []
		return false

	full.remove_at(0)
	squad.path = full
	squad.edge_progress = 0.0
	return true

## Attack-move: chases a directed `{type:"attack_target"}` order when its
## target is out of the attacker's range and it isn't already mid-chase,
## per the "attack-move repathing toward a directed target" gap noted since
## the very first movement slice. `targets` is the same
## Array[CombatTarget] CombatResolver already builds each tick (caller-
## computed-once, same convention as `auras`/`detections`).
##
## Once the target IS in range, any in-progress chase path is cleared so the
## squad holds position and fights instead of overshooting/walking through
## it — movement and combat resolve independently each tick (see this file's
## header), so this only decides WHETHER to chase, not whether to fire
## (CombatTargeting already handles firing off the squad's current position,
## re-derived after this runs). A squad without an `attack_target` order, a
## dead/vanished target, or one still mid-chase (non-empty path already) is
## left alone — this never fights the ordinary move/regiment_move systems for
## control of `path`.
static func resolve_attack_move(squads: Array[SquadInstance], troop_defs: Dictionary, grid: HexGrid, targets: Array[CombatTarget], bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> void:
	for squad in squads:
		if squad.member_ids.is_empty() or squad.is_docked():
			continue
		if squad.order.get("type", "") != "attack_target":
			continue
		var target := _find_target(String(squad.order.get("targetId", "")), targets)
		if target == null or not target.is_alive():
			continue

		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var attack_range := int(def.get("range", 0))
		if HexCoord.distance(squad.current_hex, target.hex) <= attack_range:
			squad.path = []
			continue

		if squad.path.is_empty():
			_path_toward(squad, grid, target.hex, troop_defs, bases, standalone_buildings)

static func _find_target(target_id: String, targets: Array[CombatTarget]) -> CombatTarget:
	for target in targets:
		if target.target_id() == target_id:
			return target
	return null

static func _advance_squad(squad: SquadInstance, dt: float, grid: HexGrid, troop_defs: Dictionary, auras: Dictionary = {}, blocked_land_hexes: Dictionary = {}) -> void:
	if squad.member_ids.is_empty():
		return
	if squad.is_docked():
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
		var cost := grid.edge_cost(squad.current_hex, next_hex, domain, overrides, blocked_land_hexes)
		if cost == Terrain.INF:
			if replanned_this_tick or not _replan(squad, grid, domain, overrides, blocked_land_hexes):
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
static func _replan(squad: SquadInstance, grid: HexGrid, domain: Terrain.Domain, overrides: Dictionary, blocked_land_hexes: Dictionary = {}) -> bool:
	var goal: HexCoord
	var order_type := String(squad.order.get("type", ""))
	if order_type == "move" or order_type == "regiment_move":
		goal = HexCoord.from_key(String(squad.order["goal"]))
	else:
		goal = squad.path.back()

	var new_path := grid.find_path(squad.current_hex, goal, domain, overrides, blocked_land_hexes)
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
static func issue_regiment_move(commander_squad: SquadInstance, member_squads: Array[SquadInstance], grid: HexGrid, goal: HexCoord, troop_defs: Dictionary, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> bool:
	var def: Dictionary = troop_defs.get(commander_squad.troop_type, {})
	var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
	var overrides: Dictionary = def.get("terrainOverrides", {})
	var blocked_land_hexes := BuildingPlacement.land_blocking_hexes(bases, standalone_buildings)

	var full := grid.find_path(commander_squad.current_hex, goal, domain, overrides, blocked_land_hexes)
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

## Advances a regiment one tick: rejoins any ad hoc-split or cargo-unloaded
## squad that's gone idle, advances the Commander along the shared path at
## the regiment's capped (slowest-member) speed, then mirrors the result onto
## every lock-step member.
##
## A member currently boarded/docked (`is_docked()` — see CargoSystem) never
## rejoins here: it has no independent position to mirror while carried
## (MovementResolver's `_mirror_boarded_squads` tracks its carrier/host
## building instead, same as any non-regiment boarded/docked squad), and it
## keeps its `commander_id`, so it's still logically a member the whole time.
## Once `CargoSystem.unload()`/`undock()` clears its docked state it leaves
## the squad idle (order `{}`, empty path) rather than restoring
## `regiment_move` itself (CargoSystem has no regiment awareness — same
## order-issuing-layer gap noted throughout this file) — so the idle case
## below is broadened to catch a freshly-unloaded/undocked member too, not
## just an ad hoc `{type:"move"}` split.
static func resolve_regiment_tick(dt: float, commander_squad: SquadInstance, member_squads: Array[SquadInstance], grid: HexGrid, troop_defs: Dictionary, auras: Dictionary = {}, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> void:
	for squad in member_squads:
		if squad.is_docked():
			continue
		if squad.order.get("type", "") != "regiment_move" and squad.path.is_empty():
			squad.order = {"type": "regiment_move", "goal": commander_squad.order.get("goal", "")}

	if commander_squad.is_docked() or commander_squad.path.is_empty():
		return
	# A locked-out Commander (freeze/stun/emp) halts the whole regiment — its
	# path is the shared anchor, so nothing can advance without it.
	if StatusEffectSystem.is_locked_out(commander_squad) or StatusEffectSystem.is_move_locked(commander_squad):
		return

	var lockstep: Array[SquadInstance] = [commander_squad]
	for squad in member_squads:
		if squad.is_docked() or squad.order.get("type", "") != "regiment_move":
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
	var blocked_land_hexes := BuildingPlacement.land_blocking_hexes(bases, standalone_buildings)

	var remaining_time := dt
	var replanned_this_tick := false
	while remaining_time > 0.0 and not commander_squad.path.is_empty():
		var next_hex: HexCoord = commander_squad.path[0]
		var cost := grid.edge_cost(commander_squad.current_hex, next_hex, domain, overrides, blocked_land_hexes)
		if cost == Terrain.INF:
			if replanned_this_tick or not _replan(commander_squad, grid, domain, overrides, blocked_land_hexes):
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
