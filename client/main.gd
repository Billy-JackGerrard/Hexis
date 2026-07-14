## Scene root for the Godot rendering scaffold (build-order item 2). _ready()
## only shows start_screen.gd's StartScreen overlay; _start_game() (fired by
## its single_player_requested signal) builds a demo MatchState the same way
## tests/test_sim_orchestrator.gd does, then _process() drives
## SimOrchestrator.resolve_tick() every frame. Everything under client/ only
## ever reads sim state or calls CommandProcessor — it never mutates
## MatchState directly (07-data-architecture.md section 8).
extends Node2D

const PLAYER_COUNT := 2
const WORLD_SEED := 20260709
const LOCAL_PLAYER := "p0"

var state: MatchState
var sim_clock := SimClock.new()
var demo_hexes: Array[HexCoord] = []
var owner_colors := {
	"p0": Color(0.25, 0.55, 0.95),
	"p1": Color(0.9, 0.25, 0.25),
	"neutral": Color(0.6, 0.6, 0.6),
}
var owner_names := {
	"p0": "Player 1",
	"p1": "Player 2",
	"neutral": "Neutral",
}

var board: Board
var base_view: BaseView
var squad_view: SquadView
var projectile_view: ProjectileView
var input_controller: InputController
var fog_of_war: FogOfWar
var camera_controller: CameraController
var hud_layer: HUDLayer
var build_preview: BuildPreview
var start_screen: StartScreen

var _local_capital_hex: HexCoord
var _local_capital_name: String = ""

func _ready() -> void:
	start_screen = StartScreen.new()
	add_child(start_screen)
	start_screen.setup()
	start_screen.single_player_requested.connect(_on_single_player_requested)

func _on_single_player_requested(player_name: String, capital_name: String) -> void:
	owner_names[LOCAL_PLAYER] = player_name
	_local_capital_name = capital_name
	_start_game()
	start_screen.queue_free()
	start_screen = null

func _start_game() -> void:
	state = _build_demo_state()
	var bounds := _map_bounds()

	camera_controller = $Camera2D

	board = Board.new()
	add_child(board)
	board.setup(state.grid, demo_hexes)

	base_view = BaseView.new()
	add_child(base_view)
	base_view.setup(state, state.bases, owner_colors, state.standalone_buildings, state.building_defs, state.detections, LOCAL_PLAYER, owner_names)

	squad_view = SquadView.new()
	add_child(squad_view)
	squad_view.setup(state, state.squads, state.regiments, owner_colors, state.grid, state.troop_defs, state.visions, state.detections, LOCAL_PLAYER)

	projectile_view = ProjectileView.new()
	add_child(projectile_view)
	projectile_view.setup(state, state.projectiles, owner_colors)

	input_controller = InputController.new()
	add_child(input_controller)
	input_controller.setup(state, LOCAL_PLAYER, squad_view, camera_controller)

	build_preview = BuildPreview.new()
	add_child(build_preview)
	build_preview.setup(state, input_controller)

	# Added last so it draws over the board/base/squad views beneath it.
	fog_of_war = FogOfWar.new()
	add_child(fog_of_war)
	fog_of_war.setup(state, demo_hexes, LOCAL_PLAYER)

	# Added last of all so it draws over every world-space view (screen-space
	# regardless, since it's a CanvasLayer, but this keeps add-order/draw-order
	# intuitively matched with everything else here).
	hud_layer = HUDLayer.new()
	add_child(hud_layer)
	hud_layer.setup(state, LOCAL_PLAYER, input_controller, camera_controller, owner_colors, demo_hexes, bounds[0], bounds[1])

	camera_controller.set_bounds(bounds[0], bounds[1])
	camera_controller.center_on(HexView.axial_to_pixel(_local_capital_hex))

## Pixel-space bounding box of every generated hex, +/- one hex of margin —
## keeps CameraController's pan from wandering past the ocean fringe.
func _map_bounds() -> Array:
	var bounds_min := Vector2(INF, INF)
	var bounds_max := Vector2(-INF, -INF)
	for hex in demo_hexes:
		var p := HexView.axial_to_pixel(hex)
		bounds_min = Vector2(minf(bounds_min.x, p.x), minf(bounds_min.y, p.y))
		bounds_max = Vector2(maxf(bounds_max.x, p.x), maxf(bounds_max.y, p.y))
	var margin := Vector2.ONE * HexView.HEX_SIZE
	return [bounds_min - margin, bounds_max + margin]

func _process(delta: float) -> void:
	if state == null:
		return
	sim_clock.advance(state, delta)

func _build_demo_state() -> MatchState:
	var demo_state := MatchState.new()
	demo_state.seed_rng(WORLD_SEED)
	demo_state.troop_defs = DataLoader.load_dir("res://data/troops")
	demo_state.building_defs = DataLoader.load_dir("res://data/buildings")
	demo_state.base_defs = DataLoader.load_dir("res://data/bases")

	var result := MapGenerator.generate(PLAYER_COUNT, WORLD_SEED, demo_state.base_defs, demo_state.building_defs, [], demo_state.troop_defs)
	demo_state.grid = result.grid
	demo_state.bases = result.bases
	demo_state.squads.append_array(result.squads)
	for troop_id in result.troops_by_id:
		demo_state.troops_by_id[troop_id] = result.troops_by_id[troop_id]
	demo_hexes = HexCoord.range_within(HexCoord.new(0, 0), TerrainGenerator.map_radius(PLAYER_COUNT) + Tuning.OCEAN_FRINGE_WIDTH)

	for player_index in range(PLAYER_COUNT):
		var owner := "p%d" % player_index
		var capital := _find_base(demo_state, result.capital_ids_by_player[player_index])
		if owner == LOCAL_PLAYER:
			_local_capital_hex = capital.hex_coord
			capital.display_name = _local_capital_name

	return demo_state

func _find_base(demo_state: MatchState, base_id: String) -> BaseInstance:
	for base in demo_state.bases:
		if base.id == base_id:
			return base
	return null

