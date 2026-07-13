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
var docked_building_id: String = "" ## set if currently landed/docked inside a building (e.g. Hangar)
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

## Seconds since any member of this squad last took damage — same out-of-
## combat gating shape as BuildingInstance.time_since_damage, but consumed by
## AuraSystem.apply_heals() for Commander Warden's `heal_out_of_combat` aura
## (per its own note: only ticks once a squad hasn't taken damage recently,
## unlike Ambulance/Repair Truck/Hospital's always-on `heal_over_time`). Reset
## by CombatResolver on every hit; incremented every tick by apply_heals().
var time_since_damage: float = 0.0

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

## True while this squad is cargo aboard a carrier squad OR landed/docked
## inside a building — either way it has no independent position, can't be
## targeted, fired at from, or ordered, and mirrors its host's hex instead of
## acting on its own. The two are mutually exclusive (a squad can only be
## docked one place at a time) but callers that just need "is this squad
## inert right now" should check this rather than either field individually.
func is_docked() -> bool:
	return boarded_on_squad_id != "" or docked_building_id != ""

## Plain-dict snapshot for save/load and future network replication —
## HexCoord fields go through to_key()/from_key() (already the canonical
## string form used throughout sim/) rather than a parallel encoding.
func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner_id": owner_id,
		"troop_type": troop_type,
		"member_ids": member_ids.duplicate(),
		"current_hex": current_hex.to_key(),
		"path": path.map(func(hex): return hex.to_key()),
		"edge_progress": edge_progress,
		"attack_progress": attack_progress,
		"reveal_cooldown_remaining": reveal_cooldown_remaining,
		"commander_id": commander_id,
		"boarded_on_squad_id": boarded_on_squad_id,
		"docked_building_id": docked_building_id,
		"cargo_squad_ids": cargo_squad_ids.duplicate(),
		"order": order.duplicate(),
		"lockout_remaining": lockout_remaining,
		"move_lockout_remaining": move_lockout_remaining,
		"stun_tail_remaining": stun_tail_remaining,
		"stun_tail_queued": stun_tail_queued,
		"time_since_damage": time_since_damage,
	}

static func from_dict(d: Dictionary) -> SquadInstance:
	var squad := SquadInstance.new(d["id"], d["owner_id"], d["troop_type"], HexCoord.from_key(d["current_hex"]))
	squad.member_ids.assign(d["member_ids"])
	var path: Array[HexCoord] = []
	for key in d["path"]:
		path.append(HexCoord.from_key(key))
	squad.path = path
	squad.edge_progress = d["edge_progress"]
	squad.attack_progress = d["attack_progress"]
	squad.reveal_cooldown_remaining = d["reveal_cooldown_remaining"]
	squad.commander_id = d["commander_id"]
	squad.boarded_on_squad_id = d["boarded_on_squad_id"]
	squad.docked_building_id = d["docked_building_id"]
	squad.cargo_squad_ids.assign(d["cargo_squad_ids"])
	squad.order = d["order"].duplicate()
	squad.lockout_remaining = d["lockout_remaining"]
	squad.move_lockout_remaining = d["move_lockout_remaining"]
	squad.stun_tail_remaining = d["stun_tail_remaining"]
	squad.stun_tail_queued = d["stun_tail_queued"]
	squad.time_since_damage = d["time_since_damage"]
	return squad
