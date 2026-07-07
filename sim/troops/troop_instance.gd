## Live per-unit state for one troop (see 07-data-architecture.md section 4).
## Always a member of a SquadInstance, even a lone unit (squad of 1) — the
## squad, not the troop, carries movement/pathing/targeting orders.
##
## No fuelStatus field: Fuel isn't tracked per-instance, there's no tank to
## refill. It's a draw against the shared player resource pool, computed live
## each resource tick from this troop's Domain/tags and whether it's under a
## move order or occupying/adjacent to one of the owner's own bases (see
## 03-resources.md's Fuel rules) — same "computed live, not stored" treatment
## already used for terrain-based buffs.
class_name TroopInstance
extends RefCounted

var id: String
var unit_type: String
var owner_id: String
var squad_id: String
var current_hp: float
## Still unused: aura/status-effect modifiers ended up living on SquadInstance/
## BuildingInstance instead (lockout_remaining, stun_tail_remaining, etc. —
## see StatusEffectSystem/AuraSystem), since movement/attack lockout and aura
## coverage are squad-wide, not per-troop (a squad's members all share type/
## stats and fire in unison already, per CombatResolver). Kept declared for a
## future per-troop-granular effect, if one ever needs it.
var active_buffs: Array[Dictionary] = []

func _init(p_id: String, p_unit_type: String, p_owner_id: String, p_squad_id: String, p_current_hp: float) -> void:
	id = p_id
	unit_type = p_unit_type
	owner_id = p_owner_id
	squad_id = p_squad_id
	current_hp = p_current_hp
