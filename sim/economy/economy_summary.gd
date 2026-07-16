## Per-resource production/upkeep totals for one owner — the figures both
## client/hud/resource_bar.gd's expanded view and client/pause_menu.gd's
## stats panel show, factored here so both compute them identically rather
## than each re-deriving auras/production separately. "upkeep" is troop
## upkeep (UpkeepSystem) plus building Food upkeep (BuildingUpkeepSystem)
## combined into one dict, matching how sim_orchestrator.gd's
## _resolve_economy_tick nets them against production for the real tick.
class_name EconomySummary
extends RefCounted

static func compute(state: MatchState, owner_id: String) -> Dictionary:
	var auras := AuraSystem.resolve_tick(state.squads, state.bases, state.troop_defs, state.building_defs, state.regiments)
	# state.bases, not just owner_id's own — a resource_siphon aura can redirect
	# a building's output to a *different* owner (see ProductionOutputSystem),
	# same as the real economy tick (sim_orchestrator.gd's _resolve_economy_tick)
	# computes it; scoping this to owned_bases would silently ignore siphoned-away
	# output, showing a number that doesn't match the pool's actual per-tick change.
	var production: Dictionary = ProductionOutputSystem.compute_production(state.bases, state.base_defs, state.building_defs, auras, Callable(state, "pool_for")).get(owner_id, {})
	var upkeep: Dictionary = UpkeepSystem.compute_upkeep(state.squads, state.troop_defs, auras).get(owner_id, {})
	var building_upkeep: Dictionary = BuildingUpkeepSystem.compute_upkeep(state.bases, state.building_defs).get(owner_id, {})
	for type in building_upkeep:
		upkeep[type] = float(upkeep.get(type, 0.0)) + float(building_upkeep[type])
	return {"production": production, "upkeep": upkeep, "auras": auras}
