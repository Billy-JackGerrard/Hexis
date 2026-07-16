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
##
## The percent branch uses _int_pow rather than Godot's pow() — the exponent
## is always a non-negative int (level-1), and pow()'s libm implementation is
## not required to be bit-identical across platforms/architectures (unlike
## +-*/), so two lockstepped peers computing the same cost/stat on different
## machines could round a ULP apart and silently disagree on something like
## upgrade affordability, applying the same command on one peer but not the
## other — a real desync this project hit (HQ upgrades, cross-machine LAN).
static func apply_growth(base: float, growth: Dictionary, level: int) -> float:
	var value: float = float(growth.get("value", 0.0))
	if growth.get("mode", "flat") == "percent":
		return base * _int_pow(1.0 + value / 100.0, level - 1)
	return base + value * (level - 1)

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
	return apply_growth(base_hp, growth, level)

## The nonProductionUpgrade-shaped block that carries baseStats/statGrowth for
## HP — materialStats[material] for multi-material buildings, else the plain
## nonProductionUpgrade block.
static func _hp_model(resolved: Dictionary, material: String) -> Dictionary:
	var material_stats: Dictionary = resolved.get("materialStats", {})
	if not material_stats.is_empty():
		return material_stats.get(material, {})
	return resolved.get("nonProductionUpgrade", {})

## Resolved defensiveStats block (extends applied), merged with the
## level/material-scaled attack stats for a multi-material Defensive building
## (Tower — see data/buildings/schema.json's materialStats.canTarget note:
## "each material restates its own full canTarget/damageTypes/splashRadius...
## the building-level defensiveStats block still holds the traits that are
## truly invariant across materials (detector, detectionRange)"). For a
## single-block Defensive building (Turret variants, Missile Launcher,
## Landmine) `materialStats` is empty and this is just the plain top-level
## defensiveStats, unleveled, same as before. This is what CombatResolver
## reads for a base defense's damage/attackSpeed/range/canTarget/etc.
static func defensive_stats(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> Dictionary:
	var resolved := resolve_def(def, building_defs)
	var stats: Dictionary = resolved.get("defensiveStats", {}).duplicate()

	var material_stats: Dictionary = resolved.get("materialStats", {})
	if not material_stats.is_empty():
		var block: Dictionary = material_stats.get(material, {})
		var base: Dictionary = block.get("baseStats", {})
		var growth: Dictionary = block.get("statGrowth", {})
		for key in ["damage", "attackSpeed", "range"]:
			if base.has(key):
				stats[key] = apply_growth(float(base[key]), growth.get(key, {}), level)
		for key in ["canTarget", "damageTypes", "splashRadius"]:
			if block.has(key):
				stats[key] = block[key]

	return stats

## Number of independently-targeting turrets this Defensive building fires
## with at `level` — Wood Tower only (materialStats[material].addsTurretPerLevel
## true), per 06-building-stats-and-defenses.md: "each upgrade level adds an
## additional turret" instead of pure stat scaling, so level N fires N volleys
## a tick, each free to pick its own target (see CombatResolver._advance_
## building's exclude_ids handling). Every other Defensive building — a single
## defensiveStats block, or a Tower material without the flag (Stone/Steel) —
## always fires with exactly 1.
static func turret_count(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> int:
	var resolved := resolve_def(def, building_defs)
	var material_stats: Dictionary = resolved.get("materialStats", {})
	if bool(material_stats.get(material, {}).get("addsTurretPerLevel", false)):
		return max(level, 1)
	return 1

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
		return apply_growth(base_vision, growth, level)

	return float(resolved.get("defensiveStats", {}).get("visionRange", 0.0))

## How many squads this building can hold as docked cargo at `level` (0.0 if
## the resolved block carries no cargoCapacity anywhere — everything but
## Hangar today). Same lookup/growth shape as vision_range: a leveled
## nonProductionUpgrade.baseStats.cargoCapacity entry, since capacity is
## authored as a named growable stat there rather than a dedicated schema
## field (see data/buildings/schema.json's cargoAllowedTags note).
static func cargo_capacity(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> float:
	var resolved := resolve_def(def, building_defs)
	var upgrade_model := _hp_model(resolved, material)
	if not upgrade_model.get("baseStats", {}).has("cargoCapacity"):
		return 0.0
	var base_capacity: float = float(upgrade_model.get("baseStats", {}).get("cargoCapacity", 0.0))
	var growth: Dictionary = upgrade_model.get("statGrowth", {}).get("cargoCapacity", {})
	return apply_growth(base_capacity, growth, level)

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
	return apply_growth(base_bonus, growth, level)

## Flat per-hit damage reduction this building/material grants at `level`
## (0.0 if the resolved block carries no armor entry) — data/buildings/
## schema.json's materialStats/nonProductionUpgrade baseStats.armor, e.g.
## Steel Tower/Steel Wall. Same lookup shape as max_hp/vision_range
## (materialStats[material] first, else the plain nonProductionUpgrade
## block), so it grows with level the same way HP does if a material ever
## authors non-flat statGrowth for it.
static func armor(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> float:
	var resolved := resolve_def(def, building_defs)
	var upgrade_model := _hp_model(resolved, material)
	if not upgrade_model.get("baseStats", {}).has("armor"):
		return 0.0
	var base_armor: float = float(upgrade_model.get("baseStats", {}).get("armor", 0.0))
	var growth: Dictionary = upgrade_model.get("statGrowth", {}).get("armor", {})
	return apply_growth(base_armor, growth, level)

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

## Domains/tags this building is allowed to store as docked cargo (Hangar
## only today) — same resolve_def-safe top-level lookup as detector()/
## stealth(). Capacity itself is cargo_capacity() above, not this.
static func cargo_allowed_tags(def: Dictionary, building_defs: Dictionary) -> Array:
	return resolve_def(def, building_defs).get("cargoAllowedTags", [])

## Whether docked cargo can launch out of this building mid-combat, building-
## level equivalent of troop.schema.json's canLaunchCargoMidCombat for a
## squad-carrier.
static func can_launch_cargo_mid_combat(def: Dictionary, building_defs: Dictionary) -> bool:
	return bool(resolve_def(def, building_defs).get("canLaunchCargoMidCombat", false))

## This building's aura list (Hospital, Ice Spire — Support-category), with any
## leveled magnitude override applied. Radius/target/filter/effect are used
## as-authored; only `magnitude` can scale with level, and only when the def's
## nonProductionUpgrade carries a matching baseStats key (currently just
## Hospital's healMagnitude — its aura radius stays flat per level while the
## heal amount grows, see data/buildings/healing_spire.json's notes). Ice Spire's
## slow magnitude has no such growth entry, so it's used unleveled.
static func auras(def: Dictionary, level: int, building_defs: Dictionary) -> Array:
	var resolved := resolve_def(def, building_defs)
	var upgrade: Dictionary = resolved.get("nonProductionUpgrade", {})
	var base_stats: Dictionary = upgrade.get("baseStats", {})
	var result: Array = []
	for aura in resolved.get("auras", []):
		var entry: Dictionary = (aura as Dictionary).duplicate()
		var magnitude_key := _aura_magnitude_key(String(entry.get("effect", "")))
		if magnitude_key != "" and base_stats.has(magnitude_key):
			var growth: Dictionary = upgrade.get("statGrowth", {}).get(magnitude_key, {})
			entry["magnitude"] = apply_growth(float(base_stats[magnitude_key]), growth, level)
		result.append(entry)
	return result

## Which nonProductionUpgrade.baseStats key (if any) carries this aura
## effect's leveled magnitude, mirroring how hp/visionRange are named.
static func _aura_magnitude_key(effect: String) -> String:
	if effect == "heal_over_time" or effect == "heal_out_of_combat":
		return "healMagnitude"
	return ""

## Level-1 build cost (data/*.json's raw {"stone": 40, ...} shape — not yet
## converted to ResourceType.Type, see ResourceType.dict_from_named) for this
## building/material — the basis for both a fresh placement's
## total_resources_spent and a ruin-rebuild's cost (a percentage of this, see
## rebuild_cost_percent). Checked in the same three-shape dispatch as
## _hp_model, plus Command Centre's commanderProgression (its own build cost
## lives in tierLevels, not nonProductionUpgrade — see data/buildings/schema.json).
static func base_cost(def: Dictionary, material: String, building_defs: Dictionary) -> Dictionary:
	var resolved := resolve_def(def, building_defs)

	for row in resolved.get("productionUpgradeLevels", []):
		if int(row.get("level", 0)) == 1:
			return row.get("cost", {})

	var commander_progression: Dictionary = resolved.get("commanderProgression", {})
	if not commander_progression.is_empty():
		for row in commander_progression.get("tierLevels", []):
			if int(row.get("level", 0)) == 1:
				return row.get("cost", {})

	return _hp_model(resolved, material).get("baseCost", {})

## This building's max level, or 0 for uncapped (bottlenecked only by the
## HQ ceiling elsewhere — see CommandProcessor.upgrade_building). Only
## Production-category buildings have a real cap, derived as
## length(productionUpgradeLevels) per schema.json's note that this is the
## sole source of truth for a Production building's level range — Command
## Centre is the documented exception (commanderProgression keeps growing
## past its tierLevels via postTierGrowth, so it stays uncapped like every
## other non-production building).
static func max_level(def: Dictionary, building_defs: Dictionary) -> int:
	var resolved := resolve_def(def, building_defs)
	var production_levels: Array = resolved.get("productionUpgradeLevels", [])
	if not production_levels.is_empty():
		return production_levels.size()
	return 0

## Resource cost to upgrade a building from `level` to `level + 1`, in the
## def's raw named-key shape (like base_cost()). Checked in the same
## three-shape dispatch as base_cost: an explicit productionUpgradeLevels row
## (cost to reach that row's level), Command Centre's commanderProgression
## (explicit tierLevels rows for 1-3, then postTierGrowth.costGrowth
## compounding off the last explicit row for level 4+), else the generic
## upgradeBaseCost * (1+upgradeCostGrowth)^(level-1) formula every other
## building uses (same shape as apply_growth's stat growth, since
## upgradeCostGrowth is itself a growthRate block) — upgradeBaseCost is its
## own field, independent of baseCost (the build/rebuild cost).
static func upgrade_cost(def: Dictionary, level: int, material: String, building_defs: Dictionary) -> Dictionary:
	var resolved := resolve_def(def, building_defs)
	var target_level := level + 1

	for row in resolved.get("productionUpgradeLevels", []):
		if int(row.get("level", 0)) == target_level:
			return row.get("cost", {})

	var commander_progression: Dictionary = resolved.get("commanderProgression", {})
	if not commander_progression.is_empty():
		var tier_levels: Array = commander_progression.get("tierLevels", [])
		for row in tier_levels:
			if int(row.get("level", 0)) == target_level:
				return row.get("cost", {})
		var last_row: Dictionary = tier_levels[tier_levels.size() - 1]
		var last_level := int(last_row.get("level", 1))
		var growth: Dictionary = commander_progression.get("postTierGrowth", {}).get("costGrowth", {})
		var cost: Dictionary = {}
		for key in last_row.get("cost", {}):
			cost[key] = apply_growth(float(last_row["cost"][key]), growth, target_level - last_level + 1)
		return cost

	var upgrade_model := _hp_model(resolved, material)
	var upgrade_base_cost: Dictionary = upgrade_model.get("upgradeBaseCost", {})
	var growth: Dictionary = upgrade_model.get("upgradeCostGrowth", {})
	var cost: Dictionary = {}
	for key in upgrade_base_cost:
		cost[key] = apply_growth(float(upgrade_base_cost[key]), growth, target_level)
	return cost

## Percent of base_cost() a ruined (non-HQ, non-Wall, non-standalone) building
## costs to rebuild at level 1, per 06-building-stats-and-defenses.md — the
## def's own `rebuildCost` field (default 50, i.e. 50%). Distinct from
## demolish_building's flat, hardcoded 50% refund (02-bases-and-buildings.md:
## "This is a flat 50%, unlike the combat-destruction ruin-rebuild cost
## model... which is a cost to rebuild, not a refund").
static func rebuild_cost_percent(def: Dictionary, building_defs: Dictionary) -> float:
	return float(resolve_def(def, building_defs).get("rebuildCost", 50))

## data/buildings/*.json output-field name -> ResourceType.Type, for every
## Resource-category building (Farm/Harbour/Quarry/Mine/StoneWorks/Oil Rig/
## Lumber Mill) — none of which are multi-material, so these always live under
## nonProductionUpgrade, unlike max_hp/vision_range's materialStats branch.
const _OUTPUT_KEYS := {
	"foodOutput": ResourceType.Type.FOOD,
	"stoneOutput": ResourceType.Type.STONE,
	"steelOutput": ResourceType.Type.STEEL,
	"woodOutput": ResourceType.Type.WOOD,
	"fuelOutput": ResourceType.Type.FUEL,
}

## This Resource building's per-tick output at `level`, as a ResourceType.Type
## -> float dict (already leveled via statGrowth, per-resource) — {} for any
## building with no output field at all (every non-Resource building).
## Consumed by ProductionOutputSystem, which then applies BaseDef's
## resourceModifiers (Capital's Oil Rig penalty, Foundry Reach's Steel bonus,
## etc.) on top.
static func resource_output(def: Dictionary, level: int, building_defs: Dictionary) -> Dictionary:
	var resolved := resolve_def(def, building_defs)
	var upgrade: Dictionary = resolved.get("nonProductionUpgrade", {})
	var base_stats: Dictionary = upgrade.get("baseStats", {})
	var result: Dictionary = {}
	for key in _OUTPUT_KEYS:
		if base_stats.has(key):
			var growth: Dictionary = upgrade.get("statGrowth", {}).get(key, {})
			result[_OUTPUT_KEYS[key]] = apply_growth(float(base_stats[key]), growth, level)
	return result
