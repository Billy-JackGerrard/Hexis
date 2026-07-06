## Headless assertion suite for the vision/fog-of-war slice
## (sim/hex/terrain_types.gd's vision_bonus, sim/instances/building_stats.gd's
## vision_range/global_vision_bonus, sim/vision/*.gd). Run with:
##   godot --headless --script res://tests/test_vision.gd
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

	print("Terrain.vision_bonus")
	_test_terrain_vision_bonus()
	print("BuildingStats vision helpers")
	_test_building_stats_vision()
	print("VisionSystem")
	_test_vision_system()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers -------------------------------------------------------------

func _disc_grid(radius: int, terrain: Terrain.Type) -> HexGrid:
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), radius):
		grid.set_terrain(coord, terrain)
	return grid

func _make_squad(owner: String, troop_type: String, hex: HexCoord) -> SquadInstance:
	_next_id += 1
	var squad := SquadInstance.new("sq%d" % _next_id, owner, troop_type, hex)
	squad.add_member("tr%d" % _next_id)
	return squad

func _base_with(owner: String, building_type: String, level: int, hex: HexCoord) -> BaseInstance:
	var base := BaseInstance.new("base_%s" % owner, "capital", owner, 1, HexCoord.new(0, 0))
	var building := BuildingInstance.new("bld_%s" % building_type, "base_%s" % owner, building_type, level, "", hex)
	base.buildings.append(building)
	return base

## Hex-disc size formula (3n(n+1)+1) for a full, untruncated radius-n reveal.
func _disc_size(radius: int) -> int:
	return 3 * radius * (radius + 1) + 1

## --- Terrain.vision_bonus --------------------------------------------------

func _test_terrain_vision_bonus() -> void:
	_check(Terrain.vision_bonus(Terrain.Type.PLAINS) == Terrain.PLAINS_VISION_BONUS, "Plains grants the vision bonus")
	_check(Terrain.vision_bonus(Terrain.Type.FOREST) == 0.0, "Forest grants no vision bonus")
	_check(Terrain.vision_bonus(Terrain.Type.HILLS) == 0.0, "Hills grants no vision bonus")
	_check(Terrain.vision_bonus(Terrain.Type.RIVER) == 0.0, "River grants no vision bonus")
	_check(Terrain.vision_bonus(Terrain.Type.OCEAN) == 0.0, "Ocean grants no vision bonus")

## --- BuildingStats.vision_range / global_vision_bonus ----------------------

func _test_building_stats_vision() -> void:
	# Turret: flat defensiveStats.visionRange, no growth with level.
	_check(BuildingStats.vision_range(_building_defs["turret"], 1, "", _building_defs) == 7.0, "Turret visionRange is 7 at level 1")
	_check(BuildingStats.vision_range(_building_defs["turret"], 5, "", _building_defs) == 7.0, "Turret visionRange doesn't grow with level (no growth entry, matches CombatResolver's existing un-leveled defensiveStats reads)")

	# Tower: per-material, materialStats.baseStats.visionRange (growth is 0 in data today, still exercises the lookup path).
	_check(BuildingStats.vision_range(_building_defs["tower"], 1, "stone", _building_defs) == 12.0, "Tower (stone) visionRange is 12")
	_check(BuildingStats.vision_range(_building_defs["tower"], 1, "wood", _building_defs) == 12.0, "Tower (wood) visionRange is 12")

	# Radar Array: nonProductionUpgrade.baseStats.visionRange, grows +1 flat/level.
	_check(BuildingStats.vision_range(_building_defs["radar_array"], 1, "", _building_defs) == 8.0, "Radar Array visionRange is 8 at level 1")
	_check(BuildingStats.vision_range(_building_defs["radar_array"], 2, "", _building_defs) == 9.0, "Radar Array visionRange grows to 9 at level 2 (+1 flat/level)")

	# Farm: no visionRange anywhere -> 0.0.
	_check(BuildingStats.vision_range(_building_defs["farm"], 1, "", _building_defs) == 0.0, "Farm has no visionRange -> 0.0")

	# global_vision_bonus: only Radar Array has it, +0.5 flat/level.
	_check(BuildingStats.global_vision_bonus(_building_defs["radar_array"], 1, _building_defs) == 3.0, "Radar Array globalVisionRangeBonus is 3 at level 1")
	_check(BuildingStats.global_vision_bonus(_building_defs["radar_array"], 3, _building_defs) == 4.0, "Radar Array globalVisionRangeBonus grows to 4 at level 3 (+0.5 flat/level)")
	_check(BuildingStats.global_vision_bonus(_building_defs["turret"], 1, _building_defs) == 0.0, "Turret has no globalVisionRangeBonus -> 0.0")

## --- VisionSystem -----------------------------------------------------------

func _test_vision_system() -> void:
	# 1. Edge-of-map truncation: rifleman (visionRange 8) on Plains (+2) = radius
	# 10, but the grid only has a radius-4 disc -> visible is capped to the
	# grid's own extent, not the raw vision radius.
	var small_grid := _disc_grid(4, Terrain.Type.PLAINS)
	var s1 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var visions1: Dictionary = {}
	VisionSystem.resolve_tick([s1], [], small_grid, _troop_defs, _building_defs, visions1)
	var pv1: PlayerVision = VisionSystem.vision_for(visions1, "p1")
	_check(pv1.visible_hexes.size() == _disc_size(4), "visible set is truncated to the grid's radius-4 extent, not the full radius-10 vision")
	_check(pv1.is_visible(HexCoord.new(4, 0)), "the farthest on-grid hex (distance 4) is visible")
	_check(not pv1.is_visible(HexCoord.new(5, 0)), "a hex at distance 5 (off-grid, even though within raw vision radius 10) is not visible")

	# 2. Plains vs. Hills: same troop, same radius grid (big enough not to
	# truncate either), different terrain under the squad -> different reveal.
	var plains_grid := _disc_grid(15, Terrain.Type.PLAINS)
	var hills_grid := _disc_grid(15, Terrain.Type.HILLS)
	var s2_plains := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var s2_hills := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var visions2p: Dictionary = {}
	var visions2h: Dictionary = {}
	VisionSystem.resolve_tick([s2_plains], [], plains_grid, _troop_defs, _building_defs, visions2p)
	VisionSystem.resolve_tick([s2_hills], [], hills_grid, _troop_defs, _building_defs, visions2h)
	_check(VisionSystem.vision_for(visions2p, "p1").visible_hexes.size() == _disc_size(10), "on Plains: visionRange 8 + Plains bonus 2 = radius-10 reveal")
	_check(VisionSystem.vision_for(visions2h, "p1").visible_hexes.size() == _disc_size(8), "on Hills: visionRange 8 + no bonus = radius-8 reveal")

	# 3. A base building (Turret) contributes vision with no squads present.
	var turret_grid := _disc_grid(12, Terrain.Type.PLAINS)
	var turret_base := _base_with("p1", "turret", 1, HexCoord.new(0, 0))
	var no_squads: Array[SquadInstance] = []
	var visions3: Dictionary = {}
	VisionSystem.resolve_tick(no_squads, [turret_base], turret_grid, _troop_defs, _building_defs, visions3)
	_check(VisionSystem.vision_for(visions3, "p1").visible_hexes.size() == _disc_size(9), "Turret (visionRange 7 + Plains bonus 2) reveals a radius-9 disc with no squads involved")

	# 4. Radar Array's globalVisionRangeBonus extends a squad far from the
	# Radar Array itself (map-wide, not local), and two owners stay
	# independent — p2 has the same squad at the same hex but no Radar Array.
	var big_grid := _disc_grid(40, Terrain.Type.PLAINS)
	var radar_base := _base_with("p1", "radar_array", 1, HexCoord.new(0, 0))
	var p1_squad := _make_squad("p1", "rifleman", HexCoord.new(25, 0))
	var p2_squad := _make_squad("p2", "rifleman", HexCoord.new(25, 0))
	var visions4: Dictionary = {}
	VisionSystem.resolve_tick([p1_squad, p2_squad], [radar_base], big_grid, _troop_defs, _building_defs, visions4)
	var pv1_far := VisionSystem.vision_for(visions4, "p1")
	var pv2_far := VisionSystem.vision_for(visions4, "p2")
	# p1: visionRange 8 + Plains 2 + globalVisionRangeBonus 3 = radius 13.
	_check(pv1_far.is_visible(HexCoord.new(38, 0)), "p1's squad (with the Radar Array's global bonus) sees out to distance 13, far from the Radar Array itself")
	_check(not pv1_far.is_visible(HexCoord.new(39, 0)), "p1's squad does not see past its radius-13 reveal")
	# p2: visionRange 8 + Plains 2, no global bonus = radius 10.
	_check(pv2_far.is_visible(HexCoord.new(35, 0)), "p2's squad (no Radar Array) sees out to its own radius-10")
	_check(not pv2_far.is_visible(HexCoord.new(36, 0)), "p2's squad does not get p1's global vision bonus")
	_check(not pv2_far.is_visible(HexCoord.new(38, 0)), "p1's extended vision does not leak into p2's PlayerVision")

	# 5. Explored persists after a squad moves away; visible only reflects the
	# current tick.
	var move_grid := _disc_grid(30, Terrain.Type.PLAINS)
	var s5 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	var visions5: Dictionary = {}
	VisionSystem.resolve_tick([s5], [], move_grid, _troop_defs, _building_defs, visions5)
	var pv5 := VisionSystem.vision_for(visions5, "p1")
	_check(pv5.is_visible(HexCoord.new(0, 0)) and pv5.is_explored(HexCoord.new(0, 0)), "origin starts both visible and explored")
	s5.current_hex = HexCoord.new(20, 0)
	VisionSystem.resolve_tick([s5], [], move_grid, _troop_defs, _building_defs, visions5)
	_check(not pv5.is_visible(HexCoord.new(0, 0)), "origin is no longer visible after the squad moves away")
	_check(pv5.is_explored(HexCoord.new(0, 0)), "origin stays explored (persistent fog-of-war fade) after the squad moves away")
	_check(pv5.is_visible(HexCoord.new(20, 0)), "the squad's new position is now visible")

	# 6. A boarded squad contributes no vision at all — no PlayerVision entry
	# is even created for its owner.
	var boarded_grid := _disc_grid(10, Terrain.Type.PLAINS)
	var s6 := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	s6.boarded_on_squad_id = "carrier1"
	var visions6: Dictionary = {}
	VisionSystem.resolve_tick([s6], [], boarded_grid, _troop_defs, _building_defs, visions6)
	_check(not visions6.has("p1"), "a boarded squad contributes no vision (no PlayerVision created for its owner)")
