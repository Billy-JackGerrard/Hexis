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
var production_queues: Dictionary = {} ## building_id -> ProductionQueue
var resource_pools: Dictionary = {} ## owner_id -> ResourcePool

var grid: HexGrid
var troop_defs: Dictionary = {}
var building_defs: Dictionary = {}
var base_defs: Dictionary = {}

## VisionSystem/DetectionSystem output — mutated in place each tick by
## SimOrchestrator, same "caller-owns-the-dict" convention those systems
## already use everywhere else.
var visions: Dictionary = {} ## owner_id -> PlayerVision
var detections: Dictionary = {} ## owner_id -> {hex_key: true}

## Banks leftover dt toward the next 5-second economy tick (see
## 07-data-architecture.md section 7) — lives here, not on SimOrchestrator,
## since every other per-tick accumulator in this codebase lives on the
## instance being advanced (SquadInstance.edge_progress, BuildingInstance.
## regen_progress, ...), not on the stateless resolver driving it.
var economy_accumulator: float = 0.0

var _next_id_counter: int = 0

func next_id(prefix: String) -> String:
	_next_id_counter += 1
	return "%s_%d" % [prefix, _next_id_counter]

func next_troop_id() -> String:
	return next_id("troop")

func next_squad_id() -> String:
	return next_id("squad")

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

func pool_for(owner_id: String) -> ResourcePool:
	if not resource_pools.has(owner_id):
		resource_pools[owner_id] = ResourcePool.new()
	return resource_pools[owner_id]
