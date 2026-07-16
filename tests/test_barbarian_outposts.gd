## Headless assertion suite for sim/outposts/*. Run with:
##   godot --headless --script res://tests/test_barbarian_outposts.gd
extends SceneTree

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	print("Loot system withholds until both tower and garrison are dead")
	_test_loot_waits_on_both()
	print("Loot system pays out once, attributed to the tower's actual killer")
	_test_loot_pays_correct_owner()
	print("CombatResolver._prune_dead marks tower_destroyed/tower_killer")
	_test_prune_dead_marks_outpost()
	print("BarbarianOutpostInstance.to_dict()/from_dict() round-trip")
	_test_instance_round_trip()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _make_squad(id: String, owner_id: String) -> SquadInstance:
	var squad := SquadInstance.new(id, owner_id, "rifleman", HexCoord.new(0, 0))
	squad.member_ids.append(id + "_troop")
	return squad

func _pool_for_callable(pools: Dictionary) -> Callable:
	return func(owner_id: String) -> ResourcePool:
		if not pools.has(owner_id):
			pools[owner_id] = ResourcePool.new()
		return pools[owner_id]

func _test_loot_waits_on_both() -> void:
	var outpost := BarbarianOutpostInstance.new("outpost_1", "tower_1", ["guard_1"], {"stone": 100.0})
	var outposts: Array[BarbarianOutpostInstance] = [outpost]
	var squads: Array[SquadInstance] = [_make_squad("guard_1", "neutral")]
	var pools: Dictionary = {}
	var pool_for := _pool_for_callable(pools)

	# Neither tower nor garrison dead yet.
	BarbarianOutpostLootSystem.resolve_tick(outposts, squads, pool_for)
	_check(outposts.size() == 1, "outpost record persists while the tower is alive")

	# Tower destroyed, garrison still alive: withhold.
	outpost.tower_destroyed = true
	outpost.tower_killer = "p0"
	BarbarianOutpostLootSystem.resolve_tick(outposts, squads, pool_for)
	_check(outposts.size() == 1, "outpost record persists while the garrison is still alive")
	_check(not pools.has("p0"), "no loot granted while the garrison is still alive")

	# Garrison cleared too: pays out, exactly once.
	squads.clear()
	BarbarianOutpostLootSystem.resolve_tick(outposts, squads, pool_for)
	_check(outposts.is_empty(), "outpost record removed once both tower and garrison are dead")
	var expected_stone := ResourceType.STARTING[ResourceType.Type.STONE] + 100.0
	_check(pools.has("p0") and pools["p0"].get_amount(ResourceType.Type.STONE) == expected_stone, "loot granted to the tower's killer")

	# A second tick after removal must not double-pay (the record is gone).
	BarbarianOutpostLootSystem.resolve_tick(outposts, squads, pool_for)
	_check(pools["p0"].get_amount(ResourceType.Type.STONE) == expected_stone, "loot is not granted twice on a later tick")

func _test_loot_pays_correct_owner() -> void:
	# Garrison dies first, tower dies later — order shouldn't matter, and the
	# payout must go to whoever actually killed the tower, not the garrison's
	# own (neutral) owner.
	var outpost := BarbarianOutpostInstance.new("outpost_2", "tower_2", ["guard_2"], {"wood": 50.0})
	var outposts: Array[BarbarianOutpostInstance] = [outpost]
	var squads: Array[SquadInstance] = [_make_squad("guard_2", "neutral")]
	var pools: Dictionary = {}
	var pool_for := _pool_for_callable(pools)

	squads.clear()
	BarbarianOutpostLootSystem.resolve_tick(outposts, squads, pool_for)
	_check(outposts.size() == 1, "outpost record persists: garrison dead but tower still standing")

	outpost.tower_destroyed = true
	outpost.tower_killer = "p1"
	BarbarianOutpostLootSystem.resolve_tick(outposts, squads, pool_for)
	_check(outposts.is_empty(), "outpost record removed once the tower dies too")
	var expected_wood := ResourceType.STARTING[ResourceType.Type.WOOD] + 50.0
	_check(pools.has("p1") and pools["p1"].get_amount(ResourceType.Type.WOOD) == expected_wood, "loot granted to p1, the tower's actual killer")
	_check(not pools.has("neutral"), "the garrison's own owner_id (neutral) never receives loot")

func _test_prune_dead_marks_outpost() -> void:
	var building := BuildingInstance.new("tower_3", "", "tower", 1, "stone", HexCoord.new(5, 5), BaseSiteSelector.NEUTRAL_OWNER_ID)
	building.max_hp = 100.0
	building.current_hp = 0.0
	building.last_damaged_by = "p0"
	var standalone_buildings: Array[BuildingInstance] = [building]

	var outpost := BarbarianOutpostInstance.new("outpost_3", "tower_3", [], {})
	var barbarian_outposts: Array[BarbarianOutpostInstance] = [outpost]

	var squads: Array[SquadInstance] = []
	var bases: Array[BaseInstance] = []
	var troops_by_id: Dictionary = {}
	var grid := HexGrid.new()

	CombatResolver._prune_dead(squads, bases, troops_by_id, grid, standalone_buildings, [], {}, barbarian_outposts)

	_check(standalone_buildings.is_empty(), "the destroyed tower is removed from standalone_buildings")
	_check(outpost.tower_destroyed, "the outpost's tower_destroyed flag is set")
	_check(outpost.tower_killer == "p0", "the outpost's tower_killer captures last_damaged_by before the building is removed")

## Not otherwise exercised: tests/test_determinism.gd's MatchState round-trip
## scenario is hand-built without any outposts, so MatchState.to_dict()'s
## "barbarian_outposts" key only ever round-trips an empty array there. This
## covers BarbarianOutpostInstance.to_dict()/from_dict() directly, including
## after tower_destroyed/tower_killer have been set mid-match.
func _test_instance_round_trip() -> void:
	var outpost := BarbarianOutpostInstance.new("outpost_4", "tower_4", ["guard_a", "guard_b"], {"steel": 200.0, "stone": 100.0})
	outpost.tower_destroyed = true
	outpost.tower_killer = "p2"

	var restored := BarbarianOutpostInstance.from_dict(outpost.to_dict())

	_check(restored.id == outpost.id, "id round-trips")
	_check(restored.building_id == outpost.building_id, "building_id round-trips")
	_check(restored.guard_squad_ids == outpost.guard_squad_ids, "guard_squad_ids round-trips")
	_check(restored.loot == outpost.loot, "loot round-trips")
	_check(restored.tower_destroyed == outpost.tower_destroyed, "tower_destroyed round-trips")
	_check(restored.tower_killer == outpost.tower_killer, "tower_killer round-trips")
