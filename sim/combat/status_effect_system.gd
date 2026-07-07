## Applies and ticks `statusEffectOnHit` conditions (05-troop-stat-schema.md's
## Status Effects section): freeze, stun, knockback, emp. Stateless/static,
## same split as CombatResolver/DetectionSystem — the timers themselves live
## on SquadInstance/BuildingInstance (lockout_remaining/move_lockout_remaining/
## stun_tail_remaining/stun_tail_queued), this file only writes and decrements
## them.
##
## Scoping choice: only ever applied to an attack's PRIMARY target, not splash
## victims — 04-combat.md doesn't say status effects propagate through splash,
## and doing so would let a single Cold Turret volley freeze an entire clumped
## army every hit.
class_name StatusEffectSystem
extends RefCounted

## stun's fixed trailing debuff, per schema: -30% move AND attack speed while
## stun_tail_remaining > 0. A global rule tied to the `stun` type itself, not a
## per-instance authored number.
const STUN_TAIL_SPEED_MULT := 0.7

## Rolls `effect`'s chance (default 100) and, on success, applies it to
## `target`. `target_def` is the resolved troop/building def the caller
## already has on hand (troop_defs/building_defs lookup) — used for emp's
## Domain branch and empImmune. No-op if `effect` is empty ({}: most attacks
## carry no statusEffectOnHit at all) or the roll fails.
static func apply_on_hit(effect: Dictionary, target: CombatTarget, target_def: Dictionary, attacker_hex: HexCoord, grid: HexGrid) -> void:
	if effect.is_empty():
		return
	if randf() * 100.0 >= float(effect.get("chance", 100)):
		return

	match String(effect.get("type", "")):
		"freeze":
			_set_lockout(target, float(effect.get("duration", 0.0)))
		"stun":
			var duration := float(effect.get("duration", 0.0))
			_set_lockout(target, duration)
			_queue_stun_tail(target, duration)
		"knockback":
			_apply_knockback(target, attacker_hex, int(effect.get("magnitude", 0)), grid)
		"emp":
			_apply_emp(target, target_def, float(effect.get("duration", 0.0)))

static func _set_lockout(target: CombatTarget, duration: float) -> void:
	if duration <= 0.0:
		return
	if target.kind == CombatTarget.Kind.SQUAD:
		target.squad.lockout_remaining = max(target.squad.lockout_remaining, duration)
	else:
		target.building.lockout_remaining = max(target.building.lockout_remaining, duration)

static func _queue_stun_tail(target: CombatTarget, lockout_duration: float) -> void:
	if lockout_duration <= 0.0:
		return
	if target.kind == CombatTarget.Kind.SQUAD:
		target.squad.stun_tail_queued = lockout_duration
	else:
		target.building.stun_tail_queued = lockout_duration

## Knockback only displaces squads — a building can't be shoved off its hex.
## Steps `magnitude` hexes straight away from the attacker (HexCoord.
## direction_away), clamping at the grid's edge; walls/terrain-blocking are
## deliberately not checked here — a "shove", not a path, per 05-troop-stat-
## schema.md ("magnitude is the number of hexes the target is shoved").
static func _apply_knockback(target: CombatTarget, attacker_hex: HexCoord, magnitude: int, grid: HexGrid) -> void:
	if target.kind != CombatTarget.Kind.SQUAD or magnitude <= 0 or grid == null:
		return
	var dir := HexCoord.direction_away(attacker_hex, target.squad.current_hex)
	var hex := target.squad.current_hex
	for i in range(magnitude):
		var next_hex := HexCoord.neighbor(hex, dir)
		if not grid.has_hex(next_hex):
			break
		hex = next_hex
	target.squad.current_hex = hex

## Domain-conditional per schema: Land -> movement-only lockout (can still
## attack); Air -> instant destroy; Infantry/Naval -> no effect. empImmune
## troops (Hot Air Balloon, Glider) are unaffected by either branch. Buildings
## have no Domain, so emp never affects one.
static func _apply_emp(target: CombatTarget, target_def: Dictionary, duration: float) -> void:
	if target.kind != CombatTarget.Kind.SQUAD:
		return
	if bool(target_def.get("empImmune", false)):
		return
	match String(target_def.get("domain", "")):
		"Land":
			target.squad.move_lockout_remaining = max(target.squad.move_lockout_remaining, duration)
		"Air":
			target.kill_squad()

## Decrements every live squad's/building's lockout/tail timers by `dt`.
## Arms stun_tail_remaining the instant lockout_remaining crosses from >0 to
## <=0 with a tail queued (a stun that's still mid-lockout never runs its tail
## concurrently — the tail only starts once the lockout itself is over).
static func resolve_tick(dt: float, squads: Array[SquadInstance], bases: Array[BaseInstance]) -> void:
	for squad in squads:
		_tick_one(squad, dt)
	for base in bases:
		for building in base.buildings:
			_tick_one(building, dt)

static func _tick_one(instance: Object, dt: float) -> void:
	if instance.lockout_remaining > 0.0:
		# Time left over once the lockout itself expires this same tick must
		# still count against the tail (the "elapsed time, not a raw fraction"
		# carry-over convention used everywhere else — e.g. MovementResolver's
		# edge_progress), rather than the tail's first tick silently costing 0.
		var overflow: float = dt - float(instance.lockout_remaining)
		instance.lockout_remaining = max(0.0, instance.lockout_remaining - dt)
		if instance.lockout_remaining <= 0.0 and instance.stun_tail_queued > 0.0:
			instance.stun_tail_remaining = instance.stun_tail_queued
			instance.stun_tail_queued = 0.0
			if overflow > 0.0:
				instance.stun_tail_remaining = max(0.0, instance.stun_tail_remaining - overflow)
	else:
		instance.stun_tail_remaining = max(0.0, instance.stun_tail_remaining - dt)
	if "move_lockout_remaining" in instance:
		instance.move_lockout_remaining = max(0.0, instance.move_lockout_remaining - dt)

## True while a freeze/stun full lockout is active — can't move or attack.
static func is_locked_out(instance: Object) -> bool:
	return instance.lockout_remaining > 0.0

## True while an emp Land-domain partial lockout is active — can't move, but
## CAN still attack. Squads only (buildings have no move_lockout_remaining).
static func is_move_locked(squad: SquadInstance) -> bool:
	return squad.move_lockout_remaining > 0.0

## Combined move-speed multiplier from stun's trailing debuff. 1.0 outside the
## tail window.
static func move_speed_mult(instance: Object) -> float:
	return STUN_TAIL_SPEED_MULT if instance.stun_tail_remaining > 0.0 else 1.0

## Combined attack-speed multiplier from stun's trailing debuff. 1.0 outside
## the tail window.
static func attack_speed_mult(instance: Object) -> float:
	return STUN_TAIL_SPEED_MULT if instance.stun_tail_remaining > 0.0 else 1.0
