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
## per building before summing into the owner's total.
static func compute_production(bases: Array[BaseInstance], base_defs: Dictionary, building_defs: Dictionary) -> Dictionary:
	var production: Dictionary = {}
	for base in bases:
		var base_def: Dictionary = base_defs.get(base.base_def_id, {})
		var modifiers: Array = base_def.get("resourceModifiers", [])
		var owner_totals: Dictionary = production.get(base.owner_id, {})

		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			var output := BuildingStats.resource_output(def, building.level, building_defs)
			for type in output:
				var modded := ResourceModifier.apply(float(output[type]), building.building_type, modifiers)
				owner_totals[type] = float(owner_totals.get(type, 0.0)) + modded

		if not owner_totals.is_empty():
			production[base.owner_id] = owner_totals
	return production
