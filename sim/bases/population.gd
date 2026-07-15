## Population capacity/usage for one base (see 02-bases-and-buildings.md's
## "Population" section and 07-data-architecture.md section 5). Neither value
## is stored on BaseInstance — both are computed fresh from its buildings,
## same "derived, not stored" treatment as SquadCap.
class_name Population
extends RefCounted

## Evaluates a data/buildings/schema.json `growthRate` dict ({mode, value})
## against a base stat at level N (level 1 = base_value, no growth applied).
## Percent growth uses _int_pow, not pow() — see its doc comment: pow()'s
## rounding isn't guaranteed identical across platforms, which is exactly the
## kind of thing that silently desyncs a lockstepped sim.
static func _grown_stat(base_value: float, growth: Dictionary, level: int) -> float:
	if level <= 1 or growth.is_empty():
		return base_value
	var mode: String = growth.get("mode", "percent")
	var value: float = float(growth.get("value", 0.0))
	if mode == "flat":
		return base_value + value * (level - 1)
	return base_value * _int_pow(1.0 + value / 100.0, level - 1)

## Deterministic integer-exponent power (exponentiation by squaring) — only
## +/-/*// are guaranteed bit-identical across platforms under IEEE 754;
## pow() is not. `exponent` must be >= 0 (every growthRate caller's is).
static func _int_pow(base: float, exponent: int) -> float:
	var result := 1.0
	var b := base
	var e := exponent
	while e > 0:
		if e & 1 == 1:
			result *= b
		b *= b
		e >>= 1
	return result

## Building's populationCapacity output at a given level, per its def's
## nonProductionUpgrade.baseStats/statGrowth (used for both HQ and House).
static func _population_capacity(building_def: Dictionary, level: int) -> int:
	var upgrade: Dictionary = building_def.get("nonProductionUpgrade", {})
	var base_stats: Dictionary = upgrade.get("baseStats", {})
	var stat_growth: Dictionary = upgrade.get("statGrowth", {})
	var base_capacity: float = float(base_stats.get("populationCapacity", 0.0))
	var growth: Dictionary = stat_growth.get("populationCapacity", {})
	return int(round(_grown_stat(base_capacity, growth, level)))

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
