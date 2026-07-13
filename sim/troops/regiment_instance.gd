## A Commander-led group of up to maxSquadsLed escorted squads (see
## 07-data-architecture.md section 4b). The Commander's own squad is tracked
## separately via commanderId and is never itself an entry in squadIds.
class_name RegimentInstance
extends RefCounted

var id: String
var commander_id: String
var squad_ids: Array[String] = []

func _init(p_id: String, p_commander_id: String) -> void:
	id = p_id
	commander_id = p_commander_id

func is_full(max_squads_led: int) -> bool:
	return squad_ids.size() >= max_squads_led

## Appends squad_id if there's room, returns false (no-op) if the regiment is
## already at max_squads_led — matches the "regiment-full rejection" rule.
func assign_squad(squad_id: String, max_squads_led: int) -> bool:
	if is_full(max_squads_led):
		return false
	squad_ids.append(squad_id)
	return true

func remove_squad(squad_id: String) -> void:
	squad_ids.erase(squad_id)

func to_dict() -> Dictionary:
	return {"id": id, "commander_id": commander_id, "squad_ids": squad_ids.duplicate()}

static func from_dict(d: Dictionary) -> RegimentInstance:
	var regiment := RegimentInstance.new(d["id"], d["commander_id"])
	regiment.squad_ids.assign(d["squad_ids"])
	return regiment
