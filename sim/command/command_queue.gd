## The network/replay seam in front of CommandProcessor: client input threads
## through `submit()` instead of calling CommandProcessor directly, so every
## applied command is recorded with the sim tick it landed in.
##
## Execution stays synchronous/immediate — `submit()` calls straight through
## to CommandProcessor and returns its Result, so today's client UX (an
## immediate Result for a rejected order) is unchanged. That's safe because
## Godot resolves input before _process each frame, so a command submitted
## this frame is already visible to every fixed step SimClock runs later in
## the same frame. Single-player and every existing test still go through
## `submit()` directly and are completely unaffected by the below.
##
## `schedule()`/`drain_due()` are the added lockstep seam: a networked command
## arrives tagged with the future tick it must apply on (see
## client/net/lockstep_driver.gd), and every peer must apply same-tick
## commands in the same order regardless of the order packets actually
## arrived in. `drain_due()` sorts by (owner_id, seq) before calling
## `submit()` for each, so apply order is a pure function of the command
## stream, not of network arrival timing. Single-player never calls
## `schedule()`, so `drain_due()` is a no-op for it (empty dict lookup).
class_name CommandQueue
extends RefCounted

## {tick: int, verb: String, args: Array, owner_id: String}, in application
## order. `args` are CommandProcessor.<verb>'s own arguments minus the leading
## `state` (submit() re-prepends it) — e.g. move_squad's log entry stores
## [squad_id, goal, owner_id].
var log: Array[Dictionary] = []

## exec_tick -> Array[{verb, args, owner_id, seq}], commands scheduled for a
## future tick via schedule(), drained by drain_due() once that tick arrives.
var _scheduled: Dictionary = {}

## Calls CommandProcessor.<verb>(state, *args) and records the call. `verb`
## must name one of CommandProcessor's static command functions.
func submit(state: MatchState, verb: String, args: Array, owner_id: String) -> Variant:
	var result: Variant = Callable(CommandProcessor, verb).callv([state] + args)
	log.append({"tick": state.tick, "verb": verb, "args": args.duplicate(), "owner_id": owner_id})
	return result

## Buffers a command to apply once `exec_tick` is reached. `seq` is the
## issuing peer's own monotonic counter (tie-breaks same-owner commands
## scheduled for the same tick in issue order).
func schedule(exec_tick: int, verb: String, args: Array, owner_id: String, seq: int) -> void:
	if not _scheduled.has(exec_tick):
		_scheduled[exec_tick] = []
	_scheduled[exec_tick].append({"verb": verb, "args": args, "owner_id": owner_id, "seq": seq})

## Applies every command scheduled for `tick`, sorted by (owner_id, seq) so
## every peer replays them in the same order no matter what order they were
## received in. Called once per tick from SimOrchestrator, before that tick's
## movement/combat resolve.
func drain_due(state: MatchState, tick: int) -> void:
	if not _scheduled.has(tick):
		return
	var due: Array = _scheduled[tick]
	due.sort_custom(func(a, b):
		if a["owner_id"] != b["owner_id"]:
			return a["owner_id"] < b["owner_id"]
		return a["seq"] < b["seq"])
	for entry in due:
		submit(state, entry["verb"], entry["args"], entry["owner_id"])
	_scheduled.erase(tick)
