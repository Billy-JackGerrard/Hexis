## Headless assertion suite for sim/events/match_event.gd and its emission
## points across combat_resolver.gd, upkeep_system.gd, and
## barbarian_outpost_loot_system.gd. Run with:
##   godot --headless --script res://tests/test_match_events.gd
extends SceneTree

var _failures: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	print("Squad wipe emits exactly one SQUAD_LOST, none for a surviving squad")
	_test_squad_lost()
	print("HQ capture emits BASE_CAPTURED + BASE_LOST")
	_test_base_captured_and_lost()
	print("Capturing a neutral Unique base emits only BASE_CAPTURED")
	_test_capture_from_neutral_emits_no_base_lost()
	print("Building ruin emits BUILDING_DESTROYED exactly once, not every tick")
	_test_building_destroyed_idempotent()
	print("A destroyed barbarian tower (neutral-owned) emits no BUILDING_DESTROYED")
	_test_neutral_standalone_emits_no_event()
	print("apply_deficit_deaths emits one aggregate DEFICIT_DEATH per call")
	_test_deficit_death()
	print("BarbarianOutpostLootSystem emits OUTPOST_LOOT when granting loot")
	_test_outpost_loot()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

func _events_of_type(events: Array[MatchEvent], type: MatchEvent.Type) -> Array[MatchEvent]:
	var result: Array[MatchEvent] = []
	for event in events:
		if event.type == type:
			result.append(event)
	return result

func _make_squad(id: String, owner_id: String, troop_type: String, hp: float) -> SquadInstance:
	var squad := SquadInstance.new(id, owner_id, troop_type, HexCoord.new(0, 0))
	return squad

func _test_squad_lost() -> void:
	var squads: Array[SquadInstance] = []
	var troops_by_id: Dictionary = {}

	var dying := _make_squad("squad_dead", "p0", "rifleman", 100.0)
	var dying_troop := TroopInstance.new("troop_dead", "rifleman", "p0", dying.id, 0.0)
	troops_by_id[dying_troop.id] = dying_troop
	dying.add_member(dying_troop.id)
	dying.last_damaged_by = "p1"
	squads.append(dying)

	var surviving := _make_squad("squad_alive", "p0", "rifleman", 100.0)
	var alive_troop := TroopInstance.new("troop_alive", "rifleman", "p0", surviving.id, 50.0)
	troops_by_id[alive_troop.id] = alive_troop
	surviving.add_member(alive_troop.id)
	squads.append(surviving)

	var events: Array[MatchEvent] = []
	CombatResolver._prune_dead(squads, [], troops_by_id, HexGrid.new(), [], [], {}, [], events)

	var lost := _events_of_type(events, MatchEvent.Type.SQUAD_LOST)
	_check(lost.size() == 1, "exactly one SQUAD_LOST event fired (not one for the surviving squad)")
	if lost.size() == 1:
		_check(lost[0].owner_id == "p0", "event's owner_id is the dead squad's own owner")
		_check(lost[0].payload.get("troop_type", "") == "rifleman", "event payload carries the troop_type")
		_check(lost[0].payload.get("killed_by", "") == "p1", "event payload carries the killer's owner_id")
	_check(squads.size() == 1 and squads[0].id == "squad_alive", "only the wiped squad was actually removed")

func _make_hq_base(id: String, owner_id: String, damaged_by: String) -> BaseInstance:
	var base := BaseInstance.new(id, "capital", owner_id, 1, HexCoord.new(1, 1))
	var hq := BuildingInstance.new(id + "_hq", base.id, "hq", 1, "", HexCoord.new(1, 1), "")
	hq.max_hp = 500.0
	hq.current_hp = 0.0
	hq.last_damaged_by = damaged_by
	base.buildings.append(hq)
	return base

func _test_base_captured_and_lost() -> void:
	var base := _make_hq_base("base_1", "p0", "p1")
	var events: Array[MatchEvent] = []
	CombatResolver._prune_dead([], [base], {}, HexGrid.new(), [], [], {}, [], events)

	_check(base.owner_id == "p1", "base ownership actually flipped to the killer")
	var captured := _events_of_type(events, MatchEvent.Type.BASE_CAPTURED)
	var lost := _events_of_type(events, MatchEvent.Type.BASE_LOST)
	_check(captured.size() == 1 and captured[0].owner_id == "p1", "BASE_CAPTURED fires for the new owner")
	_check(lost.size() == 1 and lost[0].owner_id == "p0", "BASE_LOST fires for the previous owner")
	if captured.size() == 1:
		_check(captured[0].payload.get("previous_owner", "") == "p0", "BASE_CAPTURED payload names the previous owner")
	if lost.size() == 1:
		_check(lost[0].payload.get("captured_by", "") == "p1", "BASE_LOST payload names the capturer")

func _test_capture_from_neutral_emits_no_base_lost() -> void:
	var base := _make_hq_base("base_2", BaseSiteSelector.NEUTRAL_OWNER_ID, "p0")
	var events: Array[MatchEvent] = []
	CombatResolver._prune_dead([], [base], {}, HexGrid.new(), [], [], {}, [], events)

	_check(base.owner_id == "p0", "neutral base flips to its first captor")
	_check(_events_of_type(events, MatchEvent.Type.BASE_CAPTURED).size() == 1, "BASE_CAPTURED still fires for the new owner")
	_check(_events_of_type(events, MatchEvent.Type.BASE_LOST).is_empty(), "no BASE_LOST fires — a Unique base's neutral owner has no HUD to notify")

func _test_building_destroyed_idempotent() -> void:
	var base := BaseInstance.new("base_3", "capital", "p0", 1, HexCoord.new(2, 2))
	var farm := BuildingInstance.new("farm_1", base.id, "farm", 1, "", HexCoord.new(3, 2), "")
	farm.max_hp = 100.0
	farm.current_hp = 0.0
	farm.last_damaged_by = "p1"
	base.buildings.append(farm)

	var events: Array[MatchEvent] = []
	CombatResolver._prune_dead([], [base], {}, HexGrid.new(), [], [], {}, [], events)
	_check(farm.is_ruin, "the building is marked as a ruin")
	_check(_events_of_type(events, MatchEvent.Type.BUILDING_DESTROYED).size() == 1, "exactly one BUILDING_DESTROYED event fires on the ruin transition")

	# A second tick over the SAME already-ruined building (still current_hp <= 0.0,
	# now is_ruin == true already) must not re-fire the event.
	CombatResolver._prune_dead([], [base], {}, HexGrid.new(), [], [], {}, [], events)
	_check(_events_of_type(events, MatchEvent.Type.BUILDING_DESTROYED).size() == 1, "no second BUILDING_DESTROYED event fires while the building stays ruined")

func _test_neutral_standalone_emits_no_event() -> void:
	var tower := BuildingInstance.new("tower_1", "", "tower", 1, "stone", HexCoord.new(4, 4), BaseSiteSelector.NEUTRAL_OWNER_ID)
	tower.max_hp = 100.0
	tower.current_hp = 0.0
	tower.last_damaged_by = "p0"
	var standalone_buildings: Array[BuildingInstance] = [tower]

	var events: Array[MatchEvent] = []
	CombatResolver._prune_dead([], [], {}, HexGrid.new(), standalone_buildings, [], {}, [], events)

	_check(standalone_buildings.is_empty(), "the destroyed tower is still removed from standalone_buildings")
	_check(events.is_empty(), "no BUILDING_DESTROYED event fires for a neutral-owned standalone building")

func _test_deficit_death() -> void:
	var squads: Array[SquadInstance] = []
	var troops_by_id: Dictionary = {}
	var troop_defs := {"rifleman": {"foodUpkeep": 1.0, "fuelUpkeep": 0.0}}

	var squad := _make_squad("squad_hungry", "p0", "rifleman", 100.0)
	var t1 := TroopInstance.new("t1", "rifleman", "p0", squad.id, 30.0)
	var t2 := TroopInstance.new("t2", "rifleman", "p0", squad.id, 10.0)
	troops_by_id[t1.id] = t1
	troops_by_id[t2.id] = t2
	squad.add_member(t1.id)
	squad.add_member(t2.id)
	squads.append(squad)

	var events: Array[MatchEvent] = []
	var killed := UpkeepSystem.apply_deficit_deaths("p0", [ResourceType.Type.FOOD], squads, troops_by_id, troop_defs, events)

	_check(killed.size() == 1, "the single weakest troop was killed (fixture sanity check)")
	var deficit_events := _events_of_type(events, MatchEvent.Type.DEFICIT_DEATH)
	_check(deficit_events.size() == 1, "exactly one aggregate DEFICIT_DEATH event fires per call")
	if deficit_events.size() == 1:
		_check(deficit_events[0].owner_id == "p0", "event is attributed to the starving owner")
		_check(int(deficit_events[0].payload.get("troop_count", 0)) == 1, "event payload's troop_count matches how many actually died")

	# No deficit, no death, no event.
	var no_events: Array[MatchEvent] = []
	UpkeepSystem.apply_deficit_deaths("p0", [], squads, troops_by_id, troop_defs, no_events)
	_check(no_events.is_empty(), "an empty deficits list emits no event")

func _test_outpost_loot() -> void:
	var outpost := BarbarianOutpostInstance.new("outpost_1", "tower_1", [], {"stone": 100.0})
	outpost.tower_destroyed = true
	outpost.tower_killer = "p0"
	var barbarian_outposts: Array[BarbarianOutpostInstance] = [outpost]

	var pools: Dictionary = {}
	var pool_for := func(owner_id: String) -> ResourcePool:
		if not pools.has(owner_id):
			pools[owner_id] = ResourcePool.new()
		return pools[owner_id]

	var events: Array[MatchEvent] = []
	BarbarianOutpostLootSystem.resolve_tick(barbarian_outposts, [], pool_for, events)

	var loot_events := _events_of_type(events, MatchEvent.Type.OUTPOST_LOOT)
	_check(loot_events.size() == 1, "exactly one OUTPOST_LOOT event fires alongside the resource grant")
	if loot_events.size() == 1:
		_check(loot_events[0].owner_id == "p0", "event is attributed to the tower's actual killer")
		_check(float(loot_events[0].payload.get("loot", {}).get("stone", 0.0)) == 100.0, "event payload carries the granted loot")
