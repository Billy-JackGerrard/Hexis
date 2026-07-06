## Population capacity/usage for one base (see 02-bases-and-buildings.md's
## "Population" section and 07-data-architecture.md section 5). Neither value
## is stored on BaseInstance — both are computed fresh from its buildings,
## same "derived, not stored" treatment as SquadCap.
class_name Population
extends RefCounted

## Evaluates a data/buildings/schema.json `growthRate` dict ({mode, value})
## against a base stat at level N (level 1 = base_value, no growth applied).
static func _grown_stat(base_value: float, growth: Dictionary, level: int) -> float:
	if level <= 1 or growth.is_empty():
		return base_value
	var mode: String = growth.get("mode", "percent")
	var value: float = float(growth.get("value", 0.0))
	if mode == "flat":
		return base_value + value * (level - 1)
	return base_value * pow(1.0 + value / 100.0, level - 1)

## House's populationCapacity output at a given level, per house.json's
## nonProductionUpgrade.baseStats/statGrowth.
static func _house_capacity(house_def: Dictionary, level: int) -> int:
	var upgrade: Dictionary = house_def.get("nonProductionUpgrade", {})
	var base_stats: Dictionary = upgrade.get("baseStats", {})
	var stat_growth: Dictionary = upgrade.get("statGrowth", {})
	var base_capacity: float = float(base_stats.get("populationCapacity", 0.0))
	var growth: Dictionary = stat_growth.get("populationCapacity", {})
	return int(round(_grown_stat(base_capacity, growth, level)))

## populationCap = HQ's level-based contribution (+2/level, per hq.json) plus
## every House's populationCapacity output at its own level.
static func population_cap(base: BaseInstance, building_defs: Dictionary) -> int:
	var cap := base.hq_level * 2
	var house_def: Dictionary = building_defs.get("house", {})
	for house in base.buildings_of_type("house"):
		cap += _house_capacity(house_def, house.level)
	return cap

## populationUsed = count of placed buildings whose def populationCost (default
## 1) is > 0 — House/HQ are 0 and don't count; Walls (deferred, not modeled as
## BuildingInstance yet) are excluded by construction.
static func population_used(base: BaseInstance, building_defs: Dictionary) -> int:
	var used := 0
	for b in base.buildings:
		var def: Dictionary = building_defs.get(b.building_type, {})
		var cost: float = float(def.get("populationCost", 1))
		if cost > 0:
			used += 1
	return used

## House and HQ grant capacity rather than consume it, so they're always
## placeable regardless of how full the base already is.
static func has_capacity_for(base: BaseInstance, building_type: String, building_defs: Dictionary) -> bool:
	if building_type == "house" or building_type == "hq":
		return true
	return population_used(base, building_defs) < population_cap(base, building_defs)
