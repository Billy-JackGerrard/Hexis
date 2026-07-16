## Live per-match record for one barbarian outpost camp — a standalone tower
## (see BuildingInstance, base_id == "") plus the guard squads seeded around
## it at world-gen (see BarbarianOutpostPlacer/GarrisonFactory), both owned by
## BaseSiteSelector.NEUTRAL_OWNER_ID. Tracks the two independent kill
## conditions BarbarianOutpostLootSystem waits on — the tower dying (recorded
## by CombatResolver._prune_dead, since the BuildingInstance itself is deleted
## the same tick and can't carry this state afterward) and the garrison
## dying (checked live against `squads` each tick, no separate flag needed) —
## so a killing blow landed while the other side is still up doesn't
## prematurely or silently drop the loot.
class_name BarbarianOutpostInstance
extends RefCounted

var id: String
var building_id: String
var guard_squad_ids: Array[String] = []
var loot: Dictionary = {}
var tower_destroyed: bool = false
## owner_id credited with the tower's killing blow (BuildingInstance.
## last_damaged_by at the moment CombatResolver prunes it) — captured here
## since the BuildingInstance carrying that field is removed the same tick.
var tower_killer: String = ""

func _init(p_id: String, p_building_id: String, p_guard_squad_ids: Array[String], p_loot: Dictionary) -> void:
	id = p_id
	building_id = p_building_id
	guard_squad_ids = p_guard_squad_ids
	loot = p_loot

func to_dict() -> Dictionary:
	return {
		"id": id,
		"building_id": building_id,
		"guard_squad_ids": guard_squad_ids,
		"loot": loot,
		"tower_destroyed": tower_destroyed,
		"tower_killer": tower_killer,
	}

static func from_dict(d: Dictionary) -> BarbarianOutpostInstance:
	var guard_squad_ids: Array[String] = []
	for squad_id in d["guard_squad_ids"]:
		guard_squad_ids.append(squad_id)
	var outpost := BarbarianOutpostInstance.new(d["id"], d["building_id"], guard_squad_ids, d["loot"])
	outpost.tower_destroyed = d["tower_destroyed"]
	outpost.tower_killer = d["tower_killer"]
	return outpost
