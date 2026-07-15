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
			is_waiting = true
			break
		is_waiting = false

		SimOrchestrator.resolve_tick(state, Tuning.SIM_TICK_SECONDS)
		_received_ticks.erase(state.tick)
		_accumulator -= Tuning.SIM_TICK_SECONDS
		steps += 1

		if state.tick % DESYNC_CHECK_INTERVAL_TICKS == 0:
			_net.send_checksum(state.tick, state.checksum())

func _has_all_input_for(tick: int) -> bool:
	if not _received_ticks.has(tick):
		return false
	var received: Dictionary = _received_ticks[tick]
	for owner_id in _expected_owner_ids:
		if not received.has(owner_id):
			return false
	return true

func _on_input_frame_received(exec_tick: int, commands: Array, owner_id: String) -> void:
	for command in commands:
		state.command_queue.schedule(exec_tick, command["verb"], command["args"], owner_id, command["seq"])
	if not _received_ticks.has(exec_tick):
		_received_ticks[exec_tick] = {}
	_received_ticks[exec_tick][owner_id] = true
