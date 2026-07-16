## Headless assertion suite for sim/data, sim/troops, sim/bases. Run with:
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
	print("ProductionManager Land spawn relocation")
	_test_land_spawn_relocation()
	print("ProductionManager Infantry spawn relocation")
	_test_infantry_spawn_relocation()

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

	# Derive expected values from the raw tierLevels/postTierGrowth data
	# rather than the algorithm under test, so a rebalance of those numbers
	# doesn't silently desync the test from what slots_at_level should return.
	var tier_levels: Array = progression["tierLevels"]
	var level_1_entry: Dictionary = tier_levels.filter(func(e): return int(e["level"]) == 1)[0]
	var level_3_entry: Dictionary = tier_levels.filter(func(e): return int(e["level"]) == 3)[0]
	var last_tier_entry: Dictionary = tier_levels[tier_levels.size() - 1]
	var max_tier_level: int = int(last_tier_entry["level"])
	var max_tier_slots: int = int(last_tier_entry["commanderSlots"])
	var per_level: int = int(progression["postTierGrowth"]["commanderSlotsPerLevel"])

	var expected_level_1: int = int(level_1_entry["commanderSlots"])
	var expected_level_3: int = int(level_3_entry["commanderSlots"])
	var expected_level_4: int = max_tier_slots + per_level * (4 - max_tier_level)
	var expected_level_6: int = max_tier_slots + per_level * (6 - max_tier_level)

	_check(CommanderProgression.slots_at_level(progression, 1) == expected_level_1, "level 1 -> %d slot(s) (tierLevels' level-1 entry)" % expected_level_1)
	_check(CommanderProgression.slots_at_level(progression, 3) == expected_level_3, "level 3 -> %d slot(s) (tiers unlock, tierLevels' level-3 entry)" % expected_level_3)
	_check(CommanderProgression.slots_at_level(progression, 4) == expected_level_4, "level 4 -> %d slot(s) (last tier's %d + postTierGrowth.commanderSlotsPerLevel %d)" % [expected_level_4, max_tier_slots, per_level])
	_check(CommanderProgression.slots_at_level(progression, 6) == expected_level_6, "level 6 -> %d slot(s) (last tier's %d + %d per level past level %d)" % [expected_level_6, max_tier_slots, per_level, max_tier_level])

func _test_squad_cap() -> void:
	var one_capital: Array[BaseInstance] = [BaseInstance.new("b1", "capital", "p1", 1)]
	_check(SquadCap.max_squads(one_capital) == 3, "fresh level-1 Capital -> maxSquads 3")

	var two_bases: Array[BaseInstance] = [
		BaseInstance.new("b1", "capital", "p1", 2),
		BaseInstance.new("b2", "fort_irongrad", "p1", 3),
	]
	_check(SquadCap.max_squads(two_bases) == 7, "hqLevel 2 + 3 -> maxSquads (2+3)*1+2 = 7")

	var building_defs := DataLoader.load_dir("res://data/buildings")
	var base_with_ccs := BaseInstance.new("b1", "capital", "p1", 1)
	base_with_ccs.buildings.append(BuildingInstance.new("cc1", "b1", "command_centre", 1))
	base_with_ccs.buildings.append(BuildingInstance.new("cc2", "b1", "command_centre", 4))
	var bases_with_ccs: Array[BaseInstance] = [base_with_ccs]
	var cc_progression: Dictionary = building_defs["command_centre"]["commanderProgression"]
	var expected_commanders: int = CommanderProgression.slots_at_level(cc_progression, 1) + CommanderProgression.slots_at_level(cc_progression, 4)
	_check(SquadCap.max_commanders(bases_with_ccs, building_defs) == expected_commanders, "level-1 + level-4 Command Centre -> maxCommanders sums each Command Centre's commanderProgression slots (%d)" % expected_commanders)

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
	var rifleman_production_time: float = float(troop_defs["rifleman"]["productionTime"])
	var queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(queue, "rifleman", troop_defs)
	_check(queue.entries[0]["production_time"] == rifleman_production_time, "enqueue reads productionTime (%s) from troop def" % rifleman_production_time)
	_check(queue.entries[0]["remaining"] == rifleman_production_time, "enqueue starts remaining at full productionTime")

	ProductionManager.advance(queue, 4.0)
	var expected_remaining_after_4: float = max(0.0, rifleman_production_time - 4.0)
	_check(queue.entries[0]["remaining"] == expected_remaining_after_4, "advance ticks front entry's remaining down by dt")

	ProductionManager.enqueue(queue, "rifleman", troop_defs)
	ProductionManager.advance(queue, expected_remaining_after_4)
	_check(queue.front_complete(), "front entry completes once remaining hits 0")
	_check(queue.entries[1]["remaining"] == rifleman_production_time, "advance leaves later entries untouched (FIFO)")

	queue.paused = true
	var remaining_before: float = queue.entries[0]["remaining"]
	ProductionManager.advance(queue, 5.0)
	_check(queue.entries[0]["remaining"] == remaining_before, "advance is a no-op while paused")
	queue.paused = false

	# lazy payment: an entry queued behind others (cost_paid false) doesn't
	# tick down until advance() can actually pay for it -- omitting pool
	# above kept every prior entry auto-paid, so this needs it explicitly.
	var rifleman_cost := ResourceType.dict_from_named(troop_defs["rifleman"].get("cost", {}))
	var poor_pool := ResourcePool.new()
	for type in rifleman_cost:
		poor_pool.set_amount(type, 0.0)
	var pay_queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(pay_queue, "rifleman", troop_defs)
	ProductionManager.advance(pay_queue, 5.0, troop_defs, poor_pool)
	_check(pay_queue.paused, "advance pauses an unpaid front entry it can't afford")
	_check(pay_queue.pause_reason == "insufficient_resources", "pause_reason is insufficient_resources")
	_check(pay_queue.entries[0]["remaining"] == rifleman_production_time, "the unpaid entry's timer doesn't move while it can't be paid for")
	_check(not bool(pay_queue.entries[0]["cost_paid"]), "still unpaid")

	for type in rifleman_cost:
		poor_pool.set_amount(type, float(rifleman_cost[type]))
	ProductionManager.advance(pay_queue, 5.0, troop_defs, poor_pool)
	_check(not pay_queue.paused, "advance clears the pause once the entry can be paid for")
	_check(bool(pay_queue.entries[0]["cost_paid"]), "cost_paid flips true once spent")
	_check(pay_queue.entries[0]["remaining"] == max(0.0, rifleman_production_time - 5.0), "the same advance() call that pays also ticks the timer")
	for type in rifleman_cost:
		_check(poor_pool.get_amount(type) == 0.0, "paying spent the full cost out of the pool")

	# completion joins an in-range squad with room, bypassing the cap entirely
	var other_a := SquadInstance.new("oa", "p1", "grenadier", spawn_hex)
	var other_b := SquadInstance.new("ob", "p1", "grenadier", spawn_hex)
	var roomy := SquadInstance.new("s_roomy", "p1", "rifleman", spawn_hex)
	roomy.add_member("t_existing")
	var join_squads: Array[SquadInstance] = [other_a, other_b, roomy]
	var join_queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(join_queue, "rifleman", troop_defs)
	ProductionManager.advance(join_queue, rifleman_production_time)
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
	ProductionManager.advance(new_squad_queue, rifleman_production_time)
	var empty_squads: Array[SquadInstance] = []
	ProductionManager.pump(new_squad_queue, "p1", spawn_hex, "barracks", empty_squads, troops, one_capital, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(new_squad_queue.is_empty(), "completed entry that forms a new squad is popped")
	_check(empty_squads.size() == 1, "under cap -> a new squad is created")
	_check(empty_squads[0].member_ids.size() == 1, "the new squad has the newly trained troop")

	# pause at squad_cap: owner already at maxSquads, no joinable squad exists
	# (one_capital is a level-1 Capital -> maxSquads 3, per the SquadCap check above)
	var at_cap_squads: Array[SquadInstance] = [
		SquadInstance.new("g1", "p1", "grenadier", spawn_hex),
		SquadInstance.new("g2", "p1", "grenadier", spawn_hex),
		SquadInstance.new("g3", "p1", "grenadier", spawn_hex),
	]
	var pause_queue := ProductionQueue.new("barracks1")
	ProductionManager.enqueue(pause_queue, "rifleman", troop_defs)
	ProductionManager.advance(pause_queue, rifleman_production_time)
	ProductionManager.pump(pause_queue, "p1", spawn_hex, "barracks", at_cap_squads, troops, one_capital, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(pause_queue.paused, "queue pauses when a new squad is needed at the squad cap")
	_check(pause_queue.pause_reason == "squad_cap", "pause_reason is squad_cap")
	_check(not pause_queue.is_empty(), "paused entry is held, not dropped")

	# auto-resume: freeing a slot and re-pumping deploys the held troop
	at_cap_squads.remove_at(0)
	ProductionManager.pump(pause_queue, "p1", spawn_hex, "barracks", at_cap_squads, troops, one_capital, building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"))
	_check(not pause_queue.paused, "re-pumping after a slot frees clears the pause")
	_check(pause_queue.is_empty(), "held entry deploys once capacity is available again")
	_check(at_cap_squads.size() == 3, "the held troop formed its new squad on resume")

	# pause at commander_cap: Command Centre, no Command Centre built yet -> maxCommanders 0
	var commander_vanguard_production_time: float = float(troop_defs["commander_vanguard"]["productionTime"])
	var commander_queue := ProductionQueue.new("cc1")
	ProductionManager.enqueue(commander_queue, "commander_vanguard", troop_defs)
	ProductionManager.advance(commander_queue, commander_vanguard_production_time)
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

## A Land vehicle's own producing building blocks Land movement just like any
## other standing building, so it can't be deployed onto that hex -- pump()
## must relocate it to an adjacent, unblocked hex instead (mirrors the
## pre-existing Naval-domain relocation, but off a building-blocked hex rather
## than to a water hex).
func _test_land_spawn_relocation() -> void:
	var troop_defs := DataLoader.load_dir("res://data/troops")
	var building_defs := DataLoader.load_dir("res://data/buildings")
	var barracks_hex := HexCoord.new(0, 0)
	var grid := HexGrid.new()
	grid.set_terrain(barracks_hex, Terrain.Type.PLAINS)
	for d in range(6):
		grid.set_terrain(HexCoord.neighbor(barracks_hex, d), Terrain.Type.PLAINS)

	var base1 := BaseInstance.new("b1", "capital", "p1", 1, barracks_hex)
	base1.buildings.append(BuildingInstance.new("bld1", "b1", "barracks", 1, "", barracks_hex))
	var blocked := BuildingPlacement.building_blocking_hexes([base1], [])

	var queue := ProductionQueue.new("bld1")
	ProductionManager.enqueue(queue, "basekiller", troop_defs)
	ProductionManager.advance(queue, float(troop_defs["basekiller"]["productionTime"]))
	var squads: Array[SquadInstance] = []
	var troops: Dictionary = {}
	ProductionManager.pump(queue, "p1", barracks_hex, "barracks", squads, troops, [base1], building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"), grid, null, blocked)

	_check(squads.size() == 1, "Land vehicle deploys into a new squad")
	if squads.size() == 1:
		_check(not squads[0].current_hex.equals(barracks_hex), "Land vehicle does not spawn on the producing building's own (blocked) hex")
		_check(HexCoord.distance(squads[0].current_hex, barracks_hex) == 1, "Land vehicle spawns on an adjacent hex instead")

## Infantry gets the same spawn-placement treatment as Land -- relocated off
## the barracks hex to the nearest empty hex -- even though, unlike Land,
## Infantry ignores standing buildings for movement afterward and could walk
## right back across the barracks hex.
func _test_infantry_spawn_relocation() -> void:
	var troop_defs := DataLoader.load_dir("res://data/troops")
	var building_defs := DataLoader.load_dir("res://data/buildings")
	var barracks_hex := HexCoord.new(0, 0)
	var grid := HexGrid.new()
	grid.set_terrain(barracks_hex, Terrain.Type.PLAINS)
	for d in range(6):
		grid.set_terrain(HexCoord.neighbor(barracks_hex, d), Terrain.Type.PLAINS)

	var base1 := BaseInstance.new("b1", "capital", "p1", 1, barracks_hex)
	base1.buildings.append(BuildingInstance.new("bld1", "b1", "barracks", 1, "", barracks_hex))
	var blocked := BuildingPlacement.building_blocking_hexes([base1], [])

	var queue := ProductionQueue.new("bld1")
	ProductionManager.enqueue(queue, "rifleman", troop_defs)
	ProductionManager.advance(queue, float(troop_defs["rifleman"]["productionTime"]))
	var squads: Array[SquadInstance] = []
	var troops: Dictionary = {}
	ProductionManager.pump(queue, "p1", barracks_hex, "barracks", squads, troops, [base1], building_defs, troop_defs, 0, _id_generator("t"), _id_generator("s"), grid, null, blocked)

	_check(squads.size() == 1, "Infantry deploys into a new squad")
	if squads.size() == 1:
		_check(not squads[0].current_hex.equals(barracks_hex), "Infantry does not spawn on the producing building's own hex")
		_check(HexCoord.distance(squads[0].current_hex, barracks_hex) == 1, "Infantry spawns on an adjacent hex instead")
