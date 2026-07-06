## A player's single shared resource pool (see 07-data-architecture.md
## section 5 — resources live on `Player`, not per-base).
##
## Amounts are allowed to go negative for Food/Fuel: a negative amount *is*
## the deficit state referenced by 03-resources.md's Deficit Consequences,
## not a value to clamp at zero. Stone/Steel/Wood aren't spent by the tick
## (only by build/train actions elsewhere), so they never go negative here.
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
	_amounts[type] += delta

func is_deficit(type: ResourceType.Type) -> bool:
	return _amounts[type] < 0.0
