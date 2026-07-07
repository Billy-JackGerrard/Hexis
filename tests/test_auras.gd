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

## Percent-based aura effects (speed_boost/attack_speed_boost/slow) apply as
## 1 + magnitude/100 — mirrors AuraSystem._percent_factor's non-damage_reduction
## branch (see sim/units/aura_system.gd's _percent_factor) — so tests can
## derive the expected multiplier from a def's authored magnitude instead of
## hardcoding the resulting multiplier.
func _boost_mult(magnitude: float) -> float:
	return 1.0 + magnitude / 100.0

## Finds an aura's magnitude by effect (+ optional filter) within a def's
## `auras` array, so tests read the live authored value instead of a
## hardcoded copy of it.
func _aura_magnitude(auras: Array, effect: String, filter: String = "") -> float:
	for aura in auras:
		if aura.get("effect") == effect and (filter == "" or aura.get("filter") == filter):
			return float(aura.get("magnitude", 0.0))
	return 0.0

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
	var hospital_heal_l1: float = float(hospital["auras"][0]["magnitude"])
	var hospital_radius: int = int(hospital["auras"][0]["radius"])
	var level1 := BuildingStats.auras(hospital, 1, _building_defs)
	_check(level1.size() == 1, "Hospital has one aura entry")
	_check(_approx(float(level1[0]["magnitude"]), hospital_heal_l1), "Hospital's heal_over_time magnitude at level 1 matches its authored base magnitude (%s)" % hospital_heal_l1)
	_check(int(level1[0]["radius"]) == hospital_radius, "Hospital's radius at level 1 matches its authored radius (%s)" % hospital_radius)

	var level3 := BuildingStats.auras(hospital, 3, _building_defs)
	_check(float(level3[0]["magnitude"]) > float(level1[0]["magnitude"]), "Hospital's heal magnitude grows with level (healMagnitude statGrowth)")
	_check(int(level3[0]["radius"]) == int(level1[0]["radius"]), "Hospital's radius stays flat per level while magnitude scales")

	var ice_spire: Dictionary = _building_defs["ice_spire"]
	var ice_slow_magnitude: float = float(ice_spire["auras"][0]["magnitude"])
	var ice_auras := BuildingStats.auras(ice_spire, 2, _building_defs)
	_check(_approx(float(ice_auras[0]["magnitude"]), ice_slow_magnitude), "Ice Spire's slow magnitude (%s) has no growth entry -> stays unleveled" % ice_slow_magnitude)

## --- Proximity troop auras --------------------------------------------------

func _test_troop_auras() -> void:
	var squads: Array[SquadInstance] = []
	var bases: Array[BaseInstance] = []
	var troops := {}

	var volt_def: Dictionary = _troop_defs["volt_truck"]
	var volt_speed_boost: float = _aura_magnitude(volt_def["auras"], "speed_boost", "Land")
	var volt_attack_speed_boost: float = _aura_magnitude(volt_def["auras"], "attack_speed_boost", "Land")
	var volt_speed_mult: float = _boost_mult(volt_speed_boost)
	var volt_attack_speed_mult: float = _boost_mult(volt_attack_speed_boost)

	# Volt Truck (Land/Air/Naval speed_boost + attack_speed_boost, radius 3,
	# deliberately excludes Infantry) at origin.
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
	_check(_approx(AuraSystem.speed_mult(auras, basekiller.id), volt_speed_mult), "in-range Land ally gets Volt Truck's speed_boost (+%s%%)" % volt_speed_boost)
	_check(_approx(AuraSystem.attack_speed_mult(auras, basekiller.id), volt_attack_speed_mult), "in-range Land ally gets Volt Truck's attack_speed_boost (+%s%%)" % volt_attack_speed_boost)
	_check(_approx(AuraSystem.speed_mult(auras, far_basekiller.id), 1.0), "out-of-range Land ally gets no boost")
	_check(_approx(AuraSystem.speed_mult(auras, rifleman.id), 1.0), "in-range Infantry ally gets no boost (filter excludes Infantry)")
	_check(_approx(AuraSystem.speed_mult(auras, enemy_basekiller.id), 1.0), "in-range enemy Land squad gets no boost (friendly_troops only)")

	# Two Volt Trucks reaching the same ally are the same source type
	# (volt_truck), so they must not double up the +40% boost.
	var squads2: Array[SquadInstance] = []
	var volt_a := _make_squad("p1", "volt_truck", HexCoord.new(0, 0), 1, troops)
	var volt_b := _make_squad("p1", "volt_truck", HexCoord.new(1, 0), 1, troops)
	var stacked_ally := _make_squad("p1", "basekiller", HexCoord.new(1, 0), 1, troops)
	squads2.append(volt_a)
	squads2.append(volt_b)
	squads2.append(stacked_ally)
	var auras2 := AuraSystem.resolve_tick(squads2, bases, _troop_defs, _building_defs)
	_check(_approx(AuraSystem.speed_mult(auras2, stacked_ally.id), volt_speed_mult), "two overlapping Volt Trucks (same source type) still contribute only +%s%%, not double" % volt_speed_boost)

## --- Building aura sources --------------------------------------------------

func _test_building_auras() -> void:
	var squads: Array[SquadInstance] = []
	var troops := {}

	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(0, 0))
	var hospital_def: Dictionary = _building_defs["hospital"]
	var hospital_heal: float = float(hospital_def["auras"][0]["magnitude"])
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
	_check(_approx(AuraSystem.squad_mods_heal(auras, patient.id), hospital_heal), "Hospital's heal_over_time (%s/s at level 1) reaches an in-range squad" % hospital_heal)

	AuraSystem.apply_heals(1.0, auras, squads, troops, _troop_defs)
	_check(_approx(patient_troop.current_hp, 50.0 + hospital_heal), "apply_heals adds heal_per_second * dt to a damaged member's HP")

	AuraSystem.apply_heals(100.0, auras, squads, troops, _troop_defs)
	var rifleman_hp: float = float(_troop_defs["rifleman"].get("hp", 0.0))
	_check(_approx(patient_troop.current_hp, rifleman_hp), "apply_heals caps healing at the troop's authored max HP (%s)" % rifleman_hp)

	# Three Hospitals in range of the same squad must not triple its heal --
	# same source type (hospital) dedupes to a single max contribution.
	var hosp2 := BuildingInstance.new("hosp2", "b1", "hospital", 1, "", HexCoord.new(1, 0))
	hosp2.init_hp(hospital_def, _building_defs)
	base.buildings.append(hosp2)
	var hosp3 := BuildingInstance.new("hosp3", "b1", "hospital", 1, "", HexCoord.new(2, 0))
	hosp3.init_hp(hospital_def, _building_defs)
	base.buildings.append(hosp3)
	var stacked_auras := AuraSystem.resolve_tick(squads, bases, _troop_defs, _building_defs)
	_check(_approx(AuraSystem.squad_mods_heal(stacked_auras, patient.id), hospital_heal), "three overlapping Hospitals still contribute only %s/s, not %s/s" % [hospital_heal, hospital_heal * 3.0])

	# A different support type (Ambulance) reaching the same squad still adds
	# on top of Hospital's heal, since it's a different source type.
	var ambulance := _make_squad("p1", "ambulance", HexCoord.new(3, 0), 1, troops)
	squads.append(ambulance)
	var mixed_auras := AuraSystem.resolve_tick(squads, bases, _troop_defs, _building_defs)
	var ambulance_heal: float = float(_troop_defs["ambulance"]["auras"][0]["magnitude"])
	var expected_mixed: float = hospital_heal + ambulance_heal
	_check(_approx(AuraSystem.squad_mods_heal(mixed_auras, patient.id), expected_mixed), "Hospital (%s/s) and Ambulance (%s/s) are different source types, so their heals still add together" % [hospital_heal, ambulance_heal])

	# Ice Spire's slow reaches an enemy squad in range, not a friendly one.
	var ice_base := BaseInstance.new("b2", "winter_forge", "p1", 1, HexCoord.new(20, 0))
	var ice_def: Dictionary = _building_defs["ice_spire"]
	var ice_slow_magnitude: float = float(ice_def["auras"][0]["magnitude"])
	var ice_slow_mult: float = _boost_mult(ice_slow_magnitude)
	var ice_spire := BuildingInstance.new("ice1", "b2", "ice_spire", 1, "", HexCoord.new(20, 0))
	ice_spire.init_hp(ice_def, _building_defs)
	ice_base.buildings.append(ice_spire)

	var enemy_near := _make_squad("p2", "rifleman", HexCoord.new(21, 0), 1, troops)
	var friendly_near := _make_squad("p1", "rifleman", HexCoord.new(21, 0), 1, troops)
	var ice_squads: Array[SquadInstance] = [enemy_near, friendly_near]
	var ice_auras := AuraSystem.resolve_tick(ice_squads, [ice_base], _troop_defs, _building_defs)
	_check(_approx(AuraSystem.speed_mult(ice_auras, enemy_near.id), ice_slow_mult), "Ice Spire's slow (%s%%) reaches an enemy squad in range" % ice_slow_magnitude)
	_check(_approx(AuraSystem.speed_mult(ice_auras, friendly_near.id), 1.0), "Ice Spire's slow does not affect the owner's own troops (enemy_troops only)")

	# Two Ice Spires in range of the same enemy squad are the same source
	# type -> only one slow applies, not two stacked.
	var ice_spire2 := BuildingInstance.new("ice2", "b2", "ice_spire", 1, "", HexCoord.new(21, 0))
	ice_spire2.init_hp(ice_def, _building_defs)
	ice_base.buildings.append(ice_spire2)
	var double_ice_auras := AuraSystem.resolve_tick([enemy_near], [ice_base], _troop_defs, _building_defs)
	_check(_approx(AuraSystem.speed_mult(double_ice_auras, enemy_near.id), ice_slow_mult), "two overlapping Ice Spires (same source type) still apply only %s%% slow, not double" % ice_slow_magnitude)

	# A squad that's simultaneously the Ice Spire's enemy (p1's base slows
	# p2) and a Volt Truck's ally (p2's own truck boosts it) gets both
	# effects -- distinct source types (ice_spire, volt_truck) still combine
	# multiplicatively on top of each other.
	var volt := _make_squad("p2", "volt_truck", HexCoord.new(21, 0), 1, troops)
	var cross_target := _make_squad("p2", "basekiller", HexCoord.new(21, 0), 1, troops)
	var cross_squads: Array[SquadInstance] = [volt, cross_target]
	var cross_auras := AuraSystem.resolve_tick(cross_squads, [ice_base], _troop_defs, _building_defs)
	var volt_speed_mult2: float = _boost_mult(_aura_magnitude(_troop_defs["volt_truck"]["auras"], "speed_boost", "Land"))
	_check(_approx(AuraSystem.speed_mult(cross_auras, cross_target.id), volt_speed_mult2 * ice_slow_mult), "Ice Spire's slow and Volt Truck's boost are different source types, so they still combine multiplicatively (%.3f x %.3f)" % [volt_speed_mult2, ice_slow_mult])

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
	# quad_bike's boosted speed (base speed * Volt Truck's Land speed_boost)
	# crosses however many whole hexes that covers in 1.0s (edge cost 1.0 each
	# on plains) -- derived from live data so a speed/aura rebalance can't
	# silently desync this expectation from the numbers actually in play.
	var quad_speed: float = float(_troop_defs["quad_bike"]["speed"])
	var volt_speed_boost: float = _aura_magnitude(_troop_defs["volt_truck"]["auras"], "speed_boost", "Land")
	var boosted_speed: float = quad_speed * _boost_mult(volt_speed_boost)
	var hexes_crossed: int = int(floor(boosted_speed))
	var expected_hex := HexCoord.new(1 + hexes_crossed, 0)
	_check(quad.current_hex.equals(expected_hex), "Volt Truck's speed_boost accelerates a nearby Land squad's movement (quad_bike speed %s x %s%% boost = %s hex/s, crossing %d hexes in 1.0s)" % [quad_speed, volt_speed_boost, boosted_speed, hexes_crossed])

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
