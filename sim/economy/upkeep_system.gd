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
## pays no Fuel at all while idle AND occupying/adjacent to one of its
## owner's own bases (the "leash range" fuel-free rule — deliberately not a
## land-in-hangar mechanic). Naval/Infantry upkeep is always flat regardless
## of movement — Naval's "very little" is just a low authored fuelUpkeep
## value, not a rule coded here. Glider needs no special case: it's Air-
## domain but authored with fuelUpkeep 0 in data, so the Air rule multiplies
## out to 0 either way.
class_name UpkeepSystem
extends RefCounted

## Every player's per-tick upkeep, keyed owner_id -> {ResourceType.Type: total}.
## Only Food/Fuel are ever populated (the only upkeep-bearing resources).
static func compute_upkeep(squads: Array[SquadInstance], bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], troop_defs: Dictionary) -> Dictionary:
	var upkeep: Dictionary = {}
	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var food_per_troop: float = float(def.get("foodUpkeep", 0.0))
		var fuel_per_troop: float = float(def.get("fuelUpkeep", 0.0))

		if fuel_per_troop > 0.0 and squad.path.is_empty():
			var domain := Terrain.domain_from_string(String(def.get("domain", "Infantry")))
			if domain == Terrain.Domain.LAND:
				fuel_per_troop = 0.0
			elif domain == Terrain.Domain.AIR and _near_own_base(squad.current_hex, squad.owner_id, bases, standalone_buildings):
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

## True if `hex` is on or adjacent to any building belonging to one of
## `owner_id`'s own bases (base-attached only — standalone buildings carry
## their own owner_id but aren't a "base", so they're excluded from the
## fuel-free footprint per 03-resources.md's wording).
static func _near_own_base(hex: HexCoord, owner_id: String, bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance]) -> bool:
	for base in bases:
		if base.owner_id != owner_id:
			continue
		for building in base.buildings:
			if building.hex != null and HexCoord.distance(hex, building.hex) <= 1:
				return true
	return false

## Per 03-resources.md's Deficit Consequences: each of `owner_id`'s squads
## with at least one member whose troop type inherently draws on a resource
## in `deficits` (its authored foodUpkeep/fuelUpkeep > 0 — not just this
## tick's live contribution, which may have been zeroed by the movement/
## near-base rule above) loses its weakest (lowest current_hp) member. A
## squad emptied by this is removed from `squads` outright, same as
## CombatResolver._prune_dead's squad-disband treatment. Returns the ids of
## every troop killed this way.
static func apply_deficit_deaths(owner_id: String, deficits: Array[ResourceType.Type], squads: Array[SquadInstance], troops_by_id: Dictionary, troop_defs: Dictionary) -> Array[String]:
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

	return killed
