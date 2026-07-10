## Headless assertion suite for the combat slice (sim/combat/combat_*.gd,
## sim/bases/building_stats.gd). Run with:
##   godot --headless --script res://tests/test_combat.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _next_id: int = 0
var _next_proj: int = 0

func _next_projectile_id() -> String:
	_next_proj += 1
	return "proj%d" % _next_proj

## Every combat troop/building now carries a projectileSpeed (see
## tests/test_projectiles.gd) -- this suite's assertions all predate that and
## assume same-call resolution, so every CombatResolver.resolve_tick call site
## below is routed through here instead, which mirrors SimOrchestrator's own
## CombatResolver -> ProjectileSystem pairing (same dt for both) exactly. Every
## fixture in this file fires at short enough range/high enough speed that
## travel_time < dt, so the shot still fully resolves within this one call --
## a fresh empty `projectiles` array per call is therefore equivalent to a
## persistent one for every test here.
func _resolve_combat(dt: float, squads: Array[SquadInstance], bases: Array[BaseInstance], troops_by_id: Dictionary, grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, detections: Dictionary = {}, auras: Dictionary = {}, standalone_buildings: Array[BuildingInstance] = [], regiments: Array[RegimentInstance] = [], production_queues: Dictionary = {}) -> void:
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(dt, squads, bases, troops_by_id, grid, troop_defs, building_defs, detections, auras, standalone_buildings, regiments, production_queues, projectiles, Callable(self, "_next_projectile_id"))
	ProjectileSystem.resolve_tick(dt, projectiles, squads, bases, troops_by_id, grid, troop_defs, building_defs, auras, standalone_buildings, regiments, production_queues)

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
	print("CombatResolver Commander-death regiment disband")
	_test_commander_death_regiment_disband()
	print("CombatResolver Wall combat")
	_test_wall_combat()
	print("CombatResolver Wood Tower turrets")
	_test_wood_tower_turrets()
	print("CombatResolver line attack (Tank Obliterator)")
	_test_line_attack()

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
	var hq_base_hp: float = float(hq.get("nonProductionUpgrade", {}).get("baseStats", {}).get("hp", 0.0))
	var hq_hp_growth_pct: float = float(hq.get("nonProductionUpgrade", {}).get("statGrowth", {}).get("hp", {}).get("value", 0.0))
	var hq_level2_hp: float = hq_base_hp * (1.0 + hq_hp_growth_pct / 100.0)
	_check(_approx(BuildingStats.max_hp(hq, 1, "", _building_defs), hq_base_hp), "HQ level 1 max_hp = baseStats.hp (%s)" % hq_base_hp)
	_check(_approx(BuildingStats.max_hp(hq, 2, "", _building_defs), hq_level2_hp), "HQ level 2 max_hp = %s * (1 + %s%%) percent growth = %s" % [hq_base_hp, hq_hp_growth_pct, hq_level2_hp])

	var wall: Dictionary = _building_defs["wall"]
	var wall_wood_hp: float = float(wall.get("materialStats", {}).get("wood", {}).get("baseStats", {}).get("hp", 0.0))
	var wall_steel_hp: float = float(wall.get("materialStats", {}).get("steel", {}).get("baseStats", {}).get("hp", 0.0))
	var wall_wood_fire_mod: float = float(wall.get("materialStats", {}).get("wood", {}).get("damageReceivedModifiers", {}).get("Fire", 1.0))
	var wall_steel_armor: float = float(wall.get("materialStats", {}).get("steel", {}).get("baseStats", {}).get("armor", 0.0))
	_check(_approx(BuildingStats.max_hp(wall, 1, "wood", _building_defs), wall_wood_hp), "Wood Wall level 1 max_hp from materialStats (%s)" % wall_wood_hp)
	_check(_approx(BuildingStats.max_hp(wall, 1, "steel", _building_defs), wall_steel_hp), "Steel Wall level 1 max_hp from materialStats (%s)" % wall_steel_hp)
	_check(BuildingStats.damage_received_modifiers(wall, "wood", _building_defs).get("Fire", 1.0) == wall_wood_fire_mod, "Wood Wall has {Fire: %s} damageReceivedModifiers" % wall_wood_fire_mod)
	_check(_approx(BuildingStats.armor(wall, 1, "steel", _building_defs), wall_steel_armor), "Steel Wall has flat armor (%s) from materialStats.baseStats.armor" % wall_steel_armor)
	_check(_approx(BuildingStats.armor(wall, 1, "stone", _building_defs), 0.0), "Stone Wall has no armor entry -> 0")
	_check(_approx(BuildingStats.armor(wall, 1, "wood", _building_defs), 0.0), "Wood Wall has no armor entry -> 0")

	# extends inheritance: a synthetic Turret variant that omits every block
	# inherits Turret's defensiveStats + nonProductionUpgrade wholesale.
	var turret_def: Dictionary = _building_defs["turret"]
	var turret_hp: float = float(turret_def.get("nonProductionUpgrade", {}).get("baseStats", {}).get("hp", 0.0))
	var turret_damage: float = float(turret_def.get("defensiveStats", {}).get("damage", 0.0))
	var variant := {"id": "test_variant", "name": "Test Variant", "category": "Defensive", "extends": "turret"}
	_check(_approx(BuildingStats.max_hp(variant, 1, "", _building_defs), turret_hp), "extends: variant inherits Turret's baseStats.hp (%s)" % turret_hp)
	_check(BuildingStats.defensive_stats(variant, 1, "", _building_defs).get("damage", 0.0) == turret_damage, "extends: variant inherits Turret's defensiveStats.damage (%s)" % turret_damage)

	# Tower (multi-material Defensive): defensive_stats merges the material's
	# level-scaled damage/attackSpeed/range/canTarget/splashRadius on top of
	# the building-level (material-invariant) detector/detectionRange, per
	# data/buildings/schema.json's materialStats.canTarget note.
	var tower: Dictionary = _building_defs["tower"]
	var tower_wood_block: Dictionary = tower.get("materialStats", {}).get("wood", {})
	var tower_wood_damage: float = float(tower_wood_block.get("baseStats", {}).get("damage", 0.0))
	var tower_wood_attack_speed: float = float(tower_wood_block.get("baseStats", {}).get("attackSpeed", 0.0))
	var tower_steel_block: Dictionary = tower.get("materialStats", {}).get("steel", {})
	var tower_steel_splash: int = int(tower_steel_block.get("splashRadius", 0))
	var tower_steel_armor: float = float(tower_steel_block.get("baseStats", {}).get("armor", 0.0))
	var tower_stone_growth_pct: float = float(tower.get("materialStats", {}).get("stone", {}).get("statGrowth", {}).get("damage", {}).get("value", 0.0))
	var wood_stats := BuildingStats.defensive_stats(tower, 1, "wood", _building_defs)
	_check(wood_stats.get("damage", 0.0) == tower_wood_damage, "Wood Tower level 1 damage from materialStats.wood.baseStats (%s)" % tower_wood_damage)
	_check(_approx(wood_stats.get("attackSpeed", 0.0), tower_wood_attack_speed), "Wood Tower attackSpeed from materialStats.wood.baseStats (%s)" % tower_wood_attack_speed)
	_check(wood_stats.get("canTarget", []) == ["Infantry", "Land", "Air", "Naval"], "Wood Tower canTarget from materialStats.wood")
	_check(wood_stats.get("detector", false) == true, "Wood Tower still carries the material-invariant detector flag")
	var steel_stats := BuildingStats.defensive_stats(tower, 1, "steel", _building_defs)
	_check(not steel_stats.get("canTarget", []).has("Air"), "Steel Tower's canTarget drops Air, unlike Wood/Stone")
	_check(steel_stats.get("splashRadius", 0) == tower_steel_splash, "Steel Tower's splashRadius (%s) from materialStats.steel" % tower_steel_splash)
	var stone_damage_l1: float = BuildingStats.defensive_stats(tower, 1, "stone", _building_defs).get("damage", 0.0)
	var stone_damage_l2: float = BuildingStats.defensive_stats(tower, 2, "stone", _building_defs).get("damage", 0.0)
	_check(stone_damage_l2 > stone_damage_l1, "Stone Tower's damage grows with level (%s%% percent growth)" % tower_stone_growth_pct)
	_check(_approx(BuildingStats.armor(tower, 1, "steel", _building_defs), tower_steel_armor), "Steel Tower has flat armor (%s) from materialStats.baseStats.armor" % tower_steel_armor)
	_check(_approx(BuildingStats.armor(tower, 1, "stone", _building_defs), 0.0), "Stone Tower has no armor entry -> 0")

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

	# damageDealtModifiers bonus: Grenadier's live {Land: X} modifier vs a Land target
	var land_target := _synthetic_target({"domain": "Land", "tags": []}, "p2", HexCoord.new(1, 0), troops)
	var grenadier_land_mult: float = float(grenadier.get("damageDealtModifiers", {}).get("Land", 1.0))
	var grenadier_land_expected: float = 8.0 * grenadier_land_mult
	_check(_approx(CombatMath.resolve_damage(grenadier, 8.0, land_target), grenadier_land_expected), "Grenadier's Land modifier (%s) vs Land = 8 * %s = %s" % [grenadier_land_mult, grenadier_land_mult, grenadier_land_expected])
	_check(_approx(CombatMath.resolve_damage(grenadier, 8.0, infantry_target), 8.0), "Grenadier's Land bonus does NOT apply to an Infantry target")

	# damageReceivedModifiers: a Fire attacker vs a Fire-vulnerable target
	var fire_attacker := {"domain": "Land", "tags": [], "damageTypes": ["Fire"], "damageDealtModifiers": {}}
	var wood_target := _synthetic_target({"domain": "Land", "damageReceivedModifiers": {"Fire": 2.0}}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(fire_attacker, 10.0, wood_target), 20.0), "Fire attacker vs {Fire:2.0} target = 20")

	# Piercing does NOT bypass damageReceivedModifiers -- it only matches keys
	# the attacker actually presents, same as any other damage type. A
	# Piercing attacker without "Fire" doesn't trigger the Fire-only target.
	var piercing_attacker := {"domain": "Land", "tags": [], "damageTypes": ["Piercing"], "damageDealtModifiers": {}}
	_check(_approx(CombatMath.resolve_damage(piercing_attacker, 10.0, wood_target), 10.0), "Piercing attacker without Fire vs {Fire:2.0} target = 10 (no match)")

	# ...but a vulnerability keyed on "Piercing" itself still applies in full --
	# Piercing does not cancel the target's received-side modifiers.
	var piercing_vulnerable := _synthetic_target({"domain": "Land", "damageReceivedModifiers": {"Piercing": 2.0}}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(piercing_attacker, 10.0, piercing_vulnerable), 20.0), "Piercing attacker vs {Piercing:2.0} target = 20 (vulnerability still applies)")

	# armor is flat, applied last, floored so a hit always deals >= 1
	var armored := _synthetic_target({"domain": "Land", "armor": 3.0}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, armored), 7.0), "armor 3 on a 10 hit -> 7")
	var tank := _synthetic_target({"domain": "Land", "armor": 100.0}, "p2", HexCoord.new(1, 0), troops)
	_check(_approx(CombatMath.resolve_damage(rifleman, 10.0, tank), 1.0), "armor floor: a hit always deals at least 1")

	# Piercing bypasses armor entirely (the flat reduction), unlike a normal attack
	_check(_approx(CombatMath.resolve_damage(piercing_attacker, 10.0, armored), 10.0), "Piercing ignores armor 3 on a 10 hit -> 10")
	_check(_approx(CombatMath.resolve_damage(piercing_attacker, 10.0, tank), 10.0), "Piercing ignores armor 100 on a 10 hit -> 10")

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
	var gren_land_mult: float = float(grenadier.get("damageDealtModifiers", {}).get("Land", 1.0))
	_check(gpick != null and gpick.target_id() == enemy_land.id, "Grenadier prefers the Land target (%sx) over an equally-near Infantry" % gren_land_mult)

	# dampener avoidance: a troop with {Land: 0.5} (deals HALF damage to Land)
	# prefers a farther neutral target (no modifier, full damage) over a nearer
	# one it's dampened against, but still engages the dampened target when
	# it's the only option in range.
	var weak_vs_land: Dictionary = rifleman.duplicate(true)
	weak_vs_land["damageDealtModifiers"] = {"Land": 0.5}
	var wv_attacker := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	var near_land := _make_squad("p2", "basekiller", HexCoord.new(1, 0), 1, troops)
	var far_inf := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var dampened_mixed: Array[CombatTarget] = [
		CombatTarget.for_squad(near_land, basekiller, troops),
		CombatTarget.for_squad(far_inf, rifleman, troops),
	]
	var wvpick := CombatTargeting.select_target(wv_attacker, weak_vs_land, dampened_mixed)
	_check(wvpick != null and wvpick.target_id() == far_inf.id, "Avoids a nearer target it's dampened (0.5x) against, in favor of a farther neutral one")
	var dampened_only: Array[CombatTarget] = [CombatTarget.for_squad(near_land, basekiller, troops)]
	var wvpick2 := CombatTargeting.select_target(wv_attacker, weak_vs_land, dampened_only)
	_check(wvpick2 != null and wvpick2.target_id() == near_land.id, "Still engages a dampened target once it's the only option")

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

	# minRange: Earthshaker can't fire at anything adjacent to it (a dead zone,
	# the mirror of the max-range check), but can once a target is at or beyond
	# minRange, up to its normal range.
	var earthshaker: Dictionary = _troop_defs["earthshaker"]
	var es_min_range: int = int(earthshaker.get("minRange", 0))
	var es_range: int = int(earthshaker.get("range", 0))
	var adjacent_enemy := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops)
	var adjacent_only: Array[CombatTarget] = [CombatTarget.for_squad(adjacent_enemy, rifleman, troops)]
	_check(CombatTargeting.candidates(HexCoord.new(0, 0), "p1", es_range, earthshaker, adjacent_only).is_empty(), "Earthshaker's minRange (%s) excludes an adjacent enemy" % es_min_range)
	var at_min_range := _make_squad("p2", "rifleman", HexCoord.new(es_min_range, 0), 1, troops)
	var at_min_only: Array[CombatTarget] = [CombatTarget.for_squad(at_min_range, rifleman, troops)]
	_check(CombatTargeting.candidates(HexCoord.new(0, 0), "p1", es_range, earthshaker, at_min_only).size() == 1, "Earthshaker can engage a target exactly at its minRange (%s)" % es_min_range)
	var beyond_range := _make_squad("p2", "rifleman", HexCoord.new(es_range + 1, 0), 1, troops)
	var beyond_only: Array[CombatTarget] = [CombatTarget.for_squad(beyond_range, rifleman, troops)]
	_check(CombatTargeting.candidates(HexCoord.new(0, 0), "p1", es_range, earthshaker, beyond_only).is_empty(), "a target beyond Earthshaker's normal range is still excluded -- minRange doesn't change the max-range check")

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
	var rifleman_hp: float = float(_troop_defs["rifleman"].get("hp", 0.0))
	var rifleman_damage: float = float(_troop_defs["rifleman"].get("damage", 0.0))
	var rifleman_attack_speed: float = float(_troop_defs["rifleman"].get("attackSpeed", 1.0))
	var a := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	var b := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops)
	var squads: Array[SquadInstance] = [a, b]
	_resolve_combat(0.5, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[b.member_ids[0]].current_hp == rifleman_hp, "no fire before attack_progress reaches 1.0 (dt 0.5, attackSpeed %s)" % rifleman_attack_speed)
	_resolve_combat(0.5, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[b.member_ids[0]].current_hp == rifleman_hp - rifleman_damage, "one volley fires when the accumulator crosses 1.0 (%s damage)" % rifleman_damage)

	# splash hits other enemies in radius but never friendlies. Targets and the
	# friendly are Engineers (Land, canTarget []): grenadier gets its live
	# {Land: X} bonus and nothing retaliates, isolating the splash to the
	# grenadier's shot.
	var t2: Dictionary = {}
	var engineer_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var grenadier_def2: Dictionary = _troop_defs["grenadier"]
	var grenadier_land_mult2: float = float(grenadier_def2.get("damageDealtModifiers", {}).get("Land", 1.0))
	var grenadier_base_damage2: float = float(grenadier_def2.get("damage", 0.0))
	var grenadier_splash_damage: float = grenadier_base_damage2 * grenadier_land_mult2
	var engineer_hp_after_splash: float = engineer_hp - grenadier_splash_damage
	var gren := _make_squad("p1", "grenadier", HexCoord.new(0, 0), 1, t2)
	var enemy_a := _make_squad("p2", "engineer", HexCoord.new(1, 0), 1, t2)
	var enemy_b := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, t2)
	var friendly := _make_squad("p1", "engineer", HexCoord.new(1, -1), 1, t2)
	var enemy_a_tid := enemy_a.member_ids[0]
	var enemy_b_tid := enemy_b.member_ids[0]
	var friendly_tid := friendly.member_ids[0]
	var splash_squads: Array[SquadInstance] = [gren, enemy_a, enemy_b, friendly]
	_resolve_combat(1.0, splash_squads, [], t2, grid, _troop_defs, _building_defs)
	# Engineer hp (engineer_hp); Grenadier vs Land = grenadier_base_damage2 *
	# grenadier_land_mult2 = grenadier_splash_damage. Primary enemy_a and
	# splashed enemy_b (1 hex away) both hit; the friendly in radius is spared.
	_check(t2[enemy_a_tid].current_hp == engineer_hp_after_splash, "splash: primary Land target takes %s (%s -> %s)" % [grenadier_splash_damage, engineer_hp, engineer_hp_after_splash])
	_check(t2[enemy_b_tid].current_hp == engineer_hp_after_splash, "splash: second enemy in radius also takes %s" % grenadier_splash_damage)
	_check(t2[friendly_tid].current_hp == engineer_hp, "splash does not damage a friendly unit in radius")

	# a squad kills a weaker enemy squad, which is then pruned
	var t3: Dictionary = {}
	var killer := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, t3)
	var victim := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, t3, 5.0)
	var victim_tid := victim.member_ids[0]
	var kill_squads: Array[SquadInstance] = [killer, victim]
	_resolve_combat(1.0, kill_squads, [], t3, grid, _troop_defs, _building_defs)
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
	# A live ProductionQueue keyed to the Farm should be erased the instant it
	# ruins, per 07-data-architecture.md 3b -- a ruined building can't produce.
	var farm_queues: Dictionary = {farm.id: ProductionQueue.new(farm.id)}
	for _i in range(200):
		if farm.is_ruin:
			break
		_resolve_combat(1.0, [siege], bases, t4, grid, _troop_defs, _building_defs, {}, {}, [], [], farm_queues)
	_check(farm.is_ruin, "Basekiller fights the Farm down to a ruin")
	_check(enemy_base.buildings.size() == 1 and enemy_base.buildings[0] == farm, "the ruined Farm stays in base.buildings, not removed")
	_check(farm.current_hp <= 0.0, "a ruin sits at 0 HP")
	_check(farm.last_damaged_by == "p1", "the ruin remembers who dealt the killing blow")
	_check(not farm_queues.has(farm.id), "the ruined Farm's ProductionQueue is erased outright")

	# an HQ sieged to 0 HP captures the base instead of ruining
	var t_hq: Dictionary = {}
	var hq_siege := _make_squad("p1", "basekiller", HexCoord.new(0, 0), 1, t_hq)
	var hq_base := _p2_base_with("hq", HexCoord.new(1, 0))
	var hq: BuildingInstance = hq_base.buildings[0]
	var hq_max_hp := hq.max_hp
	var hq_bases: Array[BaseInstance] = [hq_base]
	# A live ProductionQueue for another building on the SAME base should be
	# wiped out the moment the base is captured, not just the HQ's own (the
	# HQ itself never produces) -- per 07-data-architecture.md 3b, capture
	# clears every one of the captured base's queues.
	var other_building := BuildingInstance.new("other_prod", hq_base.id, "barracks", 1)
	hq_base.buildings.append(other_building)
	var hq_capture_queues: Dictionary = {other_building.id: ProductionQueue.new(other_building.id)}
	for _i in range(200):
		if hq_base.owner_id == "p1":
			break
		_resolve_combat(1.0, [hq_siege], hq_bases, t_hq, grid, _troop_defs, _building_defs, {}, {}, [], [], hq_capture_queues)
	_check(hq_base.owner_id == "p1", "an HQ fought to 0 HP flips the whole base to the attacker")
	_check(hq.current_hp == hq_max_hp, "the HQ respawns at full HP under its new owner")
	_check(not hq.is_ruin, "the HQ is never marked as a ruin")
	_check(hq_base.buildings.size() == 2, "the HQ is never removed from the base")
	_check(not hq_capture_queues.has(other_building.id), "capturing the base erases every one of its buildings' ProductionQueues")

	# a Defensive building fires back and damages an attacking squad
	var t5: Dictionary = {}
	var raider := _make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, t5)
	var turret_base := _p2_base_with("turret", HexCoord.new(0, 0))
	_resolve_combat(1.0, [raider], [turret_base], t5, grid, _troop_defs, _building_defs)
	_check(t5[raider.member_ids[0]].current_hp < rifleman_hp, "a Defensive Turret fires back and damages the attacking squad")
	_check(turret_base.buildings[0].current_hp < turret_base.buildings[0].max_hp, "the attacking squad also damages the Turret")

	# out-of-combat regen: a damaged, surviving building slowly heals once it
	# stops taking damage, per 06-building-stats-and-defenses.md
	var regen_base := _p2_base_with("farm", HexCoord.new(2, 0))
	var regen_building: BuildingInstance = regen_base.buildings[0]
	regen_building.current_hp = regen_building.max_hp - 100.0
	regen_building.time_since_damage = 0.0
	var no_squads: Array[SquadInstance] = []
	var no_troops: Dictionary = {}
	_resolve_combat(BuildingRegenSystem.OUT_OF_COMBAT_DELAY_SECONDS - 1.0, no_squads, [regen_base], no_troops, grid, _troop_defs, _building_defs)
	_check(regen_building.current_hp == regen_building.max_hp - 100.0, "no regen before the out-of-combat delay elapses")
	_resolve_combat(1.0, no_squads, [regen_base], no_troops, grid, _troop_defs, _building_defs)
	_check(regen_building.current_hp == regen_building.max_hp - 100.0, "crossing the delay banks no regen tick yet on its own")
	_resolve_combat(BuildingRegenSystem.REGEN_TICK_SECONDS - 1.0, no_squads, [regen_base], no_troops, grid, _troop_defs, _building_defs)
	_check(_approx(regen_building.current_hp, regen_building.max_hp - 100.0 + regen_building.max_hp * BuildingRegenSystem.REGEN_FRACTION_OF_MAX_HP), "once a full 5-second regen tick banks past the delay, it heals 5% of max HP")

	# A standalone building (Tower — Engineer-built, owner_id set directly
	# rather than derived from a BaseInstance) is targetable by CombatResolver
	# too: it fires back like any Defensive building, and a Basekiller can
	# fight it down.
	var t6: Dictionary = {}
	var basekiller_hp: float = float(_troop_defs["basekiller"].get("hp", 0.0))
	var attacker := _make_squad("p1", "basekiller", HexCoord.new(1, 0), 1, t6)
	var tower := BuildingInstance.new("standalone_tower", "", "tower", 1, "wood", HexCoord.new(0, 0), "p2")
	tower.init_hp(_building_defs["tower"], _building_defs)
	var standalone: Array[BuildingInstance] = [tower]
	var no_bases: Array[BaseInstance] = []
	_resolve_combat(1.0, [attacker], no_bases, t6, grid, _troop_defs, _building_defs, {}, {}, standalone)
	_check(t6[attacker.member_ids[0]].current_hp < basekiller_hp, "standalone Tower fires back and damages the attacking squad")
	_check(tower.current_hp < tower.max_hp, "standalone Tower is damaged by CombatResolver's targeting")

	# Fought down to 0 HP, a standalone building deletes outright — it never
	# ruins, per 06-building-stats-and-defenses.md's Destruction & Ruins section.
	for _i in range(200):
		if standalone.is_empty():
			break
		_resolve_combat(1.0, [attacker], no_bases, t6, grid, _troop_defs, _building_defs, {}, {}, standalone)
	_check(standalone.is_empty(), "a standalone Tower fought to 0 HP is deleted outright, not ruined")

	# A Landmine (selfDestructOnTrigger, no attackSpeed) fires once the instant
	# a valid enemy is in range and is deleted outright the same tick, rather
	# than sitting inert (its attackSpeed-gated repeat-fire path never engages).
	var t7: Dictionary = {}
	var intruder := _make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, t7)
	var mine := BuildingInstance.new("mine1", "", "landmine", 1, "", HexCoord.new(0, 0), "p2")
	mine.init_hp(_building_defs["landmine"], _building_defs)
	var mine_standalone: Array[BuildingInstance] = [mine]
	_resolve_combat(1.0, [intruder], no_bases, t7, grid, _troop_defs, _building_defs, {}, {}, mine_standalone)
	_check(t7[intruder.member_ids[0]].current_hp < rifleman_hp, "a Landmine deals its splash damage the instant an Infantry/Land enemy is in range")
	_check(mine_standalone.is_empty(), "the Landmine is deleted outright the same tick it triggers, not left inert")

## Per 04-combat.md: "if a Commander dies mid-battle, its regiment disbands —
## every member squad reverts to operating independently." RegimentInstance
## itself was previously untouched by any resolver (only exercised directly
## by tests/test_units.gd's assign_squad/remove_squad checks) — this proves
## CombatResolver._disband_regiments_for_dead_commanders actually fires once
## the Commander's squad is pruned.
func _test_commander_death_regiment_disband() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var commander := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0), 1, troops)
	var member_a := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	var member_b := _make_squad("p1", "sniper", HexCoord.new(0, 0), 1, troops)
	member_a.commander_id = commander.id
	member_a.order = {"type": "regiment_move", "goal": HexCoord.new(3, 0).to_key()}
	member_b.commander_id = commander.id
	member_b.order = {"type": "regiment_move", "goal": HexCoord.new(3, 0).to_key()}

	var regiment := RegimentInstance.new("r1", commander.id)
	regiment.assign_squad(member_a.id, 4)
	regiment.assign_squad(member_b.id, 4)
	var regiments: Array[RegimentInstance] = [regiment]

	# Kill the Commander directly (combat RNG/targeting isn't the point here).
	troops[commander.member_ids[0]].current_hp = 0.0

	var squads: Array[SquadInstance] = [commander, member_a, member_b]
	var bases: Array[BaseInstance] = []
	_resolve_combat(1.0, squads, bases, troops, grid, _troop_defs, _building_defs, {}, {}, [], regiments)

	_check(not squads.any(func(s): return s.id == commander.id), "the dead Commander squad is pruned")
	_check(regiments.is_empty(), "the regiment is disbanded once its Commander dies")
	_check(member_a.commander_id == "", "member squad's commander_id is cleared")
	_check(member_b.commander_id == "", "second member squad's commander_id is cleared")
	_check(member_a.order.is_empty(), "member squad's regiment_move order is reset to idle")
	_check(member_b.order.is_empty(), "second member squad's regiment_move order is reset to idle")

	# A regiment whose Commander is still alive is left completely untouched.
	var troops2: Dictionary = {}
	var live_commander := _make_squad("p1", "commander_vanguard", HexCoord.new(0, 0), 1, troops2)
	var live_member := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops2)
	live_member.commander_id = live_commander.id
	live_member.order = {"type": "regiment_move", "goal": HexCoord.new(3, 0).to_key()}
	var live_regiment := RegimentInstance.new("r2", live_commander.id)
	live_regiment.assign_squad(live_member.id, 4)
	var live_regiments: Array[RegimentInstance] = [live_regiment]
	var squads2: Array[SquadInstance] = [live_commander, live_member]
	_resolve_combat(1.0, squads2, [], troops2, grid, _troop_defs, _building_defs, {}, {}, [], live_regiments)
	_check(not live_regiments.is_empty(), "a regiment whose Commander survives is not disbanded")
	_check(live_member.commander_id == live_commander.id, "a living regiment's member commander_id is untouched")
	_check(live_member.order.get("type") == "regiment_move", "a living regiment's member order is untouched")

## Walls are edge-keyed (BuildingInstance.hex_a/hex_b, hex left null) rather
## than hex-keyed, but otherwise ride the exact same base.buildings/
## CombatResolver machinery every other base-attached building already uses
## (BuildingStats.max_hp, BuildingRegenSystem, _build_targets/_advance_building,
## _prune_dead) — this proves that reuse actually works end-to-end, plus the
## two genuinely Wall-specific behaviors: deleting outright (never ruining)
## and reopening grid.set_wall() on destruction.
func _test_wall_combat() -> void:
	var grid := HexGrid.new()
	grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)
	grid.set_terrain(HexCoord.new(1, 0), Terrain.Type.PLAINS)
	var base := BaseInstance.new("wbase", "capital", "p2", 1, HexCoord.new(0, 0))
	var wall := BuildingInstance.new("wall1", "wbase", "wall", 1, "wood")
	wall.hex_a = HexCoord.new(0, 0)
	wall.hex_b = HexCoord.new(1, 0)
	wall.init_hp(_building_defs["wall"], _building_defs)
	base.buildings.append(wall)
	grid.set_wall(wall.hex_a, wall.hex_b, true)
	_check(wall.max_hp > 0.0, "Wood Wall resolves a positive max_hp from materialStats, same as BuildingPlacement.place_wall")
	_check(grid.is_walled_edge(HexCoord.new(0, 0), HexCoord.new(1, 0)), "the edge is walled before combat")

	var t7: Dictionary = {}
	var attacker := _make_squad("p1", "basekiller", HexCoord.new(1, 0), 1, t7)
	var bases: Array[BaseInstance] = [base]
	for _i in range(200):
		if not base.buildings.any(func(b): return b.id == "wall1"):
			break
		_resolve_combat(1.0, [attacker], bases, t7, grid, _troop_defs, _building_defs)
	_check(not base.buildings.any(func(b): return b.id == "wall1"), "the Wall is fought down and deleted outright, not ruined")
	_check(not grid.is_walled_edge(HexCoord.new(0, 0), HexCoord.new(1, 0)), "destroying the Wall reopens its edge for movement/pathing")

	# Air-domain attackers ignore Walls entirely as targets, per
	# 01-map-and-terrain.md; a Land attacker can target the same Wall fine.
	var wall2 := BuildingInstance.new("wall2", "wbase2", "wall", 1, "wood")
	wall2.hex_a = HexCoord.new(0, 0)
	wall2.hex_b = HexCoord.new(1, 0)
	wall2.init_hp(_building_defs["wall"], _building_defs)
	var wall_target := CombatTarget.for_building(wall2, _building_defs["wall"], _building_defs, grid)
	wall_target.owner_id = "p2"
	var targets2: Array[CombatTarget] = [wall_target]

	var air_def: Dictionary = _troop_defs["hot_air_balloon"]
	_check(String(air_def.get("domain")) == "Air", "hot_air_balloon is Air-domain (canTarget includes Defensive, so this isn't a canTarget-mismatch)")
	var air_candidates := CombatTargeting.candidates(HexCoord.new(1, 0), "p1", 10, air_def, targets2)
	_check(air_candidates.is_empty(), "an Air-domain attacker ignores a Wall entirely, even in range and canTarget-eligible")

	var land_def: Dictionary = _troop_defs["basekiller"]
	var land_candidates := CombatTargeting.candidates(HexCoord.new(1, 0), "p1", 10, land_def, targets2)
	_check(land_candidates.size() == 1, "a Land-domain attacker can target the same Wall")

	# A Wall is in range from EITHER hex it borders, not just one.
	_check(wall_target.distance_from(HexCoord.new(0, 0)) == 0, "distance_from is 0 when the attacker stands on hex_a")
	_check(wall_target.distance_from(HexCoord.new(1, 0)) == 0, "distance_from is 0 when the attacker stands on hex_b")
	_check(wall_target.distance_from(HexCoord.new(2, 0)) == 1, "distance_from is the MIN distance to either endpoint (1 via hex_b, not 2 via hex_a)")

	# Steel Wall's flat armor reaches CombatMath the same way a troop's
	# armor stat does, and a Piercing attacker (e.g. Sniper) bypasses it.
	var steel_wall_armor: float = float(_building_defs["wall"].get("materialStats", {}).get("steel", {}).get("baseStats", {}).get("armor", 0.0))
	var steel_wall_normal_hit: float = max(10.0 - steel_wall_armor, 1.0)
	var steel_wall := BuildingInstance.new("wall3", "wbase3", "wall", 1, "steel")
	steel_wall.hex_a = HexCoord.new(0, 0)
	steel_wall.hex_b = HexCoord.new(1, 0)
	steel_wall.init_hp(_building_defs["wall"], _building_defs)
	var steel_wall_target := CombatTarget.for_building(steel_wall, _building_defs["wall"], _building_defs, grid)
	_check(_approx(steel_wall_target.armor, steel_wall_armor), "Steel Wall's CombatTarget carries armor %s" % steel_wall_armor)
	_check(_approx(CombatMath.resolve_damage(_troop_defs["rifleman"], 10.0, steel_wall_target), steel_wall_normal_hit), "a normal 10-damage hit vs Steel Wall's armor %s -> %s" % [steel_wall_armor, steel_wall_normal_hit])
	var piercing_attacker: Dictionary = {"domain": "Land", "tags": [], "damageTypes": ["Piercing"], "damageDealtModifiers": {}}
	_check(_approx(CombatMath.resolve_damage(piercing_attacker, 10.0, steel_wall_target), 10.0), "a Piercing attacker ignores Steel Wall's armor entirely")

## Wood Tower's addsTurretPerLevel (06-building-stats-and-defenses.md: "each
## upgrade level adds an additional turret" that "independently targets"):
## proves turret_count scales with level (Wood only), turret_progress sizes to
## match, and — the actual behavioral payoff — a multi-turret tower spreads
## its shots across several separate weak enemies in one tick instead of
## focus-firing whichever single target it would otherwise pick.
func _test_wood_tower_turrets() -> void:
	var grid := HexGrid.new()

	_check(BuildingStats.turret_count(_building_defs["tower"], 1, "wood", _building_defs) == 1, "Wood Tower turret_count == level (1 turret at level 1)")
	_check(BuildingStats.turret_count(_building_defs["tower"], 3, "wood", _building_defs) == 3, "Wood Tower turret_count == level (3 turrets at level 3)")
	_check(BuildingStats.turret_count(_building_defs["tower"], 3, "stone", _building_defs) == 1, "Stone Tower has no addsTurretPerLevel -> always 1 turret regardless of level")

	# A level-1 Wood Tower has exactly one turret, so only the nearest of
	# three separate weak squads in range takes a killing hit this tick.
	var troops_l1: Dictionary = {}
	var tower_l1 := BuildingInstance.new("wood_tower_l1", "", "tower", 1, "wood", HexCoord.new(0, 0), "p2")
	tower_l1.init_hp(_building_defs["tower"], _building_defs)
	_check(tower_l1.turret_progress.size() == 1, "a fresh level-1 Wood Tower's turret_progress array has 1 accumulator")
	var enemies_l1: Array[SquadInstance] = [
		_make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, troops_l1, 5.0),
		_make_squad("p1", "rifleman", HexCoord.new(2, 0), 1, troops_l1, 5.0),
		_make_squad("p1", "rifleman", HexCoord.new(3, 0), 1, troops_l1, 5.0),
	]
	var standalone_l1: Array[BuildingInstance] = [tower_l1]
	_resolve_combat(1.0, enemies_l1, [], troops_l1, grid, _troop_defs, _building_defs, {}, {}, standalone_l1)
	# _prune_dead removes a fully-dead squad from the array outright (not just
	# empties its member_ids), so "how many died" is the shrinkage in size.
	_check(enemies_l1.size() == 2, "level-1 Wood Tower (1 turret) kills exactly one of three separate weak squads in a single tick")

	# A level-3 Wood Tower has three independently-targeting turrets, so all
	# three separate weak squads die the same tick instead of one being
	# focus-fired three times over — this is the swarm-clearing payoff
	# 06-building-stats-and-defenses.md describes.
	var troops_l3: Dictionary = {}
	var tower_l3 := BuildingInstance.new("wood_tower_l3", "", "tower", 3, "wood", HexCoord.new(0, 0), "p2")
	tower_l3.init_hp(_building_defs["tower"], _building_defs)
	_check(tower_l3.turret_progress.size() == 3, "a fresh level-3 Wood Tower's turret_progress array has 3 accumulators")
	var enemies_l3: Array[SquadInstance] = [
		_make_squad("p1", "rifleman", HexCoord.new(1, 0), 1, troops_l3, 5.0),
		_make_squad("p1", "rifleman", HexCoord.new(2, 0), 1, troops_l3, 5.0),
		_make_squad("p1", "rifleman", HexCoord.new(3, 0), 1, troops_l3, 5.0),
	]
	var standalone_l3: Array[BuildingInstance] = [tower_l3]
	_resolve_combat(1.0, enemies_l3, [], troops_l3, grid, _troop_defs, _building_defs, {}, {}, standalone_l3)
	_check(enemies_l3.is_empty(), "level-3 Wood Tower's 3 independently-targeting turrets each kill a separate squad in the same tick")

## Tank Obliterator's rail gun (lineAttack): fires along a straight beam from
## the attacker's own hex through the auto-selected primary target and beyond,
## piercing every enemy troop on the line but hard-stopped by the first
## building anywhere on its path -- see 05-troop-stat-schema.md and
## combat_resolver.gd's _apply_line_attack/_beam_hexes.
func _test_line_attack() -> void:
	var grid := HexGrid.new()
	var tank_obliterator: Dictionary = _troop_defs["tank_obliterator"]
	var beam_damage: float = float(tank_obliterator.get("damage", 0.0))
	var attack_speed: float = float(tank_obliterator.get("attackSpeed", 1.0))
	var rifleman_hp: float = float(_troop_defs["rifleman"].get("hp", 0.0))
	# Cross the 1.0 attack_progress threshold across two calls of 0.7 of a
	# cycle each (1.4 total, comfortably over 1.0 even with float slop)
	# rather than one dt == 1.0/attackSpeed call: with attackSpeed 0.2 that
	# single dt (5.0) exactly equals BuildingRegenSystem.
	# OUT_OF_COMBAT_DELAY_SECONDS, and _damage_target already reset the hit
	# building's time_since_damage to 0 earlier in that same tick — so a
	# single big dt would coincidentally bank a full out-of-combat regen tick
	# in the very call that lands the hit, muddying the damage assertions
	# below with regen math that has nothing to do with line attacks. Two
	# 0.7-cycle calls still fire exactly one volley (only the second call
	# crosses the threshold) while keeping each call's own dt under the regen
	# delay.
	var cycle: float = 1.0 / attack_speed

	# Beam fires east from (0,0): e1 (1,0) is nearest -> auto-picked primary
	# target, e2 (2,0) is pierced too, the Farm at (3,0) blocks and takes the
	# hit as the beam's terminal target, e3 (4,0) sits beyond the block and is
	# untouched. off_beam (2,-2) is in range but nowhere on the line at all.
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "tank_obliterator", HexCoord.new(0, 0), 1, troops)
	var e1 := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops)
	var e2 := _make_squad("p2", "rifleman", HexCoord.new(2, 0), 1, troops)
	var off_beam := _make_squad("p2", "rifleman", HexCoord.new(2, -2), 1, troops)
	var e3 := _make_squad("p2", "rifleman", HexCoord.new(4, 0), 1, troops)
	var enemy_base := _p2_base_with("farm", HexCoord.new(3, 0))
	var farm: BuildingInstance = enemy_base.buildings[0]
	var farm_max_hp := farm.max_hp
	var farm_expected_damage: float = beam_damage * float(tank_obliterator.get("damageDealtModifiers", {}).get("Structure", 1.0))

	var squads: Array[SquadInstance] = [attacker, e1, e2, off_beam, e3]
	var bases: Array[BaseInstance] = [enemy_base]
	_resolve_combat(cycle * 0.7, squads, bases, troops, grid, _troop_defs, _building_defs)
	_resolve_combat(cycle * 0.7, squads, bases, troops, grid, _troop_defs, _building_defs)

	_check(troops[e1.member_ids[0]].current_hp == rifleman_hp - beam_damage, "line attack: nearest primary target on the beam takes full damage")
	_check(troops[e2.member_ids[0]].current_hp == rifleman_hp - beam_damage, "line attack: a second enemy squad further along the beam is also hit (goes through troops)")
	_check(troops[off_beam.member_ids[0]].current_hp == rifleman_hp, "line attack: an enemy squad in range but off the beam's line is untouched")
	_check(_approx(farm.current_hp, farm_max_hp - farm_expected_damage), "line attack: the first building on the beam takes the hit as its terminal target (%s)" % farm_expected_damage)
	_check(troops[e3.member_ids[0]].current_hp == rifleman_hp, "line attack: an enemy squad beyond the blocking building is untouched")

	# A FRIENDLY building on the beam also blocks it, but takes no damage --
	# never friendly fire, the same rule splash already follows.
	var troops2: Dictionary = {}
	var attacker2 := _make_squad("p1", "tank_obliterator", HexCoord.new(0, 0), 1, troops2)
	var f1 := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops2)
	var f3 := _make_squad("p2", "rifleman", HexCoord.new(4, 0), 1, troops2)
	var friendly_base := BaseInstance.new("p1base_beam", "capital", "p1", 1, HexCoord.new(5, 5))
	var friendly_building := BuildingInstance.new("bld_friendly_farm", "p1base_beam", "farm", 1, "", HexCoord.new(2, 0))
	friendly_building.init_hp(_building_defs["farm"], _building_defs)
	friendly_base.buildings.append(friendly_building)
	var friendly_max_hp := friendly_building.max_hp

	var squads2: Array[SquadInstance] = [attacker2, f1, f3]
	var bases2: Array[BaseInstance] = [friendly_base]
	_resolve_combat(cycle * 0.7, squads2, bases2, troops2, grid, _troop_defs, _building_defs)
	_resolve_combat(cycle * 0.7, squads2, bases2, troops2, grid, _troop_defs, _building_defs)

	_check(troops2[f1.member_ids[0]].current_hp == rifleman_hp - beam_damage, "line attack: nearest primary target still takes damage with a friendly building further down the beam")
	_check(friendly_building.current_hp == friendly_max_hp, "line attack: a friendly building on the beam takes no damage")
	_check(troops2[f3.member_ids[0]].current_hp == rifleman_hp, "line attack: a friendly building still blocks the beam from reaching what's behind it")

## Upgrading a live Wood Tower grows turret_progress by one slot without
	# resetting the slots it already had banked.
	var upgrading_tower := BuildingInstance.new("wood_tower_upgrade", "", "tower", 1, "wood", HexCoord.new(0, 0), "p2")
	upgrading_tower.init_hp(_building_defs["tower"], _building_defs)
	upgrading_tower.turret_progress[0] = 0.75
	upgrading_tower.level = 2
	upgrading_tower.upgrade_hp(_building_defs["tower"], _building_defs)
	_check(upgrading_tower.turret_progress.size() == 2, "upgrading a Wood Tower from level 1 to 2 grows turret_progress to 2 slots")
	_check(_approx(upgrading_tower.turret_progress[0], 0.75), "the pre-existing turret's banked progress survives the upgrade")
	_check(_approx(upgrading_tower.turret_progress[1], 0.0), "the newly added turret starts with no banked progress")
