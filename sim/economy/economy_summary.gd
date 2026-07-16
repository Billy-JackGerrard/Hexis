## Per-resource production/upkeep totals for one owner — the figures both
## client/hud/resource_bar.gd's expanded view and client/pause_menu.gd's
## stats panel show, factored here so both compute them identically rather
## than each re-deriving auras/production separately.
class_name EconomySummary
extends RefCounted

static func compute(state: MatchState, owner_id: String, owned_bases: Array[BaseInstance]) -> Dictionary:
	var production: Dictionary = ProductionOutputSystem.compute_production(owned_bases, state.base_defs, state.building_defs).get(owner_id, {})
	var auras := AuraSystem.resolve_tick(state.squads, state.bases, state.troop_defs, state.building_defs, state.regiments)
	var upkeep: Dictionary = UpkeepSystem.compute_upkeep(state.squads, state.troop_defs, auras).get(owner_id, {})
	return {"production": production, "upkeep": upkeep, "auras": auras}
