## Live per-match state for one built building (see 07-data-architecture.md
## section 3). Carries combat HP, ruin state, a demolish/rebuild-refund cost
## basis, and, for Defensive buildings, an attack-speed accumulator so the
## CombatResolver can fight it down / let it fire back.
class_name BuildingInstance
extends RefCounted

var id: String
var base_id: String
var building_type: String
var material: String
var level: int
var hex: HexCoord
## Wall's edge endpoints — only set when building_type == "wall", per
## 02-bases-and-buildings.md ("sits on the border between two hexes, not on a
## hex itself"). `hex` stays null for a Wall (it has no single occupied hex —
## BuildingPlacement.occupied_hexes()'s `hex != null` guard already skips it,
## exactly as intended: a Wall doesn't consume a hex-adjacency slot). Null for
## every other building type.
var hex_a: HexCoord = null
var hex_b: HexCoord = null
## max_hp/current_hp default 0 = "not combat-tracked yet" — call sites that have
## the def (BaseFactory, placement) set them via BuildingStats.max_hp; older
## cap-math call sites that only need level keep working untouched.
var max_hp: float = 0.0
var current_hp: float = 0.0
## Attack-speed accumulator(s) for Defensive buildings, one entry per turret,
## same per-entry meaning as SquadInstance.attack_progress. Every Defensive
## building fires with a single turret (array stays size 1) except Wood Tower,
## which carries one independent accumulator per level (BuildingStats.
## turret_count) — see CombatResolver._advance_building. Unused ([0.0]) for
## non-Defensive buildings.
var turret_progress: Array[float] = [0.0]
## Owner for a standalone building (base_id == ""), which has no BaseInstance
## to derive ownership from. Unused ("") for base-attached buildings — those
## keep deriving ownership from base.owner_id, per 02-bases-and-buildings.md.
var owner_id: String = ""
## Same statusEffectOnHit lockout/tail fields as SquadInstance — a frozen/
## stunned Defensive building can't fire back. Buildings never move, so there
## is no move_lockout_remaining equivalent (emp/knockback don't apply to
## buildings — see StatusEffectSystem).
var lockout_remaining: float = 0.0
var stun_tail_remaining: float = 0.0
var stun_tail_queued: float = 0.0
## True once a non-HQ building has been fought down to 0 HP: per
## 06-building-stats-and-defenses.md's Destruction & Ruins section, it stays
## in base.buildings (still occupying its hex / counting for adjacency) but
## no longer functions — combat/vision/aura systems already gate on
## current_hp <= 0, so a ruin simply never recovers that on its own. Cleared
## (back to false) only by a future rebuild-on-ruin action. HQ never sets
## this — see CombatResolver's capture-flip handling instead. Walls/
## standalone buildings never set this either — they delete outright.
var is_ruin: bool = false
## owner_id of whoever dealt this building's most recent damage — the only
## thing CombatResolver needs to know who gets an HQ's capture-flip. Reset to
## "" once consumed by a capture (a building that regens back to full without
## being finished off shouldn't leave a stale attacker attributed to it).
var last_damaged_by: String = ""
## Seconds since this building last took damage, and the accumulator banking
## toward the next regen application — same accumulator-not-absolute-time
## shape as attack_progress/edge_progress. Both reset by CombatResolver on
## every hit; BuildingRegenSystem is the only reader. See
## 06-building-stats-and-defenses.md's Regeneration rule.
var time_since_damage: float = 0.0
var regen_progress: float = 0.0
## Dict per ResourceType.Type -> float, cumulative — original build cost plus
## every upgrade/rebuild cost paid, per 07-data-architecture.md. The basis
## demolish_building refunds 50% of (CommandProcessor); set at construction
## time via init_cost() and topped up by rebuild_building and
## upgrade_building.
var total_resources_spent: Dictionary = {}
## Ids of squads currently landed/docked inside this building (Hangar) — only
## meaningful if the def carries cargoAllowedTags, same "only meaningful if
## cargoCapacity > 0" convention as SquadInstance.cargo_squad_ids for a
## carrier squad. Docked squads die with this building — see
## CombatResolver._prune_dead.
var docked_squad_ids: Array[String] = []

func _init(p_id: String, p_base_id: String, p_building_type: String, p_level: int = 1, p_material: String = "", p_hex: HexCoord = null, p_owner_id: String = "") -> void:
	id = p_id
	base_id = p_base_id
	building_type = p_building_type
	level = p_level
	material = p_material
	hex = p_hex
	owner_id = p_owner_id

## Sets max_hp from the building's def and starts current_hp at full. No-op
## (leaves HP at 0) if the def carries no HP anywhere. Also sizes
## turret_progress to this building's level-1 turret count (1, except a fresh
## Wood Tower).
func init_hp(def: Dictionary, building_defs: Dictionary) -> void:
	max_hp = BuildingStats.max_hp(def, level, material, building_defs)
	current_hp = max_hp
	_sync_turret_progress(def, building_defs)

## Resizes turret_progress to match this building's current level/material
## turret count (BuildingStats.turret_count), preserving already-banked
## accumulators on the kept slots and starting any newly added slot at 0.0 —
## a Wood Tower upgrade adds a fresh turret rather than resetting its existing
## ones' charge.
func _sync_turret_progress(def: Dictionary, building_defs: Dictionary) -> void:
	var count := BuildingStats.turret_count(def, level, material, building_defs)
	while turret_progress.size() < count:
		turret_progress.append(0.0)
	if turret_progress.size() > count:
		turret_progress.resize(count)

## Records this instance's level-1 build cost as its initial
## total_resources_spent — called once at placement, alongside init_hp.
func init_cost(def: Dictionary, building_defs: Dictionary) -> void:
	total_resources_spent = ResourceType.dict_from_named(BuildingStats.base_cost(def, material, building_defs))

## Rescales current_hp to the new max_hp after `level` has been bumped by an
## upgrade, preserving the fraction of HP already lost instead of free-healing
## (unlike init_hp/rebuild_building's full-heal, which only applies to a fresh
## build or a ruin coming back — an upgrade isn't either of those, so a
## damaged building stays damaged, proportionally, at its new HP pool).
func upgrade_hp(def: Dictionary, building_defs: Dictionary) -> void:
	var new_max_hp := BuildingStats.max_hp(def, level, material, building_defs)
	current_hp = (current_hp / max_hp * new_max_hp) if max_hp > 0.0 else new_max_hp
	max_hp = new_max_hp
	_sync_turret_progress(def, building_defs)

func to_dict() -> Dictionary:
	return {
		"id": id,
		"base_id": base_id,
		"building_type": building_type,
		"material": material,
		"level": level,
		"hex": hex.to_key() if hex != null else "",
		"hex_a": hex_a.to_key() if hex_a != null else "",
		"hex_b": hex_b.to_key() if hex_b != null else "",
		"max_hp": max_hp,
		"current_hp": current_hp,
		"turret_progress": turret_progress.duplicate(),
		"owner_id": owner_id,
		"lockout_remaining": lockout_remaining,
		"stun_tail_remaining": stun_tail_remaining,
		"stun_tail_queued": stun_tail_queued,
		"is_ruin": is_ruin,
		"last_damaged_by": last_damaged_by,
		"time_since_damage": time_since_damage,
		"regen_progress": regen_progress,
		"total_resources_spent": total_resources_spent.duplicate(),
		"docked_squad_ids": docked_squad_ids.duplicate(),
	}

static func from_dict(d: Dictionary) -> BuildingInstance:
	var hex: HexCoord = HexCoord.from_key(d["hex"]) if String(d["hex"]) != "" else null
	var building := BuildingInstance.new(d["id"], d["base_id"], d["building_type"], int(d["level"]), d["material"], hex, d["owner_id"])
	building.hex_a = HexCoord.from_key(d["hex_a"]) if String(d["hex_a"]) != "" else null
	building.hex_b = HexCoord.from_key(d["hex_b"]) if String(d["hex_b"]) != "" else null
	building.max_hp = d["max_hp"]
	building.current_hp = d["current_hp"]
	building.turret_progress.assign(d["turret_progress"])
	building.lockout_remaining = d["lockout_remaining"]
	building.stun_tail_remaining = d["stun_tail_remaining"]
	building.stun_tail_queued = d["stun_tail_queued"]
	building.is_ruin = d["is_ruin"]
	building.last_damaged_by = d["last_damaged_by"]
	building.time_since_damage = d["time_since_damage"]
	building.regen_progress = d["regen_progress"]
	building.total_resources_spent = d["total_resources_spent"].duplicate()
	building.docked_squad_ids.assign(d["docked_squad_ids"])
	return building
