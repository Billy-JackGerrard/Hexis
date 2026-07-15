## Advances every in-flight ProjectileInstance one tick and resolves arrivals.
## Stateless/static, same split as every other resolver here (state lives on
## ProjectileInstance, rules live here) — called from SimOrchestrator right
## after CombatResolver.resolve_tick() each fine tick.
##
## Resolution rebuilds a FRESH CombatTarget snapshot (CombatResolver.
## build_targets) rather than reusing the tick-start snapshot the shot was
## fired against, so an impact always reacts to current reality: a target
## that moved off `aim_hex`, boarded a carrier, or died to something else
## entirely is correctly absent (a whiff/dodge); a base captured mid-flight
## is correctly no-longer-friendly-fireable (CombatTarget.owner_id derives
## from the base's live owner_id, not anything cached at fire time).
##
## Runs CombatResolver._prune_dead afterward, exactly like CombatResolver.
## resolve_tick does after its own (instant) damage step — a kill landing
## here is otherwise invisible to every _prune_dead side effect (squad/troop
## removal, ruin/HQ-capture, Wall deletion, regiment disband, production-queue
## erasure) for a full extra tick, since CombatResolver's own prune call this
## same tick already ran BEFORE this ballistic damage was applied.
class_name ProjectileSystem
extends RefCounted

static func resolve_tick(
	dt: float,
	projectiles: Array[ProjectileInstance],
	squads: Array[SquadInstance],
	bases: Array[BaseInstance],
	troops_by_id: Dictionary,
	grid: HexGrid,
	troop_defs: Dictionary,
	building_defs: Dictionary,
	auras: Dictionary = {},
	standalone_buildings: Array[BuildingInstance] = [],
	regiments: Array[RegimentInstance] = [],
	production_queues: Dictionary = {},
	rng: RandomNumberGenerator = null,
) -> void:
	if projectiles.is_empty():
		return
	var targets := CombatResolver.build_targets(squads, bases, troops_by_id, grid, troop_defs, building_defs, auras, standalone_buildings)
	var target_index := CombatResolver.build_target_index(targets)

	for i in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[i]
		if not projectile.beam_hexes.is_empty():
			if _advance_beam(projectile, dt, target_index, troops_by_id, troop_defs, building_defs, grid, rng):
				projectiles.remove_at(i)
			continue
		projectile.remaining_time -= dt
		if projectile.remaining_time > 0.0:
			continue
		_resolve_impact(projectile, target_index, troops_by_id, troop_defs, building_defs, grid, rng)
		projectiles.remove_at(i)

	CombatResolver._prune_dead(squads, bases, troops_by_id, grid, standalone_buildings, regiments, production_queues)

## Whoever's actually standing on `aim_hex` right now (first live enemy
## found) is treated as primary, regardless of whether it's the unit this
## shot was originally aimed at — ground truth at arrival is what matters,
## per ProjectileInstance's fixed-hex dodge design. An empty aim_hex (or only
## friendlies/the original target having relocated) is a total whiff: no
## primary damage, no statusEffectOnHit roll — but splash still checks for
## other enemies near the impact hex, so a target can also partially dodge by
## stepping just outside blast radius rather than fully out of range.
static func _resolve_impact(projectile: ProjectileInstance, target_index: Dictionary, troops_by_id: Dictionary, troop_defs: Dictionary, building_defs: Dictionary, grid: HexGrid, rng: RandomNumberGenerator = null) -> void:
	var primary: CombatTarget = null
	for candidate in target_index.get(projectile.aim_hex.to_key(), []):
		if candidate.owner_id == projectile.owner_id or not candidate.is_alive():
			continue
		primary = candidate
		break
	CombatResolver._resolve_hit_at(projectile.attacker_def, projectile.base_damage, projectile.owner_id, projectile.attacker_hex, projectile.aim_hex, primary, target_index, troops_by_id, projectile.splash_radius, troop_defs, building_defs, grid, rng)

## Sweeps a traveling line-attack (ProjectileInstance.beam_hexes — no unit
## combines lineAttack with projectileSpeed today, see combat_resolver.gd's
## _fire_or_apply) forward by `dt` and resolves every beam hex it has now
## physically reached: hex i in `beam_hexes` is i+1 hexes out from the firing
## attacker_hex (a straight hex line has no diagonal shortcuts, so distance
## and index move in lockstep), reached at (i+1)/projectileSpeed seconds
## after firing. Each hex is resolved via CombatResolver._resolve_beam_hex
## against CURRENT targets — same "ground truth at arrival" rule a point
## projectile's dodge already follows, just re-checked once per hex instead
## of once total, so a squad can dodge by moving off a not-yet-reached hex
## even after the beam has already swept past its old position. A blocking
## building stops the beam dead at that hex, same as the instant path.
## Returns true once the beam should be removed (finished its full length or
## got blocked), false if still traveling.
static func _advance_beam(projectile: ProjectileInstance, dt: float, target_index: Dictionary, troops_by_id: Dictionary, troop_defs: Dictionary, building_defs: Dictionary, grid: HexGrid, rng: RandomNumberGenerator = null) -> bool:
	projectile.beam_elapsed += dt
	var speed := float(projectile.attacker_def.get("projectileSpeed", 0.0))
	while projectile.beam_next_index < projectile.beam_hexes.size():
		var distance := projectile.beam_next_index + 1
		if projectile.beam_elapsed < float(distance) / speed:
			break
		var hex: HexCoord = projectile.beam_hexes[projectile.beam_next_index]
		projectile.beam_next_index += 1
		if CombatResolver._resolve_beam_hex(projectile.attacker_def, projectile.base_damage, projectile.owner_id, projectile.attacker_hex, hex, target_index, troops_by_id, troop_defs, building_defs, grid, rng):
			return true
	return projectile.beam_next_index >= projectile.beam_hexes.size()
