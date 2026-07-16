## Headless assertion suite for Commander regiment-membership auras
## (Vanguard/Nightfall/Warden) and Mule's upkeep_reduction consumption --
## previously deferred wholesale since resolving own_regiment/
## own_regiment_and_self needs RegimentInstance.commanderId/squadIds turned
## into live squad references, the same gap CommandProcessor closes. Run
## with:
##   godot --headless --script res://tests/test_commander_auras.gd
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

	print("Vanguard speed_boost (own_regiment)")
	_test_vanguard_speed_boost()
	print("Reaver damage_boost (own_regiment)")
	_test_reaver_damage_boost()
	print("Nightfall grant_stealth (own_regiment)")
	_test_nightfall_grant_stealth()
	print("Warden heal_out_of_combat (own_regiment_and_self)")
	_test_warden_heal_out_of_combat()
	print("UpkeepSystem consumes Mule's upkeep_reduction")
	_test_mule_upkeep_reduction()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _make_squad(owner: String, troop_type: String, hex: HexCoord, troops: Dictionary, count: int = 1) -> SquadInstance:
	_next_id += 1
	var squad := SquadInstance.new("sq%d" % _next_id, owner, troop_type, hex)
	var hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 100.0))
	for i in range(count):
		_next_id += 1
		var tid := "tr%d" % _next_id
		troops[tid] = TroopInstance.new(tid, troop_type, owner, squad.id, hp)
		squad.add_member(tid)
	return squad

func _test_vanguard_speed_boost() -> void:
	var troops: Dictionary = {}
	var commander := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0), troops)
	# Escort placed far away -- own_regiment is membership-based, not
	# proximity, so distance must not matter (radius is authored 999
	# specifically so it never gates this).
	var escort := _make_squad("p1", "rifleman", HexCoord.new(50, 50), troops)
	var outsider := _make_squad("p1", "rifleman", HexCoord.new(0, 1), troops)
	var enemy := _make_squad("p2", "rifleman", HexCoord.new(0, 0), troops)

	var regiment := RegimentInstance.new("reg1", commander.id)
	regiment.assign_squad(escort.id, 4)
	var regiments: Array[RegimentInstance] = [regiment]
	var squads: Array[SquadInstance] = [commander, escort, outsider, enemy]

	var auras := AuraSystem.resolve_tick(squads, [], _troop_defs, {}, regiments)
	_check(AuraSystem.speed_mult(auras, escort.id) > 1.0, "the escort's speed is boosted regardless of distance from its Commander")
	_check(AuraSystem.speed_mult(auras, outsider.id) == 1.0, "a same-owner squad NOT in the regiment is untouched")
	_check(AuraSystem.speed_mult(auras, enemy.id) == 1.0, "an enemy squad never receives a friendly Commander's buff")
	_check(AuraSystem.speed_mult(auras, commander.id) == 1.0, "own_regiment (not own_regiment_and_self) excludes the Commander's own squad")

func _test_reaver_damage_boost() -> void:
	var troops: Dictionary = {}
	var commander := _make_squad("p1", "commander_reaver", HexCoord.new(0, 0), troops)
	var escort := _make_squad("p1", "rifleman", HexCoord.new(50, 50), troops)
	var outsider := _make_squad("p1", "rifleman", HexCoord.new(0, 1), troops)
	var enemy := _make_squad("p2", "rifleman", HexCoord.new(0, 0), troops)

	var regiment := RegimentInstance.new("reg1", commander.id)
	regiment.assign_squad(escort.id, 4)
	var regiments: Array[RegimentInstance] = [regiment]
	var squads: Array[SquadInstance] = [commander, escort, outsider, enemy]

	var auras := AuraSystem.resolve_tick(squads, [], _troop_defs, {}, regiments)
	_check(AuraSystem.damage_mult(auras, escort.id) > 1.0, "the escort's damage is boosted regardless of distance from its Commander")
	_check(AuraSystem.damage_mult(auras, outsider.id) == 1.0, "a same-owner squad NOT in the regiment is untouched")
	_check(AuraSystem.damage_mult(auras, enemy.id) == 1.0, "an enemy squad never receives a friendly Commander's buff")
	_check(AuraSystem.damage_mult(auras, commander.id) == 1.0, "own_regiment (not own_regiment_and_self) excludes the Commander's own squad")

func _test_nightfall_grant_stealth() -> void:
	var troops: Dictionary = {}
	var commander := _make_squad("p1", "commander_nightfall", HexCoord.new(0, 0), troops)
	var escort := _make_squad("p1", "rifleman", HexCoord.new(20, 0), troops)
	var outsider := _make_squad("p1", "rifleman", HexCoord.new(0, 1), troops)

	var regiment := RegimentInstance.new("reg1", commander.id)
	regiment.assign_squad(escort.id, 4)
	var regiments: Array[RegimentInstance] = [regiment]
	var squads: Array[SquadInstance] = [commander, escort, outsider]

	var auras := AuraSystem.resolve_tick(squads, [], _troop_defs, {}, regiments)
	_check(AuraSystem.is_granted_stealth(auras, escort.id), "the escort is granted stealth by Nightfall's regiment aura")
	_check(not AuraSystem.is_granted_stealth(auras, outsider.id), "a squad outside the regiment gets no granted stealth")

	var nightfall_reveal_range: float = float(_troop_defs["commander_nightfall"].get("revealRange", 0.0))
	_check(AuraSystem.granted_stealth_reveal_range(auras, escort.id) == nightfall_reveal_range, "granted_stealth_reveal_range mirrors the granting Commander's own revealRange")

	# DetectionSystem.is_squad_hidden actually treats the escort as hidden now.
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), 25):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	var escort_def: Dictionary = _troop_defs["rifleman"]
	_check(not escort_def.get("stealth", false), "rifleman carries no authored stealth (fixture assumption)")
	_check(DetectionSystem.is_squad_hidden(escort, escort_def, grid, auras), "a regiment-granted-stealth squad reads as hidden via DetectionSystem")
	_check(not DetectionSystem.is_squad_hidden(escort, escort_def, grid, {}), "without the auras dict, the same squad is not hidden (no authored stealth of its own)")

func _test_warden_heal_out_of_combat() -> void:
	var troops: Dictionary = {}
	var commander := _make_squad("p1", "commander_warden", HexCoord.new(0, 0), troops)
	var escort := _make_squad("p1", "rifleman", HexCoord.new(5, 0), troops)
	var commander_troop: TroopInstance = troops[commander.member_ids[0]]
	var escort_troop: TroopInstance = troops[escort.member_ids[0]]
	commander_troop.current_hp = 50.0
	escort_troop.current_hp = 50.0

	var regiment := RegimentInstance.new("reg1", commander.id)
	regiment.assign_squad(escort.id, 4)
	var regiments: Array[RegimentInstance] = [regiment]
	var squads: Array[SquadInstance] = [commander, escort]

	var auras := AuraSystem.resolve_tick(squads, [], _troop_defs, {}, regiments)
	_check(AuraSystem.squad_mods_heal_out_of_combat(auras, escort.id) > 0.0, "the escort receives Warden's heal_out_of_combat")
	_check(AuraSystem.squad_mods_heal_out_of_combat(auras, commander.id) > 0.0, "own_regiment_and_self also heals the Commander's own squad")

	# Freshly damaged (time_since_damage starts at 0) -- still within the
	# out-of-combat delay, so apply_heals must NOT heal yet.
	AuraSystem.apply_heals(1.0, auras, squads, troops, _troop_defs)
	_check(escort_troop.current_hp == 50.0, "heal_out_of_combat does not apply while still within the delay window")

	# Advance time_since_damage past the delay via repeated apply_heals calls
	# (each call banks dt, mirroring BuildingRegenSystem's accumulator shape).
	for i in range(10):
		AuraSystem.apply_heals(1.0, auras, squads, troops, _troop_defs)
	_check(escort_troop.current_hp > 50.0, "heal_out_of_combat applies once the squad hasn't taken damage recently")
	_check(commander_troop.current_hp > 50.0, "the Commander's own squad heals too, via own_regiment_and_self")

func _test_mule_upkeep_reduction() -> void:
	var troops: Dictionary = {}
	var mule := _make_squad("p1", "mule", HexCoord.new(0, 0), troops)
	var infantry := _make_squad("p1", "flamethrower", HexCoord.new(1, 0), troops, 2)
	var squads: Array[SquadInstance] = [mule, infantry]

	var auras := AuraSystem.resolve_tick(squads, [], _troop_defs, {})
	var mule_upkeep_reduction := 0.0
	for aura in _troop_defs["mule"].get("auras", []):
		if aura.get("effect", "") == "upkeep_reduction":
			mule_upkeep_reduction = float(aura.get("magnitude", 0.0))
	_check(AuraSystem.upkeep_reduction(auras, infantry.id) == mule_upkeep_reduction, "Mule's proximity aura reduces upkeep by its authored flat magnitude (%s)" % mule_upkeep_reduction)

	var without_mule: Dictionary = AuraSystem.resolve_tick([infantry], [], _troop_defs, {})
	var upkeep_without_mule := UpkeepSystem.compute_upkeep([infantry], _troop_defs, without_mule)
	var upkeep_with_mule := UpkeepSystem.compute_upkeep(squads, _troop_defs, auras)

	var food_without: float = float(upkeep_without_mule.get("p1", {}).get(ResourceType.Type.FOOD, 0.0))
	var food_with: float = float(upkeep_with_mule.get("p1", {}).get(ResourceType.Type.FOOD, 0.0))
	_check(food_with < food_without, "UpkeepSystem.compute_upkeep actually applies Mule's aura-sourced reduction")
