## Sources the per-tick production dictionary ResourceTick.apply() expects —
## the counterpart UpkeepSystem already is for the consumption side, per
## 07-data-architecture.md section 7 ("Sum production from all owned bases'
## resource buildings... at their current level"). Previously nothing read a
## Resource-category building's foodOutput/stoneOutput/etc. into the economy
## tick at all — production was authored data with no consumer.
class_name ProductionOutputSystem
extends RefCounted

## Every player's per-tick production, keyed owner_id -> {ResourceType.Type:
## total}. A ruined (0 HP) building produces nothing — same current_hp <= 0.0
## gate every other per-building system (Vision/Detection/Aura) already uses.
## `base_defs` supplies each base's resourceModifiers (Capital's Oil Rig
## penalty, Foundry Reach's Steel bonus, etc. — see ResourceModifier), applied
## per building before summing into the owner's total. `auras` (AuraSystem.
## resolve_tick's output, default {} for callers that don't care) redirects a
## resource_siphon-sieged building's entire output to the siphoning owner
## instead of its own base's owner — see AuraSystem.siphoned_by — so totals
## are accumulated per building's own recipient, not once per base.
static func compute_production(bases: Array[BaseInstance], base_defs: Dictionary, building_defs: Dictionary, auras: Dictionary = {}) -> Dictionary:
	var production: Dictionary = {}
	for base in bases:
		var base_def: Dictionary = base_defs.get(base.base_def_id, {})
		var modifiers: Array = base_def.get("resourceModifiers", [])

		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			var output := BuildingStats.resource_output(def, building.level, building_defs)
			if output.is_empty():
				continue
			var siphon_owner := AuraSystem.siphoned_by(auras, building.id)
			var recipient_id := siphon_owner if siphon_owner != "" else base.owner_id
			var recipient_totals: Dictionary = production.get(recipient_id, {})
			for type in output:
				var modded := ResourceModifier.apply(float(output[type]), building.building_type, modifiers)
				recipient_totals[type] = float(recipient_totals.get(type, 0.0)) + modded
			production[recipient_id] = recipient_totals
	return production
