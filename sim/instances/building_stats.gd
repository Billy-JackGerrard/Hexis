## Derives a building's live combat stats from its BuildingDef (see
## data/buildings/schema.json), so BuildingInstance can carry a real max HP and
## the CombatResolver can read a Defensive building's attack stats. Pure/static,
## same split as SquadCap/CommanderProgression (data in the def, math here).
##
## Handles the three HP shapes the schema allows — productionUpgradeLevels rows
## (Production buildings), materialStats[material] blocks (multi-material Wall/
## Tower), and nonProductionUpgrade.baseStats.hp (everything else: defenses,
## Farm, HQ, House) — plus the shallow field-level `extends` inheritance Turret
## variants use, and the `growthRate` formula (percent compounds, flat adds).
class_name BuildingStats
extends RefCounted

## A def with its `extends` parent merged in: any of the inheritable blocks the
## child omits are taken from the parent, per schema.json's `extends` note
## (field-level, child wins wholesale — no array/dict merging). Non-inheriting
## defs (no `extends`) are returned unchanged.
static func resolve_def(def: Dictionary, building_defs: Dictionary) -> Dictionary:
	var parent_id: String = def.get("extends", "")
	if parent_id == "" or not building_defs.has(parent_id):
		return def
	var parent: Dictionary = resolve_def(building_defs[parent_id], building_defs)
	var merged: Dictionary = parent.duplicate(true)
	for key in def.keys():
		merged[key] = def[key]
	return merged

## Applies a schema `growthRate` block to a level-1 base value: percent
## compounds as base*(1+value/100)^(level-1), flat adds value*(level-1). A
## missing/empty growth block means no growth.
static func _apply_growth(base: float, growth: Dictionary, level: int) -> float:
	var value: float = float(growth.get("value", 0.0))
	if growth.get("mode", "flat") == "percent":
		return base * pow(1.0 + value / 100.0, level - 1)
	return base + value * (level - 1)

## Max HP for a building of this type/level/material. Returns 0.0 if the def
## carries no HP anywhere (e.g. an Infrastructure stub) — callers treat 0 as
## "not combat-tracked".
static func max_hp(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> float:
	var resolved := resolve_def(def, building_defs)

	var production_levels: Array = resolved.get("productionUpgradeLevels", [])
	if not production_levels.is_empty():
		var best_hp := 0.0
		for row in production_levels:
			if int(row.get("level", 0)) == level:
				return float(row.get("hp", 0.0))
			if int(row.get("level", 0)) <= level:
				best_hp = float(row.get("hp", best_hp))
		return best_hp

	var upgrade_model := _hp_model(resolved, material)
	if upgrade_model.is_empty():
		return 0.0
	var base_hp: float = float(upgrade_model.get("baseStats", {}).get("hp", 0.0))
	var growth: Dictionary = upgrade_model.get("statGrowth", {}).get("hp", {})
	return _apply_growth(base_hp, growth, level)

## The nonProductionUpgrade-shaped block that carries baseStats/statGrowth for
## HP — materialStats[material] for multi-material buildings, else the plain
## nonProductionUpgrade block.
static func _hp_model(resolved: Dictionary, material: String) -> Dictionary:
	var material_stats: Dictionary = resolved.get("materialStats", {})
	if not material_stats.is_empty():
		return material_stats.get(material, {})
	return resolved.get("nonProductionUpgrade", {})

## Resolved defensiveStats block (extends applied), or {} for a non-Defensive
## building. This is what the CombatResolver reads for a base defense's
## damage/attackSpeed/range/canTarget/etc.
static func defensive_stats(def: Dictionary, building_defs: Dictionary) -> Dictionary:
	return resolve_def(def, building_defs).get("defensiveStats", {})

## The damageReceivedModifiers that apply to this building instance — per
## material for multi-material buildings (e.g. Wood Wall's {Fire: 2.0}), else
## the def's top-level block. {} if none.
static func damage_received_modifiers(def: Dictionary, material: String, building_defs: Dictionary) -> Dictionary:
	var resolved := resolve_def(def, building_defs)
	var material_stats: Dictionary = resolved.get("materialStats", {})
	if not material_stats.is_empty():
		return material_stats.get(material, {}).get("damageReceivedModifiers", {})
	return resolved.get("damageReceivedModifiers", {})
