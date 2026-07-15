## Headline stat lines for a building def's detail pop-down — shared by
## BuildingPanel's BUILD menu and SquadPanel's Engineer BUILD menu, both of
## which show a rough stat preview once a building type row is expanded.
class_name BuildingDetailView
extends RefCounted

## A handful of headline stats for the detail pop-down — whichever of these
## the def's baseStats block has, in this fixed order. Buildings without a
## single-material baseStats block (Wall's per-material materialStats) fall
## back to the first material's stats, since the pop-down shows one Build
## button per material anyway and this is just a rough preview.
static func stat_lines(def: Dictionary) -> Array[String]:
	var stats: Dictionary = {}
	var non_prod: Dictionary = def.get("nonProductionUpgrade", {})
	var production_levels: Array = def.get("productionUpgradeLevels", [])
	var material_stats: Dictionary = def.get("materialStats", {})
	if not non_prod.is_empty():
		stats = non_prod.get("baseStats", {})
	elif not production_levels.is_empty():
		stats = {"hp": production_levels[0].get("hp", 0)}
	elif not material_stats.is_empty():
		stats = (material_stats.values()[0] as Dictionary).get("baseStats", {})

	var lines: Array[String] = []
	for key in ["hp", "damage", "range", "attackSpeed", "armor"]:
		if stats.has(key):
			lines.append("%s: %s" % [key.capitalize(), str(stats[key])])
	return lines

## Same headline stats as stat_lines(), but for one specific material of a
## Wall-style building — used per material row in the BUILD pop-down instead
## of the single first-material preview stat_lines() falls back to.
static func stat_lines_for_material(def: Dictionary, material: String) -> Array[String]:
	var material_stats: Dictionary = def.get("materialStats", {})
	var stats: Dictionary = (material_stats.get(material, {}) as Dictionary).get("baseStats", {})
	var lines: Array[String] = []
	for key in ["hp", "damage", "range", "attackSpeed", "armor"]:
		if stats.has(key):
			lines.append("%s: %s" % [key.capitalize(), str(stats[key])])
	return lines
