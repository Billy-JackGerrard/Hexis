## Live per-building training queue (see 07-data-architecture.md section 3b).
## One ProductionQueue per Production-category BuildingInstance, referenced by
## building_id (never embedded on BuildingInstance itself) — never a shared
## base-wide queue.
##
## Deviates from the doc's `startedAt` field: the sim has no global clock yet,
## so each entry instead stores an immutable `production_time` (for UI
## progress %) plus a mutable `remaining` that counts down to 0, mirroring
## SquadInstance.edge_progress's "accumulator, not absolute time" treatment.
## Swapping to started_at + now is a non-breaking follow-up once a sim clock
## exists.
class_name ProductionQueue
extends RefCounted

var building_id: String
## FIFO; each entry is { troop_type: String, production_time: float, remaining: float }.
## entries[0] is the one currently training (or held complete, if paused).
var entries: Array[Dictionary] = []
var paused: bool = false
var pause_reason: String = "" ## "" | "squad_cap" | "commander_cap"

func _init(p_building_id: String) -> void:
	building_id = p_building_id

func is_empty() -> bool:
	return entries.is_empty()

func front() -> Dictionary:
	return entries[0]

func front_complete() -> bool:
	return not is_empty() and float(front().get("remaining", 0.0)) <= 0.0

func to_dict() -> Dictionary:
	return {
		"building_id": building_id,
		"entries": entries.duplicate(true),
		"paused": paused,
		"pause_reason": pause_reason,
	}

static func from_dict(d: Dictionary) -> ProductionQueue:
	var queue := ProductionQueue.new(d["building_id"])
	queue.entries = d["entries"].duplicate(true)
	queue.paused = d["paused"]
	queue.pause_reason = d["pause_reason"]
	return queue
