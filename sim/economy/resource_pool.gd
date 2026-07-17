## A player's single shared resource pool (see 07-data-architecture.md
## section 5 — resources live on `Player`, not per-base).
##
## Amounts are allowed to go negative for Food/Fuel: a negative amount *is*
## the deficit state referenced by 03-resources.md's Deficit Consequences,
## not a value to clamp at zero — but `add()` floors it at
## Tuning.RESOURCE_DEFICIT_FLOOR so an unresolved deficit (e.g. building
## upkeep still draining with no troops left to die/self-limit it) can't run
## away to an arbitrarily large debt. Stone/Steel/Wood are floored at zero
## instead — they're never spent by the tick, only by build/train actions
## elsewhere that already gate on affordability, so this is just a backstop.
class_name ResourcePool
extends RefCounted

var _amounts: Dictionary = {}

func _init() -> void:
	for type in ResourceType.ALL:
		_amounts[type] = ResourceType.STARTING[type]

func get_amount(type: ResourceType.Type) -> float:
	return _amounts[type]

func set_amount(type: ResourceType.Type, value: float) -> void:
	_amounts[type] = value

func add(type: ResourceType.Type, delta: float) -> void:
	var new_amount: float = _amounts[type] + delta
	var floor_value: float = Tuning.RESOURCE_DEFICIT_FLOOR if ResourceType.can_deficit_drain(type) else 0.0
	_amounts[type] = max(new_amount, floor_value)

func is_deficit(type: ResourceType.Type) -> bool:
	return _amounts[type] < 0.0

func to_dict() -> Dictionary:
	return _amounts.duplicate()

static func from_dict(d: Dictionary) -> ResourcePool:
	var pool := ResourcePool.new()
	for type in d:
		pool._amounts[type] = d[type]
	return pool
