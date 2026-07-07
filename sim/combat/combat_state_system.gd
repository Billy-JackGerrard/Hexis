## On-demand query: is a given squad currently within a living enemy
## attacker's engagement range? The only consumer today is
## CommandProcessor.unload_cargo's `in_combat` flag (04-combat.md: HMS Cuddles
## must be idle/docked to unload; a carrier with canLaunchCargoMidCombat can
## ignore this) — CargoSystem.can_unload/unload have long accepted a
## caller-supplied `in_combat: bool` with no way to derive it, deferred for
## "no broader combat-state/order-issuing layer exists yet". Unlike
## Vision/Detection/Aura, this is deliberately NOT a per-tick cached system:
## it's queried at most once per player-issued unload command, not every tick,
## so a fresh CombatResolver.build_targets() call each time is cheap enough and
## keeps this out of the hot per-tick path.
class_name CombatStateSystem
extends RefCounted

## True if `squad` is currently a legal, in-range target for at least one
## living enemy attacker (a squad with attackSpeed>0 and a non-empty canTarget,
## or a Defensive building) — deliberately coarser than full CombatTargeting
## (no stealth/hidden gating, no Wall line-of-sight): "is anything close enough
## and armed to shoot at me right now" is the only question this needs to
## answer, not "would it actually win the targeting priority this instant".
static func is_squad_in_combat(squad: SquadInstance, squads: Array[SquadInstance], bases: Array[BaseInstance], troops_by_id: Dictionary, grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, standalone_buildings: Array[BuildingInstance] = []) -> bool:
	if squad.member_ids.is_empty():
		return false
	var targets := CombatResolver.build_targets(squads, bases, troops_by_id, grid, troop_defs, building_defs, {}, standalone_buildings)

	for attacker in squads:
		if attacker.owner_id == squad.owner_id or attacker.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(attacker.troop_type, {})
		if float(def.get("attackSpeed", 0.0)) <= 0.0 or def.get("canTarget", []).is_empty():
			continue
		if _in_attacker_range(attacker.current_hex, attacker.owner_id, int(def.get("range", 0)), def, squad, targets):
			return true

	for base in bases:
		if base.owner_id == squad.owner_id:
			continue
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var stats := BuildingStats.defensive_stats(building_defs.get(building.building_type, {}), building.level, building.material, building_defs)
			if stats.is_empty() or float(stats.get("attackSpeed", 0.0)) <= 0.0 or stats.get("canTarget", []).is_empty():
				continue
			if building.hex != null and _in_attacker_range(building.hex, base.owner_id, int(stats.get("range", 0)), stats, squad, targets):
				return true

	return false

static func _in_attacker_range(attacker_hex: HexCoord, attacker_owner: String, attacker_range: int, attacker_def: Dictionary, squad: SquadInstance, targets: Array[CombatTarget]) -> bool:
	for target in targets:
		if target.kind != CombatTarget.Kind.SQUAD or target.squad != squad:
			continue
		return target.distance_from(attacker_hex) <= attacker_range and CombatTargeting.can_target(attacker_def, target)
	return false
