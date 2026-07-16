## Profiling harness to measure where 30ms per tick is being spent.
## Run with: godot --headless --script res://tests/test_profile_tick.gd
extends SceneTree

## Profiler with microsecond precision
class MicroProfiler:
	var times: Dictionary = {}
	
	func start(name: String) -> void:
		times[name] = Time.get_ticks_usec()
	
	func end(name: String) -> float:
		if not times.has(name):
			return 0.0
		var elapsed_us: int = Time.get_ticks_usec() - times[name]
		times.erase(name)
		return float(elapsed_us) / 1000.0  # Convert to ms

var _next_proj: int = 0

func _next_projectile_id() -> String:
	_next_proj += 1
	return "proj%d" % _next_proj

func _init() -> void:
	_run()

func _run() -> void:
	print("=== SimOrchestrator Tick Profiling ===\n")
	
	var grid := HexGrid.new()
	var state := MatchState.new()
	state.grid = grid
	state.troop_defs = DataLoader.load_dir("res://data/troops")
	state.building_defs = DataLoader.load_dir("res://data/buildings")
	state.base_defs = DataLoader.load_dir("res://data/bases")
	
	_setup_test_scenario(state, grid)
	
	print("Test scenario: %d squads, %d bases, %d standalone buildings, %d regiments" % [
		state.squads.size(),
		state.bases.size(),
		state.standalone_buildings.size(),
		state.regiments.size()
	])
	print("Grid size: %d hexes\n" % state.grid._terrain.size())
	
	var prof := MicroProfiler.new()
	var tick_times: Array[float] = []
	var system_totals: Dictionary = {}
	
	# Warm-up tick
	SimOrchestrator.resolve_tick(state, 0.016)
	
	# Profile 100 ticks
	print("Profiling 100 ticks...\n")
	for tick in range(100):
		prof.start("total_tick")
		
		state.tick += 1
		state.command_queue.drain_due(state, state.tick)
		
		prof.start("aura_system")
		var auras := AuraSystem.resolve_tick(state.squads, state.bases, state.troop_defs, state.building_defs, state.regiments)
		var aura_ms := prof.end("aura_system")
		system_totals["AuraSystem"] = system_totals.get("AuraSystem", 0.0) + aura_ms
		
		prof.start("detection_system")
		DetectionSystem.resolve_tick(state.squads, state.bases, state.standalone_buildings, state.grid, state.troop_defs, state.building_defs, state.detections)
		var detection_ms := prof.end("detection_system")
		system_totals["DetectionSystem"] = system_totals.get("DetectionSystem", 0.0) + detection_ms
		
		prof.start("vision_system")
		VisionSystem.resolve_tick(state.squads, state.bases, state.standalone_buildings, state.grid, state.troop_defs, state.building_defs, state.visions, state.base_defs, state.vision_los_cache)
		var vision_ms := prof.end("vision_system")
		system_totals["VisionSystem"] = system_totals.get("VisionSystem", 0.0) + vision_ms
		
		prof.start("combat_targeting")
		var pre_move_targets := CombatResolver.build_targets(state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, auras, state.standalone_buildings)
		var targeting_ms := prof.end("combat_targeting")
		system_totals["CombatTargeting"] = system_totals.get("CombatTargeting", 0.0) + targeting_ms
		
		prof.start("movement_attack_move")
		MovementResolver.resolve_attack_move(state.squads, state.troop_defs, state.grid, pre_move_targets, state.bases, state.standalone_buildings)
		var attack_move_ms := prof.end("movement_attack_move")
		system_totals["MovementAttackMove"] = system_totals.get("MovementAttackMove", 0.0) + attack_move_ms
		
		prof.start("movement_resolve")
		MovementResolver.resolve_tick(0.016, state.squads, state.grid, state.troop_defs, auras, state.bases, state.standalone_buildings)
		var movement_ms := prof.end("movement_resolve")
		system_totals["MovementResolve"] = system_totals.get("MovementResolve", 0.0) + movement_ms
		
		prof.start("regiment_movement")
		_resolve_regiment_movement(state, 0.016, auras)
		var regiment_ms := prof.end("regiment_movement")
		system_totals["RegimentMovement"] = system_totals.get("RegimentMovement", 0.0) + regiment_ms
		
		prof.start("combat_resolve")
		CombatResolver.resolve_tick(0.016, state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, state.detections, auras, state.standalone_buildings, state.regiments, state.production_queues, state.projectiles, Callable(self, "_next_projectile_id"), state.rng, state.barbarian_outposts, state.events)
		var combat_ms := prof.end("combat_resolve")
		system_totals["CombatResolve"] = system_totals.get("CombatResolve", 0.0) + combat_ms
		
		prof.start("projectile_system")
		ProjectileSystem.resolve_tick(0.016, state.projectiles, state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, auras, state.standalone_buildings, state.regiments, state.production_queues, state.rng, state.barbarian_outposts, state.events)
		var projectile_ms := prof.end("projectile_system")
		system_totals["ProjectileSystem"] = system_totals.get("ProjectileSystem", 0.0) + projectile_ms
		
		prof.start("barbarian_loot")
		BarbarianOutpostLootSystem.resolve_tick(state.barbarian_outposts, state.squads, Callable(state, "pool_for"), state.events)
		var barbarian_ms := prof.end("barbarian_loot")
		system_totals["BarbarianLoot"] = system_totals.get("BarbarianLoot", 0.0) + barbarian_ms
		
		prof.start("production_advance")
		_advance_production(state, 0.016)
		var production_ms := prof.end("production_advance")
		system_totals["ProductionAdvance"] = system_totals.get("ProductionAdvance", 0.0) + production_ms
		
		state.economy_accumulator += 0.016
		
		var tick_ms := prof.end("total_tick")
		tick_times.append(tick_ms)
	
	# Stats
	var avg_tick: float = tick_times.reduce(func(a, b): return a + b) / float(tick_times.size())
	var max_tick: float = tick_times.reduce(func(a, b): return max(a, b))
	var min_tick: float = tick_times.reduce(func(a, b): return min(a, b))
	
	print("=== TICK TIMES ===")
	print("Average: %.2fms" % avg_tick)
	print("Max:     %.2fms" % max_tick)
	print("Min:     %.2fms" % min_tick)
	print("")
	
	print("=== SYSTEM BREAKDOWN (100 ticks total) ===")
	var systems_sorted: Array = system_totals.keys()
	systems_sorted.sort_custom(func(a, b): return system_totals[a] > system_totals[b])
	
	for system in systems_sorted:
		var total_ms: float = system_totals[system]
		var per_tick_ms: float = total_ms / 100.0
		var pct: float = (total_ms / (avg_tick * 100.0)) * 100.0
		print("%25s: %7.2fms/tick (%5.1f%% of frame)" % [system, per_tick_ms, pct])
	
	print("\nAll checks passed.")

func _resolve_regiment_movement(state: MatchState, dt: float, auras: Dictionary) -> void:
	for regiment in state.regiments:
		var commander_squad := state.find_squad(regiment.commander_id)
		if commander_squad == null:
			continue
		var member_squads: Array[SquadInstance] = []
		for squad_id in regiment.squad_ids:
			var member := state.find_squad(squad_id)
			if member != null:
				member_squads.append(member)
		MovementResolver.resolve_regiment_tick(dt, commander_squad, member_squads, state.grid, state.troop_defs, auras, state.bases, state.standalone_buildings)

func _advance_production(state: MatchState, dt: float) -> void:
	for building_id in state.production_queues.keys():
		var queue: ProductionQueue = state.production_queues[building_id]
		var found := state.find_base_building(building_id)
		if found.is_empty():
			continue
		var base: BaseInstance = found["base"]
		var building: BuildingInstance = found["building"]
		if building.is_ruin or (building.max_hp > 0.0 and building.current_hp <= 0.0):
			continue
		
		ProductionManager.advance(queue, dt, state.troop_defs, state.pool_for(base.owner_id))
		ProductionManager.pump(
			queue,
			base.owner_id,
			building.hex,
			building.building_type,
			state.squads,
			state.troops_by_id,
			state.bases_owned_by(base.owner_id),
			state.building_defs,
			state.troop_defs,
			state.commander_count(base.owner_id),
			Callable(state, "next_troop_id"),
			Callable(state, "next_squad_id"),
			state.grid,
			state.pool_for(base.owner_id),
			BuildingPlacement.building_blocking_hexes(state.bases, state.standalone_buildings),
		)

func _setup_test_scenario(state: MatchState, grid: HexGrid) -> void:
	# Create a 80x80 hex map
	for x in range(-40, 40):
		for y in range(-40, 40):
			var coord := HexCoord.new(x, y)
			var terrain_type := Terrain.Type.PLAINS
			if randf() < 0.15:
				terrain_type = Terrain.Type.FOREST
			elif randf() < 0.1:
				terrain_type = Terrain.Type.HILLS
			grid.set_terrain(coord, terrain_type)
	
	# Player 1 base at center
	var p1_base := BaseInstance.new("base_p1", "BaseA", "player_1", 1, HexCoord.new(-5, -5))
	state.bases.append(p1_base)
	
	var hq := BuildingInstance.new("hq_p1", p1_base.id, "HQ", 1, "wood", HexCoord.new(-5, -5))
	hq.max_hp = 100.0
	hq.current_hp = 100.0
	p1_base.buildings.append(hq)
	
	# Player 2 base
	var p2_base := BaseInstance.new("base_p2", "BaseB", "player_2", 1, HexCoord.new(5, 5))
	state.bases.append(p2_base)
	
	var hq2 := BuildingInstance.new("hq_p2", p2_base.id, "HQ", 1, "wood", HexCoord.new(5, 5))
	hq2.max_hp = 100.0
	hq2.current_hp = 100.0
	p2_base.buildings.append(hq2)
	
	# Create squads for both players (~15 per side)
	for player_idx in range(2):
		var owner_id := "player_%d" % (player_idx + 1)
		var base := state.bases[player_idx]
		var squad_count := 15
		
		for i in range(squad_count):
			var offset_q := (i % 5) - 2
			var offset_r := (i / 5) - 1
			var squad_hex := HexCoord.add(base.hex_coord, HexCoord.new(offset_q, offset_r))
			var squad := SquadInstance.new("%s_squad_%d" % [owner_id, i], owner_id, "Infantry", squad_hex)
			squad.member_ids = ["m1", "m2", "m3", "m4", "m5"]
			squad.path = []
			squad.order = {"type": "idle"}
			state.squads.append(squad)
	
	# Create some tower defenses (standalone buildings)
	for i in range(4):
		var tower := BuildingInstance.new("tower_%d" % i, "", "Tower", 1, "wood", HexCoord.new((-10 + i * 5), (-10 + i * 5)), ["player_1", "player_2"][i % 2])
		tower.max_hp = 50.0
		tower.current_hp = 50.0
		state.standalone_buildings.append(tower)
	
	# Initialize player data
	state.players["player_1"] = Player.new("player_1")
	state.players["player_2"] = Player.new("player_2")
	
	# Initialize resources
	state.resource_pools["player_1"] = ResourcePool.new()
	state.resource_pools["player_2"] = ResourcePool.new()
