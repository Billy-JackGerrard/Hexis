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
## Attack-speed accumulator for Defensive buildings, same meaning as
## SquadInstance.attack_progress. Unused (stays 0) for non-Defensive buildings.
var attack_progress: float = 0.0
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
## time via init_cost() and topped up by rebuild_building. Since no
## upgrade-building action exists yet, this equals the def's level-1
## base_cost for the building's whole lifetime unless it's rebuilt from a
## ruin at least once.
var total_resources_spent: Dictionary = {}

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

## Records this instance's level-1 build cost as its initial
## total_resources_spent — called once at placement, alongside init_hp.
func init_cost(def: Dictionary, building_defs: Dictionary) -> void:
	total_resources_spent = ResourceType.dict_from_named(BuildingStats.base_cost(def, material, building_defs))
