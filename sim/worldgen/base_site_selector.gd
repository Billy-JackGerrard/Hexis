## Base-def assignment (Capital per player + 2 distinct Unique defs per
## player, drawn RANDOMLY from the authored roster — not every authored
## Unique base type appears on a given map) and site selection against an
## ALREADY-GENERATED grid (see TerrainGenerator). Runs strictly after
## terrain generation is finished — this is the deliberate point where the
## design doc's "a river can't wall off a Capital's expansion paths" balance
## constraint is enforced: a candidate Capital site is rejected outright if
## it fails has_viable_expansion(), rather than the river generator trying
## to reason about bases it doesn't know about yet.
##
## Terrain requirement for a base's flower (HQ hex + its 6 neighbors) is
## Plains by default, or the base_def's terrainException terrain (Forest for
## Treehouse, Hill for Windy Peaks) when set — see _hq_site_terrain/
## _flower_terrain_ok. Treehouse additionally requires its flower sit deep
## inside a substantial Forest patch, not just touching one Forest tile —
## see _is_deep_forest_site. Sky Fortress's moat is carved to connect to an
## existing River/Ocean tile, not left as an isolated pond — see
## _carve_channel.
class_name BaseSiteSelector
extends RefCounted

## Owner id for Unique bases and their standing garrisons at world-gen time —
## per 01-map-and-terrain.md/02-bases-and-buildings.md, Unique bases are
## neutral city-states until a player captures one (HQ capture-flip already
## reassigns base.owner_id; CombatTargeting's owner_id-inequality check
## already treats this as hostile to every player without any extra wiring).
const NEUTRAL_OWNER_ID := "neutral"

## Tunable constants (MIN_BASE_SPACING, CAPITAL_MIN_SPACING, moat/expansion
## bounds, ...) live in sim/tuning.gd (Tuning) rather than here — see that
## file for the full list and rationale.

## Result of a full placement pass. `bases` is empty and `failure_reason` is
## set on failure — callers (MapGenerator) treat empty bases as "this
## attempt failed, try a fresh seed". `next_id` is a Callable returning a
## fresh unique id string per call. `forced_unique_ids` is a TEST-ONLY hook:
## normal callers never pass it (production always draws randomly); tests
## use it to deterministically force e.g. Kraken Point or Sky Fortress onto
## a map instead of hoping a random seed happens to draw them.
##
## `troop_defs`/`next_troop_id`/`next_squad_id` drive GarrisonFactory seeding
## each placed base's `initialGarrison` — all three are optional (empty
## dict / invalid Callable) so callers that don't care about garrisons (e.g.
## siting-only tests) can omit them and get empty `squads`/`troops_by_id`
## back instead of being forced to wire up id generators they don't need.
static func place_bases(
	grid: HexGrid,
	player_count: int,
	world_seed: int,
	base_defs: Dictionary,
	building_defs: Dictionary,
	next_id: Callable,
	forced_unique_ids: Array[String] = [],
	troop_defs: Dictionary = {},
	next_troop_id: Callable = Callable(),
	next_squad_id: Callable = Callable(),
) -> Dictionary:
	var capital_def: Dictionary = base_defs.get("capital", {})
	var unique_defs: Array = []
	for def in base_defs.values():
		if not def.get("isCapital", false):
			unique_defs.append(def)

	if unique_defs.size() < player_count * 2:
		return {
			"bases": [], "capital_ids_by_player": {},
			"failure_reason": "insufficient_unique_base_defs: need %d, have %d" % [player_count * 2, unique_defs.size()],
		}

	var map_radius := TerrainGenerator.map_radius(player_count)
	var placed_bases: Array[BaseInstance] = []
	var claimed_hexes: Dictionary = {}
	var capital_ids_by_player: Dictionary = {}
	var capital_rng := _substream(world_seed, "site_capitals")
	var squads: Array[SquadInstance] = []
	var troops_by_id: Dictionary = {}
	var seed_garrisons: bool = next_troop_id.is_valid() and next_squad_id.is_valid()

	for p in range(player_count):
		var hex = _find_site(grid, map_radius, placed_bases, base_defs, claimed_hexes, capital_def, Callable(), capital_rng)
		if hex == null:
			return {"bases": [], "capital_ids_by_player": {}, "failure_reason": "no_valid_capital_site_for_player_%d" % p}
		var base: BaseInstance = BaseFactory.seed_base(next_id.call(), capital_def, "p%d" % p, hex, grid, building_defs)
		placed_bases.append(base)
		_claim(claimed_hexes, hex)
		capital_ids_by_player[p] = base.id
		if seed_garrisons:
			GarrisonFactory.seed_garrison(capital_def, "p%d" % p, hex, troop_defs, squads, troops_by_id, next_troop_id, next_squad_id, grid, base)

	var deal := _assign_unique_defs(unique_defs, player_count, _substream(world_seed, "unique_defs"), forced_unique_ids)
	var unique_rng := _substream(world_seed, "site_uniques")
	for entry in deal:
		var def: Dictionary = entry["def"]
		var base_id: String = def.get("id", "")
		var predicate := Callable()
		if base_id == "kraken_point":
			predicate = Callable(BaseSiteSelector, "_is_ocean_edge_site").bind(map_radius)
		elif base_id == "treehouse":
			predicate = Callable(BaseSiteSelector, "_is_deep_forest_site")
		elif base_id == "sky_fortress":
			predicate = Callable(BaseSiteSelector, "_sky_fortress_site_ok").bind(claimed_hexes)
		elif base_id == "rivergate":
			predicate = Callable(BaseSiteSelector, "_is_river_adjacent_site")
		var hex = _find_site(grid, map_radius, placed_bases, base_defs, claimed_hexes, def, predicate, unique_rng)
		if hex == null:
			return {"bases": [], "capital_ids_by_player": {}, "failure_reason": "no_valid_site_for_%s" % base_id}
		var base: BaseInstance = BaseFactory.seed_base(next_id.call(), def, NEUTRAL_OWNER_ID, hex, grid, building_defs)
		placed_bases.append(base)
		_claim(claimed_hexes, hex)
		if seed_garrisons:
			GarrisonFactory.seed_garrison(def, NEUTRAL_OWNER_ID, hex, troop_defs, squads, troops_by_id, next_troop_id, next_squad_id, grid)
		if base_id == "sky_fortress":
			# Channel carved on pristine terrain FIRST, moat second — carving
			# the moat first would turn the ring itself into water, making
			# the "is this ring already touching pre-existing water"
			# connectivity check for the channel trivially true afterward.
			_carve_channel(hex, grid, claimed_hexes)
			_carve_moat(hex, grid, claimed_hexes)

	return {
		"bases": placed_bases, "capital_ids_by_player": capital_ids_by_player, "failure_reason": "",
		"squads": squads, "troops_by_id": troops_by_id,
	}

## Public so tests and MapGenerator can call it directly against a
## hand-built grid fixture without going through the full random pipeline.
static func has_viable_expansion(hq_hex: HexCoord, grid: HexGrid) -> bool:
	var visited: Dictionary = {hq_hex.to_key(): true}
	var frontier: Array[HexCoord] = [hq_hex]
	var sextant_counts: Array[int] = [0, 0, 0, 0, 0, 0]
	var depth := 0
	while not frontier.is_empty() and depth < Tuning.EXPANSION_CHECK_RADIUS:
		depth += 1
		var next_frontier: Array[HexCoord] = []
		for hex in frontier:
			for n in HexCoord.neighbors(hex):
				var key := n.to_key()
				if visited.has(key):
					continue
				visited[key] = true
				if not grid.has_hex(n) or not Terrain.is_passable(grid.get_terrain(n), Terrain.Domain.LAND):
					continue
				sextant_counts[_sextant(hq_hex, n)] += 1
				next_frontier.append(n)
		frontier = next_frontier
	var viable_sextants := 0
	for count in sextant_counts:
		if count >= Tuning.EXPANSION_SEXTANT_MIN_HEXES:
			viable_sextants += 1
	return viable_sextants >= Tuning.EXPANSION_MIN_VIABLE_SEXTANTS

## Buckets `hex` into one of 6 angular sextants relative to `hq_hex`, via a
## flat-top axial->cartesian conversion.
static func _sextant(hq_hex: HexCoord, hex: HexCoord) -> int:
	var dq := hex.q - hq_hex.q
	var dr := hex.r - hq_hex.r
	var px := 1.5 * dq
	var py := sqrt(3.0) * (dr + dq / 2.0)
	var angle := atan2(py, px)
	return int(fposmod(angle, TAU) / (PI / 3.0)) % 6

static func _find_site(
	grid: HexGrid,
	map_radius: int,
	placed_bases: Array[BaseInstance],
	base_defs: Dictionary,
	claimed_hexes: Dictionary,
	base_def: Dictionary,
	extra_predicate: Callable,
	rng: RandomNumberGenerator,
) -> Variant:
	var is_capital: bool = base_def.get("isCapital", false)
	var candidates := _shuffled_candidates(map_radius, rng)
	var scanned := 0
	for h in candidates:
		if scanned >= Tuning.MAX_SITE_CANDIDATES_SCANNED:
			break
		scanned += 1
		if not _flower_terrain_ok(h, grid, base_def):
			continue
		if _flower_claimed(h, claimed_hexes):
			continue
		if not _spacing_ok(h, placed_bases, base_defs, is_capital):
			continue
		if extra_predicate.is_valid() and not extra_predicate.call(h, grid):
			continue
		if is_capital and not has_viable_expansion(h, grid):
			continue
		return h
	return null

static func _shuffled_candidates(map_radius: int, rng: RandomNumberGenerator) -> Array[HexCoord]:
	var candidates := HexCoord.range_within(HexCoord.new(0, 0), map_radius)
	for i in range(candidates.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: HexCoord = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = tmp
	return candidates

## Plains by default; the base's terrainException terrain (if set) replaces
## Plains for the WHOLE flower, not just the center hex — matches
## data/bases/treehouse.json/windy_peaks.json's own notes that the base's
## seed hex is what deviates for these two types specifically. Every other
## type (including Kraken Point/Rivergate) is still Plains-only at siting
## time; their water-adjacency need is checked separately via
## _is_ocean_edge_site, not via this mechanism.
static func _hq_site_terrain(base_def: Dictionary) -> Terrain.Type:
	match base_def.get("terrainException", ""):
		"Forest":
			return Terrain.Type.FOREST
		"Hill":
			return Terrain.Type.HILLS
		_:
			return Terrain.Type.PLAINS

static func _flower_terrain_ok(candidate: HexCoord, grid: HexGrid, base_def: Dictionary) -> bool:
	var required := _hq_site_terrain(base_def)
	if grid.get_terrain(candidate) != required:
		return false
	for n in HexCoord.neighbors(candidate):
		if grid.get_terrain(n) != required:
			return false
	return true

static func _flower_claimed(candidate: HexCoord, claimed_hexes: Dictionary) -> bool:
	if claimed_hexes.has(candidate.to_key()):
		return true
	for n in HexCoord.neighbors(candidate):
		if claimed_hexes.has(n.to_key()):
			return true
	return false

static func _spacing_ok(candidate: HexCoord, placed_bases: Array[BaseInstance], base_defs: Dictionary, is_capital: bool) -> bool:
	for b in placed_bases:
		var d := HexCoord.distance(candidate, b.hex_coord)
		if d < Tuning.MIN_BASE_SPACING:
			return false
		if is_capital and base_defs.get(b.base_def_id, {}).get("isCapital", false) and d < Tuning.CAPITAL_MIN_SPACING:
			return false
	return true

static func _claim(claimed_hexes: Dictionary, hq_hex: HexCoord) -> void:
	claimed_hexes[hq_hex.to_key()] = true
	for n in HexCoord.neighbors(hq_hex):
		claimed_hexes[n.to_key()] = true

## "found along the map's ocean edge" (data/bases/kraken_point.json) — near
## the true coastline (a distance-from-center floor, not just any interior
## water body) AND actually touching an Ocean tile.
static func _is_ocean_edge_site(candidate: HexCoord, grid: HexGrid, map_radius: int) -> bool:
	var origin := HexCoord.new(0, 0)
	if HexCoord.distance(origin, candidate) < map_radius - Tuning.KRAKEN_EDGE_INSET:
		return false
	for h in HexCoord.ring(candidate, 2):
		if grid.has_hex(h) and grid.get_terrain(h) == Terrain.Type.OCEAN:
			return true
	return false

## "must sit next to the river to actually cover the crossing"
## (data/bases/rivergate.json's notes). Unlike Kraken Point's ocean-edge
## check, this has no distance-from-center floor — a River can run anywhere
## inland — it just needs a River tile within reach of the flower, same
## ring-2 margin as Kraken Point's ocean check so seed_base's water-adjacency
## buildings (Water Turret, Ford Yard) can always find a qualifying hex
## within Tuning.MAX_SEED_SEARCH_RING.
static func _is_river_adjacent_site(candidate: HexCoord, grid: HexGrid) -> bool:
	for h in HexCoord.ring(candidate, 2):
		if grid.has_hex(h) and grid.get_terrain(h) == Terrain.Type.RIVER:
			return true
	return false

## "found in a large forest biome... on and surrounded by forest" — most of
## the hexes within Tuning.TREEHOUSE_FOREST_DEPTH rings of the candidate must be
## Forest (the flower itself, checked separately by _flower_terrain_ok, is
## always 100% Forest — this is the looser "surrounded by" halo beyond it).
static func _is_deep_forest_site(candidate: HexCoord, grid: HexGrid) -> bool:
	var region := HexCoord.range_within(candidate, Tuning.TREEHOUSE_FOREST_DEPTH)
	var forest_count := 0
	for h in region:
		if grid.get_terrain(h) == Terrain.Type.FOREST:
			forest_count += 1
	return float(forest_count) / float(region.size()) >= Tuning.TREEHOUSE_FOREST_COVERAGE_FRACTION

static func _has_viable_moat_ring(candidate: HexCoord, grid: HexGrid, claimed_hexes: Dictionary) -> bool:
	var ring := HexCoord.ring(candidate, Tuning.MOAT_INNER_RADIUS)
	var convertible := 0
	for h in ring:
		if grid.has_hex(h) and not claimed_hexes.has(h.to_key()) and grid.get_terrain(h) != Terrain.Type.RIVER:
			convertible += 1
	return float(convertible) / float(ring.size()) >= Tuning.MOAT_MIN_COVERAGE_FRACTION

## Combines the ring-coverage check with a channel-reachability dry run — a
## moat that can't reach existing water within Tuning.MOAT_CHANNEL_MAX_LENGTH is
## rejected as a site, not silently left disconnected.
static func _sky_fortress_site_ok(candidate: HexCoord, grid: HexGrid, claimed_hexes: Dictionary) -> bool:
	if not _has_viable_moat_ring(candidate, grid, claimed_hexes):
		return false
	var ring := HexCoord.ring(candidate, Tuning.MOAT_INNER_RADIUS)
	return not _bfs_to_nearest_water(ring, grid, claimed_hexes, Tuning.MOAT_CHANNEL_MAX_LENGTH).is_empty()

## Terrain-cost-agnostic hex-adjacency BFS from any of `from_hexes` (the
## moat ring) to the nearest River/Ocean tile — we're terraforming a channel
## through whatever's there (Plains/Forest/Hills), not pathing a unit, so
## domain movement cost is irrelevant (HexGrid.find_path is deliberately not
## reused for this — it's A* over domain edge costs, not a fit for "dig
## through anything"). Never crosses a claimed_hexes hex (won't dig through
## another base's flower). If a `from_hexes` tile is itself already
## River/Ocean (the ring naturally overlaps existing water), that's an
## immediate connection. Returns the full path (both endpoints included) or
## [] if nothing reachable within max_length steps.
static func _bfs_to_nearest_water(from_hexes: Array, grid: HexGrid, claimed_hexes: Dictionary, max_length: int) -> Array:
	for h in from_hexes:
		var terrain: Terrain.Type = grid.get_terrain(h)
		if terrain == Terrain.Type.RIVER or terrain == Terrain.Type.OCEAN:
			return [h]

	var visited: Dictionary = {}
	var came_from: Dictionary = {}
	var frontier: Array = from_hexes.duplicate()
	for h in from_hexes:
		visited[h.to_key()] = true
	var steps := 0
	while not frontier.is_empty() and steps < max_length:
		steps += 1
		var next_frontier: Array = []
		for hex in frontier:
			for n in HexCoord.neighbors(hex):
				var key: String = n.to_key()
				if visited.has(key) or claimed_hexes.has(key) or not grid.has_hex(n):
					continue
				visited[key] = true
				came_from[key] = hex
				var terrain: Terrain.Type = grid.get_terrain(n)
				if terrain == Terrain.Type.RIVER or terrain == Terrain.Type.OCEAN:
					return _reconstruct_path(n, came_from)
				next_frontier.append(n)
		frontier = next_frontier
	return []

static func _reconstruct_path(end: HexCoord, came_from: Dictionary) -> Array:
	var path: Array = [end]
	var current := end
	while came_from.has(current.to_key()):
		current = came_from[current.to_key()]
		path.push_front(current)
	return path

static func _carve_moat(hq_hex: HexCoord, grid: HexGrid, claimed_hexes: Dictionary) -> void:
	for h in HexCoord.ring(hq_hex, Tuning.MOAT_INNER_RADIUS):
		if grid.has_hex(h) and not claimed_hexes.has(h.to_key()) and grid.get_terrain(h) != Terrain.Type.RIVER:
			grid.set_terrain(h, Terrain.Type.OCEAN)

static func _carve_channel(hq_hex: HexCoord, grid: HexGrid, claimed_hexes: Dictionary) -> void:
	var ring := HexCoord.ring(hq_hex, Tuning.MOAT_INNER_RADIUS)
	var path := _bfs_to_nearest_water(ring, grid, claimed_hexes, Tuning.MOAT_CHANNEL_MAX_LENGTH)
	for hex in path:
		var terrain: Terrain.Type = grid.get_terrain(hex)
		if terrain != Terrain.Type.RIVER and terrain != Terrain.Type.OCEAN:
			grid.set_terrain(hex, Terrain.Type.OCEAN)

## Draws exactly player_count*2 Unique defs (never all 13 authored types —
## per 01-map-and-terrain.md's "2 Unique bases per player" ratio) and deals
## 2 to each player. `forced_ids` (test-only) are guaranteed included; the
## remaining slots are filled by a seeded shuffle of the rest of the roster.
## Kraken Point/Sky Fortress entries (if drawn) are sorted first so they're
## sited — and, for Sky Fortress, moated — while the map still has maximal
## free terrain to choose from.
static func _assign_unique_defs(unique_defs: Array, player_count: int, rng: RandomNumberGenerator, forced_ids: Array[String]) -> Array:
	var needed := player_count * 2
	var forced: Array = []
	var remaining_pool: Array = []
	for def in unique_defs:
		if forced_ids.has(def.get("id", "")):
			forced.append(def)
		else:
			remaining_pool.append(def)

	for i in range(remaining_pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = remaining_pool[i]
		remaining_pool[i] = remaining_pool[j]
		remaining_pool[j] = tmp

	var drawn: Array = forced.duplicate()
	for def in remaining_pool:
		if drawn.size() >= needed:
			break
		drawn.append(def)

	for i in range(drawn.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = drawn[i]
		drawn[i] = drawn[j]
		drawn[j] = tmp

	var pairs: Array = []
	for p in range(player_count):
		pairs.append({"player_index": p, "def": drawn[2 * p]})
		pairs.append({"player_index": p, "def": drawn[2 * p + 1]})

	var kraken: Array = []
	var sky: Array = []
	var rest: Array = []
	for entry in pairs:
		var base_id: String = entry["def"].get("id", "")
		if base_id == "kraken_point":
			kraken.append(entry)
		elif base_id == "sky_fortress":
			sky.append(entry)
		else:
			rest.append(entry)
	return kraken + sky + rest

static func _substream(world_seed: int, label: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [world_seed, label])
	return rng
