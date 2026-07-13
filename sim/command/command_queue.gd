## The network/replay seam in front of CommandProcessor: client input threads
## through `submit()` instead of calling CommandProcessor directly, so every
## applied command is recorded with the sim tick it landed in.
##
## Execution stays synchronous/immediate — `submit()` calls straight through
## to CommandProcessor and returns its Result, so today's client UX (an
## immediate Result for a rejected order) is unchanged. That's safe because
## Godot resolves input before _process each frame, so a command submitted
## this frame is already visible to every fixed step SimClock runs later in
## the same frame — tick-aligned deferred buffering only becomes necessary
## once commands can arrive asynchronously from an actual network socket,
## which is out of scope for this pass (see game-design/07-data-architecture.md
## section 8). What this class buys now: `log` is exactly the payload a host
## would ship to remote peers, and what a determinism/replay test needs to
## prove the sim reproduces identically from the same seed + command stream.
class_name CommandQueue
extends RefCounted

## {tick: int, verb: String, args: Array, owner_id: String}, in application
## order. `args` are CommandProcessor.<verb>'s own arguments minus the leading
## `state` (submit() re-prepends it) — e.g. move_squad's log entry stores
## [squad_id, goal, owner_id].
var log: Array[Dictionary] = []

## Calls CommandProcessor.<verb>(state, *args) and records the call. `verb`
## must name one of CommandProcessor's static command functions.
func submit(state: MatchState, verb: String, args: Array, owner_id: String) -> Variant:
	var result: Variant = Callable(CommandProcessor, verb).callv([state] + args)
	log.append({"tick": state.tick, "verb": verb, "args": args.duplicate(), "owner_id": owner_id})
	return result
