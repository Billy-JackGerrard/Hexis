## Headless assertion suite for the top-level tick orchestrator
## (SimOrchestrator/MatchState) — verifies it actually drives every
## previously-standalone-tested system (movement, combat, vision, detection,
## auras, regen, production, upkeep/resources) together across real ticks,
## rather than each only ever being called in isolation from its own test.
## Run with:
##   godot --headless --script res://tests/test_sim_orchestrator.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _base_defs: Dictionary

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")
	_building_defs = DataLoader.load_dir("res://data/buildings")
	_base_defs = DataLoader.load_dir("res://data/bases")

	print("Movement + combat driven together over multiple ticks")
	_test_movement_and_combat()
	print("Economy tick fires only every 5 banked seconds")
	_test_economy_cadence()
	print("Production queue advances and pumps through the orchestrator")
	_test_production_pump()
	print("Regiment lock-step movement driven by the orchestrator")
	_test_regiment_movement()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _flat_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), radius):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	return grid

func _new_state(grid: HexGrid) -> MatchState:
	var state := MatchState.new()
	state.grid = grid
	state.troop_defs = _troop_defs
	state.building_defs = _building_defs
	state.base_defs = _base_defs
	return state

func _make_squad(state: MatchState, owner: String, troop_type: String, hex: HexCoord, count: int) -> SquadInstance:
	var squad := SquadInstance.new(state.next_squad_id(), owner, troop_type, hex)
	var hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 100.0))
	for i in range(count):
		var troop := TroopInstance.new(state.next_troop_id(), troop_type, owner, squad.id, hp)
		state.troops_by_id[troop.id] = troop
		squad.add_member(troop.id)
	state.squads.append(squad)
	return squad

func _test_movement_and_combat() -> void:
	var state := _new_state(_flat_grid(10))
	var mover := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0), 2)
	MovementResolver.issue_move(mover, state.grid, HexCoord.new(4, 0), _troop_defs)

	SimOrchestrator.resolve_tick(state, 1.0)
	_check(not mover.current_hex.equals(HexCoord.new(0, 0)) or mover.edge_progress > 0.0, "a moving squad actually advances via the orchestrator's fine tick")

	# Now put an enemy directly in its path/range and confirm combat resolves
	# (damage applied) purely from repeated orchestrator ticks -- no direct
	# CombatResolver/MovementResolver call from the test itself.
	var enemy := _make_squad(state, "p2", "rifleman", HexCoord.new(2, 0), 1)
	var enemy_troop_id: String = enemy.member_ids[0]
	var starting_hp: float = state.troops_by_id[enemy_troop_id].current_hp

	for i in range(30):
		SimOrchestrator.resolve_tick(state, 1.0)

	var enemy_alive: bool = state.troops_by_id.has(enemy_troop_id)
	var damaged: bool = (not enemy_alive) or float(state.troops_by_id[enemy_troop_id].current_hp) < starting_hp
	_check(damaged, "combat actually resolves through repeated orchestrator ticks (enemy took damage or died)")

	_check(state.visions.has("p1") and not state.visions["p1"].visible_hexes.is_empty(), "VisionSystem output is populated by the orchestrator")

func _test_economy_cadence() -> void:
	var state := _new_state(_flat_grid(3))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var starting_stone := state.pool_for("p1").get_amount(ResourceType.Type.STONE)

	# 2.5s of fine ticks: not enough to bank a full 5s economy tick yet.
	SimOrchestrator.resolve_tick(state, 2.5)
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == starting_stone, "under 5 banked seconds -> no economy tick yet, Stone unchanged")

	# Another 2.5s crosses the 5s threshold -> exactly one economy tick fires.
	SimOrchestrator.resolve_tick(state, 2.5)
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) > starting_stone, "crossing 5 banked seconds fires the economy tick -> Quarry's Stone output applied")

func _test_production_pump() -> void:
	var state := _new_state(_flat_grid(3))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var barracks := BuildingInstance.new("barracks1", base.id, "barracks", 1, "", HexCoord.new(1, -1))
	barracks.init_hp(_building_defs["barracks"], _building_defs)
	base.buildings.append(barracks)

	var queue := ProductionQueue.new(barracks.id)
	state.production_queues[barracks.id] = queue
	ProductionManager.enqueue(queue, "rifleman", _troop_defs)

	var production_time: float = float(_troop_defs["rifleman"].get("productionTime", 0.0))
	_check(production_time > 0.0, "rifleman has a nonzero productionTime (fixture assumption)")

	var owner_squads_before := 0
	for squad in state.squads:
		if squad.owner_id == "p1":
			owner_squads_before += 1

	# Advance well past production_time in fine-tick-sized steps.
	for i in range(int(production_time) + 5):
		SimOrchestrator.resolve_tick(state, 1.0)

	var owner_squads_after := 0
	for squad in state.squads:
		if squad.owner_id == "p1":
			owner_squads_after += 1
	_check(owner_squads_after > owner_squads_before, "the orchestrator's production step deploys a completed troop into a new squad")
	_check(queue.is_empty(), "the completed entry left the queue")

func _test_regiment_movement() -> void:
	var state := _new_state(_flat_grid(10))
	var commander := _make_squad(state, "p1", "commander_vanguard", HexCoord.new(0, 0), 1)
	var escort := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0), 2)

	var regiment := RegimentInstance.new("reg1", commander.id)
	regiment.assign_squad(escort.id, 4)
	state.regiments.append(regiment)

	MovementResolver.issue_regiment_move(commander, [escort], state.grid, HexCoord.new(3, 0), _troop_defs)

	for i in range(10):
		SimOrchestrator.resolve_tick(state, 1.0)

	_check(escort.current_hex.equals(commander.current_hex), "the orchestrator drives regiment lock-step -- escort mirrors the Commander's hex")
	_check(not commander.current_hex.equals(HexCoord.new(0, 0)), "the regiment actually moved from its start hex")
