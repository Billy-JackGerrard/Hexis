## Per-owner visibility state (see game-design/01-map-and-terrain.md's Fog of
## War section). No Player/GameState container exists anywhere in sim/ yet —
## this follows the same convention as every other per-owner sim state
## (SquadInstance.owner_id, BaseInstance.owner_id): a small standalone holder,
## keyed externally by owner_id string, not a singleton.
class_name PlayerVision
extends RefCounted

var owner_id: String
## hex key (HexCoord.to_key) -> true. Fully recomputed every VisionSystem tick
## — currently visible only, never carried over from a prior tick.
var visible_hexes: Dictionary = {}
## hex key -> true. Persistent: once revealed, stays revealed (the "explored
## but not currently visible" fade per 01-map-and-terrain.md) — only ever
## grows, never cleared.
var explored_hexes: Dictionary = {}

func _init(p_owner_id: String) -> void:
	owner_id = p_owner_id

func is_visible(coord: HexCoord) -> bool:
	return visible_hexes.has(coord.to_key())

func is_explored(coord: HexCoord) -> bool:
	return explored_hexes.has(coord.to_key())

## explored_hexes is genuinely cumulative match state (see its own doc above)
## — unlike DetectionSystem's `detections`, which is fully recomputed every
## tick and deliberately excluded from MatchState.to_dict(), this must be
## captured in any snapshot/save or a reload would forget explored fog.
func to_dict() -> Dictionary:
	return {
		"owner_id": owner_id,
		"visible_hexes": visible_hexes.duplicate(),
		"explored_hexes": explored_hexes.duplicate(),
	}

static func from_dict(d: Dictionary) -> PlayerVision:
	var pv := PlayerVision.new(d["owner_id"])
	pv.visible_hexes = d["visible_hexes"].duplicate()
	pv.explored_hexes = d["explored_hexes"].duplicate()
	return pv
