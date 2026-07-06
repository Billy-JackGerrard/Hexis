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

## Vision range for a building of this type/level/material, or 0.0 if it
## carries no visionRange anywhere (most Production/Resource buildings don't
## emit vision on their own). Checked in the same shape as max_hp: multi-
## material blocks first (Tower — visionRange grows per statGrowth), then a
## plain nonProductionUpgrade block (Radar Array — also grows), then a flat
## defensiveStats.visionRange (Turret variants/Missile Launcher/Landmine —
## these have no growth entry today, matching how CombatResolver already
## reads their damage/range un-leveled straight off defensiveStats).
static func vision_range(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> float:
	var resolved := resolve_def(def, building_defs)

	var upgrade_model := _hp_model(resolved, material)
	if not upgrade_model.is_empty() and upgrade_model.get("baseStats", {}).has("visionRange"):
		var base_vision: float = float(upgrade_model.get("baseStats", {}).get("visionRange", 0.0))
		var growth: Dictionary = upgrade_model.get("statGrowth", {}).get("visionRange", {})
		return _apply_growth(base_vision, growth, level)

	return float(resolved.get("defensiveStats", {}).get("visionRange", 0.0))

## Flat, map-wide vision-range bonus this building grants its owner (only
## Radar Array uses this today — 02-bases-and-buildings.md), applied on top of
## every one of the owner's vision sources, not just this building's own tile.
## Grows with level the same way HP/other nonProductionUpgrade stats do.
static func global_vision_bonus(def: Dictionary, level: int, building_defs: Dictionary) -> float:
	var resolved := resolve_def(def, building_defs)
	var upgrade: Dictionary = resolved.get("nonProductionUpgrade", {})
	if not upgrade.get("baseStats", {}).has("globalVisionRangeBonus"):
		return 0.0
	var base_bonus: float = float(upgrade.get("baseStats", {}).get("globalVisionRangeBonus", 0.0))
	var growth: Dictionary = upgrade.get("statGrowth", {}).get("globalVisionRangeBonus", {})
	return _apply_growth(base_bonus, growth, level)

## The damageReceivedModifiers that apply to this building instance — per
## material for multi-material buildings (e.g. Wood Wall's {Fire: 2.0}), else
## the def's top-level block. {} if none.
static func damage_received_modifiers(def: Dictionary, material: String, building_defs: Dictionary) -> Dictionary:
	var resolved := resolve_def(def, building_defs)
	var material_stats: Dictionary = resolved.get("materialStats", {})
	if not material_stats.is_empty():
		return material_stats.get(material, {}).get("damageReceivedModifiers", {})
	return resolved.get("damageReceivedModifiers", {})

## Whether this building detects stealthed units (05/07 schema's `detector`).
## Unlike vision/HP, Tower's detector/detectionRange live directly under
## defensiveStats (not per-material) — so only two shapes exist here: a
## Defensive building's defensiveStats.detector (Tower), or a top-level
## detector (Radar Array).
static func detector(def: Dictionary, building_defs: Dictionary) -> bool:
	var resolved := resolve_def(def, building_defs)
	if bool(resolved.get("defensiveStats", {}).get("detector", false)):
		return true
	return bool(resolved.get("detector", false))

## Radius within which this building's detector reveals stealthed units.
## Falls back to vision_range() when detectionRange is omitted, per schema.
static func detection_range(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> float:
	var resolved := resolve_def(def, building_defs)
	var defensive: Dictionary = resolved.get("defensiveStats", {})
	if defensive.has("detectionRange"):
		return float(defensive["detectionRange"])
	if resolved.has("detectionRange"):
		return float(resolved["detectionRange"])
	return vision_range(def, level, material, building_defs)

## Whether this building itself is stealthed (e.g. Landmine) — always a
## top-level field, even for Defensive-category buildings.
static func stealth(def: Dictionary, building_defs: Dictionary) -> bool:
	return bool(resolve_def(def, building_defs).get("stealth", false))

## Range within which an enemy sees this building despite its stealth, without
## needing a detector.
static func reveal_range(def: Dictionary, building_defs: Dictionary) -> float:
	return float(resolve_def(def, building_defs).get("revealRange", 0.0))
