## Headless assertion suite for sim/data, sim/instances, sim/units. Run with:
##   godot --headless --script res://tests/test_units.gd
extends SceneTree

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	print("DataLoader")
	_test_data_loader()
	print("CommanderProgression")
	_test_commander_progression()
	print("SquadCap")
	_test_squad_cap()
	print("TroopInstance / SquadInstance / RegimentInstance")
	_test_instances()
	print("SquadManager")
	_test_squad_manager()
	print("ProductionQueue / ProductionManager")
	_test_production_queue()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _test_data_loader() -> void:
	var troops := DataLoader.load_dir("res://data/troops")
	_check(troops.has("rifleman"), "troop defs include rifleman")
	_check(not troops.has("schema"), "schema.json is skipped")
	_check(troops["rifleman"]["domain"] == "Infantry", "rifleman def has parsed fields")

	var buildings := DataLoader.load_dir("res://data/buildings")
	_check(buildings.has("command_centre"), "building defs include command_centre")
	_check(buildings["command_centre"].has("commanderProgression"), "command_centre def has commanderProgression")

	var bases := DataLoader.load_dir("res://data/bases")
	_check(bases.has("capital"), "base defs include capital")

func _test_commander_progression() -> void:
	var progression: Dictionary = DataLoader.load_dir("res://data/buildings")["command_centre"]["commanderProgression"]
	_check(CommanderProgression.slots_at_level(progression, 1) == 1, "level 1 -> 1 slot")
	_check(CommanderProgression.slots_at_level(progression, 3) == 1, "level 3 -> 1 slot (tiers unlock, cap stays 1)")
	_check(CommanderProgression.slots_at_level(progression, 4) == 2, "level 4 -> 2 slots (+1 postTierGrowth)")
	_check(CommanderProgression.slots_at_level(progression, 6) == 4, "level 6 -> 4 slots (+1 per level past 3)")

func _test_squad_cap() -> void:
	var one_capital: Array[BaseInstance] = [BaseInstance.new("b1", "capital", "p1", 1)]
	_check(SquadCap.max_squads(one_capital) == 4, "fresh level-1 Capital -> maxSquads 4")

	var two_bases: Array[BaseInstance] = [
		BaseInstance.new("b1", "capital", "p1", 2),
		BaseInstance.new("b2", "fort_irongrad", "p1", 3),
	]
	_check(SquadCap.max_squads(two_bases) == 12, "hqLevel 2 + 3 -> maxSquads (2+3)*2+2 = 12")

	var building_defs := DataLoader.load_dir("res://data/buildings")
	var base_with_ccs := BaseInstance.new("b1", "capital", "p1", 1)
	base_with_ccs.buildings.append(BuildingInstance.new("cc1", "b1", "command_centre", 1))
	base_with_ccs.buildings.append(BuildingInstance.new("cc2", "b1", "command_centre", 4))
	var bases_with_ccs: Array[BaseInstance] = [base_with_ccs]
	_check(SquadCap.max_commanders(bases_with_ccs, building_defs) == 3, "level-1 + level-4 Command Centre -> maxCommanders 1+2=3")

	var no_ccs: Array[BaseInstance] = [BaseInstance.new("b1", "capital", "p1", 1)]
	_check(SquadCap.max_commanders(no_ccs, building_defs) == 0, "no Command Centre -> maxCommanders 0")

func _test_instances() -> void:
	var troop := TroopInstance.new("t1", "rifleman", "p1", "s1", 40.0)
	_check(troop.owner_id == "p1", "TroopInstance stores ownerId")
	_check(troop.active_buffs.is_empty(), "TroopInstance starts with no active buffs")

	var squad := SquadInstance.new("s1", "p1", "rifleman", HexCoord.new(0, 0))
	_check(not squad.is_full(4), "empty squad isn't full")
	squad.add_member("t1")
	squad.add_member("t2")
	squad.add_member("t3")
	squad.add_member("t4")
	_check(squad.is_full(4), "squad at maxSquadSize reports full")
	squad.remove_member("t4")
	_check(not squad.is_full(4), "removing a member frees a slot")

	var regiment := RegimentInstance.new("r1", "commander1")
	_check(regiment.assign_squad("s1", 4), "assign_squad succeeds under cap")
	_check(regiment.assign_squad("s2", 4), "assign_squad succeeds under cap")
	_check(regiment.assign_squad("s3", 4), "assign_squad succeeds under cap")
	_check(regiment.assign_squad("s4", 4), "assign_squad fills regiment to maxSquadsLed")
	_check(not regiment.assign_squad("s5", 4), "assign_squad rejected once regiment is full")
	_check(regiment.squad_ids.size() == 4, "rejected assignment did not append")
	regiment.remove_squad("s1")
	_check(regiment.assign_squad("s5", 4), "assign_squad succeeds again after a squad leaves")

func _test_squad_manager() -> void:
	var full_squad := SquadInstance.new("s1", "p1", "rifleman", HexCoord.new(0, 0))
	full_squad.add_member("t1")
	full_squad.add_member("t2")
	var roomy_squad := SquadInstance.new("s2", "p1", "rifleman", HexCoord.new(1, 0))
	var far_squad := SquadInstance.new("s3", "p1", "rifleman", HexCoord.new(10, 0))
	var squads: Array[SquadInstance] = [full_squad, roomy_squad, far_squad]

	var spawn_hex := HexCoord.new(0, 0)
	var joined := SquadManager.find_joinable_squad(squads, "p1", "rifleman", spawn_hex, 2, 1)
	_check(joined != null and joined.id == "s2", "joins the in-range squad with room, skipping the full one")
	_check(not SquadManager.needs_new_squad(squads, "p1", "rifleman", spawn_hex, 2, 1), "needs_new_squad false when a joinable squad exists")

	var no_room: Array[SquadInstance] = [full_squad, far_squad]
	_check(SquadManager.needs_new_squad(no_room, "p1", "rifleman", spawn_hex, 2, 1), "needs_new_squad true when only full/out-of-range squads exist")

	var wrong_owner := SquadInstance.new("s4", "p2", "rifleman", HexCoord.new(0, 0))
	_check(SquadManager.needs_new_squad([wrong_owner], "p1", "rifleman", spawn_hex, 2, 1), "another player's squad is never joinable")

	var wrong_type := SquadInstance.new("s5", "p1", "grenadier", HexCoord.new(0, 0))
	_check(SquadManager.needs_new_squad([wrong_type], "p1", "rifleman", spawn_hex, 2, 1), "a different troopType squad is never joinable")

## Returns a Callable that yields "<prefix>1", "<prefix>2", ... on each call —
## ProductionManager.pump's next_troop_id/next_squad_id id generators.
func _id_generator(prefix: String) -> Callable:
	var counter := [0]
	return func() -> String:
		counter[0] += 1
		return "%s%d" % [prefix, counter[0]]

func _test_production_queue() -> void:
	var troop_defs := DataLoader.load_dir("res://data/troops")
	var building_defs := DataLoader.load_dir("res://data/buildings")
	var spawn_hex := HexCoord.new(0, 0)
	var troops: Dictionary = {}

	# enqueue + advance timing
	var queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(queue, "rifleman", troop_defs)
	_check(queue.entries[0]["production_time"] == 10.0, "enqueue reads productionTime from troop def")
	_check(queue.entries[0]["remaining"] == 10.0, "enqueue starts remaining at full productionTime")

	ProductionManager.advance(queue, 4.0)
	_check(queue.entries[0]["remaining"] == 6.0, "advance ticks front entry's remaining down")

	ProductionManager.enqueue(queue, "rifleman", troop_defs)
	ProductionManager.advance(queue, 6.0)
	_check(queue.front_complete(), "front entry completes once remaining hits 0")
	_check(queue.entries[1]["remaining"] == 10.0, "advance leaves later entries untouched (FIFO)")

	queue.paused = true
	var remaining_before: float = queue.entries[0]["remaining"]
	ProductionManager.advance(queue, 5.0)
	_check(queue.entries[0]["remaining"] == remaining_before, "advance is a no-op while paused")
	queue.paused = false

	# completion joins an in-range squad with room, bypassing the cap entirely
	var other_a := SquadInstance.new("oa", "p1", "grenadier", spawn_hex)
	var other_b := SquadInstance.new("ob", "p1", "grenadier", spawn_hex)
	var roomy := SquadInstance.new("s_roomy", "p1", "rifleman", spawn_hex)
	roomy.add_member("t_existing")
	var join_squads: Array[SquadInstance] = [other_a, other_b, roomy]
	var join_queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(join_queue, "rifleman", troop_defs)
	ProductionManager.advance(join_queue, 10.0)
	# owner already owns 3 squads against an (empty-bases) maxSquads of 2 --
	# joining must still succeed since an over-cap owner can still fill an
	# existing squad's spare room.
	ProductionManager.pump(join_queue, "p1", spawn_hex, "barracks", join_squads, troops, [], building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(join_queue.is_empty(), "completed entry that joins an existing squad is popped")
	_check(join_squads.size() == 3, "joining an existing squad does not create a new one")
	_check(roomy.member_ids.size() == 2, "joined troop is appended to the existing squad")

	# completion forms a new squad when under the squad cap
	var one_capital: Array[BaseInstance] = [BaseInstance.new("b1", "capital", "p1", 1)]
	var new_squad_queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(new_squad_queue, "rifleman", troop_defs)
	ProductionManager.advance(new_squad_queue, 10.0)
	var empty_squads: Array[SquadInstance] = []
	ProductionManager.pump(new_squad_queue, "p1", spawn_hex, "barracks", empty_squads, troops, one_capital, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(new_squad_queue.is_empty(), "completed entry that forms a new squad is popped")
	_check(empty_squads.size() == 1, "under cap -> a new squad is created")
	_check(empty_squads[0].member_ids.size() == 1, "the new squad has the newly trained troop")

	# pause at squad_cap: owner already at maxSquads, no joinable squad exists
	var at_cap_squads: Array[SquadInstance] = [
		SquadInstance.new("g1", "p1", "grenadier", spawn_hex),
		SquadInstance.new("g2", "p1", "grenadier", spawn_hex),
		SquadInstance.new("g3", "p1", "grenadier", spawn_hex),
		SquadInstance.new("g4", "p1", "grenadier", spawn_hex),
	]
	var pause_queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(pause_queue, "rifleman", troop_defs)
	ProductionManager.advance(pause_queue, 10.0)
	ProductionManager.pump(pause_queue, "p1", spawn_hex, "barracks", at_cap_squads, troops, one_capital, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(pause_queue.paused, "queue pauses when a new squad is needed at the squad cap")
	_check(pause_queue.pause_reason == "squad_cap", "pause_reason is squad_cap")
	_check(not pause_queue.is_empty(), "paused entry is held, not dropped")

	# auto-resume: freeing a slot and re-pumping deploys the held troop
	at_cap_squads.remove_at(0)
	ProductionManager.pump(pause_queue, "p1", spawn_hex, "barracks", at_cap_squads, troops, one_capital, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(not pause_queue.paused, "re-pumping after a slot frees clears the pause")
	_check(pause_queue.is_empty(), "held entry deploys once capacity is available again")
	_check(at_cap_squads.size() == 4, "the held troop formed its new squad on resume")

	# pause at commander_cap: Command Centre, no Command Centre built yet -> maxCommanders 0
	var commander_queue := ProductionQueue.new("cc1")
	ProductionManager.enqueue(commander_queue, "commander_vanguard", troop_defs)
	ProductionManager.advance(commander_queue, 45.0)
	var no_squads: Array[SquadInstance] = []
	ProductionManager.pump(commander_queue, "p1", spawn_hex, "command_centre", no_squads, troops, [], building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(commander_queue.paused, "queue pauses when a Commander is needed at the commander cap")
	_check(commander_queue.pause_reason == "commander_cap", "pause_reason is commander_cap")

	# auto-resume: a Command Centre gets built, raising maxCommanders to 1
	var base_with_cc := BaseInstance.new("b2", "capital", "p1", 1)
	base_with_cc.buildings.append(BuildingInstance.new("cc_bldg", "b2", "command_centre", 1))
	var bases_with_cc: Array[BaseInstance] = [base_with_cc]
	ProductionManager.pump(commander_queue, "p1", spawn_hex, "command_centre", no_squads, troops, bases_with_cc, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(not commander_queue.paused, "re-pumping after a Command Centre is built clears the commander_cap pause")
	_check(commander_queue.is_empty(), "held Commander deploys once the commander cap has room")
	_check(no_squads.size() == 1, "the deployed Commander formed its own squad")
