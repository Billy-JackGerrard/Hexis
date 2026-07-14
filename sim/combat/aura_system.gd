## Resolves passive `auras` (05-troop-stat-schema.md's Support Units section)
## fresh each tick from every live aura SOURCE — a support troop squad or a
## Support/Defensive building — within radius of each candidate target,
## matched by `target` (friendly/enemy troops or buildings) and an optional
## `filter` (a Domain/tag string for troops, a category/type string for
## buildings). Stateless/static, same "recomputed fresh, never persisted"
## shape as VisionSystem/DetectionSystem.
##
## Every effect first takes the STRONGEST single value per source type
## (troop_type/building_type) reaching a squad — three Hospitals (or three
## Ice Spires, or three Volt Trucks) next to each other contribute one
## Hospital's (Ice Spire's, Volt Truck's) worth, not triple. Distinct source
## types then combine on top of each other: flat effects (heal_over_time,
## heal_out_of_combat, upkeep_reduction) SUM their per-type strongest values;
## percent effects (speed_boost, attack_speed_boost, slow, damage_reduction)
## combine MULTIPLICATIVELY, the same "every distinct modifier applies" rule
## CombatMath already uses for damage modifiers (slow is just a negative
## speed_boost sharing the same speed_mult accumulator — magnitude's sign
## already does the work, no separate case needed). "Strongest" means
## largest by absolute value, so a weaker slow from a lower-level Ice Spire
## doesn't dilute a stronger one from a higher-level Ice Spire also in range.
## suppress_targeting is a plain OR (any matching source suppresses).
##
## Commander buff auras (Vanguard/Nightfall/Warden) use filter
## "own_regiment"/"own_regiment_and_self", which is regiment MEMBERSHIP, not
## proximity — resolved via `regiments` (RegimentInstance.commanderId/
## squadIds), the same lookup assign_to_commander/leave_regiment
## (CommandProcessor) use. Every other aura here is still plain proximity:
## Ice Spire's slow, Hospital/Ambulance/Repair Truck's heal_over_time, Mule's
## upkeep_reduction, Disruptor's suppress_targeting, Volt Truck's
## speed/attack-speed boost.
##
## Also scoped to base-attached buildings only (standalone buildings carry no
## aura data today and aren't looped here) — the same boundary CombatResolver/
## VisionSystem already stop at.
class_name AuraSystem
extends RefCounted

## Fresh per-tick aura view: {"squads": {squad_id: {speed_mult, attack_speed_mult,
## damage_reduction_mult, heal_per_second, heal_out_of_combat_per_second,
## upkeep_reduction, granted_stealth, granted_stealth_reveal_range}},
## "buildings": {building_id: {suppressed, siphoned_by, siphon_distance}}} —
## siphoned_by/siphon_distance track resource_siphon's closest-source-wins
## redirect (see _apply_effect_to_building) — every squad/building present in
## `squads`/`bases` gets an entry with neutral defaults even if no aura
## reaches it, so callers can always index in without a null check.
## `regiments` resolves own_regiment/own_regiment_and_self-filtered Commander
## auras; defaults to [] (those auras simply reach nobody) so existing callers
## keep compiling.
static func resolve_tick(squads: Array[SquadInstance], bases: Array[BaseInstance], troop_defs: Dictionary, building_defs: Dictionary, regiments: Array[RegimentInstance] = []) -> Dictionary:
	var squad_mods: Dictionary = {}
	var building_mods: Dictionary = {}
	var flat_accum: Dictionary = {} # squad_id -> {effect -> {source_type -> max_magnitude}}
	for squad in squads:
		squad_mods[squad.id] = _default_squad_mods()
	for base in bases:
		for building in base.buildings:
			building_mods[building.id] = {"suppressed": false, "siphoned_by": "", "siphon_distance": INF}

	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		for aura in def.get("auras", []):
			_apply_aura(aura, squad.owner_id, squad.current_hex, squad.troop_type, squads, bases, troop_defs, building_defs, squad_mods, building_mods, flat_accum, squad, regiments)

	for base in bases:
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			for aura in BuildingStats.auras(def, building.level, building_defs):
				_apply_aura(aura, base.owner_id, building.hex, building.building_type, squads, bases, troop_defs, building_defs, squad_mods, building_mods, flat_accum)

	_finalize_flat_effects(squad_mods, flat_accum)

	return {"squads": squad_mods, "buildings": building_mods}

static func _default_squad_mods() -> Dictionary:
	return {
		"speed_mult": 1.0,
		"attack_speed_mult": 1.0,
		"damage_reduction_mult": 1.0,
		"heal_per_second": 0.0,
		"heal_out_of_combat_per_second": 0.0,
		"upkeep_reduction": 0.0,
		"granted_stealth": false,
		"granted_stealth_reveal_range": 0.0,
	}

## `source_squad`/`regiments` are only set for a troop-sourced aura (null/[]
## for a building source, e.g. Hospital/Ice Spire/Disruptor) — building auras
## never use the own_regiment/own_regiment_and_self filter.
static func _apply_aura(aura: Dictionary, source_owner: String, source_hex: HexCoord, source_type: String, squads: Array[SquadInstance], bases: Array[BaseInstance], troop_defs: Dictionary, building_defs: Dictionary, squad_mods: Dictionary, building_mods: Dictionary, flat_accum: Dictionary, source_squad: SquadInstance = null, regiments: Array[RegimentInstance] = []) -> void:
	var radius := float(aura.get("radius", 0.0))
	var target := String(aura.get("target", "friendly_troops"))
	var filter: String = String(aura.get("filter", ""))
	var effect := String(aura.get("effect", ""))
	var magnitude := float(aura.get("magnitude", 0.0))

	if target == "friendly_troops" and source_squad != null and (filter == "own_regiment" or filter == "own_regiment_and_self"):
		_apply_regiment_aura(effect, magnitude, source_squad, squads, squad_mods, flat_accum, troop_defs, regiments, filter == "own_regiment_and_self")
		return

	if target == "friendly_troops" or target == "enemy_troops":
		var want_friendly := target == "friendly_troops"
		for squad in squads:
			if squad.member_ids.is_empty():
				continue
			if (squad.owner_id == source_owner) != want_friendly:
				continue
			if HexCoord.distance(source_hex, squad.current_hex) > int(radius):
				continue
			if filter != "" and not _troop_matches_filter(squad, filter, troop_defs):
				continue
			_apply_effect_to_squad(flat_accum, squad.id, source_type, effect, magnitude)
	elif target == "friendly_buildings" or target == "enemy_buildings":
		var want_friendly_b := target == "friendly_buildings"
		for base in bases:
			for building in base.buildings:
				# A Wall has no single hex (hex_a/hex_b instead — see
				# BuildingInstance) and never attacks, so a suppress_targeting/
				# other building-targeted aura has nothing to do to it anyway.
				if building.hex == null:
					continue
				if building.max_hp > 0.0 and building.current_hp <= 0.0:
					continue
				if (base.owner_id == source_owner) != want_friendly_b:
					continue
				var distance := HexCoord.distance(source_hex, building.hex)
				if distance > int(radius):
					continue
				if filter != "" and not _building_matches_filter(building, filter, building_defs):
					continue
				_apply_effect_to_building(building_mods, building.id, effect, source_owner, distance)

## Regiment-membership-filtered aura (Vanguard's speed_boost, Nightfall's
## grant_stealth, Warden's heal_out_of_combat): finds the RegimentInstance this
## Commander squad leads (commanderId == source_squad.id — no regiment exists
## yet if it hasn't been assigned a first squad), and applies `effect` to every
## member squad (plus the Commander's own squad too, if `include_self` —
## Warden's "own_regiment_and_self"). Radius/proximity plays no part here,
## regardless of what the aura's own `radius` field says (authored high, e.g.
## 999, purely so it never accidentally gates anything — see
## commander_vanguard.json's notes).
static func _apply_regiment_aura(effect: String, magnitude: float, source_squad: SquadInstance, squads: Array[SquadInstance], squad_mods: Dictionary, flat_accum: Dictionary, troop_defs: Dictionary, regiments: Array[RegimentInstance], include_self: bool) -> void:
	var member_ids: Array[String] = []
	for regiment in regiments:
		if regiment.commander_id == source_squad.id:
			member_ids = regiment.squad_ids.duplicate()
			break
	if include_self:
		member_ids.append(source_squad.id)
	if member_ids.is_empty():
		return

	for squad in squads:
		if squad.member_ids.is_empty() or not member_ids.has(squad.id):
			continue
		if effect == "grant_stealth":
			var m: Dictionary = squad_mods[squad.id]
			m["granted_stealth"] = true
			m["granted_stealth_reveal_range"] = float(troop_defs.get(source_squad.troop_type, {}).get("revealRange", 0.0))
		else:
			_apply_effect_to_squad(flat_accum, squad.id, source_squad.troop_type, effect, magnitude)

## `filter` is a Domain string (e.g. "Land") or a tag (e.g. "Vehicle") — same
## matching a troop already presents for canTarget/damage modifiers (see
## CombatMath.attacker_keys).
static func _troop_matches_filter(squad: SquadInstance, filter: String, troop_defs: Dictionary) -> bool:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	if String(def.get("domain", "")) == filter:
		return true
	return filter in def.get("tags", [])

## `filter` narrows by building category (e.g. "Defensive", Disruptor's
## suppress_targeting) or, failing that, the building's own type id.
static func _building_matches_filter(building: BuildingInstance, filter: String, building_defs: Dictionary) -> bool:
	var def: Dictionary = building_defs.get(building.building_type, {})
	var category := String(BuildingStats.resolve_def(def, building_defs).get("category", ""))
	return category == filter or building.building_type == filter

## Maps a SUM-across-source-types effect to its squad_mods field.
const FLAT_EFFECT_FIELDS := {
	"heal_over_time": "heal_per_second",
	"heal_out_of_combat": "heal_out_of_combat_per_second",
	"upkeep_reduction": "upkeep_reduction",
}

## Maps a MULTIPLY-across-source-types effect to its squad_mods field.
const PERCENT_EFFECT_FIELDS := {
	"speed_boost": "speed_mult",
	"slow": "speed_mult",
	"attack_speed_boost": "attack_speed_mult",
	"damage_reduction": "damage_reduction_mult",
}

## damage_reduction shrinks the multiplier (1 - magnitude/100); every other
## percent effect grows it (1 + magnitude/100) — slow's negative magnitude
## already shrinks it via the same formula as speed_boost, no separate case.
static func _percent_factor(effect: String, magnitude: float) -> float:
	if effect == "damage_reduction":
		return 1.0 - magnitude / 100.0
	return 1.0 + magnitude / 100.0

## "Strongest" = larger by absolute value, so it stays correct for
## negative-magnitude effects like slow (a -20% slow is stronger than a -10%
## one, even though -20 < -10).
static func _stronger_magnitude(a: float, b: float) -> float:
	return a if abs(a) >= abs(b) else b

static func _apply_effect_to_squad(flat_accum: Dictionary, squad_id: String, source_type: String, effect: String, magnitude: float) -> void:
	if not (FLAT_EFFECT_FIELDS.has(effect) or PERCENT_EFFECT_FIELDS.has(effect)):
		return
	if not flat_accum.has(squad_id):
		flat_accum[squad_id] = {}
	if not flat_accum[squad_id].has(effect):
		flat_accum[squad_id][effect] = {}
	var per_type: Dictionary = flat_accum[squad_id][effect]
	per_type[source_type] = _stronger_magnitude(per_type.get(source_type, 0.0), magnitude)

## `source_owner`/`distance` are only meaningful for resource_siphon (which
## owner to redirect to, and closest-source-wins); suppress_targeting ignores
## them, same as it ignores magnitude.
static func _apply_effect_to_building(building_mods: Dictionary, building_id: String, effect: String, source_owner: String = "", distance: int = 0) -> void:
	if effect == "suppress_targeting":
		building_mods[building_id]["suppressed"] = true
	elif effect == "resource_siphon":
		var mods: Dictionary = building_mods[building_id]
		if distance < mods["siphon_distance"]:
			mods["siphoned_by"] = source_owner
			mods["siphon_distance"] = distance

## Collapses flat_accum (per-source-type strongest value, built up across
## every aura application this tick) into squad_mods: N Hospitals (or Ice
## Spires, or Volt Trucks) reaching the same squad contribute one of that
## type's worth, but distinct source types reaching the same squad still
## combine on top of each other (summed if flat, multiplied if percent).
static func _finalize_flat_effects(squad_mods: Dictionary, flat_accum: Dictionary) -> void:
	for squad_id in flat_accum:
		var m: Dictionary = squad_mods[squad_id]
		for effect in flat_accum[squad_id]:
			var per_type_values: Dictionary = flat_accum[squad_id][effect]
			if FLAT_EFFECT_FIELDS.has(effect):
				var field: String = FLAT_EFFECT_FIELDS[effect]
				var total := 0.0
				for source_type in per_type_values:
					total += per_type_values[source_type]
				m[field] = total
			else:
				var field2: String = PERCENT_EFFECT_FIELDS[effect]
				for source_type in per_type_values:
					m[field2] *= _percent_factor(effect, per_type_values[source_type])

## --- Consumer-side accessors -----------------------------------------------

static func speed_mult(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("speed_mult", 1.0)

static func attack_speed_mult(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("attack_speed_mult", 1.0)

static func damage_reduction_mult(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("damage_reduction_mult", 1.0)

static func is_suppressed(auras: Dictionary, building_id: String) -> bool:
	return bool(auras.get("buildings", {}).get(building_id, {}).get("suppressed", false))

## Owner id currently siphoning this building's production ("" if none) —
## the closest in-range resource_siphon source, per _apply_effect_to_building.
static func siphoned_by(auras: Dictionary, building_id: String) -> String:
	return String(auras.get("buildings", {}).get(building_id, {}).get("siphoned_by", ""))

static func upkeep_reduction(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("upkeep_reduction", 0.0)

static func is_granted_stealth(auras: Dictionary, squad_id: String) -> bool:
	return bool(auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("granted_stealth", false))

static func granted_stealth_reveal_range(auras: Dictionary, squad_id: String) -> float:
	return float(auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("granted_stealth_reveal_range", 0.0))

## Applies every squad's aggregated heal_over_time (Ambulance/Repair Truck/
## Hospital — always-on) plus heal_out_of_combat (Warden — gated on
## time_since_damage clearing the delay above) as flat HP regen to living
## members, capped at the troop's authored max HP. Increments every live
## squad's time_since_damage by dt first (mirrors BuildingRegenSystem's
## accumulator-over-dt shape) so the gate is accurate even for a squad with no
## heal aura reaching it this tick.
static func apply_heals(dt: float, auras: Dictionary, squads: Array[SquadInstance], troops_by_id: Dictionary, troop_defs: Dictionary) -> void:
	for squad in squads:
		squad.time_since_damage += dt
		var heal := squad_mods_heal(auras, squad.id)
		if squad.time_since_damage >= Tuning.AURA_OUT_OF_COMBAT_HEAL_DELAY_SECONDS:
			heal += squad_mods_heal_out_of_combat(auras, squad.id)
		if heal <= 0.0:
			continue
		var max_hp := float(troop_defs.get(squad.troop_type, {}).get("hp", 0.0))
		for member_id in squad.member_ids:
			var troop: TroopInstance = troops_by_id.get(member_id)
			if troop == null or troop.current_hp <= 0.0:
				continue
			var healed: float = troop.current_hp + heal * dt
			troop.current_hp = min(max_hp, healed) if max_hp > 0.0 else healed

static func squad_mods_heal(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("heal_per_second", 0.0)

static func squad_mods_heal_out_of_combat(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("heal_out_of_combat_per_second", 0.0)
