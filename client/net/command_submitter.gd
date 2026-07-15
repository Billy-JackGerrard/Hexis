## The one seam every client/ call site goes through to issue a command,
## instead of calling state.command_queue.submit() directly — so the same
## input_controller.gd/hud panel code works unchanged whether the match is
## single-player (apply immediately, real Result) or multiplayer (buffer via
## LockstepDriver.issue(), applies INPUT_DELAY_TICKS later, no immediate
## Result). `lockstep` is null in single-player.
##
## Multiplayer callers lose the immediate rejection feedback single-player
## relies on (this always returns `ok_result` since the real outcome isn't
## known until the command actually applies) — client/ui/eligibility.gd's
## can_* predicates are what should gate the UI instead in that case (see
## lockstep_driver.gd's own doc comment).
class_name CommandSubmitter
extends RefCounted

var _state: MatchState
var _lockstep: LockstepDriver

func _init(state: MatchState, lockstep: LockstepDriver = null) -> void:
	_state = state
	_lockstep = lockstep

func submit(verb: String, args: Array, owner_id: String, ok_result: int = CommandProcessor.Result.OK) -> Variant:
	if _lockstep != null:
		_lockstep.issue(verb, args, owner_id)
		return ok_result
	return _state.command_queue.submit(_state, verb, args, owner_id)
