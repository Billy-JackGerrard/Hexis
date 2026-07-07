## Headless assertion suite for the combat slice (sim/units/combat_*.gd,
## sim/instances/building_stats.gd). Run with:
##   godot --headless --script res://tests/test_combat.gd
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

	print("BuildingStats")
	_test_building_stats()
	print("CombatMath")
	_test_combat_math()
	print("Terrain.defense_bonus")
	_test_terrain_defense_bonus()
	print("CombatTargeting")
	_test_combat_targeting()
	print("Stealth/detection")
	_test_stealth_and_detection()
	print("CombatResolver")
	_test_combat_resolver()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers -------------------------------------------------------------

func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.001

## Builds a squad of `count` troops of `troop_type`, registering each troop in
## `troops` with the given hp (defaults to the def's hp), and returns the squad.
func _make_squad(owner: String, troop_type: String, hex: HexCoord, count: int, troops: Dictionary, hp: float = -1.0) -> SquadInstance:
	_next_id += 1
	var squad := SquadInstance.new("sq%d" % _next_id, owner, troop_type, hex)
	var use_hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 0.0)) if hp < 0.0 else hp
	for i in range(count):
		_next_id += 1
		var tid := "tr%d" % _next_id
		troops[tid] = TroopInstance.new(tid, troop_type, owner, squad.id, use_hp)
		squad.add_member(tid)
	return squad

## A synthetic CombatTarget from a troop-def dict, for CombatMath tests.
func _synthetic_target(def: Dictionary, owner: String, hex: HexCoord, troops: Dictionary) -> CombatTarget:
	var squad := SquadInstance.new("synth", owner, "synthetic", hex)
	squad.add_member("synth_t")
	troops["synth_t"] = TroopInstance.new("synth_t", "synthetic", owner, "synth", 100.0)
	return CombatTarget.for_squad(squad, def, troops)

## --- BuildingStats -------------------------------------------------------

func _test_building_stats() -> void:
	var hq: Dictionary = _building_defs["hq"]
	_check(_approx(BuildingStats.max_hp(hq, 1, "", _building_defs), 300.0), "HQ level 1 max_hp = baseStats.hp (300)")
	_check(_approx(BuildingStats.max_hp(hq, 2, "", _building_defs), 330.0), "HQ level 2 max_hp = 300 * 1.10 (percent growth)")

	var wall: Dictionary = _building_defs["wall"]
	_check(_approx(BuildingStats.max_hp(wall, 1, "wood", _building_defs), 80.0), "Wood Wall level 1 max_hp from materialStats")
	_check(_approx(BuildingStats.max_hp(wall, 1, "steel", _building_defs), 400.0), "Steel Wall level 1 max_hp from materialStats")
	_check(BuildingStats.damage_received_modifiers(wall, "wood", _building_defs).get("Fire", 1.0) == 2.0, "Wood Wall has {Fire: 2.0} damageReceivedModifiers")

	# extends inheritance: a synthetic Turret variant that omits every block
	# inherits Turret's defensiveStats + nonProductionUpgrade wholesale.
	var variant := {"id": "test_variant", "name": "Test Variant", "category": "Defensive", "extends": "turret"}
	_check(_approx(BuildingStats.max_hp(variant, 1, "", _building_defs), 250.0), "extends: variant inherits Turret's baseStats.hp (250)")
	_check(BuildingStats.defensive_stats(variant, _building_defs).get("damage", 0.0) == 18, "extends: variant inherits Turret's defensiveStats.damage (18)")

	# a real Turret variant still resolves an HP even though it restates blocks.
	_check(BuildingStats.max_hp(_building_defs["cold_turret"], 1, "", _building_defs) > 0.0, "real Turret variant (cold_turret) resolves a positive max_hp")

## --- CombatMath ----------------------------------------------------------

func _test_combat_math() -> void:
	var troops: Dictionary = {}
	var rifleman: Dictionary = _troop_defs["rifleman"]
	var grenadier: Dictionary = _troop_defs["grenadier"]

	# plain hit, no modifiers
	var infantry_target := _synthetic_target({"domain": "Infantry", "tags": []}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, infantry_target), 10.0), "plain hit = base damage (10)")

	# damageDealtModifiers bonus: Grenadier {Land: 1.5} vs a Land target
	var land_target := _synthetic_target({"domain": "Land", "tags": []}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(grenadier, 8.0, land_target), 12.0), "Grenadier {Land:1.5} vs Land = 8 * 1.5 = 12")
	_check(_approx(CombatMath.resolve_damage(grenadier, 8.0, infantry_target), 8.0), "Grenadier's Land bonus does NOT apply to an Infantry target")

	# damageReceivedModifiers: a Fire attacker vs a Fire-vulnerable target
	var fire_attacker := {"domain": "Land", "tags": [], "damageTypes": ["Fire"], "damageDealtModifiers": {}}
	var wood_target := _synthetic_target({"domain": "Land", "damageReceivedModifiers": {"Fire": 2.0}}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(fire_attacker, 10.0, wood_target), 20.0), "Fire attacker vs {Fire:2.0} target = 20")

	# Piercing bypasses the target's received modifiers entirely (but not armor)
	var piercing_attacker := {"domain": "Land", "tags": [], "damageTypes": ["Piercing"], "damageDealtModifiers": {}}
	_check(_approx(CombatMath.resolve_damage(piercing_attacker, 10.0, wood_target), 10.0), "Piercing bypasses {Fire:2.0} -> 10")

	# armor is flat, applied last, floored so a hit always deals >= 1
	var armored := _synthetic_target({"domain": "Land", "armor": 3.0}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, armored), 7.0), "armor 3 on a 10 hit -> 7")
	var tank := _synthetic_target({"domain": "Land", "armor": 100.0}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, tank), 1.0), "armor floor: a hit always deals at least 1")

	# dealt x received stack multiplicatively
	var stack_attacker := {"domain": "Infantry", "tags": [], "damageTypes": ["Fire"], "damageDealtModifiers": {"Land": 1.5}}
	var stack_target := _synthetic_target({"domain": "Land", "damageReceivedModifiers": {"Fire": 2.0}}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(stack_attacker, 10.0, stack_target), 30.0), "dealt 1.5 x received 2.0 x base 10 = 30")

	# terrain defense multiplier (hill defender bonus) folds in as another
	# received-side multiplier, still respecting the >=1 floor.
	var hilly := HexGrid.new()
	hilly.set_terrain(HexCoord.new(1, 0), Terrain.Type.HILLS)
	var hill_target := CombatTarget.for_squad(_make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops), rifleman, troops, hilly)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, hill_target), 10.0 * Terrain.HILLS_DEFENDER_BONUS), "Hills defense_multiplier reduces a 10 hit to base * HILLS_DEFENDER_BONUS")
	var flat_target := CombatTarget.for_squad(_make_squad("p2", "rifleman", HexCoord.new(2, 0), 1, troops), rifleman, troops, hilly)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, flat_target), 10.0), "an unset (Ocean-default) hex has no terrain defense bonus")

## --- Terrain.defense_bonus ------------------------------------------------

func _test_terrain_defense_bonus() -> void:
	_check(_approx(Terrain.defense_bonus(Terrain.Type.HILLS), Terrain.HILLS_DEFENDER_BONUS), "Hills grants HILLS_DEFENDER_BONUS")
	_check(_approx(Terrain.defense_bonus(Terrain.Type.PLAINS), 1.0), "Plains grants no defense bonus")
	_check(_approx(Terrain.defense_bonus(Terrain.Type.FOREST), 1.0), "Forest grants no defense bonus (its bonus is ambush hiding, not damage reduction)")
	_check(_approx(Terrain.defense_bonus(Terrain.Type.RIVER), 1.0), "River grants no defense bonus")
	_check(_approx(Terrain.defense_bonus(Terrain.Type.OCEAN), 1.0), "Ocean grants no defense bonus")

## --- CombatTargeting -----------------------------------------------------

func _test_combat_targeting() -> void:
	var troops: Dictionary = {}
	var rifleman: Dictionary = _troop_defs["rifleman"]
	var grenadier: Dictionary = _troop_defs["grenadier"]
	var basekiller: Dictionary = _troop_defs["basekiller"]

	# nearest-in-range pick among equal-priority troop targets
	var attacker := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	var near := _make_squad("p2", "rifleman", HexCoord.new(2, 0), 1, troops)
	var far := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var targets: Array[CombatTarget] = [
		CombatTarget.for_squad(near, rifleman, troops),
		CombatTarget.for_squad(far, rifleman, troops),
	]
	var picked := CombatTargeting.select_target(attacker, rifleman, targets)
	_check(picked != null and picked.target_id() == near.id, "auto-targets the nearest in-range enemy")

	# canTarget exclusion: Grenadier cannot hit Air
	var gren := _make_squad("p1", "grenadier", HexCoord.new(0, 0), 1, troops)
	var air_squad := _make_squad("p2", "glider", HexCoord.new(1, 0), 1, troops)
	var air_only: Array[CombatTarget] = [CombatTarget.for_squad(air_squad, _troop_defs["glider"], troops)]
	_check(CombatTargeting.select_target(gren, grenadier, air_only) == null, "Grenadier can't target an Air unit -> no target")

	# highest-modifier priority: Grenadier prefers an equally-near Land vehicle over Infantry
	var gren2 := _make_squad("p1", "grenadier", HexCoord.new(0, 0), 1, troops)
	var enemy_inf := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops)
	var enemy_land := _make_squad("p2", "basekiller", HexCoord.new(0, 1), 1, troops)
	var mixed: Array[CombatTarget] = [
		CombatTarget.for_squad(enemy_inf, rifleman, troops),
		CombatTarget.for_squad(enemy_land, basekiller, troops),
	]
	var gpick := CombatTargeting.select_target(gren2, grenadier, mixed)
	_check(gpick != null and gpick.target_id() == enemy_land.id, "Grenadier prefers the Land target (1.5x) over an equally-near Infantry")

	# tier gating: a plain Structure is only chosen when no troop/Defensive is in
	# range. enemy_troop is an Engineer (Land) since Basekiller can't target Infantry.
	var bk := _make_squad("p1", "basekiller", HexCoord.new(0, 0), 1, troops)
	var enemy_troop := _make_squad("p2", "engineer", HexCoord.new(1, 0), 1, troops)
	var base := _p2_base_with("farm", HexCoord.new(0, 1))
	var struct_target := CombatTarget.for_building(base.buildings[0], _building_defs["farm"], _building_defs)
	struct_target.owner_id = "p2"
	var troop_and_struct: Array[CombatTarget] = [
		CombatTarget.for_squad(enemy_troop, _troop_defs["engineer"], troops),
		struct_target,
	]
	var bpick := CombatTargeting.select_target(bk, basekiller, troop_and_struct)
	_check(bpick != null and bpick.target_id() == enemy_troop.id, "Tier A: troop chosen over a plain Structure when both in range")
	var struct_only: Array[CombatTarget] = [struct_target]
	var bpick2 := CombatTargeting.select_target(bk, basekiller, struct_only)
	_check(bpick2 != null and bpick2.kind == CombatTarget.Kind.BUILDING, "Tier B: Structure chosen once no troop/Defensive is in range")

	# Basekiller prefers a Defensive building (2.5x) over a plain Structure
	var def_base := _p2_base_with("turret", HexCoord.new(1, 0))
	var def_target := CombatTarget.for_building(def_base.buildings[0], _building_defs["turret"], _building_defs)
	def_target.owner_id = "p2"
	var struct_and_def: Array[CombatTarget] = [struct_target, def_target]
	var dpick := CombatTargeting.select_target(bk, basekiller, struct_and_def)
	_check(dpick != null and dpick.target_id() == def_base.buildings[0].id, "Basekiller prefers the Defensive building (2.5x) over a plain Structure")

	# directed attack_target override + fallback when the directed target dies
	var directed := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	directed.order = {"type": "attack_target", "targetId": far.id}
	var directed_targets: Array[CombatTarget] = [
		CombatTarget.for_squad(near, rifleman, troops),
		CombatTarget.for_squad(far, rifleman, troops),
	]
	var dorder := CombatTargeting.select_target(directed, rifleman, directed_targets)
	_check(dorder != null and dorder.target_id() == far.id, "directed attack_target fires on the ordered target, not the nearer one")
	# kill the directed target -> order clears, falls back to auto (nearest)
	troops[far.member_ids[0]].current_hp = 0.0
	var fallback := CombatTargeting.select_target(directed, rifleman, directed_targets)
	_check(fallback != null and fallback.target_id() == near.id, "directed order falls back to auto once its target dies")
	_check(directed.order.is_empty(), "dead directed target clears the order")

## --- Stealth/detection ----------------------------------------------------

func _test_stealth_and_detection() -> void:
	var troops: Dictionary = {}
	var rifleman: Dictionary = _troop_defs["rifleman"]
	var ghost_tank: Dictionary = _troop_defs["ghost_tank"]

	# Forest ambush: an Infantry squad standing on Forest is hidden from an
	# enemy with no detector/proximity, and has no proximity reveal at all.
	var forest_grid := HexGrid.new()
	forest_grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.FOREST)
	var ambusher := _make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, troops)
	var ambush_target := CombatTarget.for_squad(ambusher, rifleman, troops, forest_grid)
	_check(ambush_target.is_hidden, "an Infantry squad on a Forest hex is ambush-hidden")
	var candidates_far := CombatTargeting.candidates(HexCoord.new(5, 0), "p2", 10, rifleman, [ambush_target])
	_check(candidates_far.is_empty(), "a forest-hidden squad is excluded from an enemy's candidates at range")
	var candidates_adjacent := CombatTargeting.candidates(HexCoord.new(2, 0), "p2", 10, rifleman, [ambush_target])
	_check(candidates_adjacent.is_empty(), "forest ambush has no proximity reveal (FOREST_AMBUSH_REVEAL_RANGE = 0)")

	# After attacking, the ambusher's reveal_cooldown_remaining is set and it's
	# no longer hidden; once elapsed, it re-hides.
	ambusher.reveal_cooldown_remaining = DetectionSystem.REVEAL_COOLDOWN_SECONDS
	var revealed_target := CombatTarget.for_squad(ambusher, rifleman, troops, forest_grid)
	_check(not revealed_target.is_hidden, "an ambusher mid reveal-cooldown (just attacked) is not hidden")
	ambusher.reveal_cooldown_remaining = 0.0
	var rehidden_target := CombatTarget.for_squad(ambusher, rifleman, troops, forest_grid)
	_check(rehidden_target.is_hidden, "the ambusher re-hides once its reveal cooldown expires")

	# A non-Infantry squad on the same Forest hex (Glider, domain Air) is not
	# ambush-hidden — the bonus is Infantry-only.
	var glider_on_forest := _make_squad("p1", "glider", HexCoord.new(1, 0), 1, troops)
	var glider_target := CombatTarget.for_squad(glider_on_forest, _troop_defs["glider"], troops, forest_grid)
	_check(not glider_target.is_hidden, "a non-Infantry squad on Forest is not ambush-hidden")

	# Authored stealth (Ghost Tank): hidden beyond revealRange, visible within it.
	# Grid must have registered hexes for DetectionSystem's has_hex() check to
	# mark any coverage at all (an empty HexGrid.new() has no hexes anywhere).
	var stealth_grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), 15):
		stealth_grid.set_terrain(coord, Terrain.Type.PLAINS)
	var ghost := _make_squad("p2", "ghost_tank", HexCoord.new(0, 0), 1, troops)
	var ghost_target := CombatTarget.for_squad(ghost, ghost_tank, troops, stealth_grid)
	_check(ghost_target.is_hidden, "Ghost Tank is stealthed regardless of terrain")
	var far_candidates := CombatTargeting.candidates(HexCoord.new(5, 0), "p1", 10, rifleman, [ghost_target])
	_check(far_candidates.is_empty(), "Ghost Tank hidden beyond its revealRange with no detector")
	var near_candidates := CombatTargeting.candidates(HexCoord.new(1, 0), "p1", 10, rifleman, [ghost_target])
	_check(near_candidates.size() == 1, "Ghost Tank visible within its revealRange (1) even with no detector")

	# A Sniper (detector: true, no detectionRange -> falls back to its full
	# 12-tile visionRange) reveals the Ghost Tank; a different owner without
	# their own detector coverage still can't see it.
	var squads: Array[SquadInstance] = [ghost]
	var bases: Array[BaseInstance] = []
	var det_p1: Dictionary = {}
	DetectionSystem.resolve_tick(squads, bases, [], stealth_grid, _troop_defs, _building_defs, det_p1)
	_check(det_p1.is_empty(), "no detector present yet -> no detection coverage")

	var sniper_squad := _make_squad("p1", "sniper", HexCoord.new(0, 0), 1, troops)
	squads.append(sniper_squad)
	DetectionSystem.resolve_tick(squads, bases, [], stealth_grid, _troop_defs, _building_defs, det_p1)
	_check(DetectionSystem.detected_hexes_for(det_p1, "p1").has(ghost.current_hex.to_key()), "p1's Sniper detector covers the Ghost Tank's hex (full visionRange fallback)")
	var revealed_candidates := CombatTargeting.candidates(HexCoord.new(5, 0), "p1", 10, rifleman, [ghost_target], det_p1)
	_check(revealed_candidates.size() == 1, "p1's detector coverage reveals the Ghost Tank to a p1 attacker beyond its revealRange")
	var other_owner_candidates := CombatTargeting.candidates(HexCoord.new(5, 0), "p3", 10, rifleman, [ghost_target], det_p1)
	_check(other_owner_candidates.is_empty(), "p1's detection coverage does not leak to a different owner (p3)")

	# Radar Array (base-attached) reveals a stealthed enemy squad within its
	# vision range for its owner only.
	var radar_base := _p2_base_with("radar_array", HexCoord.new(0, 0))
	radar_base.owner_id = "p1"
	var det_radar: Dictionary = {}
	DetectionSystem.resolve_tick([ghost], [radar_base], [], stealth_grid, _troop_defs, _building_defs, det_radar)
	_check(DetectionSystem.detected_hexes_for(det_radar, "p1").has(ghost.current_hex.to_key()), "Radar Array's detector covers a stealthed enemy squad within its vision range")
	_check(DetectionSystem.detected_hexes_for(det_radar, "p2").is_empty(), "Radar Array's coverage does not leak to a different owner")

func _p2_base_with(building_type: String, hex: HexCoord) -> BaseInstance:
	var base := BaseInstance.new("p2base", "capital", "p2", 1, HexCoord.new(0, 0))
	var building := BuildingInstance.new("bld_%s" % building_type, "p2base", building_type, 1, "", hex)
	building.init_hp(_building_defs[building_type], _building_defs)
	base.buildings.append(building)
	return base

## --- CombatResolver ------------------------------------------------------

func _test_combat_resolver() -> void:
	var grid := HexGrid.new()

	# attack-speed cadence: no fire until the accumulator reaches 1.0
	var troops: Dictionary = {}
	var a := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	var b := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops)
	var squads: Array[SquadInstance] = [a, b]
	CombatResolver.resolve_tick(0.5, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[b.member_ids[0]].current_hp == 100.0, "no fire before attack_progress reaches 1.0 (dt 0.5, attackSpeed 1)")
	CombatResolver.resolve_tick(0.5, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[b.member_ids[0]].current_hp == 90.0, "one volley fires when the accumulator crosses 1.0 (10 damage)")

	# splash hits other enemies in radius but never friendlies. Targets and the
	# friendly are Engineers (Land, canTarget []): grenadier gets its {Land:1.5}
	# bonus and nothing retaliates, isolating the splash to the grenadier's shot.
	var t2: Dictionary = {}
	var gren := _make_squad("p1", "grenadier", HexCoord.new(0, 0), 1, t2)
	var enemy_a := _make_squad("p2", "engineer", HexCoord.new(1, 0), 1, t2)
	var enemy_b := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, t2)
	var friendly := _make_squad("p1", "engineer", HexCoord.new(1, -1), 1, t2)
	var enemy_a_tid := enemy_a.member_ids[0]
	var enemy_b_tid := enemy_b.member_ids[0]
	var friendly_tid := friendly.member_ids[0]
	var splash_squads: Array[SquadInstance] = [gren, enemy_a, enemy_b, friendly]
	CombatResolver.resolve_tick(1.0, splash_squads, [], t2, grid, _troop_defs, _building_defs)
	# Engineer hp 60; Grenadier vs Land = 8 * 1.5 = 12 -> 48. Primary enemy_a and
	# splashed enemy_b (1 hex away) both hit; the friendly in radius is spared.
	_check(t2[enemy_a_tid].current_hp == 48.0, "splash: primary Land target takes 12 (60 -> 48)")
	_check(t2[enemy_b_tid].current_hp == 48.0, "splash: second enemy in radius also takes 12")
	_check(t2[friendly_tid].current_hp == 60.0, "splash does not damage a friendly unit in radius")

	# a squad kills a weaker enemy squad, which is then pruned
	var t3: Dictionary = {}
	var killer := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, t3)
	var victim := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, t3, 5.0)
	var victim_tid := victim.member_ids[0]
	var kill_squads: Array[SquadInstance] = [killer, victim]
	CombatResolver.resolve_tick(1.0, kill_squads, [], t3, grid, _troop_defs, _building_defs)
	_check(kill_squads.size() == 1 and kill_squads[0].id == killer.id, "a killed squad is pruned from the squads list")
	_check(not t3.has(victim_tid), "the dead troop is removed from the registry")

	# a Basekiller sieges a building down to 0 HP and it becomes a ruin, not
	# removed — the hex/adjacency slot stays occupied per
	# 06-building-stats-and-defenses.md's Destruction & Ruins section.
	var t4: Dictionary = {}
	var siege := _make_squad("p1", "basekiller", HexCoord.new(0, 0), 1, t4)
	var enemy_base := _p2_base_with("farm", HexCoord.new(1, 0))
	var farm: BuildingInstance = enemy_base.buildings[0]
	var farm_hp := farm.max_hp
	_check(farm_hp > 0.0, "seeded Farm has a positive max_hp to fight down")
	var bases: Array[BaseInstance] = [enemy_base]
	for _i in range(200):
		if farm.is_ruin:
			break
		CombatResolver.resolve_tick(1.0, [siege], bases, t4, grid, _troop_defs, _building_defs)
	_check(farm.is_ruin, "Basekiller fights the Farm down to a ruin")
	_check(enemy_base.buildings.size() == 1 and enemy_base.buildings[0] == farm, "the ruined Farm stays in base.buildings, not removed")
	_check(farm.current_hp <= 0.0, "a ruin sits at 0 HP")
	_check(farm.last_damaged_by == "p1", "the ruin remembers who dealt the killing blow")

	# an HQ sieged to 0 HP captures the base instead of ruining
	var t_hq: Dictionary = {}
	var hq_siege := _make_squad("p1", "basekiller", HexCoord.new(0, 0), 1, t_hq)
	var hq_base := _p2_base_with("hq", HexCoord.new(1, 0))
	var hq: BuildingInstance = hq_base.buildings[0]
	var hq_max_hp := hq.max_hp
	var hq_bases: Array[BaseInstance] = [hq_base]
	for _i in range(200):
		if hq_base.owner_id == "p1":
			break
		CombatResolver.resolve_tick(1.0, [hq_siege], hq_bases, t_hq, grid, _troop_defs, _building_defs)
	_check(hq_base.owner_id == "p1", "an HQ fought to 0 HP flips the whole base to the attacker")
	_check(hq.current_hp == hq_max_hp, "the HQ respawns at full HP under its new owner")
	_check(not hq.is_ruin, "the HQ is never marked as a ruin")
	_check(hq_base.buildings.size() == 1, "the HQ is never removed from the base")

	# a Defensive building fires back and damages an attacking squad
	var t5: Dictionary = {}
	var raider := _make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, t5)
	var turret_base := _p2_base_with("turret", HexCoord.new(0, 0))
	CombatResolver.resolve_tick(1.0, [raider], [turret_base], t5, grid, _troop_defs, _building_defs)
	_check(t5[raider.member_ids[0]].current_hp < 100.0, "a Defensive Turret fires back and damages the attacking squad")
	_check(turret_base.buildings[0].current_hp < turret_base.buildings[0].max_hp, "the attacking squad also damages the Turret")

	# out-of-combat regen: a damaged, surviving building slowly heals once it
	# stops taking damage, per 06-building-stats-and-defenses.md
	var regen_base := _p2_base_with("farm", HexCoord.new(2, 0))
	var regen_building: BuildingInstance = regen_base.buildings[0]
	regen_building.current_hp = regen_building.max_hp - 100.0
	regen_building.time_since_damage = 0.0
	var no_squads: Array[SquadInstance] = []
	var no_troops: Dictionary = {}
	CombatResolver.resolve_tick(BuildingRegenSystem.OUT_OF_COMBAT_DELAY_SECONDS - 1.0, no_squads, [regen_base], no_troops, grid, _troop_defs, _building_defs)
	_check(regen_building.current_hp == regen_building.max_hp - 100.0, "no regen before the out-of-combat delay elapses")
	CombatResolver.resolve_tick(1.0, no_squads, [regen_base], no_troops, grid, _troop_defs, _building_defs)
	_check(regen_building.current_hp == regen_building.max_hp - 100.0, "crossing the delay banks no regen tick yet on its own")
	CombatResolver.resolve_tick(BuildingRegenSystem.REGEN_TICK_SECONDS - 1.0, no_squads, [regen_base], no_troops, grid, _troop_defs, _building_defs)
	_check(_approx(regen_building.current_hp, regen_building.max_hp - 100.0 + regen_building.max_hp * BuildingRegenSystem.REGEN_FRACTION_OF_MAX_HP), "once a full 5-second regen tick banks past the delay, it heals 5% of max HP")
