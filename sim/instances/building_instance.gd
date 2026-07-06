## Live per-match state for one built building (see 07-data-architecture.md
## section 3). Deliberately minimal for now: no ruinState/totalResourcesSpent/
## lastDamagedAt/hex yet — those belong to the not-yet-built placement/combat
## systems. This exists just far enough to let BaseInstance track hqLevel-
## bearing buildings (HQ, Command Centre) for squad/commander cap math.
class_name BuildingInstance
extends RefCounted

var id: String
var base_id: String
var building_type: String
var material: String
var level: int

func _init(p_id: String, p_base_id: String, p_building_type: String, p_level: int = 1, p_material: String = "") -> void:
	id = p_id
	base_id = p_base_id
	building_type = p_building_type
	level = p_level
	material = p_material
