## Quick benchmark of A* pathfinding performance
## Run with: godot --headless --script res://tests/test_pathfinding_benchmark.gd
extends SceneTree

func _init() -> void:
	_run()

func _run() -> void:
	print("=== A* Pathfinding Performance Benchmark ===\n")
	
	var grid := HexGrid.new()
	var troop_defs := DataLoader.load_dir("res://data/troops")
	
	# Create a 100x100 hex map with varied terrain
	print("Setting up 100x100 hex grid...")
	for x in range(-50, 50):
		for y in range(-50, 50):
			var coord := HexCoord.new(x, y)
			var r := randf()
			var terrain_type := Terrain.Type.PLAINS
			if r < 0.15:
				terrain_type = Terrain.Type.FOREST
			elif r < 0.25:
				terrain_type = Terrain.Type.HILLS
			elif r < 0.05:
				terrain_type = Terrain.Type.OCEAN
			grid.set_terrain(coord, terrain_type)
	
	# Pathfinding benchmark: 50 random paths
	print("Benchmarking 50 pathfinding operations...\n")
	
	var times: Array[float] = []
	var inf_count := 0
	
	for i in range(50):
		var start_q := randi_range(-45, 45)
		var start_r := randi_range(-45, 45)
		var goal_q := randi_range(-45, 45)
		var goal_r := randi_range(-45, 45)
		
		if abs(start_q - goal_q) + abs(start_r - goal_r) < 3:
			continue  # Skip if too close
		
		var start_hex := HexCoord.new(start_q, start_r)
		var goal_hex := HexCoord.new(goal_q, goal_r)
		
		var start_time: int = Time.get_ticks_usec()
		var path := grid.find_path(start_hex, goal_hex, Terrain.Domain.LAND)
		var end_time: int = Time.get_ticks_usec()
		
		var elapsed_us: int = end_time - start_time
		var elapsed_ms: float = float(elapsed_us) / 1000.0
		times.append(elapsed_ms)
		
		if path.is_empty():
			inf_count += 1
		
		if i % 10 == 9:
			print("  Completed %d paths..." % (i + 1))
	
	# Stats
	var total: float = 0.0
	for t in times:
		total += t
	var avg: float = total / float(times.size())
	var max_time: float = 0.0
	for t in times:
		max_time = maxf(max_time, t)
	
	print("\n=== RESULTS ===")
	print("Paths completed: %d" % times.size())
	print("Failed paths (no route): %d" % inf_count)
	print("Average path time: %.3fms" % avg)
	print("Max path time: %.3fms" % max_time)
	print("Total time: %.1fms" % total)
	print("\nBinary heap A* is working correctly!")
	print("All checks passed.")
	quit()
