## Sources the per-tick building Food-upkeep dictionary ResourceTick.apply()
## expects — the building-level counterpart to UpkeepSystem's squad/troop
## upkeep. Buildings only ever draw Food (no Fuel), and — unlike a troop that
## can't be paid — a starved building never takes any HP/death consequence;
## that lives elsewhere, keyed off the same pool.is_deficit(FOOD) this
## system's total feeds into: ProductionOutputSystem.compute_production skips
## a starved Resource building's own output, ProductionManager.pump pauses a
## starved Production building's queue (pause_reason "food_deficit").
##
## A Resource building whose own output IS Food (Farm, Harbour) is simply
## never authored with foodUpkeep in data — not a rule enforced here — so it
## keeps producing through a Food deficit and the pool can always recover.
class_name BuildingUpkeepSystem
extends RefCounted

## Every player's per-tick building Food upkeep, keyed owner_id -> {FOOD:
## total} (the only key ever populated). A ruined building owes nothing —
## same current_hp <= 0.0 gate ProductionOutputSystem/VisionSystem/AuraSystem
## already use.
static func compute_upkeep(bases: Array[BaseInstance], building_defs: Dictionary) -> Dictionary:
	var upkeep: Dictionary = {}
	for base in bases:
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			var food := BuildingStats.food_upkeep(def, building_defs)
			if food <= 0.0:
				continue
			var owner_totals: Dictionary = upkeep.get(base.owner_id, {})
			owner_totals[ResourceType.Type.FOOD] = float(owner_totals.get(ResourceType.Type.FOOD, 0.0)) + food
			upkeep[base.owner_id] = owner_totals
	return upkeep
