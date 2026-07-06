## Resolves passive `auras` (05-troop-stat-schema.md's Support Units section)
## fresh each tick from every live aura SOURCE — a support troop squad or a
## Support/Defensive building — within radius of each candidate target,
## matched by `target` (friendly/enemy troops or buildings) and an optional
## `filter` (a Domain/tag string for troops, a category/type string for
## buildings). Stateless/static, same "recomputed fresh, never persisted"
## shape as VisionSystem/DetectionSystem.
##
## Percent effects (speed_boost, attack_speed_boost, slow, damage_reduction)
## combine MULTIPLICATIVELY across every matching source — the same "every
## authored modifier applies" rule CombatMath already uses for damage
## modifiers (slow is just a negative speed_boost sharing the same
## speed_mult accumulator — magnitude's sign already does the work, no
## separate case needed). Flat effects (heal_over_time, upkeep_reduction) SUM.
## suppress_targeting is a plain OR (any matching source suppresses).
##
## Scoping choice — Commander buff auras are deferred: Vanguard/Nightfall/
## Warden's auras use filter "own_regiment"/"own_regiment_and_self", which is
## regiment MEMBERSHIP, not proximity — resolving that requires turning
## RegimentInstance.commanderId/squadIds into live squad references, which
## needs the command/order-issuing layer that doesn't exist yet (the same gap
## already noted for assign_to_commander/leave_regiment elsewhere in
## 10-tech-stack-and-build-order.md). Only proximity-radius auras are resolved
## here: Ice Spire's slow, Hospital/Ambulance/Repair Truck's heal_over_time,
## Mule's upkeep_reduction, Disruptor's suppress_targeting, Volt Truck's
## speed/attack-speed boost.
##
## Also scoped to base-attached buildings only (standalone buildings carry no
## aura data today and aren't looped here) — the same boundary CombatResolver/
## VisionSystem already stop at.
class_name AuraSystem
extends RefCounted

## Fresh per-tick aura view: {"squads": {squad_id: {speed_mult, attack_speed_mult,
## damage_reduction_mult, heal_per_second, upkeep_reduction}}, "buildings":
## {building_id: {suppressed}}} — every squad/building present in `squads`/
## `bases` gets an entry with neutral defaults even if no aura reaches it, so
## callers can always index in without a null check.
static func resolve_tick(squads: Array[SquadInstance], bases: Array[BaseInstance], troop_defs: Dictionary, building_defs: Dictionary) -> Dictionary:
	var squad_mods: Dictionary = {}
	var building_mods: Dictionary = {}
	for squad in squads:
		squad_mods[squad.id] = _default_squad_mods()
	for base in bases:
		for building in base.buildings:
			building_mods[building.id] = {"suppressed": false}

	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		for aura in def.get("auras", []):
			_apply_aura(aura, squad.owner_id, squad.current_hex, squads, bases, troop_defs, building_defs, squad_mods, building_mods)

	for base in bases:
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			for aura in BuildingStats.auras(def, building.level, building_defs):
				_apply_aura(aura, base.owner_id, building.hex, squads, bases, troop_defs, building_defs, squad_mods, building_mods)

	return {"squads": squad_mods, "buildings": building_mods}

static func _default_squad_mods() -> Dictionary:
	return {
		"speed_mult": 1.0,
		"attack_speed_mult": 1.0,
		"damage_reduction_mult": 1.0,
		"heal_per_second": 0.0,
		"upkeep_reduction": 0.0,
	}

static func _apply_aura(aura: Dictionary, source_owner: String, source_hex: HexCoord, squads: Array[SquadInstance], bases: Array[BaseInstance], troop_defs: Dictionary, building_defs: Dictionary, squad_mods: Dictionary, building_mods: Dictionary) -> void:
	var radius := float(aura.get("radius", 0.0))
	var target := String(aura.get("target", "friendly_troops"))
	var filter: String = String(aura.get("filter", ""))
	var effect := String(aura.get("effect", ""))
	var magnitude := float(aura.get("magnitude", 0.0))

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
			_apply_effect_to_squad(squad_mods, squad.id, effect, magnitude)
	elif target == "friendly_buildings" or target == "enemy_buildings":
		var want_friendly_b := target == "friendly_buildings"
		for base in bases:
			for building in base.buildings:
				if building.max_hp > 0.0 and building.current_hp <= 0.0:
					continue
				if (base.owner_id == source_owner) != want_friendly_b:
					continue
				if HexCoord.distance(source_hex, building.hex) > int(radius):
					continue
				if filter != "" and not _building_matches_filter(building, filter, building_defs):
					continue
				_apply_effect_to_building(building_mods, building.id, effect)

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

static func _apply_effect_to_squad(squad_mods: Dictionary, squad_id: String, effect: String, magnitude: float) -> void:
	var m: Dictionary = squad_mods[squad_id]
	match effect:
		"speed_boost", "slow":
			m["speed_mult"] *= (1.0 + magnitude / 100.0)
		"attack_speed_boost":
			m["attack_speed_mult"] *= (1.0 + magnitude / 100.0)
		"damage_reduction":
			m["damage_reduction_mult"] *= (1.0 - magnitude / 100.0)
		"heal_over_time", "heal_out_of_combat":
			m["heal_per_second"] += magnitude
		"upkeep_reduction":
			m["upkeep_reduction"] += magnitude
		_:
			pass

static func _apply_effect_to_building(building_mods: Dictionary, building_id: String, effect: String) -> void:
	if effect == "suppress_targeting":
		building_mods[building_id]["suppressed"] = true

## --- Consumer-side accessors -----------------------------------------------

static func speed_mult(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("speed_mult", 1.0)

static func attack_speed_mult(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("attack_speed_mult", 1.0)

static func damage_reduction_mult(auras: Dictionary, squad_id: String) -> float:
	return auras.get("squads", {}).get(squad_id, _default_squad_mods()).get("damage_reduction_mult", 1.0)

static func is_suppressed(auras: Dictionary, building_id: String) -> bool:
	return bool(auras.get("buildings", {}).get(building_id, {}).get("suppressed", false))

## Applies every squad's aggregated heal_over_time (Ambulance/Repair Truck/
## Hospital) as flat HP regen to its living members, capped at the troop's
## authored max HP. heal_out_of_combat (Warden) is folded into the same
## accumulator today since Commander auras are deferred wholesale (see class
## doc) — once regiment auras land, that effect should gate on the squad not
## having taken damage recently instead of always applying.
static func apply_heals(dt: float, auras: Dictionary, squads: Array[SquadInstance], troops_by_id: Dictionary, troop_defs: Dictionary) -> void:
	for squad in squads:
		var heal := squad_mods_heal(auras, squad.id)
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
