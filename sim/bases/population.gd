## Population capacity/usage for one base (see 02-bases-and-buildings.md's
## "Population" section and 07-data-architecture.md section 5). Neither value
## is stored on BaseInstance — both are computed fresh from its buildings,
## same "derived, not stored" treatment as SquadCap.
class_name Population
extends RefCounted

## Building's populationCapacity output at a given level, per its def's
## nonProductionUpgrade.baseStats/statGrowth (used for both HQ and House).
## Growth math (BuildingStats.apply_growth) is shared with every other leveled
## building stat — same deterministic _int_pow rather than pow(), see that
## method's doc comment for why (pow()'s rounding isn't guaranteed identical
## across platforms, which is exactly the kind of thing that silently desyncs
## a lockstepped sim — this project hit that once already).
static func _population_capacity(building_def: Dictionary, level: int) -> int:
	var upgrade: Dictionary = building_def.get("nonProductionUpgrade", {})
	var base_stats: Dictionary = upgrade.get("baseStats", {})
	var stat_growth: Dictionary = upgrade.get("statGrowth", {})
	var base_capacity: float = float(base_stats.get("populationCapacity", 0.0))
	var growth: Dictionary = stat_growth.get("populationCapacity", {})
	return int(round(BuildingStats.apply_growth(base_capacity, growth, level)))

## populationCap = HQ's populationCapacity output at its own level (per
## hq.json) plus every House's populationCapacity output at its own level.
static func population_cap(base: BaseInstance, building_defs: Dictionary) -> int:
	var hq_def: Dictionary = building_defs.get("hq", {})
	var cap := _population_capacity(hq_def, base.hq_level)
	var house_def: Dictionary = building_defs.get("house", {})
	for house in base.buildings_of_type("house"):
		if house.max_hp > 0.0 and house.current_hp <= 0.0:
			continue
		cap += _population_capacity(house_def, house.level)
	return cap

## populationUsed = count of placed buildings whose def populationCost (default
## 1) is > 0 — House/HQ are 0 and don't count; Walls are also 0
## (wall.json's populationCost: 0), so they're naturally excluded too, per
## 02-bases-and-buildings.md ("Walls don't consume population").
static func population_used(base: BaseInstance, building_defs: Dictionary) -> int:
	var used := 0
	for b in base.buildings:
		if b.max_hp > 0.0 and b.current_hp <= 0.0:
			continue
		var def: Dictionary = building_defs.get(b.building_type, {})
		var cost: float = float(def.get("populationCost", 1))
		if cost > 0:
			used += 1
	return used

## House and HQ grant capacity rather than consume it, and any building whose
## populationCost is 0 (Walls) doesn't consume population — all are placeable
## regardless of how full the base already is.
static func has_capacity_for(base: BaseInstance, building_type: String, building_defs: Dictionary) -> bool:
	if building_type == "house" or building_type == "hq":
		return true
	var def: Dictionary = building_defs.get(building_type, {})
	if float(def.get("populationCost", 1)) <= 0.0:
		return true
	return population_used(base, building_defs) < population_cap(base, building_defs)
