## Scatters barbarian outpost camps across an already-sited map (grid + player/
## Unique bases already placed by BaseSiteSelector) — each camp is one
## standalone tower (reusing data/buildings/tower.json, never a new building
## def) plus a fixed-strength guard garrison, both owned by
## BaseSiteSelector.NEUTRAL_OWNER_ID, seeded via the same GarrisonFactory/
## BuildingPlacement primitives Unique bases already use.
##
## Deliberately BEST-EFFORT, unlike BaseSiteSelector.place_bases: this is
## flavor/chaos content, not a required map element, so placing fewer than
## `outpost_count` camps on a dense seed is an acceptable outcome, not a
## whole-map-generation failure.
##
## Tier (which of the 3 tower.json materials/outpost_defs entries a site
## gets) is distance-scaled, not randomly rolled: farther from every player
## Capital means a tougher garrison and better loot, rewarding exploration
## into contested territory over a flat luck draw — see _tier_def_for.
class_name BarbarianOutpostPlacer
extends RefCounted

## Deterministic given (world_seed, the already-placed bases/grid) — draws
## its own substream (label "barbarian_outpost_sites") separate from every
## other world-gen RNG use, so it can't perturb base/terrain generation for
## the same seed. See BaseSiteSelector._substream for the same pattern.
static func place_outposts(
	grid: HexGrid,
	map_radius: int,
	placed_bases: Array[BaseInstance],
	base_defs: Dictionary,
	outpost_count: int,
	world_seed: int,
	outpost_defs: Dictionary,
	building_defs: Dictionary,
	troop_defs: Dictionary,
	next_id: Callable,
	next_troop_id: Callable,
	next_squad_id: Callable,
) -> Dictionary:
	var standalone_buildings: Array[BuildingInstance] = []
	var barbarian_outposts: Array[BarbarianOutpostInstance] = []
	var squads: Array[SquadInstance] = []
	var troops_by_id: Dictionary = {}

	if outpost_count <= 0 or outpost_defs.is_empty():
		return {
			"standalone_buildings": standalone_buildings, "barbarian_outposts": barbarian_outposts,
			"squads": squads, "troops_by_id": troops_by_id,
		}

	var defs_by_material: Dictionary = {}
	for def in outpost_defs.values():
		defs_by_material[def.get("material", "")] = def

	var capital_hexes: Array[HexCoord] = []
	for base in placed_bases:
		if base_defs.get(base.base_def_id, {}).get("isCapital", false):
			capital_hexes.append(base.hex_coord)

	var rng := _substream(world_seed, "barbarian_outpost_sites")
	var candidates := _shuffled_candidates(map_radius, rng)
	var placed_hexes: Array[HexCoord] = []
	var scanned := 0

	for hex in candidates:
		if placed_hexes.size() >= outpost_count:
			break
		if scanned >= Tuning.BARBARIAN_OUTPOST_MAX_CANDIDATES_SCANNED:
			break
		scanned += 1

		var terrain := grid.get_terrain(hex)
		if terrain == Terrain.Type.OCEAN or terrain == Terrain.Type.RIVER:
			continue
		if not _spacing_ok(hex, placed_bases, placed_hexes):
			continue

		var def := _tier_def_for(hex, capital_hexes, map_radius, defs_by_material)
		if def.is_empty():
			continue

		var result := BuildingPlacement.place_standalone_building(placed_bases, standalone_buildings, def.get("buildingType", ""), hex, grid, building_defs, next_id.call(), BaseSiteSelector.NEUTRAL_OWNER_ID, def.get("material", ""))
		if result != BuildingPlacement.Result.OK:
			continue
		var building: BuildingInstance = standalone_buildings[standalone_buildings.size() - 1]

		var squads_before := squads.size()
		GarrisonFactory.seed_garrison({"initialGarrison": def.get("garrison", [])}, BaseSiteSelector.NEUTRAL_OWNER_ID, hex, troop_defs, squads, troops_by_id, next_troop_id, next_squad_id, grid)
		var guard_squad_ids: Array[String] = []
		for i in range(squads_before, squads.size()):
			guard_squad_ids.append(squads[i].id)

		barbarian_outposts.append(BarbarianOutpostInstance.new(next_id.call(), building.id, guard_squad_ids, (def.get("loot", {}) as Dictionary).duplicate()))
		placed_hexes.append(hex)

	return {
		"standalone_buildings": standalone_buildings, "barbarian_outposts": barbarian_outposts,
		"squads": squads, "troops_by_id": troops_by_id,
	}

static func _spacing_ok(candidate: HexCoord, placed_bases: Array[BaseInstance], placed_outposts: Array[HexCoord]) -> bool:
	for base in placed_bases:
		if HexCoord.distance(candidate, base.hex_coord) < Tuning.BARBARIAN_OUTPOST_MIN_SPACING_FROM_BASE:
			return false
	for hex in placed_outposts:
		if HexCoord.distance(candidate, hex) < Tuning.BARBARIAN_OUTPOST_MIN_SPACING_FROM_OUTPOST:
			return false
	return true

## closest_capital_distance/map_radius, bucketed into wood (near)/stone (mid)/
## steel (far) via Tuning.BARBARIAN_TIER_NEAR_FRACTION/FAR_FRACTION. No
## Capitals placed (player_count == 0, siting-only tests) defaults to the
## toughest tier — a rare edge case, not a real match state.
static func _tier_def_for(candidate: HexCoord, capital_hexes: Array[HexCoord], map_radius: int, defs_by_material: Dictionary) -> Dictionary:
	var material := "steel"
	if not capital_hexes.is_empty():
		var closest: int = HexCoord.distance(candidate, capital_hexes[0])
		for i in range(1, capital_hexes.size()):
			closest = min(closest, HexCoord.distance(candidate, capital_hexes[i]))
		var fraction := float(closest) / float(map_radius)
		if fraction < Tuning.BARBARIAN_TIER_NEAR_FRACTION:
			material = "wood"
		elif fraction < Tuning.BARBARIAN_TIER_FAR_FRACTION:
			material = "stone"
	return defs_by_material.get(material, {})

static func _substream(world_seed: int, label: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [world_seed, label])
	return rng

static func _shuffled_candidates(map_radius: int, rng: RandomNumberGenerator) -> Array[HexCoord]:
	var candidates := HexCoord.range_within(HexCoord.new(0, 0), map_radius)
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: HexCoord = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	return candidates
