## Board/unload orders for cargo-capable troops (Transport Truck, HMS Cuddles,
## Tank Carrier, Aircraft Carrier) per 04-combat.md's Cargo section and
## 07-data-architecture.md section 4a. Stateless, same shape as
## MovementResolver.issue_move: callers hand in already-resolved SquadInstance
## objects rather than raw order dicts — no order-issuing layer exists yet to
## resolve ids into live objects (same deferral as assign_to_commander
## elsewhere). Carrier-death-kills-cargo is handled in CombatResolver's
## _prune_dead instead, since it's a side effect of squads dying in combat,
## not an order this file issues.
class_name CargoSystem
extends RefCounted

## True if `carrier_def` (a `cargoRequiresBuildingDock` carrier, e.g.
## Cargocopter — see data/troops/schema.json) is sitting on a hex that
## carries a building capable of docking THIS carrier itself: same
## Domain/tags-vs-cargoAllowedTags match `can_dock` uses, just checked
## against the carrier's own def instead of a docking squad's. Purely a
## landing-pad location check — no dock/undock order runs, and the
## building's own cargoCapacity is never touched by it.
static func _has_docking_building_at(hex: HexCoord, carrier_def: Dictionary, bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], building_defs: Dictionary) -> bool:
	var building: BuildingInstance = BuildingPlacement.standalone_occupied_hexes(bases, standalone_buildings).get(hex.to_key())
	if building == null:
		return false
	var building_def: Dictionary = building_defs.get(building.building_type, {})
	var keys: Array[String] = [String(carrier_def.get("domain", ""))]
	for tag in carrier_def.get("tags", []):
		keys.append(String(tag))
	for allowed_key in BuildingStats.cargo_allowed_tags(building_def, building_defs):
		if String(allowed_key) in keys:
			return true
	return false

## True if `boarding_squad` can board `carrier_squad`: same owner, neither
## squad is itself currently boarded cargo, the carrier has a free slot
## (cargoCapacity summed across its own living members — capacity counts
## SQUADS, not troop headcount — must exceed its current cargoSquadIds
## count), and the boarding squad's troopType Domain/tags intersect the
## carrier's cargoAllowedTags (same match mechanism as canTarget). The
## boarding squad must also be at the carrier's current hex or an immediate
## neighbor — troops can't board a carrier from across the map — and, per
## 01-map-and-terrain.md's Naval/Coastline Rules, if the carrier is
## Naval-domain and the boarding squad is standing on a non-Naval-passable
## hex (i.e. it's ashore, not already afloat), that hex must carry a
## Dock/Port/Shipyard/Harbour (BuildingPlacement.is_naval_landing_hex) — mirrors the
## same rule `unload` enforces for putting troops back ashore. Separately, if
## the carrier's own def sets `cargoRequiresBuildingDock` (Cargocopter —
## unlike the Naval rule above, this isn't terrain-driven, since Air ignores
## terrain entirely, so it needs its own explicit opt-in), the carrier's own
## current hex must have a docking-capable building on it too (see
## `_has_docking_building_at`).
## `bases`/`standalone_buildings`/`building_defs` default to empty (no
## gating) so existing callers that need neither check don't need to pass
## them.
static func can_board(carrier_squad: SquadInstance, boarding_squad: SquadInstance, troop_defs: Dictionary, grid: HexGrid = null, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = [], building_defs: Dictionary = {}) -> bool:
	if carrier_squad.owner_id != boarding_squad.owner_id:
		return false
	if boarding_squad.member_ids.is_empty() or boarding_squad.is_docked():
		return false
	if carrier_squad.member_ids.is_empty() or carrier_squad.is_docked():
		return false
	if HexCoord.distance(carrier_squad.current_hex, boarding_squad.current_hex) > 1:
		return false

	var carrier_def: Dictionary = troop_defs.get(carrier_squad.troop_type, {})
	var capacity_per_troop := float(carrier_def.get("cargoCapacity", 0))
	if capacity_per_troop <= 0.0:
		return false
	var capacity := capacity_per_troop * carrier_squad.member_ids.size()
	if float(carrier_squad.cargo_squad_ids.size()) >= capacity:
		return false

	if grid != null:
		var carrier_domain := Terrain.domain_from_string(String(carrier_def.get("domain", "Infantry")))
		if carrier_domain == Terrain.Domain.NAVAL and not Terrain.is_passable(grid.get_terrain(boarding_squad.current_hex), Terrain.Domain.NAVAL):
			if not BuildingPlacement.is_naval_landing_hex(boarding_squad.current_hex, bases, standalone_buildings):
				return false

	if bool(carrier_def.get("cargoRequiresBuildingDock", false)):
		if not _has_docking_building_at(carrier_squad.current_hex, carrier_def, bases, standalone_buildings, building_defs):
			return false

	var boarding_def: Dictionary = troop_defs.get(boarding_squad.troop_type, {})
	var keys: Array[String] = [String(boarding_def.get("domain", ""))]
	for tag in boarding_def.get("tags", []):
		keys.append(String(tag))
	for allowed_key in carrier_def.get("cargoAllowedTags", []):
		if String(allowed_key) in keys:
			return true
	return false

## Boards `boarding_squad` aboard `carrier_squad`. The boarded squad stops
## pathing/acting independently — its position becomes the carrier's — until
## unloaded; it still counts against the owner's global squad cap. Returns
## false (no-op) if can_board rejects it.
static func board(carrier_squad: SquadInstance, boarding_squad: SquadInstance, troop_defs: Dictionary, grid: HexGrid = null, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = [], building_defs: Dictionary = {}) -> bool:
	if not can_board(carrier_squad, boarding_squad, troop_defs, grid, bases, standalone_buildings, building_defs):
		return false
	boarding_squad.boarded_on_squad_id = carrier_squad.id
	boarding_squad.path = []
	boarding_squad.order = {}
	carrier_squad.cargo_squad_ids.append(boarding_squad.id)
	return true

## True if `boarded_squad` can currently be unloaded from `carrier_squad`: it
## must actually be boarded there, and — unless the carrier's
## canLaunchCargoMidCombat is true — `in_combat` must be false (04-combat.md:
## HMS Cuddles must be idle/docked to unload; Aircraft Carrier/Transport
## Truck/Tank Carrier can launch mid-battle). `in_combat` is caller-supplied —
## no broader combat-state/order-issuing layer exists yet to derive it, the
## same gap already deferred for assign_to_commander/regiment orders — and
## defaults to false so idle-unload callers don't need to pass it.
static func can_unload(carrier_squad: SquadInstance, boarded_squad: SquadInstance, troop_defs: Dictionary, in_combat: bool = false) -> bool:
	if boarded_squad.boarded_on_squad_id != carrier_squad.id:
		return false
	if not in_combat:
		return true
	var carrier_def: Dictionary = troop_defs.get(carrier_squad.troop_type, {})
	return bool(carrier_def.get("canLaunchCargoMidCombat", false))

## Unloads `boarded_squad` at `target_hex` — the carrier's own current hex, or
## one of its immediate neighbors (04-combat.md: "the carrier's current hex or
## an adjacent hex") — provided that hex is passable for the boarded squad's
## own Domain/terrainOverrides (a wall or a terrain block for its Domain
## rejects the unload the same way it would block ordinary movement).
## Additionally, per 01-map-and-terrain.md's Naval/Coastline Rules: if the
## carrier itself is Naval-domain and `target_hex` isn't Naval-passable (i.e.
## it's land, not more open water), that hex must carry a Dock/Port/Shipyard/Harbour
## (BuildingPlacement.is_naval_landing_hex) — a ship can't put troops ashore
## anywhere along a bare coast/riverbank. Separately, if the carrier's own def
## sets `cargoRequiresBuildingDock` (Cargocopter), `target_hex` must have a
## docking-capable building on it regardless — checked even when `target_hex`
## IS the carrier's own hex (unlike the Naval check above, which only applies
## when disembarking onto a *different* hex than the carrier's own, since a
## ship's own hex is always water): dropping cargo right where the carrier
## sits is the common case for a building-gated carrier, so it can't be
## skipped the way the Naval branch skips it. `bases`/`standalone_buildings`/
## `building_defs` default to empty (no gating) so existing callers that need
## neither check (e.g. Transport Truck/Aircraft Carrier) don't need to pass
## them. Resumes independent movement/combat on success.
static func unload(carrier_squad: SquadInstance, boarded_squad: SquadInstance, target_hex: HexCoord, grid: HexGrid, troop_defs: Dictionary, in_combat: bool = false, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = [], building_defs: Dictionary = {}) -> bool:
	if not can_unload(carrier_squad, boarded_squad, troop_defs, in_combat):
		return false
	if HexCoord.distance(carrier_squad.current_hex, target_hex) > 1:
		return false

	var carrier_def: Dictionary = troop_defs.get(carrier_squad.troop_type, {})
	if bool(carrier_def.get("cargoRequiresBuildingDock", false)):
		if not _has_docking_building_at(target_hex, carrier_def, bases, standalone_buildings, building_defs):
			return false

	if not target_hex.equals(carrier_squad.current_hex):
		var boarded_def: Dictionary = troop_defs.get(boarded_squad.troop_type, {})
		var domain := Terrain.domain_from_string(String(boarded_def.get("domain", "Infantry")))
		var overrides: Dictionary = boarded_def.get("terrainOverrides", {})
		if grid.edge_cost(carrier_squad.current_hex, target_hex, domain, overrides) == Terrain.INF:
			return false

		var carrier_domain := Terrain.domain_from_string(String(carrier_def.get("domain", "Infantry")))
		if carrier_domain == Terrain.Domain.NAVAL and not Terrain.is_passable(grid.get_terrain(target_hex), Terrain.Domain.NAVAL):
			if not BuildingPlacement.is_naval_landing_hex(target_hex, bases, standalone_buildings):
				return false

	boarded_squad.boarded_on_squad_id = ""
	boarded_squad.current_hex = target_hex
	boarded_squad.path = []
	boarded_squad.edge_progress = 0.0
	carrier_squad.cargo_squad_ids.erase(boarded_squad.id)
	return true

## --- Building docking (Hangar) ----------------------------------------------
##
## Same shape as squad-to-squad boarding above, but the "carrier" is a
## BuildingInstance (base-attached only today — Hangar is Support-category,
## not standalone, so every caller here deals with a building found via a
## base's own buildings list). A base-attached BuildingInstance carries no
## owner_id of its own (see its own doc comment) — callers pass the owning
## base's owner_id explicitly, same as CombatResolver.build_targets/
## _advance_building already do.

## True if `squad` can dock inside `building`: same owner, squad not empty/
## not already boarded or docked elsewhere, the building is alive (a ruin or
## 0-HP building can't shelter anyone), squad is at the building's hex or an
## immediate neighbor, the building has a free slot (BuildingStats.
## cargo_capacity at its current level, vs. its current docked_squad_ids
## count), and the squad's troopType Domain/tags intersect the building's
## cargoAllowedTags — same match mechanism as can_board.
static func can_dock(building: BuildingInstance, building_owner_id: String, squad: SquadInstance, troop_defs: Dictionary, building_defs: Dictionary) -> bool:
	if building_owner_id != squad.owner_id:
		return false
	if squad.member_ids.is_empty() or squad.is_docked():
		return false
	if building.max_hp > 0.0 and building.current_hp <= 0.0:
		return false
	if building.hex == null or HexCoord.distance(building.hex, squad.current_hex) > 1:
		return false

	var building_def: Dictionary = building_defs.get(building.building_type, {})
	var capacity := BuildingStats.cargo_capacity(building_def, building.level, building.material, building_defs)
	if capacity <= 0.0 or float(building.docked_squad_ids.size()) >= capacity:
		return false

	var squad_def: Dictionary = troop_defs.get(squad.troop_type, {})
	var keys: Array[String] = [String(squad_def.get("domain", ""))]
	for tag in squad_def.get("tags", []):
		keys.append(String(tag))
	for allowed_key in BuildingStats.cargo_allowed_tags(building_def, building_defs):
		if String(allowed_key) in keys:
			return true
	return false

## Docks `squad` inside `building`. The docked squad stops pathing/acting
## independently — its position mirrors the building's (MovementResolver's
## _mirror_boarded_squads) until it launches — but still counts against the
## owner's global squad cap. Returns false (no-op) if can_dock rejects it.
static func dock(building: BuildingInstance, building_owner_id: String, squad: SquadInstance, troop_defs: Dictionary, building_defs: Dictionary) -> bool:
	if not can_dock(building, building_owner_id, squad, troop_defs, building_defs):
		return false
	squad.docked_building_id = building.id
	squad.path = []
	squad.order = {}
	building.docked_squad_ids.append(squad.id)
	return true

## True if `squad` can currently launch out of `building`: it must actually be
## docked there, and — unless the building's canLaunchCargoMidCombat is true —
## `in_combat` must be false, same rule as can_unload above.
static func can_undock(building: BuildingInstance, squad: SquadInstance, in_combat: bool, building_defs: Dictionary) -> bool:
	if squad.docked_building_id != building.id:
		return false
	if not in_combat:
		return true
	return BuildingStats.can_launch_cargo_mid_combat(building_defs.get(building.building_type, {}), building_defs)

## Launches `squad` out of `building` onto `target_hex` — the building's own
## hex or an immediate neighbor, same "carrier's hex or adjacent" contract as
## unload() — provided that hex is passable for the squad's own Domain/
## terrainOverrides. Resumes independent movement/combat on success.
static func undock(building: BuildingInstance, squad: SquadInstance, target_hex: HexCoord, grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, in_combat: bool = false) -> bool:
	if not can_undock(building, squad, in_combat, building_defs):
		return false
	if HexCoord.distance(building.hex, target_hex) > 1:
		return false

	if not target_hex.equals(building.hex):
		var squad_def: Dictionary = troop_defs.get(squad.troop_type, {})
		var domain := Terrain.domain_from_string(String(squad_def.get("domain", "Infantry")))
		var overrides: Dictionary = squad_def.get("terrainOverrides", {})
		if grid.edge_cost(building.hex, target_hex, domain, overrides) == Terrain.INF:
			return false

	squad.docked_building_id = ""
	squad.current_hex = target_hex
	squad.path = []
	squad.edge_progress = 0.0
	building.docked_squad_ids.erase(squad.id)
	return true
