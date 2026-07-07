## Headless assertion suite for Wall line-of-sight: HexCoord.line() (hex-line
## raycast), HexGrid.is_line_blocked(), and CombatTargeting's consumption of
## it, per 01-map-and-terrain.md ("an attack whose line from attacker-hex to
## target-hex crosses a walled edge is blocked"). Run with:
##   godot --headless --script res://tests/test_line_of_sight.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")
	_building_defs = DataLoader.load_dir("res://data/buildings")

	print("HexCoord.line()")
	_test_hex_line()
	print("HexGrid.is_line_blocked()")
	_test_line_blocked()
	print("CombatTargeting Wall LOS gating")
	_test_targeting_los()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _flat_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), radius):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	return grid

func _test_hex_line() -> void:
	var a := HexCoord.new(0, 0)
	var b := HexCoord.new(0, 0)
	var same := HexCoord.line(a, b)
	_check(same.size() == 1 and same[0].equals(a), "line(a, a) is just [a]")

	var c := HexCoord.new(3, 0)
	var line := HexCoord.line(a, c)
	_check(line.size() == HexCoord.distance(a, c) + 1, "line length is distance + 1")
	_check(line[0].equals(a), "line starts at a")
	_check(line[line.size() - 1].equals(c), "line ends at b")

	# A straight run along a single fixed neighbor direction should step
	# through every intermediate hex on that same line, one per hex.
	var expected := [HexCoord.new(0, 0), HexCoord.new(1, 0), HexCoord.new(2, 0), HexCoord.new(3, 0)]
	var all_match := true
	for i in range(expected.size()):
		if not line[i].equals(expected[i]):
			all_match = false
	_check(all_match, "straight-direction line visits each intermediate hex in order")

	# General invariant across several distances/directions: every consecutive
	# pair in the line must be actual hex neighbors (distance exactly 1) —
	# the line never "jumps".
	var no_jumps := true
	var pairs := [
		[HexCoord.new(0, 0), HexCoord.new(4, -2)],
		[HexCoord.new(-2, 3), HexCoord.new(2, -1)],
		[HexCoord.new(0, 0), HexCoord.new(-3, -1)],
		[HexCoord.new(1, 1), HexCoord.new(1, -4)],
	]
	for pair in pairs:
		var hexes := HexCoord.line(pair[0], pair[1])
		for i in range(hexes.size() - 1):
			if HexCoord.distance(hexes[i], hexes[i + 1]) != 1:
				no_jumps = false
	_check(no_jumps, "every consecutive pair along any line is a true neighbor step")

func _test_line_blocked() -> void:
	var grid := _flat_grid(5)
	var a := HexCoord.new(0, 0)
	var b := HexCoord.new(3, 0)
	_check(not grid.is_line_blocked(a, b), "no wall anywhere -> not blocked")

	# Wall a wholly unrelated edge far from the line.
	grid.set_wall(HexCoord.new(-3, 0), HexCoord.new(-3, 1), true)
	_check(not grid.is_line_blocked(a, b), "an unrelated wall doesn't block this line")

	# Wall the edge between two of the line's own intermediate hexes.
	grid.set_wall(HexCoord.new(1, 0), HexCoord.new(2, 0), true)
	_check(grid.is_line_blocked(a, b), "a wall crossing the line's own path blocks it")

	grid.set_wall(HexCoord.new(1, 0), HexCoord.new(2, 0), false)
	_check(not grid.is_line_blocked(a, b), "removing that wall reopens line of sight")

func _make_troop_squad(id: String, owner: String, troop_type: String, hex: HexCoord, troops: Dictionary) -> SquadInstance:
	var squad := SquadInstance.new(id, owner, troop_type, hex)
	var hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 100.0))
	var troop := TroopInstance.new(id + "_t", troop_type, owner, id, hp)
	troops[troop.id] = troop
	squad.add_member(troop.id)
	return squad

func _test_targeting_los() -> void:
	var grid := _flat_grid(5)
	var attacker_hex := HexCoord.new(0, 0)
	var target_hex := HexCoord.new(2, 0)
	# Non-Air combat troop; chonky's range (2) exactly covers this distance.
	var attacker_def: Dictionary = _troop_defs["chonky"]
	_check(int(attacker_def.get("range", 0)) >= 2, "chonky's range covers this test's distance (fixture assumption)")

	var troops: Dictionary = {}
	var target_squad := _make_troop_squad("target", "p2", "chonky", target_hex, troops)
	var target := CombatTarget.for_squad(target_squad, _troop_defs["chonky"], troops)
	var targets: Array[CombatTarget] = [target]

	# No wall: target is a legal candidate.
	var candidates := CombatTargeting.candidates(attacker_hex, "p1", int(attacker_def["range"]), attacker_def, targets, {}, grid)
	_check(candidates.size() == 1, "no wall -> target is a valid candidate")

	# Wall crossing the line between attacker and target blocks it.
	grid.set_wall(HexCoord.new(1, 0), HexCoord.new(2, 0), true)
	candidates = CombatTargeting.candidates(attacker_hex, "p1", int(attacker_def["range"]), attacker_def, targets, {}, grid)
	_check(candidates.is_empty(), "a wall crossing the line-of-sight excludes the target")

	# Omitting grid (default null) preserves old no-LOS-check behavior.
	candidates = CombatTargeting.candidates(attacker_hex, "p1", int(attacker_def["range"]), attacker_def, targets, {})
	_check(candidates.size() == 1, "grid defaults to null -> no LOS check, target still a candidate")

	# Air-domain attacker ignores Walls entirely, same as every other terrain
	# rule -- even for a plain (non-Wall) target behind one.
	var air_def: Dictionary = _troop_defs["hot_air_balloon"]
	candidates = CombatTargeting.candidates(attacker_hex, "p1", 10, air_def, targets, {}, grid)
	_check(candidates.size() == 1, "an Air attacker ignores the wall and still sees the target")

	# Attacking the Wall itself is never blocked by its own edge.
	var wall_building := BuildingInstance.new("wall1", "baseX", "wall", 1, "stone")
	wall_building.hex_a = HexCoord.new(1, 0)
	wall_building.hex_b = HexCoord.new(2, 0)
	wall_building.init_hp(_building_defs["wall"], _building_defs)
	var wall_target := CombatTarget.for_building(wall_building, _building_defs["wall"], _building_defs, grid)
	wall_target.owner_id = "p2"
	var wall_targets: Array[CombatTarget] = [wall_target]
	var wall_candidates := CombatTargeting.candidates(attacker_hex, "p1", int(attacker_def["range"]), attacker_def, wall_targets, {}, grid)
	_check(wall_candidates.size() == 1, "attacking the Wall itself is never blocked by its own edge")

	# select_target/select_auto thread grid through correctly end-to-end.
	var attacker_squad := _make_troop_squad("attacker", "p1", "chonky", attacker_hex, troops)
	var chosen := CombatTargeting.select_auto(attacker_hex, "p1", int(attacker_def["range"]), attacker_def, targets, {}, grid)
	_check(chosen == null, "select_auto also respects the LOS block (target still walled off)")

	grid.set_wall(HexCoord.new(1, 0), HexCoord.new(2, 0), false)
	chosen = CombatTargeting.select_auto(attacker_hex, "p1", int(attacker_def["range"]), attacker_def, targets, {}, grid)
	_check(chosen == target, "select_auto sees the target again once the wall is cleared")
