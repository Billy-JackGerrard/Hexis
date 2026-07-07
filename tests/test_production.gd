## Headless assertion suite for sim/economy/production_output_system.gd. Run
## with: godot --headless --script res://tests/test_production.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _base_defs: Dictionary
var _next_id: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")
	_building_defs = DataLoader.load_dir("res://data/buildings")
	_base_defs = DataLoader.load_dir("res://data/bases")
	# Synthetic fixture standing in for a real resource-siphon vehicle troop
	# (see tests/test_auras.gd's resource_siphon fixture note — this change
	# scopes just the aura/production mechanic, not the actual troop data).
	_troop_defs["siphon_test_unit"] = {
		"id": "siphon_test_unit",
		"domain": "Land",
		"tags": ["Vehicle", "Support"],
		"hp": 80,
		"auras": [
			{"radius": 5, "target": "enemy_buildings", "filter": "Resource", "effect": "resource_siphon"},
		],
	}

	print("ProductionOutputSystem.compute_production: baseline")
	_test_baseline()
	print("ProductionOutputSystem.compute_production: resource_siphon redirect")
	_test_siphon_redirect()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers ----------------------------------------------------------------

func _make_squad(owner: String, troop_type: String, hex: HexCoord, count: int, troops: Dictionary) -> SquadInstance:
	_next_id += 1
	var squad := SquadInstance.new("sq%d" % _next_id, owner, troop_type, hex)
	var hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 100.0))
	for i in range(count):
		_next_id += 1
		var tid := "tr%d" % _next_id
		troops[tid] = TroopInstance.new(tid, troop_type, owner, squad.id, hp)
		squad.add_member(tid)
	return squad

func _farm_food_output(level: int) -> float:
	return BuildingStats.resource_output(_building_defs["farm"], level, _building_defs).get(ResourceType.Type.FOOD, 0.0)

## --- baseline ----------------------------------------------------------------

func _test_baseline() -> void:
	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(5, 0))
	var farm := BuildingInstance.new("f1", "b1", "farm", 1, "", HexCoord.new(5, 0))
	farm.init_hp(_building_defs["farm"], _building_defs)
	base.buildings.append(farm)
	var bases: Array[BaseInstance] = [base]

	var production := ProductionOutputSystem.compute_production(bases, _base_defs, _building_defs)
	var farm_output := _farm_food_output(1)
	_check(_approx(float(production.get("p1", {}).get(ResourceType.Type.FOOD, 0.0)), farm_output), "un-sieged Farm credits its own owner's Food total (%s)" % farm_output)
	_check(not production.has("p2"), "no other owner appears in production without a siphon redirect")

## --- resource_siphon redirect -------------------------------------------------

func _test_siphon_redirect() -> void:
	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(5, 0))
	var farm := BuildingInstance.new("f1", "b1", "farm", 1, "", HexCoord.new(5, 0))
	farm.init_hp(_building_defs["farm"], _building_defs)
	base.buildings.append(farm)
	# A second, un-sieged Farm on the SAME base -- proves the redirect is
	# resolved per building, not per base.
	var farm2 := BuildingInstance.new("f2", "b1", "farm", 1, "", HexCoord.new(20, 0))
	farm2.init_hp(_building_defs["farm"], _building_defs)
	base.buildings.append(farm2)
	var bases: Array[BaseInstance] = [base]

	var troops := {}
	var siphoner := _make_squad("p2", "siphon_test_unit", HexCoord.new(5, 0), 1, troops)
	var squads: Array[SquadInstance] = [siphoner]
	var auras := AuraSystem.resolve_tick(squads, bases, _troop_defs, _building_defs)
	_check(AuraSystem.siphoned_by(auras, farm.id) == "p2", "sanity check: farm is siphoned by p2")
	_check(AuraSystem.siphoned_by(auras, farm2.id) == "", "sanity check: farm2 is out of the siphoner's range, un-sieged")

	var production := ProductionOutputSystem.compute_production(bases, _base_defs, _building_defs, auras)
	var farm_output := _farm_food_output(1)
	_check(_approx(float(production.get("p2", {}).get(ResourceType.Type.FOOD, 0.0)), farm_output), "the sieged Farm's entire Food output moves to the siphoning owner (p2)")
	_check(_approx(float(production.get("p1", {}).get(ResourceType.Type.FOOD, 0.0)), farm_output), "p1 still gets the un-sieged second Farm's output, not zero")

func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.001
