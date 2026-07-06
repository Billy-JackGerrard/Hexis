## Headless assertion suite for the aura slice (sim/units/aura_system.gd,
## sim/instances/building_stats.gd's auras() helper, plus the AuraSystem
## wiring into MovementResolver/CombatResolver). Run with:
##   godot --headless --script res://tests/test_auras.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
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

	print("BuildingStats.auras")
	_test_building_stats_auras()
	print("AuraSystem: proximity troop auras")
	_test_troop_auras()
	print("AuraSystem: building aura sources")
	_test_building_auras()
	print("AuraSystem: enemy_buildings suppress_targeting")
	_test_suppress_targeting()
	print("Integration: MovementResolver/CombatResolver consuming auras")
	_test_integration()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers -------------------------------------------------------------

func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.001

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

## --- BuildingStats.auras ----------------------------------------------------

func _test_building_stats_auras() -> void:
	var hospital: Dictionary = _building_defs["hospital"]
	var level1 := BuildingStats.auras(hospital, 1, _building_defs)
	_check(level1.size() == 1, "Hospital has one aura entry")
	_check(_approx(float(level1[0]["magnitude"]), 6.0), "Hospital's heal_over_time magnitude is 6 at level 1")
	_check(int(level1[0]["radius"]) == 8, "Hospital's radius is 8 at level 1")

	var level3 := BuildingStats.auras(hospital, 3, _building_defs)
	_check(float(level3[0]["magnitude"]) > 6.0, "Hospital's heal magnitude grows with level (healMagnitude statGrowth)")
	_check(int(level3[0]["radius"]) == 8, "Hospital's radius stays flat per level while magnitude scales")

	var ice_spire: Dictionary = _building_defs["ice_spire"]
	var ice_auras := BuildingStats.auras(ice_spire, 2, _building_defs)
	_check(_approx(float(ice_auras[0]["magnitude"]), -20.0), "Ice Spire's slow magnitude has no growth entry -> stays unleveled (-20)")

## --- Proximity troop auras --------------------------------------------------

func _test_troop_auras() -> void:
	var squads: Array[SquadInstance] = []
	var bases: Array[BaseInstance] = []
	var troops := {}

	# Volt Truck (Land/Air/Naval speed_boost 40% + attack_speed_boost 15%,
	# radius 3, deliberately excludes Infantry) at origin.
	var volt := _make_squad("p1", "volt_truck", HexCoord.new(0, 0), 1, troops)
	squads.append(volt)
	# A Land ally within radius 3 -> boosted.
	var basekiller := _make_squad("p1", "basekiller", HexCoord.new(2, 0), 1, troops)
	squads.append(basekiller)
	# A Land ally outside radius 3 -> unaffected.
	var far_basekiller := _make_squad("p1", "basekiller", HexCoord.new(4, 0), 1, troops)
	squads.append(far_basekiller)
	# An Infantry ally within radius, but Volt Truck's filter excludes Infantry.
	var rifleman := _make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, troops)
	squads.append(rifleman)
	# An enemy Land squad within radius -> friendly_troops aura never applies to it.
	var enemy_basekiller := _make_squad("p2", "basekiller", HexCoord.new(1, 0), 1, troops)
	squads.append(enemy_basekiller)

	var auras := AuraSystem.resolve_tick(squads, bases, _troop_defs, _building_defs)
	_check(_approx(AuraSystem.speed_mult(auras, basekiller.id), 1.4), "in-range Land ally gets Volt Truck's +40% speed_boost")
	_check(_approx(AuraSystem.attack_speed_mult(auras, basekiller.id), 1.15), "in-range Land ally gets Volt Truck's +15% attack_speed_boost")
	_check(_approx(AuraSystem.speed_mult(auras, far_basekiller.id), 1.0), "out-of-range Land ally gets no boost")
	_check(_approx(AuraSystem.speed_mult(auras, rifleman.id), 1.0), "in-range Infantry ally gets no boost (filter excludes Infantry)")
	_check(_approx(AuraSystem.speed_mult(auras, enemy_basekiller.id), 1.0), "in-range enemy Land squad gets no boost (friendly_troops only)")

	# Ice Spire is a building aura, tested separately below; here confirm a
	# troop-authored enemy_troops aura (none currently shipped) would combine
	# multiplicatively with an ally's speed_boost -- verified via a synthetic
	# stacked pair using two Volt Trucks on the same ally.
	var squads2: Array[SquadInstance] = []
	var volt_a := _make_squad("p1", "volt_truck", HexCoord.new(0, 0), 1, troops)
	var volt_b := _make_squad("p1", "volt_truck", HexCoord.new(1, 0), 1, troops)
	var stacked_ally := _make_squad("p1", "basekiller", HexCoord.new(1, 0), 1, troops)
	squads2.append(volt_a)
	squads2.append(volt_b)
	squads2.append(stacked_ally)
	var auras2 := AuraSystem.resolve_tick(squads2, bases, _troop_defs, _building_defs)
	_check(_approx(AuraSystem.speed_mult(auras2, stacked_ally.id), 1.4 * 1.4), "two overlapping speed_boost auras stack multiplicatively (1.4 x 1.4)")

## --- Building aura sources --------------------------------------------------

func _test_building_auras() -> void:
	var squads: Array[SquadInstance] = []
	var troops := {}

	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(0, 0))
	var hospital_def: Dictionary = _building_defs["hospital"]
	var hospital := BuildingInstance.new("hosp1", "b1", "hospital", 1, "", HexCoord.new(0, 0))
	hospital.init_hp(hospital_def, _building_defs)
	base.buildings.append(hospital)
	var bases: Array[BaseInstance] = [base]

	# A friendly, damaged squad within Hospital's radius 8 heals over time.
	var patient := _make_squad("p1", "rifleman", HexCoord.new(3, 0), 1, troops)
	squads.append(patient)
	var patient_troop: TroopInstance = troops[patient.member_ids[0]]
	patient_troop.current_hp = 50.0

	var auras := AuraSystem.resolve_tick(squads, bases, _troop_defs, _building_defs)
	_check(_approx(AuraSystem.squad_mods_heal(auras, patient.id), 6.0), "Hospital's heal_over_time (6/s at level 1) reaches an in-range squad")

	AuraSystem.apply_heals(1.0, auras, squads, troops, _troop_defs)
	_check(_approx(patient_troop.current_hp, 56.0), "apply_heals adds heal_per_second * dt to a damaged member's HP")

	AuraSystem.apply_heals(100.0, auras, squads, troops, _troop_defs)
	_check(_approx(patient_troop.current_hp, 100.0), "apply_heals caps healing at the troop's authored max HP")

	# Ice Spire's slow reaches an enemy squad in range, not a friendly one.
	var ice_base := BaseInstance.new("b2", "winter_forge", "p1", 1, HexCoord.new(20, 0))
	var ice_def: Dictionary = _building_defs["ice_spire"]
	var ice_spire := BuildingInstance.new("ice1", "b2", "ice_spire", 1, "", HexCoord.new(20, 0))
	ice_spire.init_hp(ice_def, _building_defs)
	ice_base.buildings.append(ice_spire)

	var enemy_near := _make_squad("p2", "rifleman", HexCoord.new(21, 0), 1, troops)
	var friendly_near := _make_squad("p1", "rifleman", HexCoord.new(21, 0), 1, troops)
	var ice_squads: Array[SquadInstance] = [enemy_near, friendly_near]
	var ice_auras := AuraSystem.resolve_tick(ice_squads, [ice_base], _troop_defs, _building_defs)
	_check(_approx(AuraSystem.speed_mult(ice_auras, enemy_near.id), 0.8), "Ice Spire's -20% slow reaches an enemy squad in range")
	_check(_approx(AuraSystem.speed_mult(ice_auras, friendly_near.id), 1.0), "Ice Spire's slow does not affect the owner's own troops (enemy_troops only)")

## --- suppress_targeting -----------------------------------------------------

func _test_suppress_targeting() -> void:
	var troops := {}
	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(5, 0))
	var turret_def: Dictionary = _building_defs["turret"]
	var turret := BuildingInstance.new("t1", "b1", "turret", 1, "", HexCoord.new(5, 0))
	turret.init_hp(turret_def, _building_defs)
	base.buildings.append(turret)
	var bases: Array[BaseInstance] = [base]

	var disruptor := _make_squad("p2", "disruptor", HexCoord.new(6, 0), 1, troops)
	var squads: Array[SquadInstance] = [disruptor]

	var auras := AuraSystem.resolve_tick(squads, bases, _troop_defs, _building_defs)
	_check(AuraSystem.is_suppressed(auras, turret.id), "Disruptor's suppress_targeting reaches an in-range enemy Defensive building")

	var far_disruptor := _make_squad("p2", "disruptor", HexCoord.new(20, 0), 1, troops)
	var far_squads: Array[SquadInstance] = [far_disruptor]
	var far_auras := AuraSystem.resolve_tick(far_squads, bases, _troop_defs, _building_defs)
	_check(not AuraSystem.is_suppressed(far_auras, turret.id), "a Disruptor out of range does not suppress the Turret")

## --- Integration -------------------------------------------------------------

func _test_integration() -> void:
	# MovementResolver: Volt Truck's speed_boost multiplies a Land squad's
	# effective speed.
	var grid := HexGrid.new()
	for i in range(10):
		grid.set_terrain(HexCoord.new(i, 0), Terrain.Type.PLAINS)

	var troops := {}
	var volt := _make_squad("p1", "volt_truck", HexCoord.new(0, 0), 1, troops)
	var quad := _make_squad("p1", "quad_bike", HexCoord.new(1, 0), 1, troops)
	var squads: Array[SquadInstance] = [volt, quad]
	MovementResolver.issue_move(quad, grid, HexCoord.new(9, 0), _troop_defs)

	var auras := AuraSystem.resolve_tick(squads, [], _troop_defs, _building_defs)
	MovementResolver.resolve_tick(1.0, squads, grid, _troop_defs, auras)
	# quad_bike speed 3.0 * 1.4 boost = 4.2 hexes in 1.0s -> crosses 4 whole
	# hexes (edge cost 1.0 each on plains), landing on hex 5.
	_check(quad.current_hex.equals(HexCoord.new(5, 0)), "Volt Truck's speed_boost accelerates a nearby Land squad's movement")

	# CombatResolver: a suppressed Turret doesn't fire even with a target in range.
	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(5, 0))
	var turret_def: Dictionary = _building_defs["turret"]
	var turret := BuildingInstance.new("t1", "b1", "turret", 1, "", HexCoord.new(5, 0))
	turret.init_hp(turret_def, _building_defs)
	base.buildings.append(turret)

	var disruptor := _make_squad("p2", "disruptor", HexCoord.new(6, 0), 1, troops)
	var raider := _make_squad("p2", "basekiller", HexCoord.new(4, 0), 1, troops)
	var combat_squads: Array[SquadInstance] = [disruptor, raider]
	var combat_auras := AuraSystem.resolve_tick(combat_squads, [base], _troop_defs, _building_defs)
	_check(AuraSystem.is_suppressed(combat_auras, turret.id), "Turret is suppressed for this integration check")

	CombatResolver.resolve_tick(2.0, combat_squads, [base], troops, grid, _troop_defs, _building_defs, {}, combat_auras)
	var raider_hp := (troops[raider.member_ids[0]] as TroopInstance).current_hp
	_check(_approx(raider_hp, float(_troop_defs["basekiller"].get("hp", 0.0))), "a suppressed Turret deals no damage back to the attacker, even though the attacker still damages it")
