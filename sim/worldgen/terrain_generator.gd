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

## Entry point: builds hexagon+fringe, then biomes, then rivers, then (maybe)
## a super river, then elevation, in that fixed order (biomes before rivers so
## a river can flow through/skirt existing patches realistically — a river tile
## always overwrites whatever biome was there, since it's generated last; the
## super river runs last of all so it can freely cross normal rivers/biomes
## too). Elevation runs dead last, after every terrain type is final, so it
## only ever raises hexes that are still Hills — a river carved through a hill
## range stays at lowland height, which is both what water does and what keeps
## the channel from having to climb a cliff.
static func generate_all(player_count: int, world_seed: int) -> HexGrid:
	var radius := map_radius(player_count)
	var grid := generate_base_terrain(radius, Tuning.OCEAN_FRINGE_WIDTH)
	generate_biomes(grid, radius, world_seed)
	generate_rivers(grid, radius, world_seed, player_count)
	generate_super_river(grid, radius, world_seed)
	generate_elevation(grid, world_seed)
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
## outward), always exactly 1 hex wide. Returns the primary paths (not just
## mutating the grid) so callers/tests can inspect connectivity directly.
## Balance-constraint validation (does a river wall off a Capital?) happens
## later, in BaseSiteSelector — this method has no knowledge of bases.
##
## Each completed river has a Tuning.RIVER_SPLIT_CHANCE chance to fork a
## second branch partway along its course (see _split_river), and while
## walking, a river that steps adjacent to another river's tile has a
## Tuning.RIVER_MERGE_CHANCE chance to flow into it and stop there instead
## of running parallel (see _walk_river). Branches aren't included in the
## returned array — they're grid mutations only, same as the primary path's
## own tiles — since only the primary source-to-coast rivers are the
## "num_rivers(player_count)" contract callers rely on.
static func generate_rivers(grid: HexGrid, radius: int, world_seed: int, player_count: int) -> Array:
	var rng := _substream(world_seed, "rivers")
	var origin := HexCoord.new(0, 0)
	var paths: Array = []
	var sources: Array[HexCoord] = []
	var count := num_rivers(player_count)
	var inset_radius: int = max(radius - Tuning.RIVER_MIN_LENGTH, 0)

	# Rivers reading as starting in the highlands: draw sources directly from
	# the Hills tiles already on the grid (runs after the biome pass above)
	# within the same inland inset every source has to respect anyway, so
	# nearly every river starts on Hills rather than only the ones lucky
	# enough to land within a short snap radius of one.
	var hill_candidates: Array[HexCoord] = []
	for hex in HexCoord.range_within(origin, inset_radius):
		if grid.get_terrain(hex) == Terrain.Type.HILLS:
			hill_candidates.append(hex)

	var attempts := 0
	while paths.size() < count and attempts < count * Tuning.MAX_RIVER_SOURCE_ATTEMPTS_PER_RIVER:
		attempts += 1
		var source: HexCoord
		if not hill_candidates.is_empty():
			source = hill_candidates[rng.randi_range(0, hill_candidates.size() - 1)]
		else:
			# Hill-poor map (or a caller that skipped the biome pass, e.g.
			# a unit test exercising generate_rivers on bare terrain): fall
			# back to the old unsnapped random candidate so this never
			# breaks river generation.
			source = _random_hex_in_disk(origin, inset_radius, rng)
		var too_close := false
		for existing in sources:
			if HexCoord.distance(source, existing) < Tuning.MIN_RIVER_SOURCE_SPACING:
				too_close = true
				break
		if too_close:
			continue
		sources.append(source)
		var path := _walk_river(origin, radius, source, rng, grid)
		for hex in path:
			grid.set_terrain(hex, Terrain.Type.RIVER)
		paths.append(path)
		if path.size() > 2 and rng.randf() < Tuning.RIVER_SPLIT_CHANCE:
			_split_river(grid, origin, radius, path, rng)
	return paths

## Rolled once per completed river (Tuning.RIVER_SPLIT_CHANCE): picks a
## random interior hex along `path` and peels a second branch off toward the
## coast from there, giving the river a natural fork. The branch is walked
## and committed straight to the grid — not returned as its own path, same
## reasoning as generate_rivers' docstring (it's still real River terrain,
## it just isn't one of the "num_rivers(player_count)" primary rivers).
static func _split_river(grid: HexGrid, origin: HexCoord, radius: int, path: Array, rng: RandomNumberGenerator) -> void:
	var split_index := rng.randi_range(1, path.size() - 2)
	var split_hex: HexCoord = path[split_index]
	var split_dist := HexCoord.distance(origin, split_hex)
	var next_hex: HexCoord = path[split_index + 1]
	var branch_candidates: Array[HexCoord] = []
	for n in HexCoord.neighbors(split_hex):
		if HexCoord.distance(origin, n) >= split_dist and n.to_key() != next_hex.to_key():
			branch_candidates.append(n)
	if branch_candidates.is_empty():
		return
	var branch_source: HexCoord = branch_candidates[rng.randi_range(0, branch_candidates.size() - 1)]
	var branch_path := _walk_river(origin, radius, branch_source, rng, grid)
	for hex in branch_path:
		grid.set_terrain(hex, Terrain.Type.RIVER)

## Tuning.SUPER_RIVER_CHANCE roll for one additional River, distinct from the
## radial hill-to-coast rivers above: a single straight line from one edge of
## the map to the exact opposite edge (HexCoord.line between two boundary
## hexes in opposite directions), always passing through the origin, so it
## reads as a river crossing the whole map through the middle rather than
## draining outward from a highland source. Always exactly 1 hex wide, same
## as every other river. Runs on its own RNG substream, after the normal
## rivers, so it can freely overwrite them (or biome tiles) where they cross
## — that crossing is itself a natural confluence point, same tile logic as
## a normal merge — and never perturbs any other phase's draws for the same
## seed. Returns the primary line path, or [] if the chance roll fails.
static func generate_super_river(grid: HexGrid, radius: int, world_seed: int) -> Array:
	var rng := _substream(world_seed, "super_river")
	if rng.randf() >= Tuning.SUPER_RIVER_CHANCE:
		return []

	var origin := HexCoord.new(0, 0)
	var direction := rng.randi_range(0, 5)
	var opposite := (direction + 3) % 6
	var from := HexCoord.new(origin.q + HexCoord.DIRECTIONS[direction].x * radius, origin.r + HexCoord.DIRECTIONS[direction].y * radius)
	var to := HexCoord.new(origin.q + HexCoord.DIRECTIONS[opposite].x * radius, origin.r + HexCoord.DIRECTIONS[opposite].y * radius)
	var path := HexCoord.line(from, to)
	for hex in path:
		grid.set_terrain(hex, Terrain.Type.RIVER)
	return path

## Mutates `grid` in place, assigning every Hills hex a height level (see
## HexGrid.set_elevation); every other terrain stays at lowland 0. Runs on its
## own RNG substream so adding it doesn't perturb any earlier phase's draws for
## an existing seed.
##
## Shape of a hill range: each contiguous Hills patch is split into a rim (any
## Hills hex touching non-Hills) at Tuning.HILLS_RIM_ELEVATION and an interior
## plateau at Tuning.HILLS_PEAK_ELEVATION, so the natural way in is two
## single-level slopes. A Tuning.CLIFF_FACE_CHANCE share of rim hexes is then
## promoted to peak height, which makes the edge they share with the lowland
## outside a Terrain.CLIFF_ELEVATION_DELTA drop — a cliff ground troops must
## path around rather than climb. That is the whole point of the pass: the same
## patch is scalable from some directions and sheer from others.
##
## _repair_elevation_reachability afterwards is what makes that safe to
## randomize. Rolling cliff faces independently can otherwise ring a plateau
## (or strand a lone promoted hex) behind cliffs on every side, which would be
## an unreachable island for ground domains; the repair pass walks out from
## lowland and demotes whatever it couldn't reach until everything is climbable
## from somewhere.
static func generate_elevation(grid: HexGrid, world_seed: int) -> void:
	var rng := _substream(world_seed, "elevation")
	for patch in _hill_patches(grid):
		_elevate_patch(grid, patch, rng)
	_repair_elevation_reachability(grid)

## Contiguous Hills components on the grid, each as an Array[HexCoord]. Flood
## fill rather than a single global pass because rim/peak and the minimum ramp
## count are both per-patch properties — two hill ranges that happen to touch
## the same lowland hex are still separate climbs.
static func _hill_patches(grid: HexGrid) -> Array:
	var patches: Array = []
	var seen: Dictionary = {}
	for key in grid.hex_keys():
		var hex := HexCoord.from_key(key)
		if seen.has(key) or grid.get_terrain(hex) != Terrain.Type.HILLS:
			continue
		var patch: Array[HexCoord] = []
		var frontier: Array[HexCoord] = [hex]
		seen[key] = true
		while not frontier.is_empty():
			var current: HexCoord = frontier.pop_back()
			patch.append(current)
			for n in HexCoord.neighbors(current):
				var nk := n.to_key()
				if seen.has(nk) or not grid.has_hex(n) or grid.get_terrain(n) != Terrain.Type.HILLS:
					continue
				seen[nk] = true
				frontier.append(n)
		patches.append(patch)
	return patches

## Rim/peak split plus cliff-face promotion for one patch — see
## generate_elevation. Rim hexes are shuffled before promotion so the ramps
## that survive Tuning.MIN_RAMPS_PER_HILL_PATCH aren't biased toward whichever
## corner of the patch the flood fill happened to visit first.
static func _elevate_patch(grid: HexGrid, patch: Array, rng: RandomNumberGenerator) -> void:
	var rim: Array[HexCoord] = []
	for hex in patch:
		var is_rim := false
		for n in HexCoord.neighbors(hex):
			if not grid.has_hex(n) or grid.get_terrain(n) != Terrain.Type.HILLS:
				is_rim = true
				break
		grid.set_elevation(hex, Tuning.HILLS_RIM_ELEVATION if is_rim else Tuning.HILLS_PEAK_ELEVATION)
		if is_rim:
			rim.append(hex)

	# Fisher-Yates on the caller's own rng, not Array.shuffle() — that draws
	# from Godot's global RNG and would break lockstep determinism.
	for i in range(rim.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := rim[i]
		rim[i] = rim[j]
		rim[j] = tmp

	var ramps_kept := 0
	for i in range(rim.size()):
		# "Could every remaining hex be promoted and still leave enough ramps?"
		# — compares against the hexes not yet decided (rim.size() - i), NOT
		# rim.size() - ramps_kept, which doesn't shrink as the loop consumes
		# candidates and so never fires on a patch bigger than the minimum.
		var remaining := rim.size() - i
		var must_keep := ramps_kept + remaining <= Tuning.MIN_RAMPS_PER_HILL_PATCH
		if not must_keep and rng.randf() < Tuning.CLIFF_FACE_CHANCE:
			grid.set_elevation(rim[i], Tuning.HILLS_PEAK_ELEVATION)
		else:
			ramps_kept += 1

## Guarantees every raised hex is reachable on foot from lowland, by walking
## outward from every elevation-0 hex across edges that aren't cliffs and then
## demoting anything the walk never arrived at. A demoted hex drops to one
## level above its lowest already-reachable neighbour — the smallest change
## that opens a way in — and the walk repeats until nothing is stranded.
## Terminates because every pass either reaches a new hex or lowers at least
## one hex's elevation toward 0.
static func _repair_elevation_reachability(grid: HexGrid) -> void:
	while true:
		var reached := _lowland_reachable_keys(grid)
		var best_key := ""
		var best_target := 0
		for key in grid.hex_keys():
			if reached.has(key):
				continue
			var hex := HexCoord.from_key(key)
			if grid.get_elevation(hex) <= 0:
				continue
			for n in HexCoord.neighbors(hex):
				if not grid.has_hex(n) or not reached.has(n.to_key()):
					continue
				var target: int = grid.get_elevation(n) + Terrain.CLIFF_ELEVATION_DELTA - 1
				if best_key == "" or target > best_target:
					best_key = key
					best_target = target
		if best_key == "":
			return
		grid.set_elevation(HexCoord.from_key(best_key), best_target)

## Keys of every hex a ground unit could stand on having walked from lowland,
## considering elevation only (terrain passability is edge_cost's job — this is
## purely "is the climb physically possible from somewhere").
static func _lowland_reachable_keys(grid: HexGrid) -> Dictionary:
	var reached: Dictionary = {}
	var frontier: Array[HexCoord] = []
	for key in grid.hex_keys():
		var hex := HexCoord.from_key(key)
		if grid.get_elevation(hex) == 0:
			reached[key] = true
			frontier.append(hex)
	while not frontier.is_empty():
		var current: HexCoord = frontier.pop_back()
		for n in HexCoord.neighbors(current):
			var nk := n.to_key()
			if reached.has(nk) or not grid.has_hex(n):
				continue
			if grid.is_cliff_edge(current, n):
				continue
			reached[nk] = true
			frontier.append(n)
	return reached

## `grid` is only consulted (never mutated here — callers commit `path`'s
## own tiles themselves) to detect confluence: an outward step that's
## already another river's tile has a Tuning.RIVER_MERGE_CHANCE chance to
## be taken and end the walk there, rather than carving a parallel channel
## next to it.
static func _walk_river(origin: HexCoord, radius: int, source: HexCoord, rng: RandomNumberGenerator, grid: HexGrid) -> Array:
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

		var river_candidates: Array[HexCoord] = []
		for c in candidates:
			if grid.get_terrain(c) == Terrain.Type.RIVER:
				river_candidates.append(c)
		if not river_candidates.is_empty() and rng.randf() < Tuning.RIVER_MERGE_CHANCE:
			path.append(river_candidates[rng.randi_range(0, river_candidates.size() - 1)])
			return path

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
