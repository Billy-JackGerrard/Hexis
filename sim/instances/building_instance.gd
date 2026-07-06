## Live per-match state for one built building (see 07-data-architecture.md
## section 3). Still no ruinState/totalResourcesSpent/lastDamagedAt (those
## belong to the not-yet-built ruin system), but now carries combat HP and, for
## Defensive buildings, an attack-speed accumulator so the CombatResolver can
## fight it down / let it fire back.
class_name BuildingInstance
extends RefCounted

var id: String
var base_id: String
var building_type: String
var material: String
var level: int
var hex: HexCoord
## max_hp/current_hp default 0 = "not combat-tracked yet" — call sites that have
## the def (BaseFactory, placement) set them via BuildingStats.max_hp; older
## cap-math call sites that only need level keep working untouched.
var max_hp: float = 0.0
var current_hp: float = 0.0
## Attack-speed accumulator for Defensive buildings, same meaning as
## SquadInstance.attack_progress. Unused (stays 0) for non-Defensive buildings.
var attack_progress: float = 0.0
## Owner for a standalone building (base_id == ""), which has no BaseInstance
## to derive ownership from. Unused ("") for base-attached buildings — those
## keep deriving ownership from base.owner_id, per 02-bases-and-buildings.md.
var owner_id: String = ""

func _init(p_id: String, p_base_id: String, p_building_type: String, p_level: int = 1, p_material: String = "", p_hex: HexCoord = null, p_owner_id: String = "") -> void:
	id = p_id
	base_id = p_base_id
	building_type = p_building_type
	level = p_level
	material = p_material
	hex = p_hex
	owner_id = p_owner_id

## Sets max_hp from the building's def and starts current_hp at full. No-op
## (leaves HP at 0) if the def carries no HP anywhere.
func init_hp(def: Dictionary, building_defs: Dictionary) -> void:
	max_hp = BuildingStats.max_hp(def, level, material, building_defs)
	current_hp = max_hp
