## Throwaway smoke test: drive ResourceBar's new click-to-expand breakdown
## dropdown against a real seeded base, to shake out runtime errors the
## headless sim suites can't (they never build UI).
extends SceneTree

func _flat_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	for coord in HexCoord.range_within(HexCoord.new(0, 0), radius):
		grid.set_terrain(coord, Terrain.Type.PLAINS)
	return grid

func _init() -> void:
	var troop_defs := DataLoader.load_dir("res://data/troops")
	var building_defs := DataLoader.load_dir("res://data/buildings")
	var base_defs := DataLoader.load_dir("res://data/bases")

	var state := MatchState.new()
	state.grid = _flat_grid(6)
	state.troop_defs = troop_defs
	state.building_defs = building_defs
	state.base_defs = base_defs
	var base := BaseFactory.seed_base("base1", base_defs["capital"], "p0", HexCoord.new(0, 0), state.grid, building_defs)
	state.bases.append(base)

	var host := Control.new()
	host.theme = UITheme.create_theme()
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)

	var bar := ResourceBar.new()
	bar.theme = host.theme
	host.add_child(bar)
	bar.setup(state, "p0", InputController.new())

	print("  ok   setup (expanded=%s)" % bar._expanded)

	# Simulate the click.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	bar._gui_input(click)
	print("  ok   clicked (expanded=%s)" % bar._expanded)
	assert(bar._expanded)
	for type in bar._detail_labels:
		assert(bar._detail_labels[type].visible)
		assert(bar._usage_labels[type].visible)

	for i in range(4):
		bar._process(0.3)
	print("  ok   drove _process 4x (bar size=%s)" % bar.size)

	for type in bar._detail_labels:
		print("    - %s: %s (%s)" % [type, bar._detail_labels[type].text, bar._usage_labels[type].text])

	# Click again: should collapse.
	bar._gui_input(click)
	print("  ok   clicked again (expanded=%s)" % bar._expanded)
	assert(not bar._expanded)
	for type in bar._detail_labels:
		assert(not bar._detail_labels[type].visible)
		assert(not bar._usage_labels[type].visible)

	print("\nAll checks passed.")
	quit()
