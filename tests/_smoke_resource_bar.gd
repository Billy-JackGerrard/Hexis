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

	print("  ok   setup (expanded=%s, breakdown visible=%s)" % [bar._breakdown_expanded, bar._breakdown_panel.visible])

	# Simulate the click.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	bar._gui_input(click)
	print("  ok   clicked (expanded=%s, breakdown visible=%s)" % [bar._breakdown_expanded, bar._breakdown_panel.visible])
	assert(bar._breakdown_expanded)
	assert(bar._breakdown_panel.visible)

	for i in range(4):
		bar._process(0.3)
	print("  ok   drove _process 4x (panel size=%s, rows=%d)" % [bar._breakdown_panel.size, bar._breakdown_content.get_child_count()])
	assert(bar._breakdown_content.get_child_count() == ResourceBar.DISPLAY_ORDER.size() * 2)

	for child in bar._breakdown_content.get_children():
		if child is Label:
			print("    - %s" % child.text)

	# Click again: should collapse.
	bar._gui_input(click)
	print("  ok   clicked again (expanded=%s, breakdown visible=%s)" % [bar._breakdown_expanded, bar._breakdown_panel.visible])
	assert(not bar._breakdown_expanded)
	assert(not bar._breakdown_panel.visible)

	print("\nAll checks passed.")
	quit()
