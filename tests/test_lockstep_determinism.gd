## Headless assertion suite for the lockstep-multiplayer command scheduler
## (CommandQueue.schedule()/drain_due(), MatchState.checksum()) — proves the
## piece test_determinism.gd doesn't cover: that two peers who schedule the
## *same* commands in a *different arrival order* (simulating network jitter)
## still apply them in identical order and reach identical state, because
## drain_due() sorts by (owner_id, seq) rather than trusting arrival order.
## Run with:
##   godot --headless --script res://tests/test_lockstep_determinism.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _base_defs: Dictionary

const SEED := 13371337

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

	print("Same commands scheduled in a different arrival order still apply identically")
	_test_arrival_order_independence()
	print("checksum() actually reflects state, not a constant")
	_test_checksum_sanity()
	print("Resource-starved production stays in sync over a long match")
	_test_production_economy_determinism()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers ---------------------------------------------------------------

func _flat_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), radius):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	return grid

## Two owners (p1, p2) each with a squad, plus a frost_tank/rifleman pair so
## combat RNG (statusEffectOnHit) also runs through the scheduled path, not
## just movement.
func _build_scenario() -> MatchState:
	var state := MatchState.new()
	state.grid = _flat_grid(10)
	state.troop_defs = _troop_defs
	state.building_defs = _building_defs
	state.base_defs = _base_defs
	state.seed_rng(SEED)

	var attacker := SquadInstance.new(state.next_squad_id(), "p1", "frost_tank", HexCoord.new(0, 0))
	var attacker_hp: float = float(_troop_defs["frost_tank"].get("hp", 260.0))
	for i in range(4):
		var troop := TroopInstance.new(state.next_troop_id(), "frost_tank", "p1", attacker.id, attacker_hp)
		state.troops_by_id[troop.id] = troop
		attacker.add_member(troop.id)
	state.squads.append(attacker)

	var rifleman_hp: float = float(_troop_defs["rifleman"].get("hp", 100.0))
	for i in range(3):
		var enemy := SquadInstance.new(state.next_squad_id(), "p2", "rifleman", HexCoord.new(2 + i, 0))
		var troop := TroopInstance.new(state.next_troop_id(), "rifleman", "p2", enemy.id, rifleman_hp)
		state.troops_by_id[troop.id] = troop
		enemy.add_member(troop.id)
		state.squads.append(enemy)

	return state

func _run_ticks(state: MatchState, count: int) -> void:
	for i in range(count):
		SimOrchestrator.resolve_tick(state, 1.0)

## Both p1's move+attack and p2's move are scheduled for the same exec_tick
## (5) so drain_due must sort them — the two runs below hand them to
## schedule() in opposite orders, exactly as if the two commands had arrived
## over the network in a different order on each peer.
func _test_arrival_order_independence() -> void:
	var run_a := _build_scenario()
	var run_b := _build_scenario()

	var enemy_squad_id: String = run_a.squads[1].id
	# run_a: p1's commands scheduled first, p2's second.
	run_a.command_queue.schedule(5, "move_squad", [run_a.squads[0].id, HexCoord.new(1, 0), "p1"], "p1", 1)
	run_a.command_queue.schedule(5, "attack_target", [run_a.squads[0].id, enemy_squad_id, "p1"], "p1", 2)
	run_a.command_queue.schedule(5, "move_squad", [run_a.squads[1].id, HexCoord.new(3, 0), "p2"], "p2", 1)

	# run_b: identical commands, but p2's arrives (is scheduled) before p1's —
	# simulating p2's packet reaching this peer first over the network.
	run_b.command_queue.schedule(5, "move_squad", [run_b.squads[1].id, HexCoord.new(3, 0), "p2"], "p2", 1)
	run_b.command_queue.schedule(5, "move_squad", [run_b.squads[0].id, HexCoord.new(1, 0), "p1"], "p1", 1)
	run_b.command_queue.schedule(5, "attack_target", [run_b.squads[0].id, enemy_squad_id, "p1"], "p1", 2)

	_run_ticks(run_a, 20)
	_run_ticks(run_b, 20)

	_check(run_a.checksum() == run_b.checksum(), "checksum matches after 20 ticks despite opposite schedule() call order")
	_check(var_to_str(run_a.to_dict()) == var_to_str(run_b.to_dict()), "full to_dict() snapshot matches too (checksum isn't hiding a real divergence)")

	var any_lockout_seen := false
	for squad in run_a.squads:
		if squad.owner_id == "p2" and squad.lockout_remaining > 0.0:
			any_lockout_seen = true
	_check(any_lockout_seen or run_a.squads.size() < 4, "frost_tank's freeze-chance RNG actually rolled at least once across 20 ticks (or wiped every target first)")

func _test_checksum_sanity() -> void:
	var state := _build_scenario()
	var before := state.checksum()
	state.command_queue.schedule(1, "move_squad", [state.squads[0].id, HexCoord.new(1, 0), "p1"], "p1", 1)
	_run_ticks(state, 10)
	var after := state.checksum()
	_check(before != after, "checksum changes once the scheduled command + ticks actually move state")

## Regression cover for the lazy-payment production refactor (HEAD): the desync
## reported in the field was in the `bases`/`players` sections — i.e. the
## economy + production path, which _build_scenario above never touches.
## _test_arrival_order_independence only runs 20 ticks with a full pool, so it
## can't see a divergence that only appears once a queue actually starves,
## pauses on insufficient_resources, and resumes as the Farm trickles food back
## — the exact interaction the refactor introduced. This runs a capital with a
## Barracks (produces) + Farm (food income) for LONG_MATCH_TICKS twice from an
## identical setup and asserts the two runs never diverge, comparing whole
## sections at every checksum cadence so a mismatch names which one broke.
const LONG_MATCH_TICKS := 3000
const CHECKSUM_CADENCE := 20

## A p1 capital whose starting food is set just above one rifleman's cost, so
## the first queued rifleman pays immediately and the rest sit paused on
## insufficient_resources until the Farm's foodOutput trickles enough back —
## then a deep queue of riflemen to keep that starve/resume cycle running for
## the whole match.
func _build_economy_scenario() -> MatchState:
	var state := MatchState.new()
	state.grid = _flat_grid(10)
	state.troop_defs = _troop_defs
	state.building_defs = _building_defs
	state.base_defs = _base_defs
	state.seed_rng(SEED)

	var base := BaseInstance.new("cap1", "capital", "p1", 1, HexCoord.new(0, 0))
	var barracks := BuildingInstance.new("brk1", base.id, "barracks", 1, "", HexCoord.new(0, 0))
	barracks.init_hp(_building_defs["barracks"], _building_defs)
	var farm := BuildingInstance.new("farm1", base.id, "farm", 1, "", HexCoord.new(0, 1))
	farm.init_hp(_building_defs["farm"], _building_defs)
	base.buildings.append(barracks)
	base.buildings.append(farm)
	state.bases.append(base)

	# One rifleman's worth of food + a hair, so exactly the first entry starts
	# training and everything queued behind it starves until the Farm catches up.
	var rifleman_food: float = float(_troop_defs["rifleman"].get("cost", {}).get("food", 20.0))
	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, rifleman_food + 1.0)

	for i in range(40):
		CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	return state

func _test_production_economy_determinism() -> void:
	var run_a := _build_economy_scenario()
	var run_b := _build_economy_scenario()

	var starved_at_least_once := false
	var diverged_tick := -1
	var diverged_sections: Array = []
	for i in range(LONG_MATCH_TICKS):
		SimOrchestrator.resolve_tick(run_a, 1.0)
		SimOrchestrator.resolve_tick(run_b, 1.0)
		var queue: ProductionQueue = run_a.production_queues.get("brk1")
		if queue != null and queue.pause_reason == "insufficient_resources":
			starved_at_least_once = true
		if diverged_tick == -1 and run_a.tick % CHECKSUM_CADENCE == 0:
			var checks_a := run_a.section_checksums()
			var checks_b := run_b.section_checksums()
			for key in checks_a:
				if checks_a[key] != checks_b.get(key):
					diverged_sections.append(key)
			if not diverged_sections.is_empty():
				diverged_tick = run_a.tick

	if diverged_tick != -1:
		_check(false, "two identical runs diverged at tick %d in section(s): %s" % [diverged_tick, ", ".join(diverged_sections)])
	else:
		_check(true, "%d ticks of resource-starved production stayed byte-identical across both runs" % LONG_MATCH_TICKS)
	_check(var_to_str(run_a.to_dict()) == var_to_str(run_b.to_dict()), "final full to_dict() snapshot matches after the long match")
	# Proves the run actually exercised the lazy-payment starve/resume path
	# rather than draining the queue instantly (which would make the sync
	# assertions vacuous).
	_check(starved_at_least_once, "a queued entry actually hit insufficient_resources at some point (the path under test really ran)")
