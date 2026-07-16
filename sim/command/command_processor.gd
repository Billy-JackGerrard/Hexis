## The command/order-issuing layer: resolves a player action (ids only — a
## squad id, a target id, a hex) into calls against the existing systems that
## already do the actual work (MovementResolver, CargoSystem, BuildingPlacement,
## ProductionManager, ...). Per 07-data-architecture.md section 8, the
## simulation "advances it by consuming a stream of player actions" and "the
## rendering layer... never mutates simulation state directly" — this class is
## that stream's single entry point. Before it existed, every one of those
## underlying systems already worked, but nothing resolved an id into the live
## object they need, or held the ownership/eligibility checks a raw call site
## shouldn't have to repeat (own-squad-only, own-base-only, Engineer-only
## infrastructure, Commander-only regiment assignment, isFixed-blocks-demolish,
## affordability).
##
## Resource-cost enforcement: place_building/place_standalone_building/
## place_wall/enqueue_production all check the owner's ResourcePool against
## the building/troop def's cost before mutating anything, and only deduct
## once the underlying placement/enqueue actually succeeds — same
## check-then-spend shape rebuild_building already used before this layer
## covered fresh builds and training too. Building costs run through
## BuildingStats.base_cost()/ResourceType.dict_from_named(); troop costs read
## troop_defs[type]["cost"] the same way.
class_name CommandProcessor
extends RefCounted

enum Result {
	OK,
	NOT_FOUND,
	NOT_OWNER,
	INVALID,
	REGIMENT_FULL,
	IS_FIXED,
	INSUFFICIENT_RESOURCES,
	NOT_UNLOCKED,
	NOT_ADJACENT,
	SQUAD_FULL,
	## Upgrade-rejection reasons, split out of the catch-all INVALID so the UI
	## (client/ui/eligibility.gd) can show a specific greyed-out reason. See
	## can_upgrade_building.
	MAX_LEVEL,          ## already at the def's productionUpgradeLevels cap
	HQ_LEVEL_TOO_LOW,   ## a base building can't be upgraded past its HQ's level
	NEED_MORE_POPULATION, ## HQ upgrade gated on minPopulationPerLevel
	SQUAD_CAP_REACHED,     ## enqueue_production: would need a new squad, owner at global squad cap
	COMMANDER_CAP_REACHED, ## enqueue_production: Command Centre training, owner at Commander cap
}

## --- Movement --------------------------------------------------------------

## Moves `squad_id` to `goal`. If it's a Commander currently leading a regiment
## (found via RegimentInstance.commanderId), this computes the shared lock-step
## path for the whole regiment instead of just the Commander's own squad, per
## 07-data-architecture.md 4b ("a move order targeting a Commander computes a
## single path... every member squad mirrors it"). Any other squad (unled,
## escorted, or itself a regiment member issuing an ad hoc split) just gets an
## ordinary issue_move — MovementResolver's own order.type check is what makes
## an ad hoc order on an escorted squad temporarily fall out of lock-step.
static func move_squad(state: MatchState, squad_id: String, goal: HexCoord, owner_id: String) -> Result:
	var squad := state.find_squad(squad_id)
	if squad == null:
		return Result.NOT_FOUND
	if squad.owner_id != owner_id:
		return Result.NOT_OWNER
	if squad.is_docked():
		return Result.INVALID

	for regiment in state.regiments:
		if regiment.commander_id != squad_id:
			continue
		var member_squads: Array[SquadInstance] = []
		for member_id in regiment.squad_ids:
			var member := state.find_squad(member_id)
			if member != null:
				member_squads.append(member)
		var ok := MovementResolver.issue_regiment_move(squad, member_squads, state.grid, goal, state.troop_defs, state.bases, state.standalone_buildings)
		return Result.OK if ok else Result.INVALID

	return Result.OK if MovementResolver.issue_move(squad, state.grid, goal, state.troop_defs, state.bases, state.standalone_buildings) else Result.INVALID

## Sets a directed `attack_target` order — CombatTargeting reads `squad.order`
## directly, so assigning the dict IS the action; this just validates the
## squad/target first so a bad id can't wedge the squad onto a permanently
## unreachable order (CombatTargeting only clears a directed order once the
## target is actually DEAD, not merely illegal/friendly).
static func attack_target(state: MatchState, squad_id: String, target_id: String, owner_id: String) -> Result:
	var squad := state.find_squad(squad_id)
	if squad == null:
		return Result.NOT_FOUND
	if squad.owner_id != owner_id:
		return Result.NOT_OWNER
	if squad.is_docked():
		return Result.INVALID
	var target_owner := _target_owner(state, target_id)
	if target_owner == "":
		return Result.NOT_FOUND
	if target_owner == owner_id:
		return Result.INVALID
	squad.order = {"type": "attack_target", "targetId": target_id}
	return Result.OK

static func _target_owner(state: MatchState, target_id: String) -> String:
	var squad := state.find_squad(target_id)
	if squad != null:
		return squad.owner_id
	var base_building := state.find_base_building(target_id)
	if not base_building.is_empty():
		return (base_building["base"] as BaseInstance).owner_id
	var standalone := state.find_standalone_building(target_id)
	if standalone != null:
		return standalone.owner_id
	return ""

## --- Cargo -------------------------------------------------------------

static func board_cargo(state: MatchState, carrier_squad_id: String, boarding_squad_id: String, owner_id: String) -> Result:
	var carrier := state.find_squad(carrier_squad_id)
	var boarding := state.find_squad(boarding_squad_id)
	if carrier == null or boarding == null:
		return Result.NOT_FOUND
	if carrier.owner_id != owner_id or boarding.owner_id != owner_id:
		return Result.NOT_OWNER
	return Result.OK if CargoSystem.board(carrier, boarding, state.troop_defs, state.grid, state.bases, state.standalone_buildings, state.building_defs) else Result.INVALID

## `in_combat` is derived on demand via CombatStateSystem — see that class's
## doc for why this is queried per-command rather than cached per-tick.
static func unload_cargo(state: MatchState, carrier_squad_id: String, boarded_squad_id: String, target_hex: HexCoord, owner_id: String) -> Result:
	var carrier := state.find_squad(carrier_squad_id)
	var boarded := state.find_squad(boarded_squad_id)
	if carrier == null or boarded == null:
		return Result.NOT_FOUND
	if carrier.owner_id != owner_id:
		return Result.NOT_OWNER
	var in_combat := CombatStateSystem.is_squad_in_combat(carrier, state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, state.standalone_buildings)
	var ok := CargoSystem.unload(carrier, boarded, target_hex, state.grid, state.troop_defs, in_combat, state.bases, state.standalone_buildings, state.building_defs)
	return Result.OK if ok else Result.INVALID

## --- Docking (Hangar) ---------------------------------------------------

## Lands `squad_id` inside `building_id` — a base-attached building (Hangar,
## found via find_base_building; a standalone dockable building doesn't exist
## yet, same scope CargoSystem.can_dock/dock already carry). Ownership of a
## base-attached building comes from its owning base, not the building
## instance itself (see BuildingInstance.owner_id's note).
static func dock_squad(state: MatchState, squad_id: String, building_id: String, owner_id: String) -> Result:
	var squad := state.find_squad(squad_id)
	if squad == null:
		return Result.NOT_FOUND
	var found := state.find_base_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found["base"]
	var building: BuildingInstance = found["building"]
	if squad.owner_id != owner_id:
		return Result.NOT_OWNER
	return Result.OK if CargoSystem.dock(building, base.owner_id, squad, state.troop_defs, state.building_defs) else Result.INVALID

## `in_combat` is derived on demand via CombatStateSystem.is_hex_in_combat,
## same "queried per-command, not cached per-tick" rationale as
## unload_cargo's own in_combat derivation.
static func undock_squad(state: MatchState, squad_id: String, building_id: String, target_hex: HexCoord, owner_id: String) -> Result:
	var squad := state.find_squad(squad_id)
	if squad == null:
		return Result.NOT_FOUND
	var found := state.find_base_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found["base"]
	var building: BuildingInstance = found["building"]
	if squad.owner_id != owner_id:
		return Result.NOT_OWNER
	var in_combat := CombatStateSystem.is_hex_in_combat(building.hex, base.owner_id, state.squads, state.bases, state.troop_defs, state.building_defs)
	var ok := CargoSystem.undock(building, squad, target_hex, state.grid, state.troop_defs, state.building_defs, in_combat)
	return Result.OK if ok else Result.INVALID

## --- Regiment assignment (07-data-architecture.md 4b) ----------------------

## Pure predicate behind assign_to_commander — every rejection reason it can
## return, without spending anything or creating the RegimentInstance. Lets
## the UI (client/ui/eligibility.gd) grey out an ineligible Assign button and
## show the specific reason, same split as can_upgrade_building/
## can_merge_squads. assign_to_commander calls this first and only proceeds
## on OK, so the two can never diverge.
static func can_assign_to_commander(state: MatchState, squad_id: String, commander_squad_id: String, owner_id: String) -> Result:
	var squad := state.find_squad(squad_id)
	var commander_squad := state.find_squad(commander_squad_id)
	if squad == null or commander_squad == null:
		return Result.NOT_FOUND
	if squad.owner_id != owner_id or commander_squad.owner_id != owner_id:
		return Result.NOT_OWNER
	if squad.is_docked():
		return Result.INVALID
	if squad.commander_id == commander_squad_id:
		return Result.INVALID

	var max_squads_led := int(state.troop_defs.get(commander_squad.troop_type, {}).get("maxSquadsLed", 0))
	if max_squads_led <= 0:
		return Result.INVALID

	for regiment in state.regiments:
		if regiment.commander_id == commander_squad_id:
			return Result.REGIMENT_FULL if regiment.is_full(max_squads_led) else Result.OK
	return Result.OK

## Joins `squad_id` to `commander_squad_id`'s regiment, creating the
## RegimentInstance on the Commander's first assigned squad. Rejects a
## boarded/docked squad (can't act independently while cargo, same as a full
## regiment) and a `commander_squad_id` that isn't actually a Commander
## (maxSquadsLed <= 0 in its def).
static func assign_to_commander(state: MatchState, squad_id: String, commander_squad_id: String, owner_id: String) -> Result:
	var check := can_assign_to_commander(state, squad_id, commander_squad_id, owner_id)
	if check != Result.OK:
		return check

	var squad := state.find_squad(squad_id)
	var max_squads_led := int(state.troop_defs.get(state.find_squad(commander_squad_id).troop_type, {}).get("maxSquadsLed", 0))
	var regiment: RegimentInstance = null
	for candidate in state.regiments:
		if candidate.commander_id == commander_squad_id:
			regiment = candidate
			break
	if regiment == null:
		regiment = RegimentInstance.new(state.next_id("regiment"), commander_squad_id)
		state.regiments.append(regiment)

	regiment.assign_squad(squad_id, max_squads_led)
	squad.commander_id = commander_squad_id
	return Result.OK

## Permanently detaches `squad_id` from its current regiment (distinct from
## the temporary ad hoc order-override MovementResolver already handles —
## see 07-data-architecture.md 4b).
static func leave_regiment(state: MatchState, squad_id: String, owner_id: String) -> Result:
	var squad := state.find_squad(squad_id)
	if squad == null:
		return Result.NOT_FOUND
	if squad.owner_id != owner_id:
		return Result.NOT_OWNER
	if squad.commander_id == "":
		return Result.INVALID

	for regiment in state.regiments:
		if regiment.commander_id == squad.commander_id:
			regiment.remove_squad(squad_id)
			break
	squad.commander_id = ""
	if squad.order.get("type", "") == "regiment_move":
		squad.order = {}
	return Result.OK

## Player-initiated counterpart to SquadManager's spawn-time auto-join (see
## squad_manager.gd) — combines two same-type squads standing on the same hex
## by moving `donor_squad_id`'s members into `target_squad_id` up to
## maxSquadSize, for squads that never auto-joined (produced away from each
## other) or thinned out from combat losses. Requires same hex (stricter than
## board_cargo, which has no position check) so merging reads as "stack them,
## then merge" rather than an at-range action. Rejects a Commander as donor
## (maxSquadsLed > 0) since draining one to empty would need the full
## regiment-disband handling CombatResolver does for Commander deaths
## (_disband_regiments_for_dead_commanders), not the simpler single-squad
## removal below.
## Pure (non-mutating) predicate behind merge_squads — same extraction rationale
## as can_upgrade_building/can_enqueue_production: lets the UI
## (client/ui/eligibility.gd) grey out an ineligible Merge button and name the
## reason without draining the donor. merge_squads calls this first and only
## proceeds on OK, so the two can never diverge.
static func can_merge_squads(state: MatchState, target_squad_id: String, donor_squad_id: String, owner_id: String) -> Result:
	var target := state.find_squad(target_squad_id)
	var donor := state.find_squad(donor_squad_id)
	if target == null or donor == null:
		return Result.NOT_FOUND
	if target_squad_id == donor_squad_id:
		return Result.INVALID
	if target.owner_id != owner_id or donor.owner_id != owner_id:
		return Result.NOT_OWNER
	if target.troop_type != donor.troop_type:
		return Result.INVALID
	if int(state.troop_defs.get(donor.troop_type, {}).get("maxSquadsLed", 0)) > 0:
		return Result.INVALID
	if target.is_docked() or donor.is_docked():
		return Result.INVALID
	if not donor.cargo_squad_ids.is_empty():
		return Result.INVALID
	if not target.current_hex.equals(donor.current_hex):
		return Result.NOT_ADJACENT

	var max_squad_size := int(state.troop_defs.get(target.troop_type, {}).get("maxSquadSize", 1))
	if target.is_full(max_squad_size):
		return Result.SQUAD_FULL
	return Result.OK

static func merge_squads(state: MatchState, target_squad_id: String, donor_squad_id: String, owner_id: String) -> Result:
	var check := can_merge_squads(state, target_squad_id, donor_squad_id, owner_id)
	if check != Result.OK:
		return check

	var target := state.find_squad(target_squad_id)
	var donor := state.find_squad(donor_squad_id)
	var max_squad_size := int(state.troop_defs.get(target.troop_type, {}).get("maxSquadSize", 1))

	while not donor.member_ids.is_empty() and not target.is_full(max_squad_size):
		var troop_id: String = donor.member_ids[0]
		donor.remove_member(troop_id)
		target.add_member(troop_id)

	if donor.member_ids.is_empty():
		state.squads.erase(donor)
		if donor.commander_id != "":
			for regiment in state.regiments:
				if regiment.commander_id == donor.commander_id:
					regiment.remove_squad(donor_squad_id)
					break
	return Result.OK

## --- Building placement -----------------------------------------------

## True if `pool` holds at least `cost[type]` of every resource type in
## `cost` (a Type -> float dict, e.g. from ResourceType.dict_from_named).
static func _can_afford(pool: ResourcePool, cost: Dictionary) -> bool:
	for type in cost:
		if pool.get_amount(type) < float(cost[type]):
			return false
	return true

static func _spend(pool: ResourcePool, cost: Dictionary) -> void:
	for type in cost:
		pool.add(type, -float(cost[type]))

static func place_building(state: MatchState, base_id: String, building_type: String, hex: HexCoord, material: String, owner_id: String) -> BuildingPlacement.Result:
	var base := state.find_base(base_id)
	if base == null:
		return BuildingPlacement.Result.BASE_NOT_FOUND
	if base.owner_id != owner_id:
		return BuildingPlacement.Result.NOT_OWNER
	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})
	var occupied_unit_hexes := BuildingPlacement.ground_unit_hexes(state.squads, state.troop_defs)

	var can_result := BuildingPlacement.can_place(base, base_def, building_type, hex, state.grid, state.building_defs, occupied_unit_hexes)
	if can_result != BuildingPlacement.Result.OK:
		return can_result
	var building_def: Dictionary = state.building_defs.get(building_type, {})
	var cost := ResourceType.dict_from_named(BuildingStats.base_cost(building_def, material, state.building_defs))
	var pool := state.pool_for(owner_id)
	if not _can_afford(pool, cost):
		return BuildingPlacement.Result.INSUFFICIENT_RESOURCES

	var result := BuildingPlacement.place_building(base, base_def, building_type, hex, state.grid, state.building_defs, state.next_id(building_type), material, occupied_unit_hexes)
	if result == BuildingPlacement.Result.OK:
		_spend(pool, cost)
	return result

## Standalone (Road/Bridge/Dock/Tower/Landmine) placement is issued either by
## an Engineer squad or by an owner's own HQ (as part of the base, per
## 02-bases-and-buildings.md — Road/Bridge stay standalone/public even when
## HQ-ordered, only the *authorization* path gains a second option):
## - `squad_id` set: the owner's own squad, troop def must carry
##   `canBuildInfrastructure: true` (data/troops/schema.json) and be within
##   Tuning.STANDALONE_BUILD_RANGE of `hex` — it can't drop infrastructure
##   anywhere on the map sight unseen.
## - `squad_id` empty, `building_id` set: an owner-owned "hq" building; `hex`
##   must be within BuildingPlacement.hq_build_radius(base.hq_level) of the
##   HQ, the same radius normal base construction already uses.
##
## `unlockHqLevel` (data/buildings schema, e.g. Road=2/Bridge=3) gates both
## paths alike: standalone buildings aren't tied to a single base, so the
## Engineer path checks the HIGHEST hq_level across every base owner_id owns
## (any one HQ reaching that tier unlocks the ability network-wide) — the
## HQ path just reads that one HQ's own base.hq_level directly.
static func place_standalone_building(state: MatchState, squad_id: String, building_type: String, hex: HexCoord, material: String, owner_id: String, building_id: String = "") -> BuildingPlacement.Result:
	var issuer_hq_level := 0
	if squad_id != "":
		var squad := state.find_squad(squad_id)
		if squad == null or squad.owner_id != owner_id:
			return BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE
		if not bool(state.troop_defs.get(squad.troop_type, {}).get("canBuildInfrastructure", false)):
			return BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE
		if HexCoord.distance(squad.current_hex, hex) > Tuning.STANDALONE_BUILD_RANGE:
			return BuildingPlacement.Result.OUT_OF_ENGINEER_RANGE
		for owned_base in state.bases:
			if owned_base.owner_id == owner_id:
				issuer_hq_level = max(issuer_hq_level, owned_base.hq_level)
	else:
		var found := state.find_base_building(building_id)
		if found.is_empty():
			return BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE
		var base: BaseInstance = found["base"]
		var building: BuildingInstance = found["building"]
		if building.building_type != "hq" or base.owner_id != owner_id:
			return BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE
		if HexCoord.distance(building.hex, hex) > BuildingPlacement.hq_build_radius(base.hq_level):
			return BuildingPlacement.Result.OUT_OF_HQ_RANGE
		issuer_hq_level = base.hq_level

	var building_def: Dictionary = state.building_defs.get(building_type, {})
	if issuer_hq_level < int(building_def.get("unlockHqLevel", 1)):
		return BuildingPlacement.Result.NOT_UNLOCKED

	var occupied_unit_hexes := BuildingPlacement.ground_unit_hexes(state.squads, state.troop_defs)
	var occupied := BuildingPlacement.standalone_occupied_hexes(state.bases, state.standalone_buildings)
	var can_result := BuildingPlacement.can_place_standalone(building_type, hex, state.grid, state.building_defs, occupied, occupied_unit_hexes)
	if can_result != BuildingPlacement.Result.OK:
		return can_result
	var cost := ResourceType.dict_from_named(BuildingStats.base_cost(building_def, material, state.building_defs))
	var pool := state.pool_for(owner_id)
	if not _can_afford(pool, cost):
		return BuildingPlacement.Result.INSUFFICIENT_RESOURCES

	var result := BuildingPlacement.place_standalone_building(state.bases, state.standalone_buildings, building_type, hex, state.grid, state.building_defs, state.next_id(building_type), owner_id, material, occupied_unit_hexes)
	if result == BuildingPlacement.Result.OK:
		_spend(pool, cost)
	return result

static func place_wall(state: MatchState, base_id: String, hex_a: HexCoord, hex_b: HexCoord, material: String, owner_id: String) -> BuildingPlacement.Result:
	var base := state.find_base(base_id)
	if base == null:
		return BuildingPlacement.Result.BASE_NOT_FOUND
	if base.owner_id != owner_id:
		return BuildingPlacement.Result.NOT_OWNER
	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})

	var can_result := BuildingPlacement.can_place_wall(base, base_def, hex_a, hex_b, state.grid, state.building_defs)
	if can_result != BuildingPlacement.Result.OK:
		return can_result
	var building_def: Dictionary = state.building_defs.get("wall", {})
	var cost := ResourceType.dict_from_named(BuildingStats.base_cost(building_def, material, state.building_defs))
	var pool := state.pool_for(owner_id)
	if not _can_afford(pool, cost):
		return BuildingPlacement.Result.INSUFFICIENT_RESOURCES

	var result := BuildingPlacement.place_wall(base, base_def, hex_a, hex_b, state.grid, state.building_defs, state.next_id("wall"), material)
	if result == BuildingPlacement.Result.OK:
		_spend(pool, cost)
	return result

## --- Demolish / rebuild (02-bases-and-buildings.md, 07-data-architecture.md 3a) --

## Voluntarily removes `building_id`, refunding a flat 50% of its
## total_resources_spent. Blocked for `isFixed` buildings (HQ, Ice Spire,
## Radar Array). Applies uniformly to base-attached buildings, Walls, and
## standalone buildings — all three already delete outright, this just
## triggers that deletion voluntarily plus the refund. Also clears any
## ProductionQueue keyed to this building, since a dangling queue pointing at
## a deleted BuildingInstance would break the next production tick.
static func demolish_building(state: MatchState, building_id: String, owner_id: String) -> Result:
	var found := state.find_any_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found.get("base")
	var building: BuildingInstance = found["building"]
	var current_owner := base.owner_id if base != null else building.owner_id
	if current_owner != owner_id:
		return Result.NOT_OWNER

	var def: Dictionary = state.building_defs.get(building.building_type, {})
	if bool(BuildingStats.resolve_def(def, state.building_defs).get("isFixed", false)):
		return Result.IS_FIXED

	var pool := state.pool_for(owner_id)
	for type in building.total_resources_spent:
		pool.add(type, float(building.total_resources_spent[type]) * Tuning.DEMOLISH_REFUND_FRACTION)

	if building.building_type == "wall":
		state.grid.set_wall(building.hex_a, building.hex_b, false)
		base.buildings.erase(building)
	elif base != null:
		base.buildings.erase(building)
	else:
		if building.building_type == "road" or building.building_type == "bridge":
			state.grid.set_infrastructure(building.hex, Terrain.Infrastructure.NONE)
		state.standalone_buildings.erase(building)

	state.production_queues.erase(building_id)
	return Result.OK

## Pays `rebuildCost`% (def-authored, default 50) of the building's level-1
## base_cost to restore a ruin to level 1 at full HP, same material — per
## 06-building-stats-and-defenses.md. Only ever applies to a base-attached
## ruin (Walls/standalone buildings never ruin — they delete outright, per
## find_base_building's scope).
static func rebuild_building(state: MatchState, building_id: String, owner_id: String) -> Result:
	var found := state.find_base_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found["base"]
	var building: BuildingInstance = found["building"]
	if base.owner_id != owner_id:
		return Result.NOT_OWNER
	if not building.is_ruin:
		return Result.INVALID

	var def: Dictionary = state.building_defs.get(building.building_type, {})
	if base.hq_level < int(def.get("unlockHqLevel", 1)):
		return Result.NOT_UNLOCKED
	var percent := BuildingStats.rebuild_cost_percent(def, state.building_defs) / 100.0
	var cost := ResourceType.dict_from_named(BuildingStats.base_cost(def, building.material, state.building_defs))
	for type in cost:
		cost[type] = float(cost[type]) * percent

	var pool := state.pool_for(owner_id)
	for type in cost:
		if pool.get_amount(type) < cost[type]:
			return Result.INSUFFICIENT_RESOURCES
	for type in cost:
		pool.add(type, -cost[type])
		building.total_resources_spent[type] = float(building.total_resources_spent.get(type, 0.0)) + cost[type]

	building.is_ruin = false
	building.level = 1
	building.init_hp(def, state.building_defs)
	building.last_damaged_by = ""
	building.time_since_damage = 0.0
	building.regen_progress = 0.0
	return Result.OK

## Raises `building_id` by one level, per 06-building-stats-and-defenses.md's
## Upgrades section: instant (no build timer), paid via
## BuildingStats.upgrade_cost (costGrowth intentionally outpaces stat growth),
## and capped by BuildingStats.max_level (Production buildings only — length
## of their productionUpgradeLevels table) plus, for any base-attached
## building other than the HQ itself, "no building in a base can be upgraded
## past the HQ's current level" — the HQ's own upgrade instead raises that
## ceiling (and, since HQ level also drives Population.population_cap/
## SquadCap/BuildingPlacement.hq_build_radius via BaseInstance.hq_level rather
## than this BuildingInstance's own `level`, this keeps the two in lockstep).
## A standalone building (no `base`) has no HQ to be capped by. Blocked on a
## ruin/0-HP building same as enqueue_production; not blocked by isFixed
## (that only gates demolish — HQ/Ice Spire are meant to be upgraded).
## Pure (non-mutating) predicate behind upgrade_building — every rejection
## reason it can return, without spending anything. Extracted so the UI
## (client/ui/eligibility.gd) can grey out an ineligible Upgrade button and
## show the specific reason, without duplicating this rule set or having to
## call the mutating path. upgrade_building calls this first and only proceeds
## on OK, so the two can never diverge.
static func can_upgrade_building(state: MatchState, building_id: String, owner_id: String) -> Result:
	var found := state.find_any_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found.get("base")
	var building: BuildingInstance = found["building"]
	var current_owner := base.owner_id if base != null else building.owner_id
	if current_owner != owner_id:
		return Result.NOT_OWNER
	if building.is_ruin or (building.max_hp > 0.0 and building.current_hp <= 0.0):
		return Result.INVALID

	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var target_level := building.level + 1
	var max_level := BuildingStats.max_level(def, state.building_defs)
	if max_level > 0 and target_level > max_level:
		return Result.MAX_LEVEL
	if base != null and building.building_type != "hq" and target_level > base.hq_level:
		return Result.HQ_LEVEL_TOO_LOW

	if building.building_type == "hq":
		var resolved := BuildingStats.resolve_def(def, state.building_defs)
		var min_pop_per_level := float(resolved.get("nonProductionUpgrade", {}).get("minPopulationPerLevel", 0.0))
		var required_pop := min_pop_per_level * (target_level - 1)
		if Population.population_used(base, state.building_defs) < required_pop:
			return Result.NEED_MORE_POPULATION

	var cost := ResourceType.dict_from_named(BuildingStats.upgrade_cost(def, building.level, building.material, state.building_defs))
	if not _can_afford(state.pool_for(owner_id), cost):
		return Result.INSUFFICIENT_RESOURCES
	return Result.OK

static func upgrade_building(state: MatchState, building_id: String, owner_id: String) -> Result:
	var check := can_upgrade_building(state, building_id, owner_id)
	if check != Result.OK:
		return check

	var found := state.find_any_building(building_id)
	var base: BaseInstance = found.get("base")
	var building: BuildingInstance = found["building"]
	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var target_level := building.level + 1

	var cost := ResourceType.dict_from_named(BuildingStats.upgrade_cost(def, building.level, building.material, state.building_defs))
	var pool := state.pool_for(owner_id)
	_spend(pool, cost)
	for type in cost:
		building.total_resources_spent[type] = float(building.total_resources_spent.get(type, 0.0)) + cost[type]

	building.level = target_level
	building.upgrade_hp(def, state.building_defs)
	if building.building_type == "hq":
		base.hq_level = target_level
	return Result.OK

## --- Production (07-data-architecture.md 3b) -------------------------------

## True if `troop_type` is unlocked at `building`'s current level: for a
## Command Centre (commanderProgression), the troop's own commanderTier must
## be unlocked at that level (CommanderProgression.tier_unlocked); for a
## standard Production building (productionUpgradeLevels), troop_type must
## appear in some row's `unlocks` at or below that level. A building def with
## neither block gates nothing (nothing to check against).
static func _troop_unlocked(state: MatchState, building: BuildingInstance, building_def: Dictionary, troop_type: String) -> bool:
	var resolved := BuildingStats.resolve_def(building_def, state.building_defs)

	var commander_progression: Dictionary = resolved.get("commanderProgression", {})
	if not commander_progression.is_empty():
		var tier := String(state.troop_defs.get(troop_type, {}).get("commanderTier", ""))
		return CommanderProgression.tier_unlocked(commander_progression, building.level, tier)

	var production_levels: Array = resolved.get("productionUpgradeLevels", [])
	if not production_levels.is_empty():
		for row in production_levels:
			if String(row.get("unlocks", "")) == troop_type and int(row.get("level", 0)) <= building.level:
				return true
		return false

	return true

## Building level at which `troop_type` first unlocks at a building built from
## `building_def` -- the sort key the UI uses to list troops in unlock order.
## 0 for a troop that's unlocked from level 1 (or ungated entirely).
static func _troop_unlock_level(state: MatchState, building_def: Dictionary, troop_type: String) -> int:
	var resolved := BuildingStats.resolve_def(building_def, state.building_defs)

	var commander_progression: Dictionary = resolved.get("commanderProgression", {})
	if not commander_progression.is_empty():
		var tier := String(state.troop_defs.get(troop_type, {}).get("commanderTier", ""))
		for row in commander_progression.get("tierLevels", []):
			if String(row.get("unlocksTier", "")) == tier:
				return int(row.get("level", 0))
		return 0

	for row in resolved.get("productionUpgradeLevels", []):
		if String(row.get("unlocks", "")) == troop_type:
			return int(row.get("level", 0))

	return 0

## Pure (non-mutating) predicate behind enqueue_production — same extraction
## rationale as can_upgrade_building: lets the UI grey out an unaffordable/
## locked troop and name the reason without touching the queue. Also blocks
## enqueue outright at the squad/Commander cap, mirroring the join-vs-new-squad
## check ProductionManager.pump() makes at deploy time: if an existing
## same-type squad in range still has room, training is allowed regardless of
## cap (the troop will join it); only when a brand-new squad would be needed
## and the owner is already at capacity is enqueue rejected, so the player
## can't spend resources on a troop that would just sit paused undeployed.
static func can_enqueue_production(state: MatchState, building_id: String, troop_type: String, owner_id: String) -> Result:
	var found := state.find_base_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found["base"]
	var building: BuildingInstance = found["building"]
	if base.owner_id != owner_id:
		return Result.NOT_OWNER
	if building.is_ruin or (building.max_hp > 0.0 and building.current_hp <= 0.0):
		return Result.INVALID

	var building_def: Dictionary = state.building_defs.get(building.building_type, {})
	if not _troop_unlocked(state, building, building_def, troop_type):
		return Result.NOT_UNLOCKED

	# Cost is only checked/spent up front when this order would start training
	# immediately (queue empty) -- an order queued behind others pays lazily
	# once it reaches the front (ProductionManager.advance), so it's never
	# rejected for insufficient resources here; see enqueue_production.
	var queue: ProductionQueue = state.production_queues.get(building_id)
	if queue == null or queue.is_empty():
		var cost := ResourceType.dict_from_named(state.troop_defs.get(troop_type, {}).get("cost", {}))
		if not _can_afford(state.pool_for(owner_id), cost):
			return Result.INSUFFICIENT_RESOURCES

	var troop_def: Dictionary = state.troop_defs.get(troop_type, {})
	var max_squad_size: int = int(troop_def.get("maxSquadSize", 1))
	var needs_new_squad := SquadManager.needs_new_squad(
		state.squads, owner_id, troop_type, building.hex, max_squad_size, Tuning.PRODUCTION_JOIN_RANGE_RADIUS
	)
	if needs_new_squad:
		if building.building_type == "command_centre":
			var max_commanders := SquadCap.max_commanders(state.bases_owned_by(owner_id), state.building_defs)
			if state.commander_count(owner_id) >= max_commanders:
				return Result.COMMANDER_CAP_REACHED
		else:
			var owner_squad_count := 0
			for s in state.squads:
				if s.owner_id == owner_id:
					owner_squad_count += 1
			var max_squads := SquadCap.max_squads(state.bases_owned_by(owner_id))
			if owner_squad_count >= max_squads:
				return Result.SQUAD_CAP_REACHED

	return Result.OK

static func enqueue_production(state: MatchState, building_id: String, troop_type: String, owner_id: String) -> Result:
	var check := can_enqueue_production(state, building_id, troop_type, owner_id)
	if check != Result.OK:
		return check

	if not state.production_queues.has(building_id):
		state.production_queues[building_id] = ProductionQueue.new(building_id)
	var queue: ProductionQueue = state.production_queues[building_id]

	# Queue empty -> this entry starts training immediately, so its cost is
	# spent now, synchronously with the command. Queue occupied -> this entry
	# waits its turn and pays lazily when it reaches the front (see
	# ProductionManager.advance), same as the +1 button.
	var starts_immediately := queue.is_empty()
	if starts_immediately:
		var cost := ResourceType.dict_from_named(state.troop_defs.get(troop_type, {}).get("cost", {}))
		_spend(state.pool_for(owner_id), cost)
	ProductionManager.enqueue(queue, troop_type, state.troop_defs, starts_immediately)
	return Result.OK

## Pure predicate behind dequeue_production — index 0 is always rejected: it's
## the actively-training entry (or held complete, if paused), and this command
## only ever trims queued-but-not-yet-training copies (the per-entry -1
## button, which the UI itself never offers for a run of 1).
static func can_dequeue_production(state: MatchState, building_id: String, index: int, owner_id: String) -> Result:
	var found := state.find_base_building(building_id)
	if found.is_empty():
		return Result.NOT_FOUND
	var base: BaseInstance = found["base"]
	if base.owner_id != owner_id:
		return Result.NOT_OWNER
	var queue: ProductionQueue = state.production_queues.get(building_id)
	if queue == null or index <= 0 or index >= queue.entries.size():
		return Result.INVALID
	return Result.OK

## No refund here: index 0 (the only entry ever charged before completion) is
## always rejected above, so every cancellable entry is one that's still
## queued unpaid -- nothing was ever spent on it, per enqueue_production's
## lazy-payment rule.
static func dequeue_production(state: MatchState, building_id: String, index: int, owner_id: String) -> Result:
	var check := can_dequeue_production(state, building_id, index, owner_id)
	if check != Result.OK:
		return check
	var queue: ProductionQueue = state.production_queues[building_id]
	ProductionManager.remove_at(queue, index)
	return Result.OK

## Pure predicate behind enqueue_production_after — the +1 button. Same
## afford/unlock/cap gate as can_enqueue_production (it's exactly one more of
## the same troop type), plus a check that `index` still points at an entry of
## `troop_type` (the queue may have mutated between the button being drawn and
## clicked).
static func can_enqueue_production_after(state: MatchState, building_id: String, troop_type: String, index: int, owner_id: String) -> Result:
	var check := can_enqueue_production(state, building_id, troop_type, owner_id)
	if check != Result.OK:
		return check
	var queue: ProductionQueue = state.production_queues.get(building_id)
	if queue == null or index < 0 or index >= queue.entries.size():
		return Result.INVALID
	if String(queue.entries[index].get("troop_type", "")) != troop_type:
		return Result.INVALID
	return Result.OK

## Never spends up front: the entry it inserts is always behind entries[0]
## (it's a copy of an already-queued run), so it pays lazily like any other
## queued entry once it reaches the front -- see enqueue_production.
static func enqueue_production_after(state: MatchState, building_id: String, troop_type: String, index: int, owner_id: String) -> Result:
	var check := can_enqueue_production_after(state, building_id, troop_type, index, owner_id)
	if check != Result.OK:
		return check
	ProductionManager.insert_after(state.production_queues[building_id], index, troop_type, state.troop_defs)
	return Result.OK
