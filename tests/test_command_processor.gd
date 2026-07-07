## Headless assertion suite for the command/order-issuing layer
## (CommandProcessor/MatchState) — every player-facing action, both the
## success path and its ownership/eligibility rejections. Run with:
##   godot --headless --script res://tests/test_command_processor.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _base_defs: Dictionary

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

	print("move_squad")
	_test_move_squad()
	print("move_squad (regiment lock-step via a Commander)")
	_test_move_regiment()
	print("attack_target")
	_test_attack_target()
	print("board_cargo / unload_cargo")
	_test_cargo()
	print("assign_to_commander / leave_regiment")
	_test_regiment_assignment()
	print("place_building")
	_test_place_building()
	print("place_standalone_building (Engineer enforcement)")
	_test_place_standalone()
	print("place_wall")
	_test_place_wall()
	print("demolish_building")
	_test_demolish()
	print("rebuild_building")
	_test_rebuild()
	print("enqueue_production")
	_test_enqueue_production()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _flat_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), radius):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	return grid

func _new_state(grid: HexGrid) -> MatchState:
	var state := MatchState.new()
	state.grid = grid
	state.troop_defs = _troop_defs
	state.building_defs = _building_defs
	state.base_defs = _base_defs
	return state

func _make_squad(state: MatchState, owner: String, troop_type: String, hex: HexCoord, count: int = 1) -> SquadInstance:
	var squad := SquadInstance.new(state.next_squad_id(), owner, troop_type, hex)
	var hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 100.0))
	for i in range(count):
		var troop := TroopInstance.new(state.next_troop_id(), troop_type, owner, squad.id, hp)
		state.troops_by_id[troop.id] = troop
		squad.add_member(troop.id)
	state.squads.append(squad)
	return squad

func _test_move_squad() -> void:
	var state := _new_state(_flat_grid(10))
	var squad := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))

	_check(CommandProcessor.move_squad(state, "nonexistent", HexCoord.new(1, 0), "p1") == CommandProcessor.Result.NOT_FOUND, "unknown squad id -> NOT_FOUND")
	_check(CommandProcessor.move_squad(state, squad.id, HexCoord.new(1, 0), "p2") == CommandProcessor.Result.NOT_OWNER, "wrong owner -> NOT_OWNER")

	var result := CommandProcessor.move_squad(state, squad.id, HexCoord.new(3, 0), "p1")
	_check(result == CommandProcessor.Result.OK, "owner moving their own squad -> OK")
	_check(not squad.path.is_empty(), "a real path was issued")

	var carrier := _make_squad(state, "p1", "transport_truck", HexCoord.new(0, 0))
	CargoSystem.board(carrier, squad, _troop_defs)
	_check(CommandProcessor.move_squad(state, squad.id, HexCoord.new(2, 0), "p1") == CommandProcessor.Result.INVALID, "a boarded squad can't be moved directly")

func _test_move_regiment() -> void:
	var state := _new_state(_flat_grid(10))
	var commander := _make_squad(state, "p1", "commander_vanguard", HexCoord.new(0, 0))
	var escort := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))
	var regiment := RegimentInstance.new(state.next_id("regiment"), commander.id)
	regiment.assign_squad(escort.id, 4)
	state.regiments.append(regiment)

	var result := CommandProcessor.move_squad(state, commander.id, HexCoord.new(4, 0), "p1")
	_check(result == CommandProcessor.Result.OK, "moving a Commander leading a regiment succeeds")
	_check(escort.order.get("type", "") == "regiment_move", "the escort picked up a shared regiment_move order")
	_check(escort.path == commander.path, "the escort's path mirrors the Commander's shared path")

func _test_attack_target() -> void:
	var state := _new_state(_flat_grid(10))
	var attacker := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))
	var enemy := _make_squad(state, "p2", "rifleman", HexCoord.new(1, 0))
	var friendly := _make_squad(state, "p1", "rifleman", HexCoord.new(1, 0))

	_check(CommandProcessor.attack_target(state, "nope", enemy.id, "p1") == CommandProcessor.Result.NOT_FOUND, "unknown attacker -> NOT_FOUND")
	_check(CommandProcessor.attack_target(state, attacker.id, "nope", "p1") == CommandProcessor.Result.NOT_FOUND, "unknown target -> NOT_FOUND")
	_check(CommandProcessor.attack_target(state, attacker.id, friendly.id, "p1") == CommandProcessor.Result.INVALID, "targeting your own squad is rejected")

	var result := CommandProcessor.attack_target(state, attacker.id, enemy.id, "p1")
	_check(result == CommandProcessor.Result.OK, "attacking a live enemy squad -> OK")
	_check(attacker.order.get("type", "") == "attack_target" and attacker.order.get("targetId", "") == enemy.id, "the directed order is set on the squad")

func _test_cargo() -> void:
	var state := _new_state(_flat_grid(10))
	# HMS Cuddles: canLaunchCargoMidCombat false, per its own notes ("must be
	# idle/docked to unload") -- the carrier this in_combat gating actually
	# matters for. Unloading onto the carrier's OWN hex (rather than a
	# neighbor) sidesteps CargoSystem's separate Naval-landing-hex check
	# (skipped entirely for that case), isolating the in_combat gate this test
	# cares about.
	var carrier := _make_squad(state, "p1", "hms_cuddles", HexCoord.new(0, 0))
	var cargo := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))

	_check(CommandProcessor.board_cargo(state, carrier.id, cargo.id, "p2") == CommandProcessor.Result.NOT_OWNER, "boarding someone else's cargo is rejected")
	_check(CommandProcessor.board_cargo(state, carrier.id, cargo.id, "p1") == CommandProcessor.Result.OK, "boarding succeeds")
	_check(cargo.boarded_on_squad_id == carrier.id, "cargo squad now tracks its carrier")

	# Idle, no enemy nearby -> not in combat -> unload succeeds even for a
	# carrier without canLaunchCargoMidCombat.
	var result := CommandProcessor.unload_cargo(state, carrier.id, cargo.id, carrier.current_hex, "p1")
	_check(result == CommandProcessor.Result.OK, "unloading while not in combat succeeds")
	_check(cargo.boarded_on_squad_id == "", "cargo is no longer boarded")

	# Re-board, then put a living, armed enemy in range -> in_combat -> a
	# carrier without canLaunchCargoMidCombat is rejected.
	CargoSystem.board(carrier, cargo, _troop_defs)
	var enemy := _make_squad(state, "p2", "rifleman", HexCoord.new(1, 0))
	result = CommandProcessor.unload_cargo(state, carrier.id, cargo.id, carrier.current_hex, "p1")
	_check(result == CommandProcessor.Result.INVALID, "unloading a non-mid-combat carrier while an armed enemy is in range is rejected")
	_check(cargo.boarded_on_squad_id == carrier.id, "the rejected unload left cargo still boarded")

func _test_regiment_assignment() -> void:
	var state := _new_state(_flat_grid(10))
	var commander := _make_squad(state, "p1", "commander_vanguard", HexCoord.new(0, 0))
	var squad_a := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))
	var not_a_commander := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))

	_check(CommandProcessor.assign_to_commander(state, squad_a.id, commander.id, "p2") == CommandProcessor.Result.NOT_OWNER, "assigning someone else's squad is rejected")
	_check(CommandProcessor.assign_to_commander(state, squad_a.id, not_a_commander.id, "p1") == CommandProcessor.Result.INVALID, "targeting a non-Commander squad is rejected")

	var result := CommandProcessor.assign_to_commander(state, squad_a.id, commander.id, "p1")
	_check(result == CommandProcessor.Result.OK, "assigning to a Commander succeeds, creating the regiment")
	_check(squad_a.commander_id == commander.id, "the squad's commander_id is set")
	_check(state.regiments.size() == 1 and state.regiments[0].squad_ids.has(squad_a.id), "a RegimentInstance now tracks the assignment")

	# maxSquadsLed is 4 for Vanguard -- fill the regiment then overflow it.
	var filled: Array[SquadInstance] = []
	for i in range(3):
		var s := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))
		filled.append(s)
		_check(CommandProcessor.assign_to_commander(state, s.id, commander.id, "p1") == CommandProcessor.Result.OK, "filling the regiment up to maxSquadsLed succeeds")
	var overflow := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0))
	_check(CommandProcessor.assign_to_commander(state, overflow.id, commander.id, "p1") == CommandProcessor.Result.REGIMENT_FULL, "a 5th escort is rejected once the regiment is full")

	_check(CommandProcessor.leave_regiment(state, overflow.id, "p1") == CommandProcessor.Result.INVALID, "leave_regiment on a squad with no commander is rejected")
	_check(CommandProcessor.leave_regiment(state, squad_a.id, "p1") == CommandProcessor.Result.OK, "leave_regiment succeeds")
	_check(squad_a.commander_id == "", "commander_id cleared after leaving")
	_check(not state.regiments[0].squad_ids.has(squad_a.id), "the regiment no longer lists the departed squad")

func _test_place_building() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)

	# (2,-1) is adjacent to both the seeded Farm (1,0) and Quarry (1,-1),
	# satisfying the 2-adjacent-buildings expansion rule.
	_check(CommandProcessor.place_building(state, "nope", "house", HexCoord.new(2, -1), "", "p1") == BuildingPlacement.Result.BASE_NOT_FOUND, "unknown base -> BASE_NOT_FOUND")
	_check(CommandProcessor.place_building(state, base.id, "house", HexCoord.new(2, -1), "", "p2") == BuildingPlacement.Result.NOT_OWNER, "wrong owner -> NOT_OWNER")

	# Insufficient resources rejects the placement outright — nothing is
	# appended to base.buildings and nothing is deducted.
	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 0.0)
	var building_count_before := base.buildings.size()
	var poor := CommandProcessor.place_building(state, base.id, "house", HexCoord.new(2, -1), "", "p1")
	_check(poor == BuildingPlacement.Result.INSUFFICIENT_RESOURCES, "placing without enough resources is rejected")
	_check(base.buildings.size() == building_count_before, "the rejected placement built nothing")

	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 100.0)
	var result := CommandProcessor.place_building(state, base.id, "house", HexCoord.new(2, -1), "", "p1")
	_check(result == BuildingPlacement.Result.OK, "owner placing a valid building succeeds")
	var placed := base.buildings[base.buildings.size() - 1]
	_check(placed.max_hp > 0.0, "the placed building has combat HP initialized")
	_check(not placed.total_resources_spent.is_empty(), "the placed building's total_resources_spent is initialized from its build cost")
	var expected_cost: float = placed.total_resources_spent.get(ResourceType.Type.STONE, 0.0)
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == 100.0 - expected_cost, "placement deducted its build cost from the owner's pool")

func _test_place_standalone() -> void:
	var state := _new_state(_flat_grid(5))
	var rifleman_squad := _make_squad(state, "p1", "rifleman", HexCoord.new(2, 0))
	var engineer_squad := _make_squad(state, "p1", "engineer", HexCoord.new(2, 0))

	# Placed one hex away from where the squads stand -- a Land-domain squad
	# occupying a hex blocks a NEW building there (ground_unit_hexes), same
	# rule any other placement already respects; unrelated to the
	# Engineer-only check this test targets.
	var target_hex := HexCoord.new(3, 0)
	var rejected := CommandProcessor.place_standalone_building(state, rifleman_squad.id, "tower", target_hex, "stone", "p1")
	_check(rejected == BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE, "a non-Engineer squad can't place standalone infrastructure")
	_check(state.standalone_buildings.is_empty(), "the rejected placement built nothing")

	# A Stone Tower (150 stone + 100 steel) costs more than the default
	# starting pool (100 stone, 50 steel) -- an eligible Engineer still gets
	# turned away for insufficient resources, and nothing is deducted or built.
	var stone_before := state.pool_for("p1").get_amount(ResourceType.Type.STONE)
	var poor := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", target_hex, "stone", "p1")
	_check(poor == BuildingPlacement.Result.INSUFFICIENT_RESOURCES, "an Engineer squad without enough resources is still rejected")
	_check(state.standalone_buildings.is_empty(), "the rejected placement built nothing")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == stone_before, "a rejected placement deducts nothing")

	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 500.0)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 500.0)
	var ok := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", target_hex, "stone", "p1")
	_check(ok == BuildingPlacement.Result.OK, "an Engineer squad can place standalone infrastructure")
	_check(state.standalone_buildings.size() == 1, "the Tower was actually placed")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == 500.0 - 150.0, "placement deducted the Tower's stone cost")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STEEL) == 500.0 - 100.0, "placement deducted the Tower's steel cost")

	var wrong_owner := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", HexCoord.new(-2, 0), "stone", "p2")
	_check(wrong_owner == BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE, "issuing as a different owner than the squad's own is rejected")

	# The Engineer is still at (2,0) -- a target hex further than
	# STANDALONE_BUILD_RANGE away is rejected even though everything else
	# about the order (ownership, eligibility, cost) is valid.
	var far_hex := HexCoord.new(2, 5)
	var too_far := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", far_hex, "stone", "p1")
	_check(too_far == BuildingPlacement.Result.OUT_OF_ENGINEER_RANGE, "a target hex out of the Engineer's build range is rejected")
	_check(state.standalone_buildings.size() == 1, "the out-of-range order built nothing")

func _test_place_wall() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var hq := base.buildings_of_type("hq")[0]
	var neighbor := HexCoord.neighbor(hq.hex, 3)

	var stone_before := state.pool_for("p1").get_amount(ResourceType.Type.STONE)
	var result := CommandProcessor.place_wall(state, base.id, hq.hex, neighbor, "stone", "p1")
	_check(result == BuildingPlacement.Result.OK, "placing a Wall adjacent to an existing building succeeds")
	_check(state.grid.is_walled_edge(hq.hex, neighbor), "the grid records the new wall's edge")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == stone_before - 40.0, "placing a Stone Wall deducted its 40-stone cost")

func _test_demolish() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	CommandProcessor.place_building(state, base.id, "house", HexCoord.new(-1, 0), "", "p1")
	var house: BuildingInstance = base.buildings[base.buildings.size() - 1]
	var expected_refund: float = float(house.total_resources_spent.get(ResourceType.Type.STONE, 0.0)) * 0.5
	var stone_before := state.pool_for("p1").get_amount(ResourceType.Type.STONE)

	_check(CommandProcessor.demolish_building(state, house.id, "p2") == CommandProcessor.Result.NOT_OWNER, "demolishing someone else's building is rejected")

	var hq := base.buildings_of_type("hq")[0]
	_check(CommandProcessor.demolish_building(state, hq.id, "p1") == CommandProcessor.Result.IS_FIXED, "an isFixed building (HQ) cannot be demolished")

	var result := CommandProcessor.demolish_building(state, house.id, "p1")
	_check(result == CommandProcessor.Result.OK, "demolishing your own non-fixed building succeeds")
	_check(not base.buildings.has(house), "the demolished building is removed from the base")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == stone_before + expected_refund, "demolish refunds exactly 50% of total_resources_spent")

	# Standalone building demolish (Tower) also refunds and deletes outright.
	# Tower placed a hex away from the Engineer itself -- see
	# _test_place_standalone's note on ground_unit_hexes self-blocking.
	var engineer_squad := _make_squad(state, "p1", "engineer", HexCoord.new(3, 0))
	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 500.0)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 500.0)
	CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", HexCoord.new(4, 0), "stone", "p1")
	_check(not state.standalone_buildings.is_empty(), "the Tower placement for this section succeeded (fixture assumption)")
	var tower: BuildingInstance = state.standalone_buildings[0]
	_check(CommandProcessor.demolish_building(state, tower.id, "p1") == CommandProcessor.Result.OK, "demolishing a standalone building succeeds")
	_check(state.standalone_buildings.is_empty(), "the standalone building is removed")

func _test_rebuild() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var farm := base.buildings_of_type("farm")[0]

	_check(CommandProcessor.rebuild_building(state, farm.id, "p1") == CommandProcessor.Result.INVALID, "rebuilding a non-ruined building is rejected")

	farm.is_ruin = true
	farm.current_hp = 0.0
	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 0.0)
	_check(CommandProcessor.rebuild_building(state, farm.id, "p1") == CommandProcessor.Result.INSUFFICIENT_RESOURCES, "rebuilding without enough resources is rejected")
	_check(farm.is_ruin, "a rejected rebuild leaves the ruin untouched")

	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 1000.0)
	var result := CommandProcessor.rebuild_building(state, farm.id, "p1")
	_check(result == CommandProcessor.Result.OK, "rebuilding with enough resources succeeds")
	_check(not farm.is_ruin, "the building is no longer a ruin")
	_check(farm.current_hp == farm.max_hp, "the rebuilt building is at full HP")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) < 1000.0, "rebuild cost was actually deducted from the pool")

func _test_enqueue_production() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var barracks := BuildingInstance.new("barracks1", base.id, "barracks", 1, "", HexCoord.new(1, -1))
	barracks.init_hp(_building_defs["barracks"], _building_defs)
	base.buildings.append(barracks)

	_check(CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p2") == CommandProcessor.Result.NOT_OWNER, "queuing at someone else's building is rejected")

	# Rifleman costs 20 Food -- draining the pool rejects the order for
	# insufficient resources and enqueues nothing.
	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, 0.0)
	var poor := CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	_check(poor == CommandProcessor.Result.INSUFFICIENT_RESOURCES, "queuing without enough resources is rejected")
	_check(not state.production_queues.has(barracks.id), "the rejected order created no ProductionQueue")

	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, 100.0)
	var result := CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	_check(result == CommandProcessor.Result.OK, "queuing at your own Production building succeeds")
	_check(state.production_queues.has(barracks.id), "a ProductionQueue was created and registered for this building")
	_check(state.production_queues[barracks.id].entries.size() == 1, "the troop was enqueued")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.FOOD) == 80.0, "enqueuing deducted the troop's Food cost from the pool")
