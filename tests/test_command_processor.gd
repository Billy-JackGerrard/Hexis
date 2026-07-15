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
	print("dock_squad / undock_squad")
	_test_dock()
	print("assign_to_commander / leave_regiment")
	_test_regiment_assignment()
	print("merge_squads")
	_test_merge_squads()
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
	print("upgrade_building")
	_test_upgrade()
	print("upgrade_building (Production max level)")
	_test_upgrade_max_level()
	print("upgrade_building (HQ ceiling + population gate)")
	_test_upgrade_hq()
	print("enqueue_production")
	_test_enqueue_production()
	print("enqueue_production (squad/Commander cap gate)")
	_test_enqueue_production_cap_gate()
	print("dequeue_production / enqueue_production_after (queue -1/+1)")
	_test_queue_adjust()

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

	# A boarded/docked squad can't be given an attack order either — it has
	# no independent position to fire from.
	var carrier := _make_squad(state, "p1", "transport_truck", HexCoord.new(0, 0))
	CargoSystem.board(carrier, attacker, _troop_defs)
	_check(CommandProcessor.attack_target(state, attacker.id, enemy.id, "p1") == CommandProcessor.Result.INVALID, "a boarded squad can't be given an attack order")

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
	# HMS Cuddles is Naval-domain and (0,0) isn't Naval-passable on a flat
	# land grid, so per CargoSystem.can_board's coastline rule the pickup hex
	# needs a Dock -- same requirement unload already enforces in reverse.
	state.standalone_buildings.append(BuildingInstance.new("dock_cargo", "", "dock", 1, "stone", HexCoord.new(0, 0), "p1"))

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

func _make_hangar(state: MatchState, owner: String, hex: HexCoord) -> BuildingInstance:
	var base := BaseInstance.new(state.next_id("base"), "capital", owner, 1, hex)
	var hangar := BuildingInstance.new(state.next_id("hangar"), base.id, "hangar", 1, "", hex)
	hangar.init_hp(_building_defs["hangar"], _building_defs)
	base.buildings.append(hangar)
	state.bases.append(base)
	return hangar

func _test_dock() -> void:
	var state := _new_state(_flat_grid(10))
	var hangar := _make_hangar(state, "p1", HexCoord.new(0, 0))
	var glider := _make_squad(state, "p1", "glider", HexCoord.new(0, 0))

	_check(CommandProcessor.dock_squad(state, glider.id, hangar.id, "p2") == CommandProcessor.Result.NOT_OWNER, "docking someone else's squad is rejected")
	_check(CommandProcessor.dock_squad(state, glider.id, "nonexistent", "p1") == CommandProcessor.Result.NOT_FOUND, "unknown building id -> NOT_FOUND")
	_check(CommandProcessor.dock_squad(state, glider.id, hangar.id, "p1") == CommandProcessor.Result.OK, "docking succeeds")
	_check(glider.docked_building_id == hangar.id, "docked squad now tracks its Hangar")

	# Idle, no enemy nearby -> not in combat -> undock succeeds even for a
	# building without canLaunchCargoMidCombat (moot here since Hangar's is
	# true, but exercises the same code path unload_cargo's test does).
	var result := CommandProcessor.undock_squad(state, glider.id, hangar.id, hangar.hex, "p1")
	_check(result == CommandProcessor.Result.OK, "undocking while not in combat succeeds")
	_check(glider.docked_building_id == "", "squad is no longer docked")

	# Re-dock, then put a living, armed enemy in range -> in_combat -> still
	# succeeds because Hangar's canLaunchCargoMidCombat is true.
	CommandProcessor.dock_squad(state, glider.id, hangar.id, "p1")
	var enemy := _make_squad(state, "p2", "rifleman", HexCoord.new(1, 0))
	result = CommandProcessor.undock_squad(state, glider.id, hangar.id, hangar.hex, "p1")
	_check(result == CommandProcessor.Result.OK, "Hangar can still launch mid-combat (canLaunchCargoMidCombat: true)")

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

func _test_merge_squads() -> void:
	var state := _new_state(_flat_grid(10))

	_check(CommandProcessor.merge_squads(state, "nope1", "nope2", "p1") == CommandProcessor.Result.NOT_FOUND, "unknown squad ids -> NOT_FOUND")

	var solo := _make_squad(state, "p1", "rifleman", HexCoord.new(0, 0), 3)
	_check(CommandProcessor.merge_squads(state, solo.id, solo.id, "p1") == CommandProcessor.Result.INVALID, "merging a squad into itself is rejected")

	var mine := _make_squad(state, "p1", "rifleman", HexCoord.new(1, 0), 3)
	var theirs := _make_squad(state, "p2", "rifleman", HexCoord.new(1, 0), 3)
	_check(CommandProcessor.merge_squads(state, mine.id, theirs.id, "p1") == CommandProcessor.Result.NOT_OWNER, "merging someone else's squad in is rejected")
	_check(CommandProcessor.merge_squads(state, theirs.id, mine.id, "p2") == CommandProcessor.Result.NOT_OWNER, "wrong owner issuing the order is rejected")

	var engineer := _make_squad(state, "p1", "engineer", HexCoord.new(1, 0))
	_check(CommandProcessor.merge_squads(state, mine.id, engineer.id, "p1") == CommandProcessor.Result.INVALID, "merging different troop types is rejected")

	var commander_target := _make_squad(state, "p1", "commander_vanguard", HexCoord.new(1, 0))
	var commander_donor := _make_squad(state, "p1", "commander_vanguard", HexCoord.new(1, 0))
	_check(CommandProcessor.merge_squads(state, commander_target.id, commander_donor.id, "p1") == CommandProcessor.Result.INVALID, "a Commander squad can't be merged away as a donor")

	var far := _make_squad(state, "p1", "rifleman", HexCoord.new(5, 0), 1)
	_check(CommandProcessor.merge_squads(state, mine.id, far.id, "p1") == CommandProcessor.Result.NOT_ADJACENT, "merging squads that aren't on the same hex is rejected")

	var carrier := _make_squad(state, "p1", "transport_truck", HexCoord.new(1, 0))
	var boarded := _make_squad(state, "p1", "rifleman", HexCoord.new(1, 0), 1)
	CargoSystem.board(carrier, boarded, _troop_defs)
	_check(CommandProcessor.merge_squads(state, mine.id, boarded.id, "p1") == CommandProcessor.Result.INVALID, "a boarded donor squad can't be merged")
	_check(CommandProcessor.merge_squads(state, boarded.id, mine.id, "p1") == CommandProcessor.Result.INVALID, "a boarded target squad can't receive a merge")

	var loaded_cargo := _make_squad(state, "p1", "rifleman", HexCoord.new(1, 0), 1)
	var loaded_carrier := _make_squad(state, "p1", "transport_truck", HexCoord.new(1, 0))
	CargoSystem.board(loaded_carrier, loaded_cargo, _troop_defs)
	var another_carrier := _make_squad(state, "p1", "transport_truck", HexCoord.new(1, 0))
	_check(CommandProcessor.merge_squads(state, another_carrier.id, loaded_carrier.id, "p1") == CommandProcessor.Result.INVALID, "a donor squad still carrying cargo can't be merged away")

	var full_target := _make_squad(state, "p1", "rifleman", HexCoord.new(1, 0), 8)
	_check(CommandProcessor.merge_squads(state, full_target.id, mine.id, "p1") == CommandProcessor.Result.SQUAD_FULL, "merging into an already-full squad is rejected")

	# Full-drain merge, including regiment cleanup for a donor that was
	# assigned to a Commander.
	var target := _make_squad(state, "p1", "rifleman", HexCoord.new(2, 0), 5)
	var donor := _make_squad(state, "p1", "rifleman", HexCoord.new(2, 0), 2)
	var commander := _make_squad(state, "p1", "commander_vanguard", HexCoord.new(2, 0))
	CommandProcessor.assign_to_commander(state, donor.id, commander.id, "p1")
	var regiment := state.regiments[0]

	var result := CommandProcessor.merge_squads(state, target.id, donor.id, "p1")
	_check(result == CommandProcessor.Result.OK, "merging a smaller donor fully into a target with room succeeds")
	_check(target.member_ids.size() == 7, "the target absorbed all of the donor's members")
	_check(not state.squads.has(donor), "the fully-drained donor squad was removed")
	_check(not regiment.squad_ids.has(donor.id), "the drained donor was removed from its regiment")

	# Partial merge: the target fills up before the donor fully drains, so the
	# donor survives with its leftover members.
	var target2 := _make_squad(state, "p1", "rifleman", HexCoord.new(3, 0), 7)
	var donor2 := _make_squad(state, "p1", "rifleman", HexCoord.new(3, 0), 3)

	result = CommandProcessor.merge_squads(state, target2.id, donor2.id, "p1")
	var rifleman_max_squad_size: int = int(_troop_defs["rifleman"].get("maxSquadSize", 0))
	var donor2_leftover: int = 3 - (rifleman_max_squad_size - 7)
	_check(result == CommandProcessor.Result.OK, "merging a donor larger than the target's remaining room still succeeds")
	_check(target2.member_ids.size() == rifleman_max_squad_size, "the target filled up to maxSquadSize (%d)" % rifleman_max_squad_size)
	_check(donor2.member_ids.size() == donor2_leftover, "the donor kept its leftover members once the target filled")
	_check(state.squads.has(donor2), "a donor with leftover members is not removed")

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
	var tower_stone_cost: float = float(_building_defs["tower"].get("materialStats", {}).get("stone", {}).get("baseCost", {}).get("stone", 0.0))
	var tower_steel_cost: float = float(_building_defs["tower"].get("materialStats", {}).get("stone", {}).get("baseCost", {}).get("steel", 0.0))
	var ok := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", target_hex, "stone", "p1")
	_check(ok == BuildingPlacement.Result.OK, "an Engineer squad can place standalone infrastructure")
	_check(state.standalone_buildings.size() == 1, "the Tower was actually placed")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == 500.0 - tower_stone_cost, "placement deducted the Tower's stone cost (%s)" % tower_stone_cost)
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STEEL) == 500.0 - tower_steel_cost, "placement deducted the Tower's steel cost (%s)" % tower_steel_cost)

	var wrong_owner := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", HexCoord.new(-2, 0), "stone", "p2")
	_check(wrong_owner == BuildingPlacement.Result.CANNOT_BUILD_INFRASTRUCTURE, "issuing as a different owner than the squad's own is rejected")

	# The Engineer is still at (2,0) -- a target hex further than
	# Tuning.STANDALONE_BUILD_RANGE away is rejected even though everything else
	# about the order (ownership, eligibility, cost) is valid.
	var far_hex := HexCoord.new(2, 5)
	var too_far := CommandProcessor.place_standalone_building(state, engineer_squad.id, "tower", far_hex, "stone", "p1")
	_check(too_far == BuildingPlacement.Result.OUT_OF_ENGINEER_RANGE, "a target hex out of the Engineer's build range is rejected")
	_check(state.standalone_buildings.size() == 1, "the out-of-range order built nothing")

func _test_place_wall() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	base.hq_level = 2 # Wall's unlockHqLevel is 2 -- this test targets place_wall itself, not the unlock gate.
	var hq := base.buildings_of_type("hq")[0]
	var neighbor := HexCoord.neighbor(hq.hex, 3)

	var stone_before := state.pool_for("p1").get_amount(ResourceType.Type.STONE)
	var wall_stone_cost: float = float(_building_defs["wall"].get("materialStats", {}).get("stone", {}).get("baseCost", {}).get("stone", 0.0))
	var result := CommandProcessor.place_wall(state, base.id, hq.hex, neighbor, "stone", "p1")
	_check(result == BuildingPlacement.Result.OK, "placing a Wall adjacent to an existing building succeeds")
	_check(state.grid.is_walled_edge(hq.hex, neighbor), "the grid records the new wall's edge")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) == stone_before - wall_stone_cost, "placing a Stone Wall deducted its %s-stone cost" % wall_stone_cost)

func _test_demolish() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	CommandProcessor.place_building(state, base.id, "house", HexCoord.new(-1, 0), "", "p1")
	var house: BuildingInstance = base.buildings[base.buildings.size() - 1]
	var expected_refund: float = float(house.total_resources_spent.get(ResourceType.Type.STONE, 0.0)) * Tuning.DEMOLISH_REFUND_FRACTION
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

	# A building with unlockHqLevel > the base's current HQ level (e.g. inherited
	# by capturing a Unique base, then ruined) can't be rebuilt until the HQ
	# catches up — same gate as a fresh build, per 02-bases-and-buildings.md's
	# Building Unlock Levels section.
	var hospital := BuildingInstance.new("hospital1", base.id, "hospital", 1, "", HexCoord.new(1, 0))
	hospital.init_hp(_building_defs["hospital"], _building_defs)
	hospital.init_cost(_building_defs["hospital"], _building_defs)
	hospital.is_ruin = true
	hospital.current_hp = 0.0
	base.buildings.append(hospital)
	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 1000.0)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 1000.0)
	_check(base.hq_level == 1, "fixture assumption: base's HQ is still level 1")
	_check(CommandProcessor.rebuild_building(state, hospital.id, "p1") == CommandProcessor.Result.NOT_UNLOCKED,
		"rebuilding a ruin whose type needs a higher HQ level than the base currently has is rejected")
	_check(hospital.is_ruin, "the rejected rebuild leaves the ruin untouched")

	base.hq_level = 3
	_check(CommandProcessor.rebuild_building(state, hospital.id, "p1") == CommandProcessor.Result.OK,
		"once the HQ reaches the required level, the same ruin can be rebuilt")

func _test_upgrade() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var farm := base.buildings_of_type("farm")[0]

	_check(CommandProcessor.upgrade_building(state, farm.id, "p2") == CommandProcessor.Result.NOT_OWNER, "upgrading someone else's building is rejected")
	_check(CommandProcessor.upgrade_building(state, farm.id, "p1") == CommandProcessor.Result.HQ_LEVEL_TOO_LOW, "upgrading past the HQ's own level (still 1) is rejected")
	_check(farm.level == 1, "the rejected upgrade left the farm's level untouched")

	# Raise the HQ ceiling by hand (isolating this test from HQ's own upgrade
	# path, covered separately in _test_upgrade_hq) so the Farm has room to
	# climb.
	base.hq_level = 5
	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 0.0)
	_check(CommandProcessor.upgrade_building(state, farm.id, "p1") == CommandProcessor.Result.INSUFFICIENT_RESOURCES, "upgrading without enough resources is rejected")

	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 1000.0)
	var stone_before := state.pool_for("p1").get_amount(ResourceType.Type.STONE)
	var level1_hp := farm.max_hp
	var farm_level1_stone_cost: float = float(_building_defs["farm"].get("nonProductionUpgrade", {}).get("baseCost", {}).get("stone", 0.0))
	var result := CommandProcessor.upgrade_building(state, farm.id, "p1")
	_check(result == CommandProcessor.Result.OK, "upgrading with enough resources under the HQ ceiling succeeds")
	_check(farm.level == 2, "the farm's level incremented")
	_check(farm.max_hp > level1_hp, "max_hp grew with the level (statGrowth)")
	_check(farm.current_hp == farm.max_hp, "an undamaged building stays at full HP after upgrading")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.STONE) < stone_before, "the upgrade cost was deducted from the pool")
	_check(float(farm.total_resources_spent.get(ResourceType.Type.STONE, 0.0)) > farm_level1_stone_cost, "total_resources_spent grew past the level-1 build cost (%s)" % farm_level1_stone_cost)

	# Damage it partway, then upgrade again -- HP should scale proportionally
	# with the new max, not free-heal back to full (that's rebuild_building's
	# behavior, not upgrade's).
	farm.current_hp = farm.max_hp * 0.5
	var damaged_ratio := farm.current_hp / farm.max_hp
	CommandProcessor.upgrade_building(state, farm.id, "p1")
	_check(farm.level == 3, "the farm upgraded a second time")
	_check(absf(farm.current_hp / farm.max_hp - damaged_ratio) < 0.001, "upgrading preserves the damaged HP fraction instead of free-healing")

	farm.is_ruin = true
	_check(CommandProcessor.upgrade_building(state, farm.id, "p1") == CommandProcessor.Result.INVALID, "a ruined building can't be upgraded")

func _test_upgrade_max_level() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	base.hq_level = 10 # room enough that only Barracks' own cap is being tested
	var barracks := BuildingInstance.new("barracks1", base.id, "barracks", 1, "", HexCoord.new(1, -1))
	barracks.init_hp(_building_defs["barracks"], _building_defs)
	barracks.init_cost(_building_defs["barracks"], _building_defs)
	base.buildings.append(barracks)

	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 100000.0)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 100000.0)
	var barracks_max_level: int = int(_building_defs["barracks"].get("productionUpgradeLevels", []).size())
	for i in range(4):
		_check(CommandProcessor.upgrade_building(state, barracks.id, "p1") == CommandProcessor.Result.OK, "upgrading Barracks up through its productionUpgradeLevels table succeeds")
	_check(barracks.level == barracks_max_level, "Barracks reached its max level (%d, the length of its productionUpgradeLevels table)" % barracks_max_level)
	_check(CommandProcessor.upgrade_building(state, barracks.id, "p1") == CommandProcessor.Result.MAX_LEVEL, "upgrading past a Production building's derived max level is rejected")

func _test_upgrade_hq() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var hq := base.buildings_of_type("hq")[0]
	state.pool_for("p1").set_amount(ResourceType.Type.STONE, 100000.0)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 100000.0)

	# Capital seeds HQ + Farm + Quarry + Command Centre -- populationUsed is
	# already 3 (Farm/Quarry/Command Centre cost 1 each; HQ itself is
	# populationCost 0), which already meets hq.json's minPopulationPerLevel:3
	# requirement for level 2 (3 * (2-1)), so the very first HQ upgrade
	# succeeds immediately with no further building needed.
	var first_upgrade := CommandProcessor.upgrade_building(state, hq.id, "p1")
	_check(first_upgrade == CommandProcessor.Result.OK, "level-1->2 HQ upgrade succeeds immediately (seeded populationUsed already meets the level-2 gate)")
	_check(base.hq_level == 2, "hq_level advanced to 2")

	# Level 3 requires populationUsed >= 6 (3 * (3-1)) -- still short at 3.
	_check(CommandProcessor.upgrade_building(state, hq.id, "p1") == CommandProcessor.Result.NEED_MORE_POPULATION, "upgrading HQ without enough populationUsed is rejected")
	_check(base.hq_level == 2, "the rejected HQ upgrade left hq_level untouched")

	# A House (populationCost 0, always placeable, grants its own
	# populationCapacity) plus three more Farms at hexes each already
	# doubly-adjacent to two of the four seeded buildings raise populationUsed
	# from 3 to 6, meeting the level-3 gate.
	CommandProcessor.place_building(state, base.id, "house", HexCoord.new(2, -1), "", "p1")
	CommandProcessor.place_building(state, base.id, "farm", HexCoord.new(-1, 0), "", "p1")
	CommandProcessor.place_building(state, base.id, "farm", HexCoord.new(0, 1), "", "p1")
	CommandProcessor.place_building(state, base.id, "farm", HexCoord.new(1, -2), "", "p1")
	_check(Population.population_used(base, _building_defs) == 6, "three more Farms raised populationUsed to meet HQ's level-3 gate")

	var result := CommandProcessor.upgrade_building(state, hq.id, "p1")
	_check(result == CommandProcessor.Result.OK, "upgrading HQ once populationUsed meets the gate succeeds")
	_check(hq.level == 3, "the HQ BuildingInstance's own level incremented")
	_check(base.hq_level == 3, "BaseInstance.hq_level stays in lockstep with the HQ building's level")
	# HQ's own populationCapacity at its level (hq.json baseStats + flat
	# statGrowth) plus the House's own populationCapacity contribution.
	var hq_upgrade: Dictionary = _building_defs["hq"]["nonProductionUpgrade"]
	var hq_base_capacity: float = float(hq_upgrade["baseStats"]["populationCapacity"])
	var hq_capacity_growth: float = float(hq_upgrade["statGrowth"]["populationCapacity"]["value"])
	var hq_capacity: int = int(round(hq_base_capacity + hq_capacity_growth * (base.hq_level - 1)))
	var house_capacity: int = int(_building_defs["house"].get("nonProductionUpgrade", {}).get("baseStats", {}).get("populationCapacity", 0.0))
	var expected_population_cap: int = hq_capacity + house_capacity
	_check(Population.population_cap(base, _building_defs) == expected_population_cap, "population_cap grew from the HQ upgrade to %d (HQ's own level-%d capacity %d + House's %d capacity) -- it reads BaseInstance.hq_level, not the HQ BuildingInstance's own level" % [expected_population_cap, base.hq_level, hq_capacity, house_capacity])

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
	var rifleman_food_cost: float = float(_troop_defs["rifleman"].get("cost", {}).get("food", 0.0))
	var result := CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	_check(result == CommandProcessor.Result.OK, "queuing at your own Production building succeeds")
	_check(state.production_queues.has(barracks.id), "a ProductionQueue was created and registered for this building")
	_check(state.production_queues[barracks.id].entries.size() == 1, "the troop was enqueued")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.FOOD) == 100.0 - rifleman_food_cost, "enqueuing deducted the troop's Food cost (%s) from the pool" % rifleman_food_cost)

	# Level-gating: Barracks unlocks Grenadier at level 2 (data/buildings/barracks.json).
	# A level-1 Barracks must reject it, with nothing enqueued and nothing spent.
	var not_unlocked := CommandProcessor.enqueue_production(state, barracks.id, "grenadier", "p1")
	_check(not_unlocked == CommandProcessor.Result.NOT_UNLOCKED, "queuing a not-yet-unlocked troop is rejected")
	_check(state.production_queues[barracks.id].entries.size() == 1, "the rejected order enqueued nothing")

	barracks.level = 2
	var unlocked := CommandProcessor.enqueue_production(state, barracks.id, "grenadier", "p1")
	_check(unlocked == CommandProcessor.Result.OK, "queuing a troop unlocked by the building's current level succeeds")

	# Commander tier-gating: Command Centre level 1 unlocks only `common`
	# (Vanguard); `rare` (Nightfall) and `epic` (Warden) require levels 2/3.
	var cc := BuildingInstance.new("cc1", base.id, "command_centre", 1, "", HexCoord.new(0, 1))
	cc.init_hp(_building_defs["command_centre"], _building_defs)
	base.buildings.append(cc)
	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, 1000.0)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 1000.0)
	state.pool_for("p1").set_amount(ResourceType.Type.FUEL, 1000.0)

	_check(CommandProcessor.enqueue_production(state, cc.id, "commander_vanguard", "p1") == CommandProcessor.Result.OK, "a level-1 Command Centre can train a common-tier Commander")
	_check(CommandProcessor.enqueue_production(state, cc.id, "commander_nightfall", "p1") == CommandProcessor.Result.NOT_UNLOCKED, "a level-1 Command Centre cannot train a rare-tier Commander")
	_check(CommandProcessor.enqueue_production(state, cc.id, "commander_warden", "p1") == CommandProcessor.Result.NOT_UNLOCKED, "a level-1 Command Centre cannot train an epic-tier Commander")

	cc.level = 2
	_check(CommandProcessor.enqueue_production(state, cc.id, "commander_nightfall", "p1") == CommandProcessor.Result.OK, "a level-2 Command Centre can train a rare-tier Commander")
	_check(CommandProcessor.enqueue_production(state, cc.id, "commander_warden", "p1") == CommandProcessor.Result.NOT_UNLOCKED, "a level-2 Command Centre still cannot train an epic-tier Commander")

	cc.level = 3
	_check(CommandProcessor.enqueue_production(state, cc.id, "commander_warden", "p1") == CommandProcessor.Result.OK, "a level-3 Command Centre can train an epic-tier Commander")

## Squad/Commander cap must reject enqueue outright (no resources spent) when
## a brand-new squad would be needed and the owner's already at capacity --
## unless an existing same-type squad in range still has room, in which case
## training is allowed regardless of cap since the troop will just join it.
func _test_enqueue_production_cap_gate() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var barracks := BuildingInstance.new("barracks1", base.id, "barracks", 1, "", HexCoord.new(1, -1))
	barracks.init_hp(_building_defs["barracks"], _building_defs)
	base.buildings.append(barracks)
	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, 1000.0)

	var max_squads := SquadCap.max_squads(state.bases_owned_by("p1"))
	for i in range(max_squads):
		# A different troop_type than the one we're about to train, so none of
		# these can ever be a joinable squad -- only their count against the cap matters.
		state.squads.append(SquadInstance.new("filler%d" % i, "p1", "grenadier", barracks.hex))

	var capped := CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	_check(capped == CommandProcessor.Result.SQUAD_CAP_REACHED, "queuing a troop that needs a brand-new squad is rejected once the owner is at the global squad cap")
	_check(not state.production_queues.has(barracks.id), "the cap-rejected order enqueued nothing and spent no resources")

	# An existing same-type squad in range with room means no new squad is
	# needed -- training is allowed even though the owner is still at cap.
	state.squads.append(SquadInstance.new("joinable", "p1", "rifleman", barracks.hex))
	var joined := CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	_check(joined == CommandProcessor.Result.OK, "queuing a troop that could join an existing squad succeeds even at the squad cap")

	# Command Centre / Commander cap: same gate, driven by commander_count()
	# instead of live squad count.
	var cc := BuildingInstance.new("cc1", base.id, "command_centre", 1, "", HexCoord.new(0, 1))
	cc.init_hp(_building_defs["command_centre"], _building_defs)
	base.buildings.append(cc)
	state.pool_for("p1").set_amount(ResourceType.Type.STEEL, 1000.0)
	state.pool_for("p1").set_amount(ResourceType.Type.FUEL, 1000.0)

	var max_commanders := SquadCap.max_commanders(state.bases_owned_by("p1"), _building_defs)
	for i in range(max_commanders):
		state.troops_by_id["cmdr%d" % i] = TroopInstance.new("cmdr%d" % i, "commander_vanguard", "p1", "irrelevant", 1.0)

	var commander_capped := CommandProcessor.enqueue_production(state, cc.id, "commander_vanguard", "p1")
	_check(commander_capped == CommandProcessor.Result.COMMANDER_CAP_REACHED, "queuing a Commander is rejected once the owner is at the Commander cap")
	_check(not state.production_queues.has(cc.id), "the Commander-cap-rejected order enqueued nothing")

func _test_queue_adjust() -> void:
	var state := _new_state(_flat_grid(5))
	var base := BaseFactory.seed_base("base1", _base_defs["capital"], "p1", HexCoord.new(0, 0), state.grid, _building_defs)
	state.bases.append(base)
	var barracks := BuildingInstance.new("barracks1", base.id, "barracks", 1, "", HexCoord.new(1, -1))
	barracks.init_hp(_building_defs["barracks"], _building_defs)
	base.buildings.append(barracks)
	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, 1000.0)
	var rifleman_food_cost: float = float(_troop_defs["rifleman"].get("cost", {}).get("food", 0.0))

	for i in range(3):
		CommandProcessor.enqueue_production(state, barracks.id, "rifleman", "p1")
	var queue: ProductionQueue = state.production_queues[barracks.id]
	_check(queue.entries.size() == 3, "3 riflemen queued")
	var before_pool := state.pool_for("p1").get_amount(ResourceType.Type.FOOD)

	_check(CommandProcessor.dequeue_production(state, barracks.id, 0, "p1") == CommandProcessor.Result.INVALID, "index 0 -- the actively-training entry -- can't be cancelled")
	_check(CommandProcessor.dequeue_production(state, barracks.id, 5, "p1") == CommandProcessor.Result.INVALID, "out-of-range index is rejected")
	_check(CommandProcessor.dequeue_production(state, barracks.id, 2, "p2") == CommandProcessor.Result.NOT_OWNER, "cancelling someone else's queue entry is rejected")

	var removed := CommandProcessor.dequeue_production(state, barracks.id, 2, "p1")
	_check(removed == CommandProcessor.Result.OK, "-1 on the last queued entry succeeds")
	_check(queue.entries.size() == 2, "queue shrank by one")
	_check(state.pool_for("p1").get_amount(ResourceType.Type.FOOD) == before_pool + rifleman_food_cost, "-1 refunded the troop's Food cost")

	var added := CommandProcessor.enqueue_production_after(state, barracks.id, "rifleman", 1, "p1")
	_check(added == CommandProcessor.Result.OK, "+1 after the last rifleman entry succeeds")
	_check(queue.entries.size() == 3, "queue grew by one")
	_check(String(queue.entries[2].get("troop_type", "")) == "rifleman", "+1 inserted right after the run it was clicked from")

	state.pool_for("p1").set_amount(ResourceType.Type.FOOD, 0.0)
	var poor := CommandProcessor.enqueue_production_after(state, barracks.id, "rifleman", 1, "p1")
	_check(poor == CommandProcessor.Result.INSUFFICIENT_RESOURCES, "+1 without enough resources is rejected, same afford gate as enqueue_production")
