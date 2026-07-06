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
## Countdown (seconds) while a stealthed/forest-ambushing squad is forcibly
## visible after attacking; 0 once expired, re-enabling hidden state if the
## stealth/terrain condition still holds. Mutated only by CombatResolver, the
## sole actor that knows when this squad actually fired.
var reveal_cooldown_remaining: float = 0.0
var commander_id: String = "" ## set if assigned to a Commander's regiment
var boarded_on_squad_id: String = "" ## set if currently cargo aboard a carrier squad
var cargo_squad_ids: Array[String] = [] ## only meaningful if troopType's cargoCapacity > 0
var order: Dictionary = {} ## { type, targetId }

## Countdown (seconds) of a `freeze`/`stun` statusEffectOnHit's full lockout —
## can't move or attack while > 0. Set (never stacked additively, only ever
## raised to `max()`) by StatusEffectSystem.apply_on_hit(), decremented by
## StatusEffectSystem.resolve_tick().
var lockout_remaining: float = 0.0
## Countdown (seconds) of an `emp` hit's Land-domain partial lockout — can't
## move, but CAN still attack if something is already in range (distinct from
## the full lockout above). Air/Infantry/Naval domains never set this.
var move_lockout_remaining: float = 0.0
## Countdown (seconds) of `stun`'s fixed trailing -30% move/attack-speed
## debuff, active once the lockout above has fully expired.
var stun_tail_remaining: float = 0.0
## Duration (seconds) to arm stun_tail_remaining with once lockout_remaining
## reaches 0 — set alongside lockout_remaining by a `stun` hit (not `freeze`,
## which never queues a tail); consumed by StatusEffectSystem.resolve_tick().
var stun_tail_queued: float = 0.0

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
