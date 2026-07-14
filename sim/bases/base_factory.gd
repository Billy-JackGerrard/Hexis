## Seeds a fresh BaseInstance from its BaseDef's `initialBuildings`, per
## 02-bases-and-buildings.md's "Base Seeding" section: every base (new or
## captured) starts with HQ + Farm + Quarry, mutually adjacent, on Plains by
## default or the base's terrainException terrain (Forest/Hill) when set —
## see sim/worldgen/base_site_selector.gd for the world-gen siting rules
## that pick hq_hex accordingly. Authored placement, not player-driven, so
## it bypasses the isFixed/isStandalone/buildableBuildings menu gates that
## BuildingPlacement enforces for normal builds — it still requires the
## correct terrain to already exist in the grid around hq_hex; seed_base
## itself performs no siteTerrain validation (every seeded building lands on
## the flower, already guaranteed correct by the site selector), but it DOES
## honor each building's `placementRequirement.adjacentTerrainRequired`
## (Water/Forest) when choosing which hex to put it on — see _pick_seed_hex.
##
## The Capital's seeded Command Centre is the one deliberate exception: it's
## seeded already ruined (current_hp forced to 0, is_ruin true) rather than
## full-health — a fresh Capital hasn't earned Commander access yet, so the
## player has to spend resources on CommandProcessor.rebuild_building before
## training any Commander, same rebuild path a combat-destroyed Command
## Centre already uses (see command_processor.gd's rebuild_building).
class_name BaseFactory
extends RefCounted

## Building types seeded already-ruined instead of full-health — currently
## just the Capital's Command Centre (see class doc comment above).
const SEEDED_AS_RUIN: Array[String] = ["command_centre"]

## Non-wall, non-HQ seeded buildings can't all fit on HQ's 6 immediate
## neighbors (most Unique bases seed 7-8 of them) — Tuning.MAX_SEED_SEARCH_RING
## bounds how far _pick_seed_hex is willing to ring-search outward for a free
## (and, for an adjacency-requiring building, terrain-qualifying) hex before
## giving up and taking whatever's closest. 4 comfortably covers a building
## whose water/forest requirement is only satisfiable near the edge of a
## site's flower (e.g. Kraken Point's water is guaranteed within ring-2 of
## hq_hex per BaseSiteSelector._is_ocean_edge_site — a hex up to ring-3 out
## can still be adjacent to it).

## Seed layout: HQ at the center; every other non-Wall initialBuildings entry
## claims the nearest still-free hex ring-searched outward from hq_hex
## (_pick_seed_hex) — entries carrying an adjacentTerrainRequired are placed
## FIRST so they get first pick of the (usually few) qualifying hexes, then
## everything else fills in around them. This still keeps the cluster compact
## (most bases fit within ring 1-2 of hq_hex) without either colliding two
## buildings onto the same hex (the old fixed 6-direction fan wrapped and did
## exactly that for any base with >6 non-Wall buildings — nearly all of
## them) or ignoring adjacency requirements (e.g. Kraken Point's Water
## Turrets/Shipyard). Walls are seeded last, as real hex_a/hex_b edges around
## the finished cluster's perimeter (see _seed_walls) rather than as
## hex-keyed buildings. `building_defs` is optional: when supplied, each
## seeded building's combat HP is initialised from its def (BuildingStats.
## max_hp), so the base is fightable; omit it (cap-math/placement callers
## that don't need HP) and buildings seed with HP left at 0 and every
## adjacency requirement is ignored (falls back to plain ring order).
static func seed_base(id: String, base_def: Dictionary, owner_id: String, hq_hex: HexCoord, grid: HexGrid, building_defs: Dictionary = {}) -> BaseInstance:
	var base := BaseInstance.new(id, base_def.get("id", ""), owner_id, 1, hq_hex)
	var building_index := 0

	var hq_building := BuildingInstance.new("%s_seed_%d" % [id, building_index], id, "hq", 1, "", hq_hex)
	if building_defs.has("hq"):
		hq_building.init_hp(building_defs["hq"], building_defs)
	base.buildings.append(hq_building)
	building_index += 1

	var claimed: Dictionary = {hq_hex.to_key(): true}
	var wall_count := 0
	var wall_material := ""

	var hex_entries: Array = []
	for entry in base_def.get("initialBuildings", []):
		var building_type: String = entry.get("buildingType")
		if building_type == "hq":
			continue
		var count: int = int(entry.get("count", 1))
		if building_type == "wall":
			wall_count += count
			wall_material = entry.get("material", "")
			continue
		for i in range(count):
			hex_entries.append({"building_type": building_type, "material": entry.get("material", "")})

	# Adjacency-requiring entries first, so they claim a qualifying hex before
	# the unconstrained ones fill in the rest of the ring.
	hex_entries.sort_custom(func(a, b): return _adjacent_terrain_required(a["building_type"], building_defs) != "" and _adjacent_terrain_required(b["building_type"], building_defs) == "")

	for entry in hex_entries:
		var building_type: String = entry["building_type"]
		var required := _adjacent_terrain_required(building_type, building_defs)
		var hex := _pick_seed_hex(hq_hex, grid, claimed, required)
		claimed[hex.to_key()] = true
		var building := BuildingInstance.new("%s_seed_%d" % [id, building_index], id, building_type, 1, entry["material"], hex)
		if building_defs.has(building_type):
			building.init_hp(building_defs[building_type], building_defs)
			if SEEDED_AS_RUIN.has(building_type):
				building.current_hp = 0.0
				building.is_ruin = true
		base.buildings.append(building)
		building_index += 1

	if wall_count > 0:
		building_index = _seed_walls(base, id, building_index, wall_count, wall_material, claimed, grid, building_defs)

	return base

static func _adjacent_terrain_required(building_type: String, building_defs: Dictionary) -> String:
	var def: Dictionary = building_defs.get(building_type, {})
	return String(def.get("placementRequirement", {}).get("adjacentTerrainRequired", ""))

## Ring-searches outward from hq_hex (ring 1, 2, 3, ...) for the first
## unclaimed on-grid hex that also satisfies `adjacent_terrain_required` (if
## any — reuses BuildingPlacement's own Water/Forest neighbor check, so this
## agrees exactly with what a player-built placement of the same building
## would require). Falls back to the closest unclaimed hex regardless of
## adjacency if nothing qualifies within Tuning.MAX_SEED_SEARCH_RING (better an
## authored building lands somewhere on-site than the seed silently drops
## it), and to hq_hex itself in the degenerate case nothing at all is free.
static func _pick_seed_hex(hq_hex: HexCoord, grid: HexGrid, claimed: Dictionary, adjacent_terrain_required: String) -> HexCoord:
	var fallback: HexCoord = null
	for radius in range(1, Tuning.MAX_SEED_SEARCH_RING + 1):
		for hex in _ring_candidates(hq_hex, radius):
			if not grid.has_hex(hex) or claimed.has(hex.to_key()):
				continue
			if fallback == null:
				fallback = hex
			if adjacent_terrain_required == "" or _has_adjacent_terrain(hex, grid, adjacent_terrain_required):
				return hex
	return fallback if fallback != null else hq_hex

## Ring-1 candidates walk HexCoord.DIRECTIONS in plain 0..5 order (matching
## the old fixed-fan code's HexCoord.neighbor(hq_hex, direction) sequence
## exactly) rather than HexCoord.ring()'s own (correct, but differently
## rotated) perimeter-walk order — every base whose non-Wall building count
## fits within ring 1 (most of them; only overflow buildings ever spill into
## ring 2+) ends up on the exact same hexes as before this rewrite. Ring 2+
## has no legacy order to match (the old code never validly reached past
## ring 1), so those just use HexCoord.ring() directly.
static func _ring_candidates(hq_hex: HexCoord, radius: int) -> Array[HexCoord]:
	if radius == 1:
		var result: Array[HexCoord] = []
		for direction in range(6):
			result.append(HexCoord.neighbor(hq_hex, direction))
		return result
	return HexCoord.ring(hq_hex, radius)

static func _has_adjacent_terrain(hex: HexCoord, grid: HexGrid, required: String) -> bool:
	for n in HexCoord.neighbors(hex):
		if BuildingPlacement._matches_adjacent_terrain_required(required, grid.get_terrain(n)):
			return true
	return false

## Wraps the finished (HQ + hex_entries) cluster in real edge-keyed Wall
## BuildingInstances (hex_a/hex_b, matching how a player-placed Wall looks —
## unlike the old code, which mistakenly gave seeded Walls a single `hex`,
## making them both invisible to base_view.gd's wall renderer and inert to
## grid.is_walled_edge()) instead of hex-keyed ones. Perimeter edges are every
## (claimed hex -> unclaimed neighbor) pair — walking only from the claimed
## side naturally visits each boundary edge once. Registers each wall with
## grid.set_wall() too, so pathing/line-of-sight respect it immediately, same
## as BuildingPlacement.place_wall does for a player-built one. Returns the
## next free building_index for the caller.
static func _seed_walls(base: BaseInstance, id: String, building_index: int, count: int, material: String, claimed: Dictionary, grid: HexGrid, building_defs: Dictionary) -> int:
	var wall_def: Dictionary = building_defs.get("wall", {})
	var placed := 0
	for hex_key in claimed:
		if placed >= count:
			break
		var hex: HexCoord = HexCoord.from_key(hex_key)
		for neighbor in HexCoord.neighbors(hex):
			if placed >= count:
				break
			if claimed.has(neighbor.to_key()) or not grid.has_hex(neighbor):
				continue
			var wall := BuildingInstance.new("%s_seed_%d" % [id, building_index], id, "wall", 1, material)
			wall.hex_a = hex
			wall.hex_b = neighbor
			if building_defs.has("wall"):
				wall.init_hp(wall_def, building_defs)
			base.buildings.append(wall)
			grid.set_wall(hex, neighbor, true)
			building_index += 1
			placed += 1
	return building_index
