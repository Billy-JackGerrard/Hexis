## Root of the screen-space UI layer (build order item 3): a CanvasLayer so
## every child Control ignores the world Camera2D's pan/zoom, added last in
## main.gd (after fog_of_war) so it draws over every world-space view beneath
## it — same "added last" convention fog_of_war itself established. Control
## children consume mouse input before it reaches InputController's
## _unhandled_input (default mouse_filter = STOP), so clicking a HUD panel
## never also triggers a world click-to-move.
##
## The always-on chrome — resource_bar (top), toast_panel (top-center,
## persistent per-condition alert rows plus fire-once event toasts — see
## sim/events/match_event.gd), minimap (bottom-right) — plus the one
## selection-driven building_panel (right) that replaced the old
## base_panel/build_menu/building_info_panel/production_panel quartet. Every
## panel shares one UITheme.create_theme(): a CanvasLayer isn't a Control so
## its theme doesn't cascade, so it's assigned per top-level panel (each
## panel's own children inherit from there).
class_name HUDLayer
extends CanvasLayer

var theme: Theme

var resource_bar: ResourceBar
var building_panel: BuildingPanel
var troop_info_panel: TroopInfoPanel
var squad_panel: SquadPanel
var toast_panel: ToastPanel
var minimap: Minimap
var upgrade_buildings_panel: UpgradeBuildingsPanel

func setup(state: MatchState, owner_id: String, input_controller: InputController, camera_controller: CameraController, owner_colors: Dictionary, hexes: Array[HexCoord], bounds_min: Vector2, bounds_max: Vector2) -> void:
	theme = UITheme.create_theme()

	resource_bar = ResourceBar.new()
	resource_bar.theme = theme
	add_child(resource_bar)
	resource_bar.setup(state, owner_id, input_controller)

	# Created before building_panel so building_panel can reach it in setup().
	troop_info_panel = TroopInfoPanel.new()
	troop_info_panel.theme = theme
	add_child(troop_info_panel)
	troop_info_panel.setup(state)

	# Created before building_panel so building_panel's HQ body can open it.
	upgrade_buildings_panel = UpgradeBuildingsPanel.new()
	upgrade_buildings_panel.theme = theme
	add_child(upgrade_buildings_panel)
	upgrade_buildings_panel.setup(state, owner_id, input_controller)

	building_panel = BuildingPanel.new()
	building_panel.theme = theme
	add_child(building_panel)
	building_panel.setup(state, owner_id, input_controller, troop_info_panel, camera_controller, resource_bar, upgrade_buildings_panel)

	squad_panel = SquadPanel.new()
	squad_panel.theme = theme
	add_child(squad_panel)
	squad_panel.setup(state, owner_id, input_controller, input_controller.squad_view, camera_controller, resource_bar)

	toast_panel = ToastPanel.new()
	toast_panel.theme = theme
	add_child(toast_panel)
	toast_panel.setup(state, owner_id, camera_controller)

	minimap = Minimap.new()
	minimap.theme = theme
	add_child(minimap)
	minimap.setup(state, owner_colors, camera_controller, hexes, bounds_min, bounds_max, owner_id)
