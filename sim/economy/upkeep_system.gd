## Sources the per-tick Food/Fuel upkeep dictionaries ResourceTick.apply()
## expects, and applies the per-squad-troop-death consequence of a Food/Fuel
## deficit — the two gaps ResourceTick's own header comment calls out as not
## its job. Squads/bases both exist by the time this lands, so nothing here
## is deferred further.
##
## Per 03-resources.md's Consumption Rules: every troop's `foodUpkeep`/
## `fuelUpkeep` (data/troops/*.json) is a flat per-troop draw, EXCEPT that a
## Land-domain vehicle only pays Fuel while under a move order (an empty
## `path` means idle/arrived — see MovementResolver), and an Air-domain unit
## pays no Fuel at all while landed/docked (SquadInstance.is_docked() —
## boarded on a carrier squad, e.g. Aircraft Carrier, or landed inside a
## building, e.g. Hangar). There is no near-base fuel-free rule any more:
## an airborne aircraft always drains Fuel regardless of proximity to a
## friendly base — only actually docking stops the drain (see
## CargoSystem.dock/CommandProcessor.dock_squad). Naval/Infantry upkeep is
## always flat regardless of movement — Naval's "very little" is just a low
## authored fuelUpkeep value, not a rule coded here. Glider needs no special
## case: it's Air-domain but authored with fuelUpkeep 0 in data, so the Air
## rule multiplies out to 0 either way.
class_name UpkeepSystem
extends RefCounted

## Every player's per-tick upkeep, keyed owner_id -> {ResourceType.Type: total}.
## Only Food/Fuel are ever populated (the only upkeep-bearing resources).
## `auras` (AuraSystem.resolve_tick() output, default {} = no reduction) feeds
## Mule's upkeep_reduction: a flat per-troop discount applied to BOTH
## foodUpkeep and fuelUpkeep simultaneously, floored at 0 per troop (per
## troop.schema.json's auras.magnitude note), applied before the movement/
## docked fuel-free rules below so an already-zeroed value stays zero.
static func compute_upkeep(squads: Array[SquadInstance], troop_defs: Dictionary, auras: Dictionary = {}) -> Dictionary:
	var upkeep: Dictionary = {}
	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var food_per_troop: float = float(def.get("foodUpkeep", 0.0))
		var fuel_per_troop: float = float(def.get("fuelUpkeep", 0.0))

		var reduction := AuraSystem.upkeep_reduction(auras, squad.id)
		if reduction > 0.0:
			food_per_troop = max(0.0, food_per_troop - reduction)
			fuel_per_troop = max(0.0, fuel_per_troop - reduction)

		if fuel_per_troop > 0.0 and squad.path.is_empty():
			var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
			if domain == Terrain.Domain.LAND:
				fuel_per_troop = 0.0
			elif domain == Terrain.Domain.AIR and squad.is_docked():
				fuel_per_troop = 0.0

		if food_per_troop == 0.0 and fuel_per_troop == 0.0:
			continue

		var owner_totals: Dictionary = upkeep.get(squad.owner_id, {})
		var member_count := squad.member_ids.size()
		if food_per_troop > 0.0:
			owner_totals[ResourceType.Type.FOOD] = float(owner_totals.get(ResourceType.Type.FOOD, 0.0)) + food_per_troop * member_count
		if fuel_per_troop > 0.0:
			owner_totals[ResourceType.Type.FUEL] = float(owner_totals.get(ResourceType.Type.FUEL, 0.0)) + fuel_per_troop * member_count
		upkeep[squad.owner_id] = owner_totals
	return upkeep

## Same live per-tick totals as compute_upkeep, but broken down per troop
## type instead of summed to one number per resource — feeds the resource
## bar's expanded "Usage" breakdown (ResourceBar._refresh_usage), mirroring
## the producer-group breakdown it already shows for buildings. Keyed
## owner_id -> {ResourceType.Type: {troop_type: total}}.
static func compute_upkeep_by_troop_type(squads: Array[SquadInstance], troop_defs: Dictionary, auras: Dictionary = {}) -> Dictionary:
	var upkeep: Dictionary = {}
	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var food_per_troop: float = float(def.get("foodUpkeep", 0.0))
		var fuel_per_troop: float = float(def.get("fuelUpkeep", 0.0))

		var reduction := AuraSystem.upkeep_reduction(auras, squad.id)
		if reduction > 0.0:
			food_per_troop = max(0.0, food_per_troop - reduction)
			fuel_per_troop = max(0.0, fuel_per_troop - reduction)

		if fuel_per_troop > 0.0 and squad.path.is_empty():
			var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
			if domain == Terrain.Domain.LAND:
				fuel_per_troop = 0.0
			elif domain == Terrain.Domain.AIR and squad.is_docked():
				fuel_per_troop = 0.0

		if food_per_troop == 0.0 and fuel_per_troop == 0.0:
			continue

		var owner_totals: Dictionary = upkeep.get(squad.owner_id, {})
		var member_count := squad.member_ids.size()
		if food_per_troop > 0.0:
			var by_troop: Dictionary = owner_totals.get(ResourceType.Type.FOOD, {})
			by_troop[squad.troop_type] = float(by_troop.get(squad.troop_type, 0.0)) + food_per_troop * member_count
			owner_totals[ResourceType.Type.FOOD] = by_troop
		if fuel_per_troop > 0.0:
			var by_troop: Dictionary = owner_totals.get(ResourceType.Type.FUEL, {})
			by_troop[squad.troop_type] = float(by_troop.get(squad.troop_type, 0.0)) + fuel_per_troop * member_count
			owner_totals[ResourceType.Type.FUEL] = by_troop
		upkeep[squad.owner_id] = owner_totals
	return upkeep

## Per 03-resources.md's Deficit Consequences: each of `owner_id`'s squads
## with at least one member whose troop type inherently draws on a resource
## in `deficits` (its authored foodUpkeep/fuelUpkeep > 0 — not just this
## tick's live contribution, which may have been zeroed by the movement/
## near-base rule above) loses its weakest (lowest current_hp) member. A
## squad emptied by this is removed from `squads` outright, same as
## CombatResolver._prune_dead's squad-disband treatment. Returns the ids of
## every troop killed this way.
static func apply_deficit_deaths(owner_id: String, deficits: Array[ResourceType.Type], squads: Array[SquadInstance], troops_by_id: Dictionary, troop_defs: Dictionary, events: Array[MatchEvent] = []) -> Array[String]:
	var killed: Array[String] = []
	if deficits.is_empty():
		return killed

	for squad in squads:
		if squad.owner_id != owner_id or squad.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var consumes := false
		for type in deficits:
			if type == ResourceType.Type.FOOD and float(def.get("foodUpkeep", 0.0)) > 0.0:
				consumes = true
			elif type == ResourceType.Type.FUEL and float(def.get("fuelUpkeep", 0.0)) > 0.0:
				consumes = true
		if not consumes:
			continue

		var weakest_id := ""
		var weakest_hp := INF
		for member_id in squad.member_ids:
			var troop: TroopInstance = troops_by_id.get(member_id)
			if troop != null and troop.current_hp < weakest_hp:
				weakest_hp = troop.current_hp
				weakest_id = member_id
		if weakest_id != "":
			squad.remove_member(weakest_id)
			troops_by_id.erase(weakest_id)
			killed.append(weakest_id)

	for i in range(squads.size() - 1, -1, -1):
		if squads[i].owner_id == owner_id and squads[i].member_ids.is_empty():
			squads.remove_at(i)

	# One aggregate event per owner per call (this function is already called
	# once per owner per economy tick) rather than per troop or per squad —
	# a deficit kills the single weakest member across many squads, not whole
	# squads, so "per squad wipe" doesn't apply the way it does for combat.
	if not killed.is_empty():
		events.append(MatchEvent.new(MatchEvent.Type.DEFICIT_DEATH, owner_id, {"resource_types": deficits.duplicate(), "troop_count": killed.size()}))

	return killed
