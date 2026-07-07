## Picks which enemy an attacking squad fires on this tick, per 04-combat.md's
## target-priority rules. Stateless; operates on a pre-built list of enemy
## CombatTargets (the CombatResolver builds it once per tick).
##
## Priority for undirected (auto) targeting:
##   1. Only enemies in range that the attacker canTarget are candidates.
##   2. Tier A (enemy troops + Defensive buildings) is engaged before Tier B
##      (plain Structures) — Tier B is only considered when A is empty.
##   3. Within the chosen tier, prefer the target matching the attacker's
##      HIGHEST qualifying damageDealtModifiers entry (>1.0); distance is the
##      tie-break among equal multipliers (and among targets with none).
##
## A directed `attack_target` order overrides all of the above when its target
## is still a valid, in-range enemy; otherwise it's cleared and auto applies.
class_name CombatTargeting
extends RefCounted

## True if any of the attacker's canTarget entries matches a key the target
## presents (Domain/tag for a squad, "Structure"/"Defensive" for a building).
static func can_target(attacker_def: Dictionary, target: CombatTarget) -> bool:
	for key in attacker_def.get("canTarget", []):
		if String(key) in target.match_keys:
			return true
	return false

## Enemies that are alive, in range, legal to attack, and not hidden from
## `attacker_owner` (stealth/forest-ambush — DetectionSystem). `detections` is
## the owner_id -> {hex_key: true} map DetectionSystem.resolve_tick() produces;
## defaults to {} (no detector coverage) so existing callers keep compiling.
static func candidates(attacker_hex: HexCoord, attacker_owner: String, attacker_range: int, attacker_def: Dictionary, targets: Array[CombatTarget], detections: Dictionary = {}) -> Array[CombatTarget]:
	var result: Array[CombatTarget] = []
	for target in targets:
		if target.owner_id == attacker_owner or not target.is_alive():
			continue
		if target.distance_from(attacker_hex) > attacker_range:
			continue
		# Air-domain attackers ignore Walls entirely, same as every other
		# terrain rule (01-map-and-terrain.md) — a Wall target always has
		# hex_b set (it's the only thing that does).
		if target.hex_b != null and String(attacker_def.get("domain", "")) == "Air":
			continue
		if target.is_hidden and not _is_revealed_to(target, attacker_hex, attacker_owner, detections):
			continue
		if can_target(attacker_def, target):
			result.append(target)
	return result

## A hidden target is still seen if the attacker is within its reveal_range
## (proximity, no detector needed) or the attacker's owner has detector
## coverage on the target's hex.
static func _is_revealed_to(target: CombatTarget, attacker_hex: HexCoord, attacker_owner: String, detections: Dictionary) -> bool:
	if HexCoord.distance(attacker_hex, target.hex) <= target.reveal_range:
		return true
	return DetectionSystem.detected_hexes_for(detections, attacker_owner).has(target.hex.to_key())

## The attacker's highest damageDealtModifiers entry (>1.0) matching this
## target, or 1.0 if none qualify — the target-priority hint from 04-combat.md.
static func _priority_multiplier(attacker_def: Dictionary, target: CombatTarget) -> float:
	var best := 1.0
	var modifiers: Dictionary = attacker_def.get("damageDealtModifiers", {})
	for key in target.match_keys:
		if modifiers.has(key):
			var value := float(modifiers[key])
			if value > best:
				best = value
	return best

## Picks the best target from an already-tier-filtered candidate list: highest
## priority multiplier first, nearest as the tie-break.
static func _best_in_tier(attacker_hex: HexCoord, attacker_def: Dictionary, tier: Array[CombatTarget]) -> CombatTarget:
	var best: CombatTarget = null
	var best_mult := -1.0
	var best_dist := 1 << 30
	for target in tier:
		var mult := _priority_multiplier(attacker_def, target)
		var dist := target.distance_from(attacker_hex)
		if mult > best_mult or (mult == best_mult and dist < best_dist):
			best = target
			best_mult = mult
			best_dist = dist
	return best

## Auto tier/priority selection from a given position — the shared core used by
## both squads (after order handling) and Defensive buildings (which have no
## orders). Returns null if nothing is engageable.
static func select_auto(attacker_hex: HexCoord, attacker_owner: String, attacker_range: int, attacker_def: Dictionary, targets: Array[CombatTarget], detections: Dictionary = {}) -> CombatTarget:
	var in_range := candidates(attacker_hex, attacker_owner, attacker_range, attacker_def, targets, detections)
	if in_range.is_empty():
		return null

	var tier_a: Array[CombatTarget] = []
	var tier_b: Array[CombatTarget] = []
	for target in in_range:
		if target.is_tier_a:
			tier_a.append(target)
		else:
			tier_b.append(target)
	var chosen_tier := tier_a if not tier_a.is_empty() else tier_b
	return _best_in_tier(attacker_hex, attacker_def, chosen_tier)

## Resolves an attacking squad's target for this tick. Honours a directed
## `attack_target` order when still valid (clearing it when the target is dead),
## then falls back to auto tier/priority selection. Returns null if nothing is
## engageable.
static func select_target(attacker_squad: SquadInstance, attacker_def: Dictionary, targets: Array[CombatTarget], detections: Dictionary = {}) -> CombatTarget:
	var attacker_range := int(attacker_def.get("range", 0))

	var order: Dictionary = attacker_squad.order
	if order.get("type", "") == "attack_target":
		var directed_id: String = order.get("targetId", "")
		var in_range := candidates(attacker_squad.current_hex, attacker_squad.owner_id, attacker_range, attacker_def, targets, detections)
		for target in in_range:
			if target.target_id() == directed_id:
				return target
		# Directed target dead / out of range / illegal: drop the order only
		# once it's actually gone (an out-of-range-but-living target keeps the
		# order — movement toward it is the movement system's job, deferred),
		# then fall through to auto-targeting.
		if not _target_alive_anywhere(directed_id, targets):
			attacker_squad.order = {}

	return select_auto(attacker_squad.current_hex, attacker_squad.owner_id, attacker_range, attacker_def, targets, detections)

static func _target_alive_anywhere(target_id: String, targets: Array[CombatTarget]) -> bool:
	for target in targets:
		if target.target_id() == target_id:
			return target.is_alive()
	return false
