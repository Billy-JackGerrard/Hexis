## Reads a Command Centre BuildingDef's `commanderProgression` block (see
## data/buildings/schema.json) to answer how many commanderSlots a Command
## Centre contributes at a given level — levels 1-3 come straight from
## `tierLevels`, level 4+ is `tierLevels`' last entry plus
## `postTierGrowth.commanderSlotsPerLevel` per level beyond that.
class_name CommanderProgression
extends RefCounted

const TIER_ORDER := ["common", "rare", "epic"]

## Highest commanderTier unlocked at `level` — tierLevels are cumulative
## (level 1 unlocks common, level 2 additionally unlocks rare, level 3
## additionally unlocks epic; level 4+ keeps epic, postTierGrowth only adds
## slots/hp/cost, never a new tier). "" if level is below tierLevels' first
## entry.
static func unlocked_tier_at_level(progression: Dictionary, level: int) -> String:
	var tier_levels: Array = progression.get("tierLevels", [])
	var best_level := -1
	var best_tier := ""
	for entry in tier_levels:
		var entry_level := int(entry.get("level"))
		if entry_level <= level and entry_level > best_level:
			best_level = entry_level
			best_tier = String(entry.get("unlocksTier", ""))
	return best_tier

## True if `tier` (common/rare/epic) is unlocked at `level` — i.e. it's at or
## below the highest tier unlocked at that level, per TIER_ORDER.
static func tier_unlocked(progression: Dictionary, level: int, tier: String) -> bool:
	var unlocked_index := TIER_ORDER.find(unlocked_tier_at_level(progression, level))
	var tier_index := TIER_ORDER.find(tier)
	if unlocked_index == -1 or tier_index == -1:
		return false
	return tier_index <= unlocked_index

static func slots_at_level(progression: Dictionary, level: int) -> int:
	var tier_levels: Array = progression.get("tierLevels", [])
	var post_growth: Dictionary = progression.get("postTierGrowth", {})
	var per_level: int = int(post_growth.get("commanderSlotsPerLevel", 1))

	var max_tier_level := 0
	var max_tier_slots := 0
	for entry in tier_levels:
		var entry_level := int(entry.get("level"))
		if entry_level == level:
			return int(entry.get("commanderSlots"))
		if entry_level > max_tier_level:
			max_tier_level = entry_level
			max_tier_slots = int(entry.get("commanderSlots"))

	return max_tier_slots + per_level * (level - max_tier_level)
