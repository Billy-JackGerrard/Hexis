## Headless assertion suite for sim/economy/*. Run with:
##   godot --headless --script res://tests/test_resources.gd
extends SceneTree

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	print("ResourcePool")
	_test_pool()
	print("ResourceTick")
	_test_tick()
	print("ResourceModifier")
	_test_modifier()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _test_pool() -> void:
	var pool := ResourcePool.new()
	_check(pool.get_amount(ResourceType.Type.FOOD) == 100.0, "starting Food is 100")
	_check(pool.get_amount(ResourceType.Type.STONE) == 100.0, "starting Stone is 100")
	_check(pool.get_amount(ResourceType.Type.STEEL) == 50.0, "starting Steel is 50")
	_check(pool.get_amount(ResourceType.Type.WOOD) == 0.0, "starting Wood is 0")
	_check(pool.get_amount(ResourceType.Type.FUEL) == 0.0, "starting Fuel is 0")

	pool.add(ResourceType.Type.FOOD, -150.0)
	_check(pool.get_amount(ResourceType.Type.FOOD) == -50.0, "add() can drive a resource negative")
	_check(pool.is_deficit(ResourceType.Type.FOOD), "negative Food reports as deficit")

	pool.set_amount(ResourceType.Type.FOOD, 10.0)
	_check(not pool.is_deficit(ResourceType.Type.FOOD), "set_amount back to positive clears deficit")

func _test_tick() -> void:
	# Normal tick: production covers upkeep, no deficit.
	var pool := ResourcePool.new()
	var deficits := ResourceTick.apply(pool, {ResourceType.Type.FOOD: 20.0}, {ResourceType.Type.FOOD: 5.0})
	_check(pool.get_amount(ResourceType.Type.FOOD) == 115.0, "production minus upkeep applied to pool")
	_check(deficits.is_empty(), "no deficit reported when net delta is positive")

	# Fuel upkeep with zero production drives Fuel negative and is reported.
	pool = ResourcePool.new()
	deficits = ResourceTick.apply(pool, {}, {ResourceType.Type.FUEL: 8.0})
	_check(pool.get_amount(ResourceType.Type.FUEL) == -8.0, "unmet Fuel upkeep goes negative")
	_check(deficits.has(ResourceType.Type.FUEL), "Fuel deficit reported")
	_check(deficits.size() == 1, "only the deficient resource is reported")

	# Stone/Steel/Wood never trigger the per-squad-drain deficit list, even negative.
	pool = ResourcePool.new()
	deficits = ResourceTick.apply(pool, {}, {ResourceType.Type.STEEL: 999.0})
	_check(pool.get_amount(ResourceType.Type.STEEL) < 0.0, "Steel can still go negative")
	_check(deficits.is_empty(), "Steel deficit never reported (not a deficit-drain resource)")

	# A deficit that's fed enough production clears itself the following tick.
	pool = ResourcePool.new()
	pool.set_amount(ResourceType.Type.FOOD, -10.0)
	_check(pool.is_deficit(ResourceType.Type.FOOD), "Food starts this scenario in deficit")
	deficits = ResourceTick.apply(pool, {ResourceType.Type.FOOD: 40.0}, {})
	_check(not pool.is_deficit(ResourceType.Type.FOOD), "enough production pulls Food back out of deficit")
	_check(deficits.is_empty(), "no deficit reported once resolved")

func _test_modifier() -> void:
	# Capital's Oil Rig -50% penalty, per 03-resources.md's Oil Rig Notes.
	var capital_mods: Array = [{"scope": "building", "buildingType": "oil_rig", "multiplier": 0.5}]
	_check(ResourceModifier.apply(10.0, "oil_rig", capital_mods) == 5.0, "Capital Oil Rig output halved")
	_check(ResourceModifier.apply(10.0, "farm", capital_mods) == 10.0, "unrelated building unaffected")

	# Winter Forge's +50% Oil Rig boost.
	var winter_forge_mods: Array = [{"scope": "building", "buildingType": "oil_rig", "multiplier": 1.5}]
	_check(ResourceModifier.apply(10.0, "oil_rig", winter_forge_mods) == 15.0, "Winter Forge Oil Rig output boosted")

	# Building-scoped and base-scoped entries stack multiplicatively.
	var stacked_mods: Array = [
		{"scope": "building", "buildingType": "oil_rig", "multiplier": 0.5},
		{"scope": "base", "multiplier": 2.0},
	]
	_check(ResourceModifier.apply(10.0, "oil_rig", stacked_mods) == 10.0, "building- and base-scoped modifiers stack multiplicatively")
