## Headless assertion suite for sim/economy/*. Run with:
##   godot --headless --script res://tests/test_resources.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _next_id: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")

	print("ResourcePool")
	_test_pool()
	print("ResourceTick")
	_test_tick()
	print("ResourceModifier")
	_test_modifier()
	print("UpkeepSystem.compute_upkeep")
	_test_upkeep_compute()
	print("UpkeepSystem.apply_deficit_deaths")
	_test_upkeep_deficit_deaths()

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

## --- helpers -------------------------------------------------------------

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

## --- UpkeepSystem ---------------------------------------------------------

func _test_upkeep_compute() -> void:
	var troops: Dictionary = {}

	# Infantry (flamethrower) always pays flat Food regardless of movement —
	# no domain-based zeroing applies.
	var flamethrower_food_upkeep: float = float(_troop_defs["flamethrower"]["foodUpkeep"])
	var infantry := _make_squad("p1", "flamethrower", HexCoord.new(0, 0), 3, troops)
	var upkeep: Dictionary = UpkeepSystem.compute_upkeep([infantry], _troop_defs)
	var expected_infantry_food := 3 * flamethrower_food_upkeep
	_check(float(upkeep["p1"].get(ResourceType.Type.FOOD, 0.0)) == expected_infantry_food, "3-member Infantry squad draws 3x flamethrower's foodUpkeep (%s) = %s" % [flamethrower_food_upkeep, expected_infantry_food])
	_check(not upkeep["p1"].has(ResourceType.Type.FUEL), "Infantry squad draws no Fuel")

	# Land vehicle (chonky) idle (empty path) pays no Fuel.
	troops = {}
	var idle_tank := _make_squad("p1", "chonky", HexCoord.new(0, 0), 2, troops)
	upkeep = UpkeepSystem.compute_upkeep([idle_tank], _troop_defs)
	_check(not upkeep.has("p1"), "idle Land vehicle squad pays no Fuel (and no Food, chonky has none)")

	# Same Land vehicle under a move order (non-empty path) pays flat Fuel.
	troops = {}
	var chonky_fuel_upkeep: float = float(_troop_defs["chonky"]["fuelUpkeep"])
	var moving_tank := _make_squad("p1", "chonky", HexCoord.new(0, 0), 2, troops)
	moving_tank.path = [HexCoord.new(1, 0)]
	upkeep = UpkeepSystem.compute_upkeep([moving_tank], _troop_defs)
	var expected_moving_tank_fuel := 2 * chonky_fuel_upkeep
	_check(float(upkeep["p1"].get(ResourceType.Type.FUEL, 0.0)) == expected_moving_tank_fuel, "moving 2-member Land vehicle squad pays 2x chonky's fuelUpkeep (%s) = %s" % [chonky_fuel_upkeep, expected_moving_tank_fuel])

	# Air unit (hot_air_balloon) idle but NOT docked still pays flat Fuel —
	# there is no more near-base fuel-free rule, only actually landing/
	# docking (SquadInstance.is_docked()) stops the drain.
	troops = {}
	var hot_air_balloon_fuel_upkeep: float = float(_troop_defs["hot_air_balloon"]["fuelUpkeep"])
	var idle_air := _make_squad("p1", "hot_air_balloon", HexCoord.new(1, 0), 1, troops)
	upkeep = UpkeepSystem.compute_upkeep([idle_air], _troop_defs)
	_check(float(upkeep["p1"].get(ResourceType.Type.FUEL, 0.0)) == hot_air_balloon_fuel_upkeep, "idle Aircraft always pays hot_air_balloon's fuelUpkeep (%s) — near-base is no longer fuel-free" % hot_air_balloon_fuel_upkeep)

	# Same Air unit, docked (boarded_on_squad_id/docked_building_id set), pays
	# no Fuel regardless of position.
	troops = {}
	var docked_air := _make_squad("p1", "hot_air_balloon", HexCoord.new(10, 10), 1, troops)
	docked_air.docked_building_id = "hangar_1"
	upkeep = UpkeepSystem.compute_upkeep([docked_air], _troop_defs)
	_check(not upkeep.has("p1"), "docked Aircraft pays no Fuel regardless of position")

	# Same Air unit under a move order pays Fuel even if somehow flagged docked
	# (a docked squad never has a path in practice, but the rule is gated on
	# path.is_empty() first regardless).
	troops = {}
	var moving_air := _make_squad("p1", "hot_air_balloon", HexCoord.new(1, 0), 1, troops)
	moving_air.path = [HexCoord.new(2, 0)]
	upkeep = UpkeepSystem.compute_upkeep([moving_air], _troop_defs)
	_check(float(upkeep["p1"].get(ResourceType.Type.FUEL, 0.0)) == hot_air_balloon_fuel_upkeep, "Aircraft under a move order pays fuelUpkeep (%s)" % hot_air_balloon_fuel_upkeep)

	# Glider: Air-domain but authored with fuelUpkeep 0 — the Air rule
	# multiplies out to 0 either way, Food is unaffected.
	troops = {}
	var glider_food_upkeep: float = float(_troop_defs["glider"]["foodUpkeep"])
	var glider := _make_squad("p1", "glider", HexCoord.new(10, 10), 1, troops)
	upkeep = UpkeepSystem.compute_upkeep([glider], _troop_defs)
	_check(float(upkeep["p1"].get(ResourceType.Type.FOOD, 0.0)) == glider_food_upkeep, "Glider always pays flat foodUpkeep (%s)" % glider_food_upkeep)
	_check(not upkeep["p1"].has(ResourceType.Type.FUEL), "Glider never pays Fuel")

	# Multiple squads/owners accumulate independently.
	troops = {}
	var p1_squad := _make_squad("p1", "flamethrower", HexCoord.new(0, 0), 2, troops)
	var p2_squad := _make_squad("p2", "flamethrower", HexCoord.new(5, 5), 4, troops)
	upkeep = UpkeepSystem.compute_upkeep([p1_squad, p2_squad], _troop_defs)
	var expected_p1_food := 2 * flamethrower_food_upkeep
	var expected_p2_food := 4 * flamethrower_food_upkeep
	_check(float(upkeep["p1"].get(ResourceType.Type.FOOD, 0.0)) == expected_p1_food, "p1's own 2-member squad upkeep tallied separately = %s" % expected_p1_food)
	_check(float(upkeep["p2"].get(ResourceType.Type.FOOD, 0.0)) == expected_p2_food, "p2's own 4-member squad upkeep tallied separately = %s" % expected_p2_food)

func _test_upkeep_deficit_deaths() -> void:
	# A squad whose troop type doesn't consume the deficient resource is untouched.
	var troops: Dictionary = {}
	var chonky_squad := _make_squad("p1", "chonky", HexCoord.new(0, 0), 2, troops)
	var squads: Array[SquadInstance] = [chonky_squad]
	var killed := UpkeepSystem.apply_deficit_deaths("p1", [ResourceType.Type.FOOD], squads, troops, _troop_defs)
	_check(killed.is_empty(), "Fuel-only squad untouched by a Food deficit")
	_check(chonky_squad.member_ids.size() == 2, "no member removed")

	# A squad whose troop type does consume the deficient resource loses its
	# weakest (lowest current_hp) member.
	troops = {}
	var infantry := _make_squad("p1", "flamethrower", HexCoord.new(0, 0), 3, troops)
	var weak_id: String = infantry.member_ids[1]
	troops[weak_id].current_hp = 1.0
	squads = [infantry]
	killed = UpkeepSystem.apply_deficit_deaths("p1", [ResourceType.Type.FOOD], squads, troops, _troop_defs)
	_check(killed == [weak_id], "the lowest-HP member is the one killed")
	_check(infantry.member_ids.size() == 2, "squad shrinks by exactly one member")
	_check(not troops.has(weak_id), "killed troop removed from the registry")

	# A squad emptied by this (its last member killed) is disbanded entirely.
	troops = {}
	var lone_squad := _make_squad("p1", "flamethrower", HexCoord.new(0, 0), 1, troops)
	squads = [lone_squad]
	killed = UpkeepSystem.apply_deficit_deaths("p1", [ResourceType.Type.FOOD], squads, troops, _troop_defs)
	_check(killed.size() == 1, "the squad's only member is killed")
	_check(squads.is_empty(), "the emptied squad is disbanded/removed")

	# Only the affected owner's squads are touched.
	troops = {}
	var p1_inf := _make_squad("p1", "flamethrower", HexCoord.new(0, 0), 2, troops)
	var p2_inf := _make_squad("p2", "flamethrower", HexCoord.new(5, 5), 2, troops)
	squads = [p1_inf, p2_inf]
	killed = UpkeepSystem.apply_deficit_deaths("p1", [ResourceType.Type.FOOD], squads, troops, _troop_defs)
	_check(killed.size() == 1, "only p1's squad is affected")
	_check(p2_inf.member_ids.size() == 2, "p2's squad is untouched by p1's deficit")

	# No deficits: no-op.
	troops = {}
	var untouched := _make_squad("p1", "flamethrower", HexCoord.new(0, 0), 2, troops)
	squads = [untouched]
	killed = UpkeepSystem.apply_deficit_deaths("p1", [], squads, troops, _troop_defs)
	_check(killed.is_empty(), "empty deficits list kills nothing")
