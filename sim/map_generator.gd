## Top-level procedural map/base generation entry point — builds terrain
## (TerrainGenerator) then sites every Capital/Unique base against it
## (BaseSiteSelector), retrying the WHOLE pipeline with a fresh derived seed
## if constrained base placement dead-ends on a given terrain roll (simpler
## and more robust than patching a bad terrain layout in place — a river
## that walls off too much of the map, or biome coverage that eats the only
## viable Capital sites, is best fixed by rerolling terrain, not by
## endlessly retrying placement against unusable ground).
##
## Deterministic given (player_count, world_seed): the same inputs always
## retry in the same order and produce the same result (or the same
## failure), since every retry's derived seed is a pure function of
## (world_seed, attempt_index).
##
## Mirrors sim_orchestrator.gd/match_state.gd's placement at sim/ root — a
## cross-cutting top-level driver over sim/worldgen/'s domain algorithms,
## the same relationship SimOrchestrator has to sim/combat/, sim/movement/,
## etc.
class_name MapGenerator
extends RefCounted

## 13 authored Unique base types (13 >= 2*6, < 2*7) — see
## BaseSiteSelector._assign_unique_defs, which never duplicates a Unique
## base type onto one map.
const MAX_SUPPORTED_PLAYER_COUNT: int = 6

## Returns null on unrecoverable failure (player_count too high for the
## authored Unique-base roster, or every retry dead-ended) — callers must
## check for null rather than assume a result. push_error() always precedes
## a null return, describing why, so a failure is loud even outside a test
## harness. `forced_unique_ids` is a test-only pass-through to
## BaseSiteSelector.place_bases — production callers never set it. `troop_defs`
## seeds each placed base's `initialGarrison` (see GarrisonFactory) — optional
## so callers that only care about terrain/base siting can omit it and get
## empty result.squads/result.troops_by_id back.
static func generate(player_count: int, world_seed: int, base_defs: Dictionary, building_defs: Dictionary, forced_unique_ids: Array[String] = [], troop_defs: Dictionary = {}) -> MapGenerationResult:
	if player_count > MAX_SUPPORTED_PLAYER_COUNT:
		push_error("MapGenerator.generate: player_count %d exceeds MAX_SUPPORTED_PLAYER_COUNT %d given the current authored Unique base roster" % [player_count, MAX_SUPPORTED_PLAYER_COUNT])
		return null

	var last_failure_reason := ""
	for attempt in range(Tuning.MAX_GENERATION_ATTEMPTS):
		var attempt_seed: int = world_seed if attempt == 0 else hash("%d:attempt:%d" % [world_seed, attempt])
		var grid := TerrainGenerator.generate_all(player_count, attempt_seed)
		var next_id_counter := {"n": 0}
		var next_id := func() -> String:
			next_id_counter["n"] += 1
			return "base_%d" % next_id_counter["n"]
		# Distinct "garrison_" prefix (not "troop_"/"squad_") so these ids can't
		# collide with a MatchState's own next_troop_id()/next_squad_id()
		# counters once a caller merges result.squads/troops_by_id into a
		# live match — see client/main.gd's _build_demo_state. Left as
		# invalid Callables when troop_defs is empty so BaseSiteSelector's
		# own seed_garrisons gate skips garrison seeding entirely, rather
		# than seeding zero-HP placeholder troops for a caller that never
		# asked for garrisons.
		var next_troop_id := Callable()
		var next_squad_id := Callable()
		if not troop_defs.is_empty():
			var next_troop_id_counter := {"n": 0}
			next_troop_id = func() -> String:
				next_troop_id_counter["n"] += 1
				return "garrison_troop_%d" % next_troop_id_counter["n"]
			var next_squad_id_counter := {"n": 0}
			next_squad_id = func() -> String:
				next_squad_id_counter["n"] += 1
				return "garrison_squad_%d" % next_squad_id_counter["n"]
		var placement := BaseSiteSelector.place_bases(grid, player_count, attempt_seed, base_defs, building_defs, next_id, forced_unique_ids, troop_defs, next_troop_id, next_squad_id)
		if not (placement["bases"] as Array).is_empty() or player_count == 0:
			return MapGenerationResult.new(grid, placement["bases"], placement["capital_ids_by_player"], attempt_seed, placement["squads"], placement["troops_by_id"])
		last_failure_reason = placement["failure_reason"]

	push_error("MapGenerator.generate: exhausted %d attempts for player_count %d, seed %d — last failure: %s" % [Tuning.MAX_GENERATION_ATTEMPTS, player_count, world_seed, last_failure_reason])
	return null

const _TERRAIN_SYMBOLS := {
	Terrain.Type.PLAINS: ".",
	Terrain.Type.FOREST: "F",
	Terrain.Type.HILLS: "^",
	Terrain.Type.RIVER: "~",
	Terrain.Type.OCEAN: "≈",
}

## Dev-only ASCII dump of a generated map to stdout — there's no renderer
## yet, so this is the only way to eyeball whether biomes/rivers/base
## spacing look organic during development. Base hexes are marked with the
## last character of their owner_id. Not covered by assertions; call ad hoc
## from a scratch script, not from the test suite.
static func debug_print(result: MapGenerationResult, player_count: int) -> void:
	if result == null:
		print("MapGenerator.debug_print: null result")
		return
	var radius := TerrainGenerator.map_radius(player_count)
	var fringe := radius + Tuning.OCEAN_FRINGE_WIDTH
	var owner_by_hex: Dictionary = {}
	for base in result.bases:
		owner_by_hex[base.hex_coord.to_key()] = base.owner_id
	var origin := HexCoord.new(0, 0)
	for r in range(-fringe, fringe + 1):
		var line := " ".repeat(abs(r))
		for q in range(-fringe, fringe + 1):
			var hex := HexCoord.new(q, r)
			if HexCoord.distance(origin, hex) > fringe:
				continue
			if not result.grid.has_hex(hex):
				line += "  "
				continue
			var key := hex.to_key()
			if owner_by_hex.has(key):
				line += String(owner_by_hex[key]).right(1) + " "
			else:
				line += String(_TERRAIN_SYMBOLS.get(result.grid.get_terrain(hex), "?")) + " "
		print(line)
