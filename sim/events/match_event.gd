## A single "this happened" record for the player-facing alert/toast system —
## squad lost, base captured/lost, building destroyed, deficit death, outpost
## loot. Appended to MatchState.events during tick resolution, drained (read
## then cleared) by the client once per rendered frame — see
## client/hud/toast_panel.gd.
##
## Deliberately NOT serialized (no to_dict/from_dict): MatchState.events is
## excluded from to_dict()/sections()/checksum() entirely, the same "carries
## no state a desync check needs" precedent command_log's own exclusion sets
## (see match_state.gd) — an event is transient, drained immediately by the
## client, and never needs to survive a save/load or desync dump. Every
## lockstep peer still sees identical events regardless, as a side effect of
## the sim itself being deterministic — this class just isn't part of the
## state that's compared/replayed.
class_name MatchEvent
extends RefCounted

enum Type { SQUAD_LOST, BASE_CAPTURED, BASE_LOST, BUILDING_DESTROYED, DEFICIT_DEATH, OUTPOST_LOOT }

var type: Type
var owner_id: String ## whose HUD this is relevant to
var payload: Dictionary ## type-specific extra data — see each emission site

func _init(p_type: Type, p_owner_id: String, p_payload: Dictionary = {}) -> void:
	type = p_type
	owner_id = p_owner_id
	payload = p_payload
