## Multiplayer replacement for sim_clock.gd: the same fixed-step accumulator
## (Tuning.SIM_TICK_SECONDS, MAX_STEPS_PER_ADVANCE), but every step is gated
## on having received an input frame — see NetManager.input_frame_received —
## from every player for that tick, not just run freely. That's the entire
## lockstep contract: a tick only resolves once every peer has confirmed what
## it did (or didn't do) on that tick, so replaying the same command stream
## anywhere reproduces the same state (sim/command/command_queue.gd's
## drain_due already makes same-tick apply order independent of arrival
## order — this class is what actually feeds it from the network).
##
## Input delay: a command issued locally during tick T is scheduled for
## T + INPUT_DELAY_TICKS rather than T, giving the network time to deliver it
## to every other peer before anyone needs to resolve that tick. An input
## frame is sent every tick regardless of whether anything was issued —
## peers need positive confirmation of "nothing happened" just as much as
## real commands, or a quiet player would stall the gate forever.
##
## Not a resend-suppression scheme: if advance() stalls waiting on a peer, the
## next call resends an (likely still-empty) frame for the same exec_tick.
## Harmless — CommandQueue.schedule()/the receiving gate both tolerate a tick
## being touched more than once — just not bandwidth-optimal, fine for a
## first pass on direct-IP/LAN play.
class_name LockstepDriver
extends RefCounted

const INPUT_DELAY_TICKS := 3
const DESYNC_CHECK_INTERVAL_TICKS := 20
## How many past checksum ticks' full section snapshots to keep for the
## on-desync dump. A desync is detected a few ticks after the offending tick
## (the host has to aggregate every peer's checksum and broadcast back), so
## the snapshot for that tick has to still be around when desync_detected
## fires — 8 * DESYNC_CHECK_INTERVAL_TICKS ticks of slack covers the round
## trip comfortably while staying a handful of dicts in memory.
const SNAPSHOT_HISTORY := 8

## True whenever advance() is stalled on a missing peer input frame — main.gd
## surfaces this as a "Waiting for players…" banner.
var is_waiting: bool = false

var state: MatchState
var _net: NetManager
var _accumulator: float = 0.0
var _local_seq: int = 0
var _pending_local_commands: Array = [] ## [{"verb", "args", "seq"}], flushed every tick
var _received_ticks: Dictionary = {} ## exec_tick -> {owner_id: true}
var _expected_owner_ids: Array[String] = []
## tick -> MatchState.sections() taken at that tick's checksum send, kept for
## the on-desync dump so both peers can write the *same* diverged tick rather
## than whatever tick they happen to have advanced to by the time the desync
## is reported. Pruned to the newest SNAPSHOT_HISTORY entries.
var _section_snapshots: Dictionary = {}
## tick -> a duplicate() of state.command_queue.log as of that tick's checksum
## send (log is append-only, so this is just "every command applied up to and
## including this tick"). Bundled with the on-desync dump alongside the state
## sections: a state diff says *what* differs, but the command log says *why*
## — a command present on one peer's log and missing (or reordered, or
## different args) on the other's is the direct cause, versus a value
## divergence which could be either a bad command or a bad computation off an
## otherwise-identical command stream.
var _command_log_snapshots: Dictionary = {}

func start(p_state: MatchState, net_manager: NetManager, roster: Dictionary) -> void:
	state = p_state
	_net = net_manager
	_expected_owner_ids.clear()
	for entry in roster.values():
		_expected_owner_ids.append(entry["owner_id"])
	_net.input_frame_received.connect(_on_input_frame_received)

	# Bootstrap: the very first advance() sends its input frame for
	# 1 + INPUT_DELAY_TICKS, not for tick 1 — so ticks 1..INPUT_DELAY_TICKS
	# would otherwise never get a frame from anyone and stall the gate
	# forever. Nobody could have issued a command before the match even
	# started, so priming them as trivially-satisfied/empty is correct, not
	# a shortcut.
	for tick in range(1, INPUT_DELAY_TICKS + 1):
		var received: Dictionary = {}
		for owner_id in _expected_owner_ids:
			received[owner_id] = true
		_received_ticks[tick] = received

## The multiplayer counterpart to state.command_queue.submit() — called by
## input_controller.gd/hud panels instead, when a NetManager/LockstepDriver is
## active. No immediate Result: the command only actually applies
## INPUT_DELAY_TICKS later, once every peer has it (see
## client/ui/eligibility.gd's can_* predicates for the immediate feedback
## this loses).
func issue(verb: String, args: Array, owner_id: String) -> void:
	_local_seq += 1
	_pending_local_commands.append({"verb": verb, "args": args, "seq": _local_seq})

func advance(delta: float) -> void:
	_accumulator += delta
	var steps := 0
	while _accumulator >= Tuning.SIM_TICK_SECONDS and steps < Tuning.MAX_STEPS_PER_ADVANCE:
		var exec_tick := state.tick + 1 + INPUT_DELAY_TICKS
		_net.send_input_frame(exec_tick, _pending_local_commands, _net.local_owner_id)
		_pending_local_commands = []

		if not _has_all_input_for(state.tick + 1):
			if not is_waiting:
				var received: Dictionary = _received_ticks.get(state.tick + 1, {})
				var missing: Array = []
				for owner_id in _expected_owner_ids:
					if not received.has(owner_id):
						missing.append(owner_id)
				_net.net_debug.emit("stall start tick=%d missing=%s expected=%s" % [state.tick + 1, missing, _expected_owner_ids])
			is_waiting = true
			break
		if is_waiting:
			_net.net_debug.emit("stall cleared tick=%d" % (state.tick + 1))
		is_waiting = false

		SimOrchestrator.resolve_tick(state, Tuning.SIM_TICK_SECONDS)
		_received_ticks.erase(state.tick)
		_accumulator -= Tuning.SIM_TICK_SECONDS
		steps += 1

		if state.tick % DESYNC_CHECK_INTERVAL_TICKS == 0:
			_net.send_checksum(state.tick, state.section_checksums())
			_snapshot_sections(state.tick)

## Stashes this tick's full section values (the same view section_checksums()
## hashed) plus a copy of the command log up to this tick, so the on-desync
## dump can reproduce exactly what diverged and exactly what command stream
## produced it, then prunes both rings back to SNAPSHOT_HISTORY newest ticks.
func _snapshot_sections(tick: int) -> void:
	_section_snapshots[tick] = state.sections()
	_command_log_snapshots[tick] = state.command_queue.log.duplicate()
	if _section_snapshots.size() <= SNAPSHOT_HISTORY:
		return
	var ticks := _section_snapshots.keys()
	ticks.sort()
	for stale_tick in ticks.slice(0, ticks.size() - SNAPSHOT_HISTORY):
		_section_snapshots.erase(stale_tick)
		_command_log_snapshots.erase(stale_tick)

## The stashed full section values for `tick`, or {} if it's already been
## pruned (or was never a checksum tick). main.gd's desync dump reads this.
func section_snapshot(tick: int) -> Dictionary:
	return _section_snapshots.get(tick, {})

## The stashed command log (every command applied up to and including `tick`)
## for `tick`, or [] if already pruned. main.gd's desync dump reads this.
func command_log_snapshot(tick: int) -> Array:
	return _command_log_snapshots.get(tick, [])

func _has_all_input_for(tick: int) -> bool:
	if not _received_ticks.has(tick):
		return false
	var received: Dictionary = _received_ticks[tick]
	for owner_id in _expected_owner_ids:
		if not received.has(owner_id):
			return false
	return true

func _on_input_frame_received(exec_tick: int, commands: Array, owner_id: String) -> void:
	_net.net_debug.emit("lockstep applied tick=%d owner=%s" % [exec_tick, owner_id])
	for command in commands:
		state.command_queue.schedule(exec_tick, command["verb"], command["args"], owner_id, command["seq"])
	if not _received_ticks.has(exec_tick):
		_received_ticks[exec_tick] = {}
	_received_ticks[exec_tick][owner_id] = true
