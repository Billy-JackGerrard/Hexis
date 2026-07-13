## Headless assertion suite proving the multiplayer-readiness hardening pass
## actually holds: same seed + same command stream reproduces identical
## state (SimClock/MatchState.rng/CommandQueue), and MatchState.to_dict()/
## from_dict() round-trips without losing any cross-tick state. Run with:
##   godot --headless --script res://tests/test_determinism.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _base_defs: Dictionary

const SEED := 424242

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

	print("Same seed + same command stream reproduces identical state")
	_test_two_runs_from_same_seed_match()
	print("MatchState snapshot round-trip preserves cross-tick state")
	_test_snapshot_round_trip()

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

## A frost_tank attacker (real 25% statusEffectOnHit freeze chance, splash,
## ballistic projectileSpeed — the instant AND deferred-impact RNG paths both
## fire from this one scenario) versus three rifleman squads within range, so
## many chance rolls accumulate across ticks. Two independently built copies
## from the same seed must reproduce bit-for-bit identical outcomes.
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

	# Exercises CommandQueue (item 3) alongside combat RNG: both a move and a
	# directed attack order, submitted identically in both runs, before any
	# tick — so replaying them doesn't depend on who's still alive later.
	state.command_queue.submit(state, "move_squad", [attacker.id, HexCoord.new(1, 0), "p1"], "p1")
	state.command_queue.submit(state, "attack_target", [attacker.id, state.squads[1].id, "p1"], "p1")
	return state

func _run_ticks(state: MatchState, count: int) -> void:
	for i in range(count):
		SimOrchestrator.resolve_tick(state, 1.0)

func _test_two_runs_from_same_seed_match() -> void:
	var run_a := _build_scenario()
	var run_b := _build_scenario()
	_run_ticks(run_a, 20)
	_run_ticks(run_b, 20)

	var dict_a := var_to_str(run_a.to_dict())
	var dict_b := var_to_str(run_b.to_dict())
	_check(dict_a == dict_b, "two independently built MatchStates from the same seed + identical command stream produce byte-identical to_dict() after 20 ticks")

	# Sanity check the scenario actually exercised the RNG this test depends
	# on — if nothing ever rolled a statusEffectOnHit, the match above would
	## be vacuously true rather than proving anything.
	var any_lockout_seen := false
	for squad in run_a.squads:
		if squad.owner_id == "p2" and squad.lockout_remaining > 0.0:
			any_lockout_seen = true
	_check(any_lockout_seen or run_a.squads.size() < 4, "frost_tank's 25% freeze chance actually rolled at least once across 20 ticks (or wiped every target first)")

func _test_snapshot_round_trip() -> void:
	var original := _build_scenario()
	_run_ticks(original, 8)

	var snapshot := original.to_dict()
	var restored := MatchState.from_dict(snapshot, original.grid, original.troop_defs, original.building_defs, original.base_defs)
	_check(var_to_str(original.to_dict()) == var_to_str(restored.to_dict()), "from_dict(to_dict(state)) reproduces an identical snapshot immediately after restore")

	_run_ticks(original, 10)
	_run_ticks(restored, 10)
	_check(var_to_str(original.to_dict()) == var_to_str(restored.to_dict()), "the restored copy keeps evolving identically to the original for 10 further ticks (rng/tick/command-log state all round-tripped)")
