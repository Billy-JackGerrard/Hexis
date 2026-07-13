## A single ballistic shot in flight, spawned when a squad/building's attack
## commits against a def carrying `projectileSpeed` (see CombatResolver's
## `_fire_or_apply`). Aims at a FIXED hex — the target's hex at the moment of
## firing, never a tracked entity id — so a target that moves off `aim_hex`
## before ProjectileSystem resolves the impact is a genuine dodge, with no
## homing and no continuous-position math. `attacker_hex`/`aim_hex` are
## copies, not the live CombatTarget/SquadInstance hex references, since
## nothing should retroactively move an already-fired shot's aim point.
##
## `beam_hexes` (non-empty) turns this into a traveling LINE attack instead of
## a single-point shot — a line attack that carries projectileSpeed, slow
## enough to sweep visibly down its beam rather than resolving instantly like
## Tank Obliterator's rail gun (attacker_def.lineAttack with no projectileSpeed
## still resolves the whole beam in one instant tick via CombatResolver.
## _apply_line_attack; this is the slow-travel alternative — see
## ProjectileSystem._advance_beam). Wind Spire is the one real unit combining
## lineAttack with projectileSpeed today.
## `aim_hex` is still set for a beam (its last hex, for bookkeeping/dodge
## symmetry) but `remaining_time` is unused; the beam instead advances via
## `beam_elapsed`/`beam_next_index` as it sweeps each hex in order.
class_name ProjectileInstance
extends RefCounted

var id: String
var owner_id: String
var attacker_hex: HexCoord
var aim_hex: HexCoord
var remaining_time: float
## Frozen snapshot of the firing attacker's resolved stat dict (troop def, or
## BuildingStats.defensive_stats() for a building) — a mid-flight upgrade
## correctly doesn't retroactively change an already-fired shell's damage.
var attacker_def: Dictionary
var base_damage: float
var splash_radius: int
## Beam-only fields (empty beam_hexes = an ordinary point projectile).
var beam_hexes: Array[HexCoord] = []
var beam_next_index: int = 0
var beam_elapsed: float = 0.0

func _init(p_id: String, p_owner_id: String, p_attacker_hex: HexCoord, p_aim_hex: HexCoord, p_remaining_time: float, p_attacker_def: Dictionary, p_base_damage: float, p_splash_radius: int, p_beam_hexes: Array[HexCoord] = []) -> void:
	id = p_id
	owner_id = p_owner_id
	attacker_hex = HexCoord.new(p_attacker_hex.q, p_attacker_hex.r)
	aim_hex = HexCoord.new(p_aim_hex.q, p_aim_hex.r)
	remaining_time = p_remaining_time
	attacker_def = p_attacker_def
	base_damage = p_base_damage
	splash_radius = p_splash_radius
	beam_hexes = p_beam_hexes

func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner_id": owner_id,
		"attacker_hex": attacker_hex.to_key(),
		"aim_hex": aim_hex.to_key(),
		"remaining_time": remaining_time,
		"attacker_def": attacker_def,
		"base_damage": base_damage,
		"splash_radius": splash_radius,
		"beam_hexes": beam_hexes.map(func(hex): return hex.to_key()),
		"beam_next_index": beam_next_index,
		"beam_elapsed": beam_elapsed,
	}

static func from_dict(d: Dictionary) -> ProjectileInstance:
	var beam_hexes: Array[HexCoord] = []
	for key in d["beam_hexes"]:
		beam_hexes.append(HexCoord.from_key(key))
	var projectile := ProjectileInstance.new(d["id"], d["owner_id"], HexCoord.from_key(d["attacker_hex"]), HexCoord.from_key(d["aim_hex"]), d["remaining_time"], d["attacker_def"], d["base_damage"], d["splash_radius"], beam_hexes)
	projectile.beam_next_index = d["beam_next_index"]
	projectile.beam_elapsed = d["beam_elapsed"]
	return projectile
