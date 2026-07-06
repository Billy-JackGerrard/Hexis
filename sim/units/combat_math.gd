## Pure damage math for one attack, per 05-troop-stat-schema.md's Damage
## Modifiers / Damage Types / Armor rules. Stateless; reused by both troop
## squads and Defensive buildings (an "attacker" is just its stat dict plus the
## keys it presents on the receiving side).
##
## final = max(1, base * dealtMult * receivedMult - armor)
##   dealtMult    — product of the attacker's damageDealtModifiers whose key
##                  matches any of the target's match-keys (Domain/tags/reserved).
##   receivedMult — product of the target's damageReceivedModifiers whose key
##                  matches the attacker's Domain/tags/damageTypes, UNLESS the
##                  attacker's damageTypes include "Piercing" (armor-ignoring),
##                  which skips the target's received-side modifiers entirely.
##   armor        — flat, applied last; a hit always deals at least 1.
##
## Multiple matching keys within a dict multiply together (every authored
## modifier applies) rather than taking the single best — a deliberate choice,
## flagged in the plan for review.
class_name CombatMath
extends RefCounted

const PIERCING := "Piercing"

## Product of `modifiers` entries whose key appears in `keys`; 1.0 if none match.
static func _product_for_keys(modifiers: Dictionary, keys: Array[String]) -> float:
	var result := 1.0
	for key in keys:
		if modifiers.has(key):
			result *= float(modifiers[key])
	return result

static func dealt_multiplier(attacker_def: Dictionary, target: CombatTarget) -> float:
	return _product_for_keys(attacker_def.get("damageDealtModifiers", {}), target.match_keys)

## The keys an attacker presents to a target's damageReceivedModifiers: its
## Domain, its tags, and its damageTypes (all matched the same way per schema).
static func attacker_keys(attacker_def: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	if attacker_def.has("domain"):
		keys.append(String(attacker_def["domain"]))
	for tag in attacker_def.get("tags", []):
		keys.append(String(tag))
	for dt in attacker_def.get("damageTypes", []):
		keys.append(String(dt))
	return keys

static func received_multiplier(attacker_def: Dictionary, target: CombatTarget) -> float:
	if PIERCING in attacker_def.get("damageTypes", []):
		return 1.0
	return _product_for_keys(target.damage_received_modifiers, attacker_keys(attacker_def))

## Damage a single attack from `attacker_def` deals to `target`. `base_damage`
## is passed explicitly because a Defensive building's damage lives in its
## defensiveStats block, not at the def's top level like a troop's.
static func resolve_damage(attacker_def: Dictionary, base_damage: float, target: CombatTarget) -> float:
	var raw := base_damage * dealt_multiplier(attacker_def, target) * received_multiplier(attacker_def, target)
	return max(1.0, raw - target.armor)
