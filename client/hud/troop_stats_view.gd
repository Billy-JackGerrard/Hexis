## Shared "domain + tags, headline combat stats, notes description" block for
## a troop def — used by SquadPanel (a squad selected on the map) and
## TroopInfoPanel (a troop clicked in a building's TRAIN menu) so both read
## from one place instead of duplicating the field list.
class_name TroopStatsView
extends RefCounted

static func build(content: VBoxContainer, def: Dictionary) -> void:
	var type_bits: Array[String] = []
	var domain := String(def.get("domain", ""))
	if domain != "":
		type_bits.append(domain)
	for tag in def.get("tags", []):
		type_bits.append(String(tag))
	if not type_bits.is_empty():
		content.add_child(UITheme.muted_label(", ".join(type_bits)))

	for key in ["damage", "range", "attackSpeed", "armor", "speed", "visionRange"]:
		if def.has(key):
			content.add_child(UITheme.body_label("%s: %s" % [String(key).capitalize(), str(def[key])]))

	var food_upkeep := float(def.get("foodUpkeep", 0.0))
	if food_upkeep > 0.0:
		content.add_child(UITheme.body_label("Food Upkeep: %s" % str(food_upkeep)))
	var fuel_upkeep := float(def.get("fuelUpkeep", 0.0))
	if fuel_upkeep > 0.0:
		content.add_child(UITheme.body_label("Fuel Upkeep: %s" % str(fuel_upkeep)))

	var notes := String(def.get("notes", ""))
	if notes != "":
		var notes_label := UITheme.muted_label(notes)
		notes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(notes_label)
