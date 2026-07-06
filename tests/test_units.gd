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
