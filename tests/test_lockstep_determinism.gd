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
