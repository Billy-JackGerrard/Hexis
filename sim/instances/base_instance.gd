## Live per-match state for one owned base (see 07-data-architecture.md
## section 5). Deliberately minimal for now: no hexCoord/population/walls —
## just enough (hqLevel + its buildings) to drive squad/commander cap math
## ahead of full base/building placement rules landing.
class_name BaseInstance
extends RefCounted

var id: String
var base_def_id: String
var owner_id: String
var hq_level: int
var buildings: Array[BuildingInstance] = []

func _init(p_id: String, p_base_def_id: String, p_owner_id: String, p_hq_level: int = 1) -> void:
	id = p_id
	base_def_id = p_base_def_id
	owner_id = p_owner_id
	hq_level = p_hq_level

func buildings_of_type(building_type: String) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	for b in buildings:
		if b.building_type == building_type:
			result.append(b)
	return result
