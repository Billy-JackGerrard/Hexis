## The top-level tick orchestrator: ties every previously-standalone-tested
## resolver (MovementResolver, CombatResolver, VisionSystem, DetectionSystem,
## AuraSystem, BuildingRegenSystem, StatusEffectSystem, ProductionManager,
## UpkeepSystem, ResourceTick, ProductionOutputSystem, ProjectileSystem) into
## the two tick rates
## 07-data-architecture.md section 7/"Simulation Tick Rates" specifies:
## movement/combat every call (nominally 100ms/10-per-second, but — same
## "accumulator over dt" convention as everything else here — this class
## doesn't assume a fixed external cadence, the caller's dt drives it), and
## economy every 5 banked seconds. Before this class, every one of those
## systems was only ever driven directly from a test, one at a time; nothing
## wired them into one live per-tick loop.
##
## Stateless/static like every other resolver in sim/ — MatchState carries the
## one piece of state a tick genuinely needs across calls
## (economy_accumulator), the same "state on the instance, not the resolver"
## split SquadInstance.edge_progress/BuildingInstance.regen_progress already
## use.
class_name SimOrchestrator
extends RefCounted

## Economy tick cadence lives in sim/tuning.gd as Tuning.ECONOMY_TICK_SECONDS.

static func resolve_tick(state: MatchState, dt: float) -> void:
	state.tick += 1
	state.command_queue.drain_due(state, state.tick)
	var auras := AuraSystem.resolve_tick(state.squads, state.bases, state.troop_defs, state.building_defs, state.regiments)
	_resolve_fine_tick(state, dt, auras)

	state.economy_accumulator += dt
	while state.economy_accumulator >= Tuning.ECONOMY_TICK_SECONDS:
		_resolve_economy_tick(state, auras)
		state.economy_accumulator -= Tuning.ECONOMY_TICK_SECONDS

## Movement/combat/vision/detection/production — everything that advances
## every call regardless of the economy's coarser 5-second cadence.
static func _resolve_fine_tick(state: MatchState, dt: float, auras: Dictionary) -> void:
	DetectionSystem.resolve_tick(state.squads, state.bases, state.standalone_buildings, state.grid, state.troop_defs, state.building_defs, state.detections)
	VisionSystem.resolve_tick(state.squads, state.bases, state.standalone_buildings, state.grid, state.troop_defs, state.building_defs, state.visions, state.base_defs, state.vision_los_cache)

	# Attack-move chase decisions use a target snapshot from THIS tick's
	# starting positions (before movement below runs) — one step behind
	# CombatResolver's own post-move rebuild, the same small, accepted lag
	# every other cross-system read in this codebase tolerates (e.g. Auras
	# computed once and reused across both Movement and Combat this same
	# tick).
	var pre_move_targets := CombatResolver.build_targets(state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, auras, state.standalone_buildings)
	MovementResolver.resolve_attack_move(state.squads, state.troop_defs, state.grid, pre_move_targets, state.bases, state.standalone_buildings)
	MovementResolver.resolve_tick(dt, state.squads, state.grid, state.troop_defs, auras, state.bases, state.standalone_buildings)
	_resolve_regiment_movement(state, dt, auras)

	CombatResolver.resolve_tick(dt, state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, state.detections, auras, state.standalone_buildings, state.regiments, state.production_queues, state.projectiles, Callable(state, "next_projectile_id"), state.rng)
	ProjectileSystem.resolve_tick(dt, state.projectiles, state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, auras, state.standalone_buildings, state.regiments, state.production_queues, state.rng)

	_advance_production(state, dt)

## Regiment lock-step movement isn't driven by MovementResolver.resolve_tick()
## (which explicitly skips any squad whose order is "regiment_move") — each
## regiment's Commander/member squads must be resolved from ids and advanced
## via resolve_regiment_tick() instead, per MovementResolver's own Regiment
## section.
static func _resolve_regiment_movement(state: MatchState, dt: float, auras: Dictionary) -> void:
	for regiment in state.regiments:
		var commander_squad := state.find_squad(regiment.commander_id)
		if commander_squad == null:
			continue
		var member_squads: Array[SquadInstance] = []
		for squad_id in regiment.squad_ids:
			var member := state.find_squad(squad_id)
			if member != null:
				member_squads.append(member)
		MovementResolver.resolve_regiment_tick(dt, commander_squad, member_squads, state.grid, state.troop_defs, auras, state.bases, state.standalone_buildings)

## Advances and pumps every Production building's queue. A queue whose
## building can no longer be found (e.g. removed this tick — demolished, or a
## Wall/standalone deleted outright) is simply skipped for this tick rather
## than erased here; a base-attached building's queue is instead actively
## erased on ruin/capture by CombatResolver._prune_dead (called from
## _resolve_fine_tick, above), per 07-data-architecture.md 3b.
static func _advance_production(state: MatchState, dt: float) -> void:
	for building_id in state.production_queues.keys():
		var queue: ProductionQueue = state.production_queues[building_id]
		var found := state.find_base_building(building_id)
		if found.is_empty():
			continue
		var base: BaseInstance = found["base"]
		var building: BuildingInstance = found["building"]
		if building.is_ruin or (building.max_hp > 0.0 and building.current_hp <= 0.0):
			continue

		ProductionManager.advance(queue, dt)
		ProductionManager.pump(
			queue,
			base.owner_id,
			building.hex,
			building.building_type,
			state.squads,
			state.troops_by_id,
			state.bases_owned_by(base.owner_id),
			state.building_defs,
			state.troop_defs,
			state.commander_count(base.owner_id),
			Callable(state, "next_troop_id"),
			Callable(state, "next_squad_id"),
			state.grid,
		)

## Resources/upkeep/deficits — the 5-second cadence from
## 07-data-architecture.md section 7. `auras` is the same tick-start snapshot
## _resolve_fine_tick used — Mule's upkeep_reduction and resource_siphon's
## building redirect are the aura effects the economy side reads.
##
## The `neutral` owner (BaseSiteSelector.NEUTRAL_OWNER_ID — every not-yet-
## captured Unique base and its standing garrison) is skipped entirely: it has
## no economy at all rather than an isolated one, per 02-bases-and-buildings.md
## — its resource buildings produce nothing and its garrison pays no food/fuel
## upkeep, so a neutral garrison can never starve down before a player ever
## reaches it. This is deliberately NOT "give neutral its own ResourcePool
## fed by its own buildings" — that would still eventually starve a
## food-negative garrison with nothing but its own single seeded Farm to live
## on; skipping the tick outright avoids relying on that balance holding.
static func _resolve_economy_tick(state: MatchState, auras: Dictionary) -> void:
	var production := ProductionOutputSystem.compute_production(state.bases, state.base_defs, state.building_defs, auras)
	var upkeep := UpkeepSystem.compute_upkeep(state.squads, state.troop_defs, auras)

	var owner_ids: Dictionary = {}
	for base in state.bases:
		owner_ids[base.owner_id] = true
	for owner_id in production:
		owner_ids[owner_id] = true
	for owner_id in upkeep:
		owner_ids[owner_id] = true
	owner_ids.erase(BaseSiteSelector.NEUTRAL_OWNER_ID)

	for owner_id in owner_ids:
		var pool := state.pool_for(owner_id)
		var deficits := ResourceTick.apply(pool, production.get(owner_id, {}), upkeep.get(owner_id, {}))
		if not deficits.is_empty():
			UpkeepSystem.apply_deficit_deaths(owner_id, deficits, state.squads, state.troops_by_id, state.troop_defs)
