## Per-resource production/upkeep totals for one owner — the figures both
## client/hud/resource_bar.gd's expanded view and client/pause_menu.gd's
## stats panel show, factored here so both compute them identically rather
## than each re-deriving auras/production separately.
class_name EconomySummary
extends RefCounted

static func compute(state: MatchState, owner_id: String) -> Dictionary:
	var auras := AuraSystem.resolve_tick(state.squads, state.bases, state.troop_defs, state.building_defs, state.regiments)
	# state.bases, not just owner_id's own — a resource_siphon aura can redirect
	# a building's output to a *different* owner (see ProductionOutputSystem),
	# same as the real economy tick (sim_orchestrator.gd's _resolve_economy_tick)
	# computes it; scoping this to owned_bases would silently ignore siphoned-away
	# output, showing a number that doesn't match the pool's actual per-tick change.
	var production: Dictionary = ProductionOutputSystem.compute_production(state.bases, state.base_defs, state.building_defs, auras).get(owner_id, {})
	var upkeep: Dictionary = UpkeepSystem.compute_upkeep(state.squads, state.troop_defs, auras).get(owner_id, {})
	return {"production": production, "upkeep": upkeep, "auras": auras}
