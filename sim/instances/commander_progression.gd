## Reads a Command Centre BuildingDef's `commanderProgression` block (see
## data/buildings/schema.json) to answer how many commanderSlots a Command
## Centre contributes at a given level — levels 1-3 come straight from
## `tierLevels`, level 4+ is `tierLevels`' last entry plus
## `postTierGrowth.commanderSlotsPerLevel` per level beyond that.
class_name CommanderProgression
extends RefCounted

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
