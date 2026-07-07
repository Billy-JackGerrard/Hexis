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
## same rule `unload` enforces for putting troops back ashore.
## `bases`/`standalone_buildings` default to empty (no gating) so existing
## non-Naval-carrier callers don't need to pass them.
static func can_board(carrier_squad: SquadInstance, boarding_squad: SquadInstance, troop_defs: Dictionary, grid: HexGrid = null, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> bool:
	if carrier_squad.owner_id != boarding_squad.owner_id:
		return false
	if boarding_squad.member_ids.is_empty() or boarding_squad.boarded_on_squad_id != "":
		return false
	if carrier_squad.member_ids.is_empty() or carrier_squad.boarded_on_squad_id != "":
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
static func board(carrier_squad: SquadInstance, boarding_squad: SquadInstance, troop_defs: Dictionary, grid: HexGrid = null, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> bool:
	if not can_board(carrier_squad, boarding_squad, troop_defs, grid, bases, standalone_buildings):
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
## anywhere along a bare coast/riverbank. `bases`/`standalone_buildings`
## default to empty (no gating) so existing non-Naval-carrier callers (e.g.
## Transport Truck/Aircraft Carrier, which never trip the Naval check) don't
## need to pass them. Resumes independent movement/combat on success.
static func unload(carrier_squad: SquadInstance, boarded_squad: SquadInstance, target_hex: HexCoord, grid: HexGrid, troop_defs: Dictionary, in_combat: bool = false, bases: Array[BaseInstance] = [], standalone_buildings: Array[BuildingInstance] = []) -> bool:
	if not can_unload(carrier_squad, boarded_squad, troop_defs, in_combat):
		return false
	if HexCoord.distance(carrier_squad.current_hex, target_hex) > 1:
		return false

	if not target_hex.equals(carrier_squad.current_hex):
		var boarded_def: Dictionary = troop_defs.get(boarded_squad.troop_type, {})
		var domain := Terrain.domain_from_string(String(boarded_def.get("domain", "Infantry")))
		var overrides: Dictionary = boarded_def.get("terrainOverrides", {})
		if grid.edge_cost(carrier_squad.current_hex, target_hex, domain, overrides) == Terrain.INF:
			return false

		var carrier_def: Dictionary = troop_defs.get(carrier_squad.troop_type, {})
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
