## Headless assertion suite for the status-effect slice (sim/combat/
## status_effect_system.gd, plus its wiring into CombatResolver/
## MovementResolver). Run with:
##   godot --headless --script res://tests/test_status_effects.gd
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

	print("StatusEffectSystem.apply_on_hit")
	_test_apply_on_hit()
	print("StatusEffectSystem.resolve_tick")
	_test_resolve_tick()
	print("Integration: CombatResolver + MovementResolver")
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

func _line_grid(size: int) -> HexGrid:
	var grid := HexGrid.new()
	for i in range(size):
		grid.set_terrain(HexCoord.new(i, 0), Terrain.Type.PLAINS)
	return grid

## --- apply_on_hit ----------------------------------------------------------

func _test_apply_on_hit() -> void:
	var troops := {}

	# freeze: full lockout, no tail.
	var s1 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t1 := CombatTarget.for_squad(s1, _troop_defs["rifleman"], troops)
	StatusEffectSystem.apply_on_hit({"type": "freeze", "duration": 2.0, "chance": 100}, t1, _troop_defs["rifleman"], HexCoord.new(0, 0), null)
	_check(_approx(s1.lockout_remaining, 2.0), "freeze sets lockout_remaining to duration")
	_check(_approx(s1.stun_tail_queued, 0.0), "freeze never queues a stun tail")

	# chance 0 -> never applies.
	var s2 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t2 := CombatTarget.for_squad(s2, _troop_defs["rifleman"], troops)
	StatusEffectSystem.apply_on_hit({"type": "freeze", "duration": 2.0, "chance": 0}, t2, _troop_defs["rifleman"], HexCoord.new(0, 0), null)
	_check(_approx(s2.lockout_remaining, 0.0), "chance 0 -> freeze never applies")

	# stun: full lockout AND queues the tail (armed only once lockout expires).
	var s3 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t3 := CombatTarget.for_squad(s3, _troop_defs["rifleman"], troops)
	StatusEffectSystem.apply_on_hit({"type": "stun", "duration": 1.5, "chance": 100}, t3, _troop_defs["rifleman"], HexCoord.new(0, 0), null)
	_check(_approx(s3.lockout_remaining, 1.5), "stun sets lockout_remaining to duration")
	_check(_approx(s3.stun_tail_queued, 1.5), "stun queues a tail of the same duration")
	_check(_approx(s3.stun_tail_remaining, 0.0), "stun's tail is not active while still locked out")

	# knockback: shoves the target directly away from the attacker.
	var grid4 := _line_grid(6)
	var s4 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t4 := CombatTarget.for_squad(s4, _troop_defs["rifleman"], troops, grid4)
	StatusEffectSystem.apply_on_hit({"type": "knockback", "magnitude": 2, "chance": 100}, t4, _troop_defs["rifleman"], HexCoord.new(0, 0), grid4)
	_check(s4.current_hex.equals(HexCoord.new(5, 0)), "knockback shoves 2 hexes directly away from the attacker")

	# knockback clamps at the grid edge rather than moving off-map.
	var grid5 := _line_grid(4)
	var s5 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t5 := CombatTarget.for_squad(s5, _troop_defs["rifleman"], troops, grid5)
	StatusEffectSystem.apply_on_hit({"type": "knockback", "magnitude": 5, "chance": 100}, t5, _troop_defs["rifleman"], HexCoord.new(0, 0), grid5)
	_check(s5.current_hex.equals(HexCoord.new(3, 0)), "knockback clamps at the grid's edge (hex 3 is the last hex on this 4-hex line)")

	# emp: Land -> movement-only lockout, can still attack.
	var s6 := _make_squad("p2", "basekiller", HexCoord.new(3, 0), 1, troops)
	var t6 := CombatTarget.for_squad(s6, _troop_defs["basekiller"], troops)
	StatusEffectSystem.apply_on_hit({"type": "emp", "duration": 3.0, "chance": 100}, t6, _troop_defs["basekiller"], HexCoord.new(0, 0), null)
	_check(_approx(s6.move_lockout_remaining, 3.0), "emp on a Land unit sets move_lockout_remaining")
	_check(_approx(s6.lockout_remaining, 0.0), "emp on a Land unit does NOT set the full lockout (can still attack)")

	# emp: Air -> instant destroy.
	var s7 := _make_squad("p2", "glider", HexCoord.new(3, 0), 2, troops)
	# glider is empImmune, so use a non-immune Air troop instead.
	var s7b := _make_squad("p2", "wingfighter", HexCoord.new(3, 0), 2, troops)
	var t7b := CombatTarget.for_squad(s7b, _troop_defs["wingfighter"], troops)
	StatusEffectSystem.apply_on_hit({"type": "emp", "duration": 3.0, "chance": 100}, t7b, _troop_defs["wingfighter"], HexCoord.new(0, 0), null)
	_check(not t7b.is_alive(), "emp on a non-empImmune Air unit destroys every member outright")

	# emp: empImmune Air troop (Glider) is unaffected entirely.
	var t7 := CombatTarget.for_squad(s7, _troop_defs["glider"], troops)
	StatusEffectSystem.apply_on_hit({"type": "emp", "duration": 3.0, "chance": 100}, t7, _troop_defs["glider"], HexCoord.new(0, 0), null)
	_check(t7.is_alive(), "empImmune Air troop (Glider) survives an emp hit")
	_check(_approx(s7.move_lockout_remaining, 0.0), "empImmune troop gets no move_lockout_remaining either")

	# emp: Infantry/Naval -> no effect at all.
	var s8 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t8 := CombatTarget.for_squad(s8, _troop_defs["rifleman"], troops)
	StatusEffectSystem.apply_on_hit({"type": "emp", "duration": 3.0, "chance": 100}, t8, _troop_defs["rifleman"], HexCoord.new(0, 0), null)
	_check(_approx(s8.move_lockout_remaining, 0.0), "emp on Infantry has no effect")
	_check(t8.is_alive(), "emp on Infantry does not kill it")

	# empty effect dict (most attacks) -> pure no-op.
	var s9 := _make_squad("p2", "rifleman", HexCoord.new(3, 0), 1, troops)
	var t9 := CombatTarget.for_squad(s9, _troop_defs["rifleman"], troops)
	StatusEffectSystem.apply_on_hit({}, t9, _troop_defs["rifleman"], HexCoord.new(0, 0), null)
	_check(_approx(s9.lockout_remaining, 0.0), "no statusEffectOnHit -> no-op")

## --- resolve_tick -----------------------------------------------------------

func _test_resolve_tick() -> void:
	var troops := {}
	var s := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	s.lockout_remaining = 1.0
	s.stun_tail_queued = 1.0
	s.move_lockout_remaining = 0.5

	StatusEffectSystem.resolve_tick(0.6, [s], [])
	_check(_approx(s.lockout_remaining, 0.4), "lockout_remaining ticks down by dt")
	_check(_approx(s.stun_tail_remaining, 0.0), "tail not armed yet -- lockout hasn't reached 0")
	_check(_approx(s.move_lockout_remaining, 0.0), "move_lockout_remaining floors at 0, doesn't go negative")

	StatusEffectSystem.resolve_tick(0.5, [s], [])
	_check(_approx(s.lockout_remaining, 0.0), "lockout_remaining reaches 0")
	_check(_approx(s.stun_tail_remaining, 0.9), "tail arms the instant lockout crosses to 0, then itself ticks down by the same dt")
	_check(_approx(s.stun_tail_queued, 0.0), "stun_tail_queued is consumed once armed")

	_check(StatusEffectSystem.move_speed_mult(s) == StatusEffectSystem.STUN_TAIL_SPEED_MULT, "move_speed_mult reflects the active tail")
	_check(StatusEffectSystem.attack_speed_mult(s) == StatusEffectSystem.STUN_TAIL_SPEED_MULT, "attack_speed_mult reflects the active tail")

	StatusEffectSystem.resolve_tick(0.9, [s], [])
	_check(_approx(s.stun_tail_remaining, 0.0), "tail expires after its own duration")
	_check(StatusEffectSystem.move_speed_mult(s) == 1.0, "move_speed_mult back to 1.0 once the tail expires")

## --- Integration ------------------------------------------------------------

func _test_integration() -> void:
	var troops := {}
	var grid := _line_grid(6)

	# Cold Turret's freeze (100% chance for this test) locks the attacking
	# squad out of both attacking and moving on its very next tick.
	var base := BaseInstance.new("b1", "capital", "p1", 1, HexCoord.new(5, 0))
	var turret_def: Dictionary = _building_defs["cold_turret"].duplicate(true)
	turret_def["defensiveStats"]["statusEffectOnHit"]["chance"] = 100
	var building_defs := _building_defs.duplicate(true)
	building_defs["cold_turret"] = turret_def
	var turret := BuildingInstance.new("bldg1", "b1", "cold_turret", 1, "", HexCoord.new(4, 0))
	turret.init_hp(turret_def, building_defs)
	base.buildings.append(turret)

	# Attacker starts within Cold Turret's range (4) and has a move order queued.
	var attacker := _make_squad("p2", "rifleman", HexCoord.new(1, 0), 1, troops)
	_check(MovementResolver.issue_move(attacker, grid, HexCoord.new(4, 0), _troop_defs), "attacker has a valid move order queued")

	# attackSpeed 0.8, so dt 2.0 banks 1.6 -- enough for exactly one volley.
	CombatResolver.resolve_tick(2.0, [attacker], [base], troops, grid, _troop_defs, building_defs)
	_check(attacker.lockout_remaining > 0.0, "Cold Turret's freeze locks the attacking squad out")

	var path_before_locked_tick := attacker.path.size()
	MovementResolver.resolve_tick(1.0, [attacker], grid, _troop_defs)
	_check(attacker.current_hex.equals(HexCoord.new(1, 0)), "a locked-out squad does not move")
	_check(attacker.path.size() == path_before_locked_tick, "a locked-out squad's path is untouched")

	CombatResolver.resolve_tick(2.0, [attacker], [base], troops, grid, _troop_defs, building_defs)
	_check(_living_members_count(attacker, troops) == 1, "a locked-out squad survives (frozen, not killed) if the Turret alone doesn't finish it")

func _living_members_count(squad: SquadInstance, troops: Dictionary) -> int:
	var count := 0
	for member_id in squad.member_ids:
		var troop: TroopInstance = troops.get(member_id)
		if troop != null and troop.current_hp > 0.0:
			count += 1
	return count
