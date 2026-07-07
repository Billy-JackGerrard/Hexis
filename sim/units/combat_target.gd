## A uniform view over "something combat can shoot at" — an enemy SquadInstance
## or an enemy BuildingInstance — so CombatTargeting and CombatMath treat both
## the same way (see 04-combat.md: troops, Defensive buildings, and plain
## Structures are all auto-targetable). Built fresh each tick from live state;
## holds references, never a copy.
class_name CombatTarget
extends RefCounted

enum Kind { SQUAD, BUILDING }

var kind: Kind
var owner_id: String
var hex: HexCoord
## Set only for a Wall target (Kind.BUILDING, building.hex_a/hex_b both set —
## a Wall has no single occupied hex, it sits on the edge between two). `hex`
## is set to hex_a as the canonical anchor (splash-radius math, mostly); range
## checks use distance_from() below instead, which is correct for either edge
## endpoint.
var hex_b: HexCoord = null
## The keys this target presents for canTarget / damage-modifier matching:
## a squad presents its troop Domain + tags; a building presents "Defensive"
## (Defensive-category) or "Structure" (any other building/wall).
var match_keys: Array[String] = []
## Priority tier per 04-combat.md: A (troops + Defensive buildings) is engaged
## before B (plain Structures).
var is_tier_a: bool
var damage_received_modifiers: Dictionary = {}
## Flat per-hit reduction (troop `armor`; buildings have no armor stat -> 0).
var armor: float = 0.0
## Received-damage multiplier from standing on this hex's terrain
## (Terrain.defense_bonus(), e.g. Hills' defender bonus). Live-computed at
## construction time from `grid`, never a stored buff. 1.0 with no grid
## (e.g. a synthetic test target).
var defense_multiplier: float = 1.0
## Whether this target is currently hidden (stealth/forest-ambush) from
## enemies that lack detector coverage or proximity — see DetectionSystem.
var is_hidden: bool = false
## Range within which an enemy sees this target despite is_hidden, without
## needing a detector.
var reveal_range: float = 0.0
## Received-damage multiplier from a friendly damage_reduction aura (e.g.
## Shield Tank) — see AuraSystem. 1.0 with no aura coverage; buildings never
## carry one today (no data authors a friendly_buildings damage_reduction
## aura) so this stays 1.0 for Kind.BUILDING.
var aura_damage_reduction_mult: float = 1.0

## Backing references — exactly one is set depending on kind.
var squad: SquadInstance
var building: BuildingInstance
## id -> TroopInstance registry (squad targets only) so is_alive() can tell a
## squad whose members all just died (this tick, pre-prune) from a live one —
## member_ids alone would still read as "alive" until _prune_dead runs.
var _troops: Dictionary = {}

static func for_squad(p_squad: SquadInstance, troop_def: Dictionary, troops_by_id: Dictionary, grid: HexGrid = null, auras: Dictionary = {}) -> CombatTarget:
	var t := CombatTarget.new()
	t.kind = Kind.SQUAD
	t.owner_id = p_squad.owner_id
	t.hex = p_squad.current_hex
	t.squad = p_squad
	t._troops = troops_by_id
	t.is_tier_a = true
	var keys: Array[String] = [String(troop_def.get("domain", ""))]
	for tag in troop_def.get("tags", []):
		keys.append(String(tag))
	t.match_keys = keys
	t.damage_received_modifiers = troop_def.get("damageReceivedModifiers", {})
	t.armor = float(troop_def.get("armor", 0.0))
	if grid != null:
		t.defense_multiplier = Terrain.defense_bonus(grid.get_terrain(p_squad.current_hex))
		t.is_hidden = DetectionSystem.is_squad_hidden(p_squad, troop_def, grid, auras)
		t.reveal_range = DetectionSystem.squad_reveal_range(p_squad, troop_def, grid, auras)
	if not auras.is_empty():
		t.aura_damage_reduction_mult = AuraSystem.damage_reduction_mult(auras, p_squad.id)
	return t

static func for_building(p_building: BuildingInstance, building_def: Dictionary, building_defs: Dictionary, grid: HexGrid = null) -> CombatTarget:
	var t := CombatTarget.new()
	t.kind = Kind.BUILDING
	# Standalone buildings carry their own ownerId; base buildings derive it from
	# the base. Only base buildings exist in this slice, so ownership comes from
	# the caller wiring (set after construction). Left blank here; CombatTargeting
	# sets owner_id from the owning BaseInstance.
	t.building = p_building
	var is_defensive: bool = BuildingStats.resolve_def(building_def, building_defs).get("category", "") == "Defensive"
	var keys: Array[String] = []
	keys.append("Defensive" if is_defensive else "Structure")
	t.match_keys = keys
	t.is_tier_a = is_defensive
	t.damage_received_modifiers = BuildingStats.damage_received_modifiers(building_def, p_building.material, building_defs)
	# A Wall has no single occupied hex (hex is null; hex_a/hex_b are set
	# instead) — it never stands "on" terrain, so it skips the
	# terrain-defense-bonus/stealth lookups below (they'd have no hex to read).
	if p_building.hex_a != null:
		t.hex = p_building.hex_a
		t.hex_b = p_building.hex_b
		return t
	t.hex = p_building.hex
	if grid != null:
		t.defense_multiplier = Terrain.defense_bonus(grid.get_terrain(p_building.hex))
		t.is_hidden = BuildingStats.stealth(building_def, building_defs)
		t.reveal_range = BuildingStats.reveal_range(building_def, building_defs)
	return t

## Range/proximity distance from `attacker_hex` — plain hex distance for
## every ordinary target, or the nearer of a Wall's two edge endpoints (a Wall
## is in range of an attacker adjacent to EITHER hex it borders, not just one).
func distance_from(attacker_hex: HexCoord) -> int:
	if hex_b != null:
		return min(HexCoord.distance(attacker_hex, hex), HexCoord.distance(attacker_hex, hex_b))
	return HexCoord.distance(attacker_hex, hex)

func target_id() -> String:
	return building.id if kind == Kind.BUILDING else squad.id

func current_hp() -> float:
	return building.current_hp if kind == Kind.BUILDING else 0.0

## Kills every living member of a squad target outright (emp's Air-domain
## instant-destroy branch, see StatusEffectSystem) — a no-op for a building.
func kill_squad() -> void:
	if kind != Kind.SQUAD:
		return
	for member_id in squad.member_ids:
		var troop: TroopInstance = _troops.get(member_id)
		if troop != null:
			troop.current_hp = 0.0

func is_alive() -> bool:
	if kind == Kind.BUILDING:
		return building.current_hp > 0.0
	for member_id in squad.member_ids:
		var troop: TroopInstance = _troops.get(member_id)
		if troop != null and troop.current_hp > 0.0:
			return true
	return false
