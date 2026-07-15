## Procedural terrain generation: hexagon landmass + a narrow, strategically
## navigable ocean fringe, Forest/Hill biome clusters, and rivers. Pure grid
## mutation, no base/player knowledge — sim/worldgen/base_site_selector.gd
## sites bases against the finished grid afterward (a river's "can't wall off
## a Capital's expansion" balance constraint is enforced there, not here,
## since this generator has no knowledge of where bases will go).
class_name TerrainGenerator
extends RefCounted

## Tunable constants (map radius, biome/river budgets, ...) live in
## sim/tuning.gd (Tuning) rather than here — see that file for the full list
## and rationale.

static func map_radius(player_count: int) -> int:
	return Tuning.MAP_RADIUS_BASE + player_count * Tuning.MAP_RADIUS_PER_PLAYER

static func num_rivers(player_count: int) -> int:
	return Tuning.RIVER_BASE_COUNT + (player_count - 2) / 2

## Entry point: builds hexagon+fringe, then biomes, then rivers, in that
## fixed order (biomes before rivers so a river can flow through/skirt
## existing patches realistically — a river tile always overwrites whatever
## biome was there, since it's generated last).
static func generate_all(player_count: int, world_seed: int) -> HexGrid:
	var radius := map_radius(player_count)
	var grid := generate_base_terrain(radius, Tuning.OCEAN_FRINGE_WIDTH)
	generate_biomes(grid, radius, world_seed)
	generate_rivers(grid, radius, world_seed, player_count)
	return grid

## Hexagon of Plains out to `radius`, plus a `fringe_width`-wide Ocean ring
## beyond it. No biomes/rivers yet — independently testable slice.
static func generate_base_terrain(radius: int, fringe_width: int) -> HexGrid:
	var grid := HexGrid.new()
	var origin := HexCoord.new(0, 0)
	for hex in HexCoord.range_within(origin, radius + fringe_width):
		var terrain := Terrain.Type.PLAINS if HexCoord.distance(origin, hex) <= radius else Terrain.Type.OCEAN
		grid.set_terrain(hex, terrain)
	return grid

## Mutates `grid` in place, converting PLAINS hexes to HILLS/FOREST in
## organic blob clusters. Two independent passes (Hills then Forest) so a
## later Forest seed simply can't land on a hex Hills already claimed
## (checked via current terrain == PLAINS).
static func generate_biomes(grid: HexGrid, radius: int, world_seed: int) -> void:
	var interior_area := 3 * radius * radius + 3 * radius + 1
	_grow_biome(grid, radius, Terrain.Type.HILLS, int(interior_area * Tuning.HILLS_COVERAGE_FRACTION), _substream(world_seed, "biomes_hills"))
	_grow_biome(grid, radius, Terrain.Type.FOREST, int(interior_area * Tuning.FOREST_COVERAGE_FRACTION), _substream(world_seed, "biomes_forest"))

static func _grow_biome(grid: HexGrid, radius: int, terrain: Terrain.Type, budget: int, rng: RandomNumberGenerator) -> void:
	var origin := HexCoord.new(0, 0)
	var placed := 0
	var seed_centers: Array[HexCoord] = []
	var attempts := 0
	while placed < budget and attempts < Tuning.MAX_BIOME_SEED_ATTEMPTS:
		attempts += 1
		var candidate := _random_hex_in_disk(origin, radius - Tuning.BIOME_EDGE_BUFFER, rng)
		if grid.get_terrain(candidate) != Terrain.Type.PLAINS:
			continue
		var too_close := false
		for existing in seed_centers:
			if HexCoord.distance(candidate, existing) < Tuning.MIN_BIOME_SEED_SPACING:
				too_close = true
				break
		if too_close:
			continue
		seed_centers.append(candidate)
		var target_size := _roll_patch_size(rng)
		placed += _grow_patch(grid, radius, candidate, terrain, target_size, rng)

## Randomized flood-fill from `seed_hex`, converting up to `target_size`
## PLAINS hexes to `terrain`. Returns the actual number converted (may be
## less than target_size if the frontier runs out near the coast or another
## biome). Jitter (Tuning.BIOME_GROWTH_JITTER) skips some valid neighbors so the
## blob isn't a perfect disk.
static func _grow_patch(grid: HexGrid, radius: int, seed_hex: HexCoord, terrain: Terrain.Type, target_size: int, rng: RandomNumberGenerator) -> int:
	var origin := HexCoord.new(0, 0)
	var converted := 0
	var frontier: Array[HexCoord] = [seed_hex]
	var visited: Dictionary = {}
	while converted < target_size and not frontier.is_empty():
		var idx := rng.randi_range(0, frontier.size() - 1)
		var hex: HexCoord = frontier[idx]
		frontier.remove_at(idx)
		var key := hex.to_key()
		if visited.has(key):
			continue
		visited[key] = true
		if HexCoord.distance(origin, hex) > radius or grid.get_terrain(hex) != Terrain.Type.PLAINS:
			continue
		grid.set_terrain(hex, terrain)
		converted += 1
		for n in HexCoord.neighbors(hex):
			if not visited.has(n.to_key()) and rng.randf() > Tuning.BIOME_GROWTH_JITTER:
				frontier.append(n)
	return converted

static func _roll_patch_size(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	var range_pick: Vector2i = Tuning.SMALL_PATCH_RANGE
	if roll > Tuning.PATCH_SIZE_WEIGHTS[0] + Tuning.PATCH_SIZE_WEIGHTS[1]:
		range_pick = Tuning.LARGE_PATCH_RANGE
	elif roll > Tuning.PATCH_SIZE_WEIGHTS[0]:
		range_pick = Tuning.MEDIUM_PATCH_RANGE
	return rng.randi_range(range_pick.x, range_pick.y)

## Generates num_rivers(player_count) connected River paths, each running
## from an inland source to the coastline (a constrained random walk biased
## outward). Returns the paths (not just mutating the grid) so callers/tests
## can inspect connectivity directly. Balance-constraint validation (does a
## river wall off a Capital?) happens later, in BaseSiteSelector — this
## method has no knowledge of bases.
static func generate_rivers(grid: HexGrid, radius: int, world_seed: int, player_count: int) -> Array:
	var rng := _substream(world_seed, "rivers")
	var origin := HexCoord.new(0, 0)
	var paths: Array = []
	var sources: Array[HexCoord] = []
	var count := num_rivers(player_count)
	var attempts := 0
	while paths.size() < count and attempts < count * Tuning.MAX_RIVER_SOURCE_ATTEMPTS_PER_RIVER:
		attempts += 1
		var source := _random_hex_in_disk(origin, max(radius - Tuning.RIVER_MIN_LENGTH, 0), rng)
		# Rivers reading as starting in the highlands: snap the candidate onto
		# the nearest Hills tile within a short search, if one's nearby (runs
		# after the biome pass above, so Hills already exist on the grid).
		# Falls back to the unsnapped candidate when no Hills tile is close,
		# so this never breaks river generation on a hill-poor map.
		source = _nearest_hill_hex(grid, source, Tuning.RIVER_SOURCE_HILL_SEARCH_RADIUS)
		var too_close := false
		for existing in sources:
			if HexCoord.distance(source, existing) < Tuning.MIN_RIVER_SOURCE_SPACING:
				too_close = true
				break
		if too_close:
			continue
		sources.append(source)
		var path := _walk_river(origin, radius, source, rng)
		for hex in path:
			grid.set_terrain(hex, Terrain.Type.RIVER)
		paths.append(path)
	return paths

static func _walk_river(origin: HexCoord, radius: int, source: HexCoord, rng: RandomNumberGenerator) -> Array:
	var path: Array[HexCoord] = [source]
	var current := source
	var steps := 0
	var max_steps := radius * Tuning.RIVER_MAX_STEPS_MULTIPLIER
	while HexCoord.distance(origin, current) < radius and steps < max_steps:
		steps += 1
		var current_dist := HexCoord.distance(origin, current)
		var candidates: Array[HexCoord] = []
		for n in HexCoord.neighbors(current):
			if HexCoord.distance(origin, n) >= current_dist:
				candidates.append(n)
		if candidates.is_empty():
			break
		var chosen: HexCoord
		if rng.randf() < Tuning.RIVER_STRAIGHTNESS:
			chosen = candidates[0]
			var best_dist := HexCoord.distance(origin, chosen)
			for c in candidates:
				var d := HexCoord.distance(origin, c)
				if d > best_dist:
					best_dist = d
					chosen = c
		else:
			chosen = candidates[rng.randi_range(0, candidates.size() - 1)]
		current = chosen
		path.append(current)
	return path

## BFS outward from `from` for the nearest Hills hex, `max_radius` hexes out
## at most — returns `from` unchanged if it's already Hills or nothing
## qualifies nearby. Same shape as HexGrid.nearest_passable_hex but keyed on
## a specific Terrain.Type instead of domain passability.
static func _nearest_hill_hex(grid: HexGrid, from: HexCoord, max_radius: int) -> HexCoord:
	if grid.get_terrain(from) == Terrain.Type.HILLS:
		return from
	var visited: Dictionary = {from.to_key(): true}
	var frontier: Array[HexCoord] = [from]
	var r := 0
	while r < max_radius and not frontier.is_empty():
		r += 1
		var next_frontier: Array[HexCoord] = []
		for hex in frontier:
			for n in HexCoord.neighbors(hex):
				var key := n.to_key()
				if visited.has(key) or not grid.has_hex(n):
					continue
				visited[key] = true
				if grid.get_terrain(n) == Terrain.Type.HILLS:
					return n
				next_frontier.append(n)
		frontier = next_frontier
	return from

## Uniform-ish random hex within `radius` of `center`, reusing
## range_within's own axial-disk math rather than rejection-sampling a
## bounding box.
static func _random_hex_in_disk(center: HexCoord, radius: int, rng: RandomNumberGenerator) -> HexCoord:
	var r: int = max(radius, 0)
	var dq := rng.randi_range(-r, r)
	var r_min: int = max(-r, -dq - r)
	var r_max: int = min(r, -dq + r)
	var dr := rng.randi_range(r_min, r_max)
	return HexCoord.new(center.q + dq, center.r + dr)

## Deterministic, independent RNG substream per generation phase, so e.g.
## changing river count never perturbs biome placement for the same seed —
## keeps each phase's output stable in isolation, which the determinism
## tests rely on.
static func _substream(world_seed: int, label: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%s" % [world_seed, label])
	return rng
