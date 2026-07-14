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
