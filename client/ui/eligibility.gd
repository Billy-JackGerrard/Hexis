## Non-mutating "can the local player do this, and if not why" helpers for the
## HUD (client/hud/building_panel.gd). Every rule lives in the sim already —
## these just compose the sim's pure predicates (CommandProcessor.
## can_upgrade_building / can_enqueue_production, BuildingPlacement.can_place,
## Population, SquadCap) into a single short reason string, "" meaning eligible.
## Keeping the mapping here (not in the panel) means the greying logic is
## reusable and the panel stays about layout.
class_name UIEligibility
extends RefCounted

## Reason a build-menu entry can't be built right now, or "" if it can. The
## expensive "does any valid placement hex exist" scan is hoisted out to
## any_valid_hex() and passed in as `has_valid_hex`, so this stays cheap enough
## to re-check every frame while the affordability/population parts change live.
static func build_reason(state: MatchState, base: BaseInstance, building_type: String, owner_id: String, has_valid_hex: bool) -> String:
	var def: Dictionary = state.building_defs.get(building_type, {})
	var required_level := int(def.get("unlockHqLevel", 1))
	if base.hq_level < required_level:
		return "Requires HQ level %d" % required_level
	var named_cost := BuildingStats.base_cost(def, _first_material(def), state.building_defs)
	var missing := _first_unaffordable(state.pool_for(owner_id), named_cost)
	if missing != "":
		return "Not enough %s" % missing
	if not Population.has_capacity_for(base, building_type, state.building_defs):
		return "Population full"
	if not has_valid_hex:
		return "No available tiles"
	return ""

## Whether at least one hex in the base's HQ build radius accepts `building_type`
## — the "no available tiles" test. O(radius^2 * can_place); only called on
## panel rebuild (selection change), then its result cached, never per frame.
static func any_valid_hex(state: MatchState, base: BaseInstance, base_def: Dictionary, building_type: String) -> bool:
	var occupied := BuildingPlacement.ground_unit_hexes(state.squads, state.troop_defs)
	var radius := BuildingPlacement.hq_build_radius(base.hq_level)
	for hex in HexCoord.range_within(_hq_hex(base), radius):
		if BuildingPlacement.can_place(base, base_def, building_type, hex, state.grid, state.building_defs, occupied) == BuildingPlacement.Result.OK:
			return true
	return false

## Reason a building can't be upgraded, or "" if it can. Thin mapping over the
## sim predicate so a granular Result becomes red UI text.
static func upgrade_reason(state: MatchState, building_id: String, owner_id: String) -> String:
	match CommandProcessor.can_upgrade_building(state, building_id, owner_id):
		CommandProcessor.Result.OK:
			return ""
		CommandProcessor.Result.MAX_LEVEL:
			return "Max level"
		CommandProcessor.Result.HQ_LEVEL_TOO_LOW:
			return "Upgrade the HQ first"
		CommandProcessor.Result.NEED_MORE_POPULATION:
			return "Need more population"
		CommandProcessor.Result.INSUFFICIENT_RESOURCES:
			return _upgrade_cost_reason(state, building_id, owner_id)
		_:
			return "Can't upgrade"

## Reason a troop can't be trained here, or "" if it can. can_enqueue_production
## itself blocks at the squad/Commander cap (unless an existing same-type squad
## still has room to join), so this is a thin mapping over its Result.
static func troop_reason(state: MatchState, building_id: String, troop_type: String, owner_id: String) -> String:
	match CommandProcessor.can_enqueue_production(state, building_id, troop_type, owner_id):
		CommandProcessor.Result.OK:
			return ""
		CommandProcessor.Result.NOT_UNLOCKED:
			return "Locked"
		CommandProcessor.Result.INSUFFICIENT_RESOURCES:
			var cost: Dictionary = state.troop_defs.get(troop_type, {}).get("cost", {})
			return "Not enough %s" % _first_unaffordable(state.pool_for(owner_id), cost)
		CommandProcessor.Result.SQUAD_CAP_REACHED:
			return "Squad cap reached"
		CommandProcessor.Result.COMMANDER_CAP_REACHED:
			return "Commander cap reached"
		_:
			return "Can't train"

# --- Squad panel (client/hud/squad_panel.gd) --------------------------------

## The squad `donor` would merge INTO when the player hits Merge on `squad`:
## the first OTHER same-type, non-Commander, undocked, empty-cargo squad sitting
## on `squad`'s own hex, or null. Same conditions can_merge_squads enforces, so
## a returned donor is one merge_squads will accept (barring `squad` being full,
## which merge_reason surfaces separately).
static func find_merge_donor(state: MatchState, squad: SquadInstance) -> SquadInstance:
	for other in state.squads:
		if other == squad or other.owner_id != squad.owner_id:
			continue
		if other.troop_type != squad.troop_type:
			continue
		if int(state.troop_defs.get(other.troop_type, {}).get("maxSquadsLed", 0)) > 0:
			continue
		if other.is_docked() or not other.cargo_squad_ids.is_empty():
			continue
		if other.current_hex.equals(squad.current_hex):
			return other
	return null

## Reason `squad` can't merge with a same-hex sibling right now, or "" if it can.
## Maps CommandProcessor.can_merge_squads' Result to UI text; a null donor
## (nothing to merge with) short-circuits to its own message.
static func merge_reason(state: MatchState, squad: SquadInstance, donor: SquadInstance, owner_id: String) -> String:
	if donor == null:
		return "No squad to merge here"
	match CommandProcessor.can_merge_squads(state, squad.id, donor.id, owner_id):
		CommandProcessor.Result.OK:
			return ""
		CommandProcessor.Result.SQUAD_FULL:
			return "Squad full"
		CommandProcessor.Result.NOT_ADJACENT:
			return "Must be on the same hex"
		_:
			return "Can't merge"

## Reason `squad` (an Engineer) can't build `building_type` right now, or "" if
## it can. Same two-part shape as build_reason: affordability first, then a
## "does any hex within STANDALONE_BUILD_RANGE accept it" scan (mirrors
## any_valid_hex, but over the Engineer's own reach and can_place_standalone).
static func standalone_build_reason(state: MatchState, squad: SquadInstance, building_type: String, owner_id: String) -> String:
	var def: Dictionary = state.building_defs.get(building_type, {})
	var named_cost := BuildingStats.base_cost(def, _first_material(def), state.building_defs)
	var missing := _first_unaffordable(state.pool_for(owner_id), named_cost)
	if missing != "":
		return "Not enough %s" % missing
	if not _any_valid_standalone_hex(state, squad, building_type):
		return "No available tiles in range"
	return ""

## Whether any hex within the Engineer's build range accepts `building_type` —
## the "no available tiles" test for the engineer build menu. Only called on
## panel rebuild (selection change), same throttle as any_valid_hex.
static func _any_valid_standalone_hex(state: MatchState, squad: SquadInstance, building_type: String) -> bool:
	var occupied_unit := BuildingPlacement.ground_unit_hexes(state.squads, state.troop_defs)
	var occupied := BuildingPlacement.standalone_occupied_hexes(state.bases, state.standalone_buildings)
	for hex in HexCoord.range_within(squad.current_hex, Tuning.STANDALONE_BUILD_RANGE):
		if BuildingPlacement.can_place_standalone(building_type, hex, state.grid, state.building_defs, occupied, occupied_unit) == BuildingPlacement.Result.OK:
			return true
	return false

# --- internals --------------------------------------------------------------

static func _upgrade_cost_reason(state: MatchState, building_id: String, owner_id: String) -> String:
	var found := state.find_any_building(building_id)
	if found.is_empty():
		return "Not enough resources"
	var building: BuildingInstance = found["building"]
	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var cost := BuildingStats.upgrade_cost(def, building.level, building.material, state.building_defs)
	return "Not enough %s" % _first_unaffordable(state.pool_for(owner_id), cost)

## First resource in a data/*.json-shaped named cost dict the pool can't cover,
## as a display label (e.g. "Steel"), or "" if everything's affordable.
static func _first_unaffordable(pool: ResourcePool, named: Dictionary) -> String:
	for type in ResourceType.ALL:
		var key := String(UITheme.RESOURCE_LABEL[type]).to_lower()
		if named.has(key) and pool.get_amount(type) < float(named[key]):
			return UITheme.RESOURCE_LABEL[type]
	return ""

static func _first_material(def: Dictionary) -> String:
	var materials: Array = def.get("materials", [])
	return String(materials[0]) if not materials.is_empty() else ""

static func _hq_hex(base: BaseInstance) -> HexCoord:
	var hqs := base.buildings_of_type("hq")
	if not hqs.is_empty() and hqs[0].hex != null:
		return hqs[0].hex
	return base.hex_coord
