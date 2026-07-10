## Headless assertion suite for the projectile travel-time/dodge slice
## (sim/combat/projectile_instance.gd, sim/combat/projectile_system.gd, and
## CombatResolver's _fire_or_apply branch). Run with:
##   godot --headless --script res://tests/test_projectiles.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _next_id: int = 0
var _next_proj: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")
	_building_defs = DataLoader.load_dir("res://data/buildings")

	print("ProjectileSystem")
	_test_instant_units_unaffected()
	_test_ballistic_fire_and_arrival()
	_test_full_dodge_when_target_moves_off_aim_hex()
	_test_splash_still_hits_neighbor_when_primary_dodges()
	_test_whiff_when_target_already_dead_before_impact()
	_test_whiff_when_target_docked_mid_flight()
	_test_no_friendly_fire_when_base_captured_mid_flight()
	_test_shell_resolves_after_attacker_dies()
	_test_status_effect_applies_to_whoever_is_at_aim_hex()
	_test_multi_turret_building_fires_independent_projectiles()

	print("ProjectileSystem traveling beam (lineAttack + projectileSpeed)")
	_test_beam_fire_spawns_traveling_projectile_not_instant_damage()
	_test_beam_hits_nearer_hex_before_farther_hex()
	_test_beam_status_effect_applies_independently_per_victim()
	_test_beam_stops_at_blocking_building()
	_test_beam_target_dodges_by_moving_off_its_hex_before_arrival()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers -------------------------------------------------------------

func _approx(a: float, b: float) -> bool:
	return abs(a - b) < 0.001

func _next_projectile_id() -> String:
	_next_proj += 1
	return "proj%d" % _next_proj

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

func _p2_base_with(building_type: String, hex: HexCoord) -> BaseInstance:
	var base := BaseInstance.new("p2base", "capital", "p2", 1, HexCoord.new(0, 0))
	var building := BuildingInstance.new("bld_%s" % building_type, "p2base", building_type, 1, "", hex)
	building.init_hp(_building_defs[building_type], _building_defs)
	base.buildings.append(building)
	return base

## --- tests -----------------------------------------------------------------

## Baseline regression: a unit with no projectileSpeed is completely
## unaffected by the new branch -- damage still lands the same tick it fires,
## and nothing is appended to the projectiles out-array. Every real combat
## troop now carries a projectileSpeed except Tank Obliterator (lineAttack
## always stays instant via a separate guard), so this proves the "absent
## projectileSpeed" code path itself still resolves instantly via a synthetic
## def (a duplicated rifleman with projectileSpeed erased) rather than
## depending on any specific real unit remaining instant.
func _test_instant_units_unaffected() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_def: Dictionary = _troop_defs["rifleman"].duplicate(true)
	synthetic_def.erase("projectileSpeed")
	var synthetic_troop_defs: Dictionary = {"rifleman": synthetic_def, "engineer": _troop_defs["engineer"]}
	var engineer_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var rifleman_damage: float = float(synthetic_def.get("damage", 0.0))
	var a := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	var b := _make_squad("p2", "engineer", HexCoord.new(1, 0), 1, troops)
	var squads: Array[SquadInstance] = [a, b]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, synthetic_troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))
	_check(troops[b.member_ids[0]].current_hp == engineer_hp - rifleman_damage, "a unit with no projectileSpeed still resolves damage instantly")
	_check(projectiles.is_empty(), "no ProjectileInstance is spawned for an instant-hit unit")

## The core ballistic path: firing spawns a ProjectileInstance instead of
## applying damage, travel_time == distance / projectileSpeed, and the shot
## deals its damage only once that travel time has fully elapsed.
func _test_ballistic_fire_and_arrival() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var target_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var frost_damage: float = float(_troop_defs["frost_tank"].get("damage", 0.0))
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))
	_check(troops[target.member_ids[0]].current_hp == target_hp, "a ballistic shot does not damage its target the tick it's fired")
	_check(projectiles.size() == 1, "firing a ballistic attack spawns exactly one ProjectileInstance")

	var expected_travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	_check(_approx(projectiles[0].remaining_time, expected_travel), "the projectile's travel time is distance / projectileSpeed (%s)" % expected_travel)

	ProjectileSystem.resolve_tick(expected_travel * 0.5, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[target.member_ids[0]].current_hp == target_hp, "the shot hasn't landed yet halfway through its travel time")
	_check(projectiles.size() == 1, "the projectile is still in flight halfway through its travel time")

	ProjectileSystem.resolve_tick(expected_travel * 0.6, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[target.member_ids[0]].current_hp == target_hp - frost_damage, "the shot lands for full damage once its travel time elapses")
	_check(projectiles.is_empty(), "a resolved projectile is removed from the in-flight list")

## The crux dodge mechanic: a projectile aims at a FIXED hex, not a tracked
## target id, so a target that fully relocates off that hex before impact
## takes zero damage.
func _test_full_dodge_when_target_moves_off_aim_hex() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var target_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))
	_check(projectiles.size() == 1, "the shot is in flight")

	# The target relocates off the aimed hex before the shell lands -- same
	# "current_hex is the only position gameplay reads" model MovementResolver
	# uses, just mutated directly here instead of via a real move order.
	target.current_hex = HexCoord.new(6, 0)

	var travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	ProjectileSystem.resolve_tick(travel + 0.01, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[target.member_ids[0]].current_hp == target_hp, "a target that moved off the aim hex before impact takes zero damage -- a full dodge")
	_check(projectiles.is_empty(), "the projectile resolves (as a whiff) and is removed even though it hit nothing")

## Partial dodge: splash still checks other enemies near the fixed aim hex,
## so a target that steps just outside blast radius can dodge while a
## bystander that stayed nearby still eats the splash.
func _test_splash_still_hits_neighbor_when_primary_dodges() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var primary := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var bystander := _make_squad("p2", "engineer", HexCoord.new(3, 0), 1, troops) # 1 hex from the aim hex
	var engineer_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var frost_damage: float = float(_troop_defs["frost_tank"].get("damage", 0.0))
	var squads: Array[SquadInstance] = [attacker, primary, bystander]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	primary.current_hex = HexCoord.new(8, 0) # dodges fully clear of the blast

	var travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	ProjectileSystem.resolve_tick(travel + 0.01, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[primary.member_ids[0]].current_hp == engineer_hp, "the primary target that relocated off the aim hex takes no damage")
	_check(troops[bystander.member_ids[0]].current_hp == engineer_hp - frost_damage, "a second enemy still standing within splash radius of the aim hex is hit anyway")

## A target killed by something unrelated between fire and impact is simply
## absent from the fresh snapshot ProjectileSystem builds at arrival -- a
## whiff, not a crash.
func _test_whiff_when_target_already_dead_before_impact() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	troops[target.member_ids[0]].current_hp = 0.0 # killed by something else mid-flight

	var travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	ProjectileSystem.resolve_tick(travel + 0.01, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(projectiles.is_empty(), "a shot aimed at a target that died to something else before impact resolves without error")

## A target that boards a carrier mid-flight is docked (no independent
## position, not in the fresh target snapshot) by the time the shell lands.
func _test_whiff_when_target_docked_mid_flight() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var engineer_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	target.boarded_on_squad_id = "carrier_x" # boards a carrier before the shell lands

	var travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	ProjectileSystem.resolve_tick(travel + 0.01, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[target.member_ids[0]].current_hp == engineer_hp, "a target that boarded a carrier before impact is untargetable and takes no damage")
	_check(projectiles.is_empty(), "the projectile still resolves (as a whiff) without error")

## A base captured mid-flight (by something else entirely) is friendly to the
## original attacker by the time the shell lands -- CombatTarget.owner_id
## always derives from the base's LIVE owner_id, never anything cached at
## fire time, so this falls out for free from rebuilding targets at impact.
func _test_no_friendly_fire_when_base_captured_mid_flight() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var base := _p2_base_with("farm", HexCoord.new(2, 0))
	var farm: BuildingInstance = base.buildings[0]
	var farm_hp := farm.current_hp
	var squads: Array[SquadInstance] = [attacker]
	var bases: Array[BaseInstance] = [base]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, bases, troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))
	_check(projectiles.size() == 1, "firing at a Structure spawns a projectile just like firing at a squad")

	base.owner_id = "p1" # the base flips to the attacker's own side mid-flight

	var travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	ProjectileSystem.resolve_tick(travel + 0.01, projectiles, squads, bases, troops, grid, _troop_defs, _building_defs)
	_check(farm.current_hp == farm_hp, "a base captured mid-flight is friendly by the time the shell lands -- no friendly fire")

## A ProjectileInstance never holds a live reference to its firer -- only the
## owner_id string and a frozen attacker_def snapshot -- so an already-fired
## shell still lands even if the attacker is destroyed before it arrives.
func _test_shell_resolves_after_attacker_dies() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var engineer_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var frost_damage: float = float(_troop_defs["frost_tank"].get("damage", 0.0))
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, _troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	squads.erase(attacker) # the attacker is destroyed the same tick it fired

	var travel: float = 2.0 / float(_troop_defs["frost_tank"].get("projectileSpeed", 0.0))
	ProjectileSystem.resolve_tick(travel + 0.01, projectiles, squads, [], troops, grid, _troop_defs, _building_defs)
	_check(troops[target.member_ids[0]].current_hp == engineer_hp - frost_damage, "an already-fired shell still lands even if its attacker died before impact")

## statusEffectOnHit is rolled against whoever's actually standing on the aim
## hex at arrival, not necessarily the unit the shot was originally aimed at.
func _test_status_effect_applies_to_whoever_is_at_aim_hex() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	# A synthetic def (frost_tank's real statusEffectOnHit is a 25% chance --
	# not deterministic enough for this test) with chance omitted, which
	# StatusEffectSystem.apply_on_hit defaults to 100.
	var synthetic_def: Dictionary = _troop_defs["frost_tank"].duplicate(true)
	synthetic_def["statusEffectOnHit"] = {"type": "freeze", "duration": 2}
	var synthetic_troop_defs: Dictionary = {"frost_tank": synthetic_def, "rifleman": _troop_defs["rifleman"]}

	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var original_target := _make_squad("p2", "rifleman", HexCoord.new(2, 0), 1, troops)
	var squads: Array[SquadInstance] = [attacker, original_target]
	var targets := CombatResolver.build_targets(squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	var target_ct := CombatTargeting.select_target(attacker, synthetic_def, targets, {}, grid)

	var projectiles: Array[ProjectileInstance] = []
	CombatResolver._fire_or_apply(synthetic_def, float(synthetic_def.get("damage", 0.0)), "p1", attacker.current_hex, target_ct, targets, troops, int(synthetic_def.get("splashRadius", 0)), synthetic_troop_defs, _building_defs, grid, projectiles, Callable(self, "_next_projectile_id"))
	_check(projectiles.size() == 1, "the synthetic ballistic attack spawns a projectile")

	# original_target relocates off the aim hex; a fresh enemy squad is
	# standing on the aim hex instead by the time the shell lands.
	original_target.current_hex = HexCoord.new(9, 0)
	var replacement := _make_squad("p2", "rifleman", HexCoord.new(2, 0), 1, troops)
	squads.append(replacement)

	ProjectileSystem.resolve_tick(projectiles[0].remaining_time + 0.01, projectiles, squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	_check(original_target.lockout_remaining == 0.0, "the original target, having relocated, is not the one frozen")
	_check(replacement.lockout_remaining > 0.0, "whoever is actually standing on the aim hex at arrival gets the statusEffectOnHit instead")

## A multi-turret Defensive building (Wood Tower) fires one independent shot
## per turret per volley -- with a ballistic projectileSpeed, that means one
## independent ProjectileInstance per turret, not one for the whole building.
## No building is in this slice's pilot, so this uses a synthetic tower def
## (projectileSpeed added to the top-level defensiveStats block, which
## BuildingStats.defensive_stats forwards to every material variant
## unmodified per its own "traits truly invariant across materials" doc note)
## rather than touching real building data.
func _test_multi_turret_building_fires_independent_projectiles() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_building_defs: Dictionary = _building_defs.duplicate(true)
	synthetic_building_defs["tower"] = _building_defs["tower"].duplicate(true)
	synthetic_building_defs["tower"]["defensiveStats"] = {"detector": true, "detectionRange": 3, "projectileSpeed": 6}

	var tower := BuildingInstance.new("wood_tower", "", "tower", 3, "wood", HexCoord.new(0, 0), "p2")
	tower.init_hp(synthetic_building_defs["tower"], synthetic_building_defs)
	_check(tower.turret_progress.size() == 3, "a level-3 Wood Tower still has 3 independent turret accumulators with the synthetic def")

	# Engineer (canTarget []) rather than a real attacker, so these are purely
	# passive punching bags -- otherwise, now that every combat troop carries
	# a projectileSpeed, a real attacker in range would fire back and add its
	# own projectile(s) to the same array, confounding the exact-3-projectiles
	# assertion below.
	var enemies: Array[SquadInstance] = [
		_make_squad("p1", "engineer", HexCoord.new(1, 0), 1, troops, 5.0),
		_make_squad("p1", "engineer", HexCoord.new(2, 0), 1, troops, 5.0),
		_make_squad("p1", "engineer", HexCoord.new(3, 0), 1, troops, 5.0),
	]
	var standalone: Array[BuildingInstance] = [tower]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, enemies, [], troops, grid, _troop_defs, synthetic_building_defs, {}, {}, standalone, [], {}, projectiles, Callable(self, "_next_projectile_id"))

	_check(enemies.size() == 3, "no squad dies the tick the shots are fired -- ballistic turret damage is deferred")
	_check(projectiles.size() == 3, "a level-3 Wood Tower's 3 turrets each spawn their own independent projectile in one tick")

	var aimed_at: Dictionary = {}
	for p in projectiles:
		aimed_at[p.aim_hex.q] = true
	_check(aimed_at.size() == 3, "the 3 turret projectiles are aimed at 3 different enemies (spread across targets, not focus-fired)")

## --- traveling beam (lineAttack + projectileSpeed, e.g. Wind Spire) --------

## A synthetic lineAttack def carrying projectileSpeed too, deterministic
## (chance omitted -> 100 per StatusEffectSystem.apply_on_hit) freeze so the
## status-effect tests below don't depend on frost_tank's real 25% roll.
func _beam_def() -> Dictionary:
	var synthetic_def: Dictionary = _troop_defs["frost_tank"].duplicate(true)
	synthetic_def["lineAttack"] = true
	synthetic_def["range"] = 6
	synthetic_def["projectileSpeed"] = 2.0
	synthetic_def["splashRadius"] = 0
	synthetic_def["statusEffectOnHit"] = {"type": "freeze", "duration": 2}
	return synthetic_def

## Firing a lineAttack unit that ALSO carries projectileSpeed spawns a
## traveling beam ProjectileInstance (beam_hexes populated to the full
## `range`) instead of resolving the whole line instantly -- the Wind Spire
## case, distinct from Tank Obliterator's instant beam (no projectileSpeed).
func _test_beam_fire_spawns_traveling_projectile_not_instant_damage() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_def := _beam_def()
	var synthetic_troop_defs: Dictionary = {"frost_tank": synthetic_def, "engineer": _troop_defs["engineer"]}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var target_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, synthetic_troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))
	_check(troops[target.member_ids[0]].current_hp == target_hp, "a traveling beam deals no damage the tick it's fired")
	_check(projectiles.size() == 1, "firing a lineAttack+projectileSpeed unit spawns exactly one ProjectileInstance")
	_check(projectiles[0].beam_hexes.size() == int(synthetic_def["range"]), "the beam projectile's beam_hexes is populated out to the full range, same as the instant path's _beam_hexes")

## The gust sweeps outward in order: a nearer squad is hit (and takes its
## statusEffectOnHit) before a farther one on the same beam even gets there,
## proving this isn't a single fixed-delay impact like a point projectile.
func _test_beam_hits_nearer_hex_before_farther_hex() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_def := _beam_def()
	var synthetic_troop_defs: Dictionary = {"frost_tank": synthetic_def, "engineer": _troop_defs["engineer"]}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var near := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops) # distance 2
	var far := _make_squad("p2", "engineer", HexCoord.new(4, 0), 1, troops) # distance 4
	var near_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var beam_damage: float = float(synthetic_def.get("damage", 0.0))
	var squads: Array[SquadInstance] = [attacker, near, far]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, synthetic_troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	var speed: float = float(synthetic_def["projectileSpeed"])
	var near_arrival := 2.0 / speed
	var far_arrival := 4.0 / speed

	ProjectileSystem.resolve_tick(near_arrival + 0.01, projectiles, squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	_check(troops[near.member_ids[0]].current_hp == near_hp - beam_damage, "the nearer squad is damaged once the gust reaches its hex")
	_check(troops[far.member_ids[0]].current_hp == near_hp, "the farther squad is untouched -- the gust hasn't reached it yet")
	_check(projectiles.size() == 1, "the beam projectile is still traveling after only its nearer hex resolves")

	ProjectileSystem.resolve_tick(far_arrival - near_arrival, projectiles, squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	_check(troops[far.member_ids[0]].current_hp == near_hp - beam_damage, "the farther squad is damaged once the gust finally reaches its hex")
	_check(projectiles.size() == 1, "the beam projectile is still in flight -- it keeps traveling out to the full range even past its last actual victim")

	var full_length: float = float(synthetic_def["range"])
	ProjectileSystem.resolve_tick(full_length / speed - far_arrival + 0.01, projectiles, squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	_check(projectiles.is_empty(), "the beam projectile is removed once it finishes traversing its full length")

## The whole point of the "whole line gets knocked back" design: a traveling
## beam's statusEffectOnHit rolls independently for EVERY victim it damages
## as it sweeps past them, not just one privileged "primary" target.
func _test_beam_status_effect_applies_independently_per_victim() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_def := _beam_def()
	var synthetic_troop_defs: Dictionary = {"frost_tank": synthetic_def, "engineer": _troop_defs["engineer"]}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var near := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops)
	var far := _make_squad("p2", "engineer", HexCoord.new(4, 0), 1, troops)
	var squads: Array[SquadInstance] = [attacker, near, far]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, synthetic_troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	var speed: float = float(synthetic_def["projectileSpeed"])
	ProjectileSystem.resolve_tick(4.0 / speed + 0.01, projectiles, squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	_check(near.lockout_remaining > 0.0, "the nearer squad, hit first, is frozen")
	_check(far.lockout_remaining > 0.0, "the farther squad, hit later by the same beam, is ALSO frozen -- not just the first victim")

## A building on the beam's path (friend or foe -- a physical obstruction)
## stops a traveling gust dead in its tracks exactly like it stops an instant
## beam: nothing behind it is ever resolved, even once the beam's full travel
## time has elapsed.
func _test_beam_stops_at_blocking_building() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_def := _beam_def()
	var synthetic_troop_defs: Dictionary = {"frost_tank": synthetic_def, "engineer": _troop_defs["engineer"]}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var base := _p2_base_with("farm", HexCoord.new(2, 0)) # distance 2, blocks the beam
	var farm: BuildingInstance = base.buildings[0]
	var farm_hp := farm.current_hp
	var beam_damage: float = float(synthetic_def.get("damage", 0.0))
	var beyond := _make_squad("p2", "engineer", HexCoord.new(4, 0), 1, troops) # distance 4, behind the building
	var beyond_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var squads: Array[SquadInstance] = [attacker, beyond]
	var bases: Array[BaseInstance] = [base]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, bases, troops, grid, synthetic_troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	var speed: float = float(synthetic_def["projectileSpeed"])
	ProjectileSystem.resolve_tick(4.0 / speed + 0.01, projectiles, squads, bases, troops, grid, synthetic_troop_defs, _building_defs)
	_check(farm.current_hp == farm_hp - beam_damage, "the building on the beam's path takes the hit as its terminal target")
	_check(troops[beyond.member_ids[0]].current_hp == beyond_hp, "a squad beyond the blocking building is never reached, even after the beam's full travel time elapses")
	_check(projectiles.is_empty(), "the beam projectile is removed once blocked, not left in flight forever")

## Same "ground truth at arrival" dodge rule a point projectile already
## follows, just re-checked per hex instead of once total: a target that
## relocates off its beam hex before the gust physically reaches it takes no
## damage, even though it was standing there at the moment the shot fired.
func _test_beam_target_dodges_by_moving_off_its_hex_before_arrival() -> void:
	var grid := HexGrid.new()
	var troops: Dictionary = {}
	var synthetic_def := _beam_def()
	var synthetic_troop_defs: Dictionary = {"frost_tank": synthetic_def, "engineer": _troop_defs["engineer"]}
	var attacker := _make_squad("p1", "frost_tank", HexCoord.new(0, 0), 1, troops)
	var target := _make_squad("p2", "engineer", HexCoord.new(2, 0), 1, troops) # distance 2
	var target_hp: float = float(_troop_defs["engineer"].get("hp", 0.0))
	var squads: Array[SquadInstance] = [attacker, target]
	var projectiles: Array[ProjectileInstance] = []
	CombatResolver.resolve_tick(1.0, squads, [], troops, grid, synthetic_troop_defs, _building_defs, {}, {}, [], [], {}, projectiles, Callable(self, "_next_projectile_id"))

	target.current_hex = HexCoord.new(9, 0) # relocates off its beam hex before the gust arrives

	var speed: float = float(synthetic_def["projectileSpeed"])
	ProjectileSystem.resolve_tick(2.0 / speed + 0.01, projectiles, squads, [], troops, grid, synthetic_troop_defs, _building_defs)
	_check(troops[target.member_ids[0]].current_hp == target_hp, "a target that moved off its beam hex before the gust arrived takes no damage")
	_check(target.lockout_remaining == 0.0, "a dodged victim also gets no statusEffectOnHit")
