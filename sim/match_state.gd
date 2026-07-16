## The live per-match world: every registry SimOrchestrator/CommandProcessor
## need in order to tick the simulation or resolve a player action. A plain
## data holder, not a system — no logic beyond id generation and the small
## lookups below live here, matching every other class in sim/'s "state on the
## instance, rules in a stateless resolver" split. Introduced alongside the
## top-level tick orchestrator and command layer: both need to thread the same
## dozen registries through every call, so bundling them is what actually
## keeps those two classes' signatures readable, not premature abstraction.
class_name MatchState
extends RefCounted

var squads: Array[SquadInstance] = []
var bases: Array[BaseInstance] = []
var troops_by_id: Dictionary = {} ## id -> TroopInstance
var regiments: Array[RegimentInstance] = []
var standalone_buildings: Array[BuildingInstance] = []
var barbarian_outposts: Array[BarbarianOutpostInstance] = [] ## see sim/outposts/
## Player-facing "this happened" records appended during tick resolution (see
## sim/events/match_event.gd) — drained (read then cleared) by the client once
## per rendered frame, NOT once per tick, since SimClock.advance()/
## LockstepDriver can run several ticks per frame and every one of them must
## accumulate here before the client drains. Deliberately excluded from
## to_dict()/sections()/checksum() below, same as command_log's own exclusion
## — see MatchEvent's own doc comment for why.
var events: Array[MatchEvent] = []
var projectiles: Array[ProjectileInstance] = [] ## in-flight ballistic shots, see ProjectileSystem
var production_queues: Dictionary = {} ## building_id -> ProductionQueue
var players: Dictionary = {} ## owner_id -> Player

var grid: HexGrid
var troop_defs: Dictionary = {}
var building_defs: Dictionary = {}
var base_defs: Dictionary = {}

## VisionSystem/DetectionSystem output — mutated in place each tick by
## SimOrchestrator, same "caller-owns-the-dict" convention those systems
## already use everywhere else.
var visions: Dictionary = {} ## owner_id -> PlayerVision
var detections: Dictionary = {} ## owner_id -> {hex_key: true}

## Memoizes VisionSystem._reveal's per-source revealed-hex-key set, keyed by
## [center_hex_key, vision_range, exempt_terrain] — see vision_system.gd's
## own doc comment for why this is safe (terrain never mutates after
## worldgen, so the same key always yields the same result for the whole
## match). Lives on MatchState rather than a VisionSystem static so it's
## correctly scoped per-match (a static would leak stale results across
## separate MatchState instances sharing the same process, e.g. tests).
var vision_los_cache: Dictionary = {}

## Banks leftover dt toward the next 5-second economy tick (see
## 07-data-architecture.md section 7) — lives here, not on SimOrchestrator,
## since every other per-tick accumulator in this codebase lives on the
## instance being advanced (SquadInstance.edge_progress, BuildingInstance.
## regen_progress, ...), not on the stateless resolver driving it.
var economy_accumulator: float = 0.0

## Sim ticks resolved so far (SimOrchestrator.resolve_tick calls, i.e. fine
## ticks — SimClock's fixed-timestep unit, not the coarser 5s economy tick).
## Stamped onto CommandQueue.log entries so a recorded command can be replayed
## against a fresh state at the same point in the tick sequence.
var tick: int = 0

## Seeded, per-match RNG for in-tick rolls (e.g. StatusEffectSystem's
## statusEffectOnHit chance) — the sim must never call the engine's bare
## global randf()/randi(), or two runs from the same seed/command stream
## would diverge (see 07-data-architecture.md section 8's multiplayer-ready
## goal). Worldgen (MapGenerator/TerrainGenerator/BaseSiteSelector) already
## seeds its own substreams directly from world_seed; this is the separate
## substream for everything that happens during live ticks.
var rng := RandomNumberGenerator.new()

## Records every CommandProcessor call actually applied to this state,
## tagged with `tick` — see CommandQueue.
var command_queue := CommandQueue.new()

var _next_id_counter: int = 0

## Seeds both this match's live-tick rng and (deterministic, distinct
## substream) `worldgen_seed` for MapGenerator — call once at match setup,
## same convention TerrainGenerator/BaseSiteSelector's own _substream()
## already use to keep unrelated random streams from correlating.
func seed_rng(world_seed: int) -> void:
	rng.seed = hash("%d:sim" % world_seed)

func next_id(prefix: String) -> String:
	_next_id_counter += 1
	return "%s_%d" % [prefix, _next_id_counter]

func next_troop_id() -> String:
	return next_id("troop")

func next_squad_id() -> String:
	return next_id("squad")

func next_projectile_id() -> String:
	return next_id("projectile")

func find_squad(id: String) -> SquadInstance:
	for squad in squads:
		if squad.id == id:
			return squad
	return null

func find_base(id: String) -> BaseInstance:
	for base in bases:
		if base.id == id:
			return base
	return null

func find_standalone_building(id: String) -> BuildingInstance:
	for building in standalone_buildings:
		if building.id == id:
			return building
	return null

## {"base": BaseInstance, "building": BuildingInstance} for a base-attached
## building, or {} if no base building has this id (including a standalone
## building — see find_standalone_building for that).
func find_base_building(building_id: String) -> Dictionary:
	for base in bases:
		for building in base.buildings:
			if building.id == building_id:
				return {"base": base, "building": building}
	return {}

## {"base": BaseInstance|null, "building": BuildingInstance} across BOTH
## base-attached and standalone buildings — used by demolish_building, which
## needs to handle either kind uniformly. {} if not found anywhere.
func find_any_building(building_id: String) -> Dictionary:
	var found := find_base_building(building_id)
	if not found.is_empty():
		return found
	var standalone := find_standalone_building(building_id)
	if standalone != null:
		return {"base": null, "building": standalone}
	return {}

func bases_owned_by(owner_id: String) -> Array[BaseInstance]:
	var result: Array[BaseInstance] = []
	for base in bases:
		if base.owner_id == owner_id:
			result.append(base)
	return result

## Live count of `owner_id`'s Commander-tagged troops — ProductionManager.pump
## needs this for the Command Centre's commander-cap-pause branch; regiments
## aren't a global registry the sim can derive it from, so it's counted
## directly off troops_by_id (mirrors the same gap ProductionManager's own doc
## comment notes about current_commander_count being caller-supplied).
func commander_count(owner_id: String) -> int:
	var count := 0
	for troop in troops_by_id.values():
		if troop.owner_id == owner_id and "Commander" in troop_defs.get(troop.unit_type, {}).get("tags", []):
			count += 1
	return count

func player_for(owner_id: String) -> Player:
	if not players.has(owner_id):
		players[owner_id] = Player.new(owner_id)
	return players[owner_id]

## Convenience accessor for the common case (every call site so far only
## needs the resource pool, not the Player itself).
func pool_for(owner_id: String) -> ResourcePool:
	return player_for(owner_id).resources

## Plain-dict snapshot of every piece of live match state — the payload for
## save/load and (later) network replication. Static def tables
## (grid/troop_defs/building_defs/base_defs) are deliberately NOT included:
## they're reconstructed from data + seed by the caller and passed into
## from_dict(), the same "defs are caller-supplied, not sim state" split
## every resolver in sim/ already follows. `detections` is also excluded —
## DetectionSystem fully recomputes it from scratch every tick (see its own
## doc comment), so it's disposable, unlike PlayerVision.explored_hexes
## (persistent, and so included via `visions`).
##
## Every dict-keyed section below serializes in *sorted* key order rather
## than raw Dictionary insertion order. `players` in particular is populated
## lazily by pool_for()/player_for(), including from client-side HUD code
## (resource_bar.gd etc.) that only ever touches the local player's entry —
## two peers in a multiplayer match can easily insert "p0"/"p1" in opposite
## order despite having otherwise-identical state, which produced two
## different var_to_str() outputs (and checksum() values) for the same
## match — a false-positive desync. Sorting makes to_dict()/checksum() a
## function of the state's actual contents, not of incidental client-side
## read order.
func to_dict() -> Dictionary:
	var troops_dict: Dictionary = {}
	for key in _sorted_keys(troops_by_id):
		troops_dict[key] = troops_by_id[key].to_dict()
	var queues_dict: Dictionary = {}
	for key in _sorted_keys(production_queues):
		queues_dict[key] = production_queues[key].to_dict()
	var players_dict: Dictionary = {}
	for key in _sorted_keys(players):
		players_dict[key] = players[key].to_dict()
	var visions_dict: Dictionary = {}
	for key in _sorted_keys(visions):
		visions_dict[key] = visions[key].to_dict()

	return {
		"squads": squads.map(func(s): return s.to_dict()),
		"bases": bases.map(func(b): return b.to_dict()),
		"troops_by_id": troops_dict,
		"regiments": regiments.map(func(r): return r.to_dict()),
		"standalone_buildings": standalone_buildings.map(func(b): return b.to_dict()),
		"barbarian_outposts": barbarian_outposts.map(func(o): return o.to_dict()),
		"projectiles": projectiles.map(func(p): return p.to_dict()),
		"production_queues": queues_dict,
		"players": players_dict,
		"visions": visions_dict,
		"economy_accumulator": economy_accumulator,
		"tick": tick,
		"rng_seed": rng.seed,
		"rng_state": rng.state,
		"command_log": command_queue.log.map(func(entry): return {
			"tick": entry["tick"],
			"verb": entry["verb"],
			"args": _serialize_command_args(entry["args"]),
			"owner_id": entry["owner_id"],
		}),
		"next_id_counter": _next_id_counter,
	}

## The desync-relevant slice of to_dict(): every top-level state key except
## command_log (which only ever grows and carries no state a desync check
## needs — the state it produced is already covered by everything else). Both
## the checksum path (below) and the on-desync full-state dump
## (client/net/lockstep_driver.gd's snapshot ring) read this same view, so a
## mismatch's hash and its dumped values can never describe different data.
func sections() -> Dictionary:
	var d := to_dict()
	d.erase("command_log")
	return d

## Deterministic fingerprint of the mutable sim state, for lockstep desync
## detection (see client/net/lockstep_driver.gd) — peers periodically compare
## this instead of the full state.
func checksum() -> int:
	return hash(var_to_str(sections()))

## Per-section breakdown of checksum() — same fields, each hashed on its own
## instead of collapsed into one int. A whole-state mismatch only tells you
## *that* two peers diverged; hashing section-by-section tells you *which*
## top-level piece of MatchState did (squads vs. bases vs. players vs. RNG
## state, etc.), which is the difference between "desync" and "desync in
## base assignment, so go look at worldgen/data loading" (see
## sim/data/data_loader.gd's load order bug for exactly this kind of case).
func section_checksums() -> Dictionary:
	var d := sections()
	var result: Dictionary = {}
	for key in d:
		result[key] = hash(var_to_str(d[key]))
	return result

static func _sorted_keys(d: Dictionary) -> Array:
	var keys := d.keys()
	keys.sort()
	return keys

## CommandQueue.log's args are whatever CommandProcessor.<verb> takes (mixed
## String/HexCoord) — flat, one level deep, for every command wired through
## CommandQueue today. Stringifies any HexCoord via to_key() so the log stays
## plain-dict-serializable like the rest of to_dict(); restored purely as
## informational history on from_dict() (CommandQueue's own doc note: this
## log isn't a re-runnable script).
static func _serialize_command_args(args: Array) -> Array:
	var result: Array = []
	for value in args:
		result.append(value.to_key() if value is HexCoord else value)
	return result

## Reconstructs a MatchState from to_dict()'s output. `grid`/`troop_defs`/
## `building_defs`/`base_defs` are the caller's already-loaded def tables
## (DataLoader + MapGenerator/worldgen), not part of the snapshot itself.
static func from_dict(d: Dictionary, grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, base_defs: Dictionary) -> MatchState:
	var state := MatchState.new()
	state.grid = grid
	state.troop_defs = troop_defs
	state.building_defs = building_defs
	state.base_defs = base_defs

	for squad_dict in d["squads"]:
		state.squads.append(SquadInstance.from_dict(squad_dict))
	for base_dict in d["bases"]:
		state.bases.append(BaseInstance.from_dict(base_dict))
	for key in d["troops_by_id"]:
		state.troops_by_id[key] = TroopInstance.from_dict(d["troops_by_id"][key])
	for regiment_dict in d["regiments"]:
		state.regiments.append(RegimentInstance.from_dict(regiment_dict))
	for building_dict in d["standalone_buildings"]:
		state.standalone_buildings.append(BuildingInstance.from_dict(building_dict))
	for outpost_dict in d["barbarian_outposts"]:
		state.barbarian_outposts.append(BarbarianOutpostInstance.from_dict(outpost_dict))
	for projectile_dict in d["projectiles"]:
		state.projectiles.append(ProjectileInstance.from_dict(projectile_dict))
	for key in d["production_queues"]:
		state.production_queues[key] = ProductionQueue.from_dict(d["production_queues"][key])
	for key in d["players"]:
		state.players[key] = Player.from_dict(d["players"][key])
	for key in d["visions"]:
		state.visions[key] = PlayerVision.from_dict(d["visions"][key])

	state.economy_accumulator = d["economy_accumulator"]
	state.tick = d["tick"]
	state.rng.seed = d["rng_seed"]
	state.rng.state = d["rng_state"]
	state.command_queue.log.assign(d["command_log"])
	state._next_id_counter = d["next_id_counter"]
	return state
