## Root of the screen-space UI layer (build order item 3): a CanvasLayer so
## every child Control ignores the world Camera2D's pan/zoom, added last in
## main.gd (after fog_of_war) so it draws over every world-space view beneath
## it — same "added last" convention fog_of_war itself established. Control
## children consume mouse input before it reaches InputController's
## _unhandled_input (default mouse_filter = STOP), so clicking a HUD panel
## never also triggers a world click-to-move.
class_name HUDLayer
extends CanvasLayer

var resource_bar: ResourceBar
var base_panel: BasePanel
var build_menu: BuildMenu
var production_panel: ProductionPanel
var alerts_panel: AlertsPanel
var minimap: Minimap

func setup(state: MatchState, owner_id: String, input_controller: InputController, camera_controller: CameraController, owner_colors: Dictionary, hexes: Array[HexCoord], bounds_min: Vector2, bounds_max: Vector2) -> void:
	resource_bar = ResourceBar.new()
	add_child(resource_bar)
	resource_bar.setup(state, owner_id)

	base_panel = BasePanel.new()
	add_child(base_panel)
	base_panel.setup(state, owner_id, input_controller)

	build_menu = BuildMenu.new()
	add_child(build_menu)
	build_menu.setup(state, owner_id, input_controller)

	production_panel = ProductionPanel.new()
	add_child(production_panel)
	production_panel.setup(state, owner_id, input_controller)

	alerts_panel = AlertsPanel.new()
	add_child(alerts_panel)
	alerts_panel.setup(state, owner_id, camera_controller)

	minimap = Minimap.new()
	add_child(minimap)
	minimap.setup(state, owner_colors, camera_controller, hexes, bounds_min, bounds_max)
