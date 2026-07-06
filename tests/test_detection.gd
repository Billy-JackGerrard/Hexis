## Headless assertion suite for the detector-coverage slice
## (sim/vision/detection_system.gd, sim/instances/building_stats.gd's
## detector/detection_range/stealth/reveal_range). Run with:
##   godot --headless --script res://tests/test_detection.gd
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

	print("BuildingStats detector/stealth helpers")
	_test_building_stats_detector()
	print("DetectionSystem")
	_test_detection_system()

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

## --- BuildingStats.detector / detection_range / stealth / reveal_range ----

func _test_building_stats_detector() -> void:
	# Tower: defensiveStats.detector/detectionRange, independent of its own
	# (per-material) 12-tile visionRange.
	_check(BuildingStats.detector(_building_defs["tower"], _building_defs) == true, "Tower is a detector")
	_check(BuildingStats.detection_range(_building_defs["tower"], 1, "stone", _building_defs) == 3.0, "Tower detectionRange is 3, not its 12-tile visionRange")

	# Radar Array: top-level detector: true, no detectionRange -> falls back to
	# vision_range() (8 at level 1, growing +1/level).
	_check(BuildingStats.detector(_building_defs["radar_array"], _building_defs) == true, "Radar Array is a detector")
	_check(BuildingStats.detection_range(_building_defs["radar_array"], 1, "", _building_defs) == 8.0, "Radar Array detectionRange falls back to visionRange (8) at level 1")
	_check(BuildingStats.detection_range(_building_defs["radar_array"], 2, "", _building_defs) == 9.0, "Radar Array's fallback visionRange grows to 9 at level 2")

	# Farm: no detector at all.
	_check(BuildingStats.detector(_building_defs["farm"], _building_defs) == false, "Farm is not a detector")
	_check(BuildingStats.detection_range(_building_defs["farm"], 1, "", _building_defs) == 0.0, "Farm's detection_range falls back to its (zero) visionRange")

	# Landmine: stealthed building, always top-level even though its category
	# is Defensive.
	_check(BuildingStats.stealth(_building_defs["landmine"], _building_defs) == true, "Landmine is stealthed")
	_check(BuildingStats.reveal_range(_building_defs["landmine"], _building_defs) == 1.0, "Landmine's revealRange is 1")
	_check(BuildingStats.stealth(_building_defs["farm"], _building_defs) == false, "Farm is not stealthed")

## --- DetectionSystem -------------------------------------------------------

func _test_detection_system() -> void:
	# A detector troop (Sniper, no detectionRange -> full visionRange 12)
	# reveals a radius-12 disc around itself.
	var grid := _disc_grid(15, Terrain.Type.PLAINS)
	var sniper := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	var detections1: Dictionary = {}
	DetectionSystem.resolve_tick([sniper], [], grid, _troop_defs, _building_defs, detections1)
	_check(DetectionSystem.detected_hexes_for(detections1, "p1").size() == _disc_size(12), "Sniper detector covers a radius-12 disc (its full visionRange, no detectionRange override)")

	# A non-detector troop (Rifleman) contributes no detection coverage at all.
	var detections2: Dictionary = {}
	var rifleman := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	DetectionSystem.resolve_tick([rifleman], [], grid, _troop_defs, _building_defs, detections2)
	_check(detections2.is_empty(), "a non-detector troop contributes no detection coverage")

	# Tower (base-attached is out of scope for this slice, but detectionRange
	# resolution itself is exercised via BuildingStats above) — here, Radar
	# Array as a base-attached detector building covers its own (small, fixed)
	# detectionRange fallback radius.
	var radar_base := _base_with("p1", "radar_array", 1, HexCoord.new(0, 0))
	var detections3: Dictionary = {}
	DetectionSystem.resolve_tick([], [radar_base], grid, _troop_defs, _building_defs, detections3)
	_check(DetectionSystem.detected_hexes_for(detections3, "p1").size() == _disc_size(8), "Radar Array (base-attached) covers a radius-8 disc (its visionRange fallback) with no squads involved")

	# Two owners stay independent: p2's detector coverage never appears under
	# p1's key.
	var detections4: Dictionary = {}
	var p1_sniper := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	var p2_sniper := _make_squad("p2", "sniper", HexCoord.new(0, 0))
	DetectionSystem.resolve_tick([p1_sniper, p2_sniper], [], grid, _troop_defs, _building_defs, detections4)
	_check(DetectionSystem.detected_hexes_for(detections4, "p1").size() == _disc_size(12), "p1's Sniper coverage is present under p1's key")
	_check(DetectionSystem.detected_hexes_for(detections4, "p2").size() == _disc_size(12), "p2's Sniper coverage is present under p2's key")

	# A boarded squad contributes no detection coverage (no independent
	# position while carried), mirroring VisionSystem's treatment.
	var detections5: Dictionary = {}
	var boarded := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	boarded.boarded_on_squad_id = "carrier1"
	DetectionSystem.resolve_tick([boarded], [], grid, _troop_defs, _building_defs, detections5)
	_check(detections5.is_empty(), "a boarded detector squad contributes no detection coverage")
