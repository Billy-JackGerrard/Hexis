## Headless assertion suite for the detector-coverage slice
## (sim/vision/detection_system.gd, sim/bases/building_stats.gd's
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
	print("CombatTargeting stealth integration (Landmine)")
	_test_landmine_combat_targeting()

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

func _standalone(owner: String, building_type: String, material: String, level: int, hex: HexCoord) -> BuildingInstance:
	return BuildingInstance.new("standalone_%s" % building_type, "", building_type, level, material, hex, owner)

## Hex-disc size formula (3n(n+1)+1) for a full, untruncated radius-n reveal.
func _disc_size(radius: int) -> int:
	return 3 * radius * (radius + 1) + 1

## --- BuildingStats.detector / detection_range / stealth / reveal_range ----

func _test_building_stats_detector() -> void:
	# Tower: defensiveStats.detector/detectionRange, independent of its own
	# (per-material) visionRange.
	var tower_detection_range: float = float(_building_defs["tower"]["defensiveStats"]["detectionRange"])
	_check(BuildingStats.detector(_building_defs["tower"], _building_defs) == true, "Tower is a detector")
	_check(BuildingStats.detection_range(_building_defs["tower"], 1, "stone", _building_defs) == tower_detection_range, "Tower detectionRange (%s) is used, not its (much larger) visionRange" % tower_detection_range)

	# Radar Array: top-level detector: true, no detectionRange -> falls back to
	# vision_range() (base value at level 1, growing with level per its
	# authored statGrowth).
	var radar_vision_base: float = float(_building_defs["radar_array"]["nonProductionUpgrade"]["baseStats"]["visionRange"])
	var radar_vision_growth: float = float(_building_defs["radar_array"]["nonProductionUpgrade"]["statGrowth"]["visionRange"].get("value", 0.0))
	_check(BuildingStats.detector(_building_defs["radar_array"], _building_defs) == true, "Radar Array is a detector")
	_check(BuildingStats.detection_range(_building_defs["radar_array"], 1, "", _building_defs) == radar_vision_base, "Radar Array detectionRange falls back to visionRange (%s) at level 1" % radar_vision_base)
	_check(BuildingStats.detection_range(_building_defs["radar_array"], 2, "", _building_defs) == radar_vision_base + radar_vision_growth, "Radar Array's fallback visionRange grows by %s/level to %s at level 2" % [radar_vision_growth, radar_vision_base + radar_vision_growth])

	# Farm: no detector at all.
	_check(BuildingStats.detector(_building_defs["farm"], _building_defs) == false, "Farm is not a detector")
	_check(BuildingStats.detection_range(_building_defs["farm"], 1, "", _building_defs) == 0.0, "Farm's detection_range falls back to its (zero) visionRange")

	# Landmine: stealthed building, always top-level even though its category
	# is Defensive.
	var landmine_reveal_range: float = float(_building_defs["landmine"]["revealRange"])
	_check(BuildingStats.stealth(_building_defs["landmine"], _building_defs) == true, "Landmine is stealthed")
	_check(BuildingStats.reveal_range(_building_defs["landmine"], _building_defs) == landmine_reveal_range, "Landmine's revealRange (%s) is returned correctly" % landmine_reveal_range)
	_check(BuildingStats.stealth(_building_defs["farm"], _building_defs) == false, "Farm is not stealthed")

## --- DetectionSystem -------------------------------------------------------

func _test_detection_system() -> void:
	# A detector troop (Sniper, no detectionRange -> full visionRange) reveals
	# a disc sized to that visionRange around itself.
	var sniper_vision_range: int = int(_troop_defs["sniper"]["visionRange"])
	var grid := _disc_grid(15, Terrain.Type.PLAINS)
	var sniper := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	var detections1: Dictionary = {}
	DetectionSystem.resolve_tick([sniper], [], [], grid, _troop_defs, _building_defs, detections1)
	_check(DetectionSystem.detected_hexes_for(detections1, "p1").size() == _disc_size(sniper_vision_range), "Sniper detector covers a radius-%d disc (its full visionRange, no detectionRange override)" % sniper_vision_range)

	# A non-detector troop (Rifleman) contributes no detection coverage at all.
	var detections2: Dictionary = {}
	var rifleman := _make_squad("p1", "rifleman", HexCoord.new(0, 0))
	DetectionSystem.resolve_tick([rifleman], [], [], grid, _troop_defs, _building_defs, detections2)
	_check(detections2.is_empty(), "a non-detector troop contributes no detection coverage")

	# Tower (base-attached is out of scope for this slice, but detectionRange
	# resolution itself is exercised via BuildingStats above) — here, Radar
	# Array as a base-attached detector building covers its own (small, fixed)
	# detectionRange fallback radius.
	var radar_vision_base: int = int(_building_defs["radar_array"]["nonProductionUpgrade"]["baseStats"]["visionRange"])
	var radar_base := _base_with("p1", "radar_array", 1, HexCoord.new(0, 0))
	var detections3: Dictionary = {}
	DetectionSystem.resolve_tick([], [radar_base], [], grid, _troop_defs, _building_defs, detections3)
	_check(DetectionSystem.detected_hexes_for(detections3, "p1").size() == _disc_size(radar_vision_base), "Radar Array (base-attached) covers a radius-%d disc (its visionRange fallback) with no squads involved" % radar_vision_base)

	# Two owners stay independent: p2's detector coverage never appears under
	# p1's key.
	var detections4: Dictionary = {}
	var p1_sniper := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	var p2_sniper := _make_squad("p2", "sniper", HexCoord.new(0, 0))
	DetectionSystem.resolve_tick([p1_sniper, p2_sniper], [], [], grid, _troop_defs, _building_defs, detections4)
	_check(DetectionSystem.detected_hexes_for(detections4, "p1").size() == _disc_size(sniper_vision_range), "p1's Sniper coverage is present under p1's key")
	_check(DetectionSystem.detected_hexes_for(detections4, "p2").size() == _disc_size(sniper_vision_range), "p2's Sniper coverage is present under p2's key")

	# A boarded squad contributes no detection coverage (no independent
	# position while carried), mirroring VisionSystem's treatment.
	var detections5: Dictionary = {}
	var boarded := _make_squad("p1", "sniper", HexCoord.new(0, 0))
	boarded.boarded_on_squad_id = "carrier1"
	DetectionSystem.resolve_tick([boarded], [], [], grid, _troop_defs, _building_defs, detections5)
	_check(detections5.is_empty(), "a boarded detector squad contributes no detection coverage")

	# A standalone Tower (no owning base) contributes detector coverage keyed
	# by its own owner_id — this is the Tower detector/detectionRange wiring
	# the build-order item calls out. Its detectionRange is much smaller than
	# its own visionRange, and must not leak into another owner.
	var tower_detection_range: int = int(_building_defs["tower"]["defensiveStats"]["detectionRange"])
	var detections6: Dictionary = {}
	var standalone_tower := _standalone("p3", "tower", "stone", 1, HexCoord.new(0, 0))
	var standalone_buildings: Array[BuildingInstance] = [standalone_tower]
	DetectionSystem.resolve_tick([], [], standalone_buildings, grid, _troop_defs, _building_defs, detections6)
	_check(DetectionSystem.detected_hexes_for(detections6, "p3").size() == _disc_size(tower_detection_range), "standalone Tower's detector coverage is a radius-%d disc (its detectionRange, not its much larger visionRange), keyed by its own owner_id" % tower_detection_range)
	_check(DetectionSystem.detected_hexes_for(detections6, "p1").is_empty(), "standalone Tower's coverage does not leak into an unrelated owner's key")

## --- CombatTargeting stealth integration (Landmine) -------------------------

## Building-side stealth (Landmine's own stealth/revealRange, previously
## deferred as "not wired up anywhere") turns out to already be consumed
## generically by CombatTarget.for_building()'s is_hidden/reveal_range fields
## (shared with squad-side stealth) and CombatTargeting.candidates(), which
## gates on target.is_hidden regardless of Kind — so this is an integration
## check confirming it actually works end-to-end for a building target, not
## new plumbing.
func _test_landmine_combat_targeting() -> void:
	var grid := _disc_grid(5, Terrain.Type.PLAINS)
	var landmine := _standalone("p2", "landmine", "", 1, HexCoord.new(0, 0))
	landmine.init_hp(_building_defs["landmine"], _building_defs)
	var target := CombatTarget.for_building(landmine, _building_defs["landmine"], _building_defs, grid)
	target.owner_id = landmine.owner_id
	var targets: Array[CombatTarget] = [target]
	var rifleman_def: Dictionary = _troop_defs["rifleman"]
	var landmine_reveal_range: float = float(_building_defs["landmine"]["revealRange"])

	_check(target.is_hidden, "a Landmine CombatTarget is hidden by default")
	_check(target.reveal_range == landmine_reveal_range, "a Landmine CombatTarget's reveal_range matches its authored revealRange (%s)" % landmine_reveal_range)

	# Beyond revealRange, with no detector coverage: invisible to targeting.
	var far_candidates := CombatTargeting.candidates(HexCoord.new(3, 0), "p1", 10, rifleman_def, targets)
	_check(far_candidates.is_empty(), "an attacker beyond the Landmine's revealRange, with no detector coverage, cannot target it")

	# Within revealRange: visible without needing a detector.
	var near_candidates := CombatTargeting.candidates(HexCoord.new(1, 0), "p1", 10, rifleman_def, targets)
	_check(near_candidates.size() == 1, "an attacker within the Landmine's revealRange (%s) can target it, no detector needed" % landmine_reveal_range)

	# Beyond revealRange, but the attacker's owner has detector coverage on
	# the Landmine's hex: visible.
	var detections: Dictionary = {"p1": {HexCoord.new(0, 0).to_key(): true}}
	var detected_candidates := CombatTargeting.candidates(HexCoord.new(3, 0), "p1", 10, rifleman_def, targets, detections)
	_check(detected_candidates.size() == 1, "an attacker beyond revealRange but with detector coverage on the Landmine's hex can target it")
