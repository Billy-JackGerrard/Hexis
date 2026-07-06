## The atomic move/select/order unit (see 07-data-architecture.md section 4a).
## Always single-type — combined arms happens one level up, at RegimentInstance.
class_name SquadInstance
extends RefCounted

var id: String
var owner_id: String
var troop_type: String
var member_ids: Array[String] = []
var current_hex: HexCoord
var path: Array[HexCoord] = []
var edge_progress: float = 0.0
## Attack-speed accumulator (attacks, not seconds): CombatResolver adds
## dt * attackSpeed each tick and fires one volley per whole unit, mirroring
## edge_progress's "accumulator, not absolute time" treatment. All members
## share type/stats, so the squad fires in unison — one attack per living member.
var attack_progress: float = 0.0
var commander_id: String = "" ## set if assigned to a Commander's regiment
var boarded_on_squad_id: String = "" ## set if currently cargo aboard a carrier squad
var cargo_squad_ids: Array[String] = [] ## only meaningful if troopType's cargoCapacity > 0
var order: Dictionary = {} ## { type, targetId }

func _init(p_id: String, p_owner_id: String, p_troop_type: String, p_current_hex: HexCoord) -> void:
	id = p_id
	owner_id = p_owner_id
	troop_type = p_troop_type
	current_hex = p_current_hex

func is_full(max_squad_size: int) -> bool:
	return member_ids.size() >= max_squad_size

func add_member(troop_id: String) -> void:
	member_ids.append(troop_id)

func remove_member(troop_id: String) -> void:
	member_ids.erase(troop_id)
