## Scene root for the Godot rendering scaffold (build-order item 2). _ready()
## only shows start_screen.gd's StartScreen overlay; _start_game() builds a
## demo MatchState the same way tests/test_sim_orchestrator.gd does and wires
## up every view/controller, then _process() drives the sim forward one of
## two ways depending on how the match was started (see lockstep_driver
## below). Everything under client/ only ever reads sim state or calls
## CommandProcessor (via CommandSubmitter, see client/net/) — it never
## mutates MatchState directly (07-data-architecture.md section 8).
##
## Single-player: single_player_requested fires _on_single_player_requested,
## sim_clock.advance() drives every frame, commands apply immediately via
## CommandSubmitter (lockstep null).
## Multiplayer: NetManager.match_starting fires _on_match_starting once the
## host clicks Start Match; lockstep_driver.advance() drives every frame
## instead (gated on every peer's input, see lockstep_driver.gd), and
## commands buffer through CommandSubmitter -> LockstepDriver.issue() instead
## of applying immediately.
extends Node2D

const PLAYER_COUNT := 2 ## single-player only; multiplayer's is match_starting's player_count
const LOCAL_PLAYER := "p0" ## single-player only; multiplayer's is net_manager.local_owner_id

const OWNER_COLOR_PALETTE: Array[Color] = [
	Color(0.25, 0.55, 0.95), Color(0.9, 0.25, 0.25), Color(0.25, 0.75, 0.35),
	Color(0.9, 0.75, 0.15), Color(0.65, 0.35, 0.85), Color(0.9, 0.55, 0.15),
]

## Set once per match: SP rolls it fresh (Godot's global RNG is already
## OS-entropy-seeded on engine startup, no explicit randomize() needed) so
## every match gets a different map/spawn; MP takes it from match_starting so
## every peer builds the identical map.
var _world_seed: int
var _local_owner_id: String = LOCAL_PLAYER
var _player_count: int = PLAYER_COUNT

var state: MatchState
var sim_clock := SimClock.new()
var demo_hexes: Array[HexCoord] = []
var owner_colors := {}
var owner_names := {}

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
var net_manager: NetManager
var lockstep_driver: LockstepDriver ## null in single-player (sim_clock drives instead)

var _local_capital_hex: HexCoord
var _local_capital_name: String = ""
var _waiting_label: Label
var _desync_label: Label

func _ready() -> void:
	net_manager = NetManager.new()
	add_child(net_manager)
	net_manager.match_starting.connect(_on_match_starting)
	net_manager.desync_detected.connect(_on_desync_detected)

	start_screen = StartScreen.new()
	add_child(start_screen)
	start_screen.setup(net_manager)
	start_screen.single_player_requested.connect(_on_single_player_requested)

func _on_single_player_requested(player_name: String, capital_name: String) -> void:
	_local_owner_id = LOCAL_PLAYER
	_player_count = PLAYER_COUNT
	_local_capital_name = capital_name
	_build_owner_visuals(_player_count, {LOCAL_PLAYER: player_name})
	_world_seed = randi()
	_start_game()
	_close_start_screen()

func _on_match_starting(world_seed: int, player_count: int, roster: Dictionary) -> void:
	_local_owner_id = net_manager.local_owner_id
	_player_count = player_count
	_world_seed = world_seed
	var names_by_owner: Dictionary = {}
	for entry in roster.values():
		names_by_owner[entry["owner_id"]] = entry["name"]
	_build_owner_visuals(_player_count, names_by_owner)

	lockstep_driver = LockstepDriver.new()
	_start_game()
	lockstep_driver.start(state, net_manager, roster)
	_close_start_screen()

func _close_start_screen() -> void:
	if start_screen != null:
		start_screen.queue_free()
		start_screen = null

func _build_owner_visuals(player_count: int, names_by_owner: Dictionary) -> void:
	owner_colors.clear()
	owner_names.clear()
	for i in range(player_count):
		var owner := "p%d" % i
		owner_colors[owner] = OWNER_COLOR_PALETTE[i % OWNER_COLOR_PALETTE.size()]
		owner_names[owner] = names_by_owner.get(owner, "Player %d" % (i + 1))
	owner_colors["neutral"] = Color(0.6, 0.6, 0.6)
	owner_names["neutral"] = "Neutral"

func _start_game() -> void:
	state = _build_demo_state()
	var bounds := _map_bounds()

	camera_controller = $Camera2D

	board = Board.new()
	add_child(board)
	board.setup(state.grid, demo_hexes)

	base_view = BaseView.new()
	add_child(base_view)
	base_view.setup(state, state.bases, owner_colors, state.standalone_buildings, state.building_defs, state.detections, _local_owner_id, owner_names)

	squad_view = SquadView.new()
	add_child(squad_view)
	squad_view.setup(state, state.squads, state.regiments, owner_colors, state.grid, state.troop_defs, state.visions, state.detections, _local_owner_id)

	projectile_view = ProjectileView.new()
	add_child(projectile_view)
	projectile_view.setup(state, state.projectiles, owner_colors)

	var submitter := CommandSubmitter.new(state, lockstep_driver)

	input_controller = InputController.new()
	add_child(input_controller)
	input_controller.setup(state, _local_owner_id, squad_view, camera_controller, submitter)

	build_preview = BuildPreview.new()
	add_child(build_preview)
	build_preview.setup(state, input_controller)

	# Added last so it draws over the board/base/squad views beneath it.
	fog_of_war = FogOfWar.new()
	add_child(fog_of_war)
	fog_of_war.setup(state, demo_hexes, _local_owner_id, camera_controller)

	# Added last of all so it draws over every world-space view (screen-space
	# regardless, since it's a CanvasLayer, but this keeps add-order/draw-order
	# intuitively matched with everything else here).
	hud_layer = HUDLayer.new()
	add_child(hud_layer)
	hud_layer.setup(state, _local_owner_id, input_controller, camera_controller, owner_colors, demo_hexes, bounds[0], bounds[1])

	camera_controller.set_bounds(bounds[0], bounds[1])
	camera_controller.center_on(HexView.axial_to_pixel(_local_capital_hex))

	if lockstep_driver != null:
		_waiting_label = Label.new()
		_waiting_label.text = "Waiting for players…"
		_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_waiting_label.anchor_right = 1.0
		_waiting_label.offset_top = 16.0
		_waiting_label.visible = false
		var waiting_layer := CanvasLayer.new()
		add_child(waiting_layer)
		waiting_layer.add_child(_waiting_label)

		_desync_label = Label.new()
		_desync_label.text = ""
		_desync_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_desync_label.anchor_right = 1.0
		_desync_label.offset_top = 48.0
		_desync_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		var desync_layer := CanvasLayer.new()
		add_child(desync_layer)
		desync_layer.add_child(_desync_label)

## Pixel-space bounding box of every generated hex, plus a few hexes of
## margin. CameraController.set_bounds now clamps the viewport's visible
## *edge* to this box (not just the camera center), so this margin is what
## you actually see past the map's true edge at max pan — sized past a
## single hex so the coastline doesn't sit flush against the screen border.
func _map_bounds() -> Array:
	var bounds_min := Vector2(INF, INF)
	var bounds_max := Vector2(-INF, -INF)
	for hex in demo_hexes:
		var p := HexView.axial_to_pixel(hex)
		bounds_min = Vector2(minf(bounds_min.x, p.x), minf(bounds_min.y, p.y))
		bounds_max = Vector2(maxf(bounds_max.x, p.x), maxf(bounds_max.y, p.y))
	var margin := Vector2.ONE * HexView.HEX_SIZE * 3.0
	return [bounds_min - margin, bounds_max + margin]

func _process(delta: float) -> void:
	if state == null:
		return
	if _desync_label != null and not _desync_label.text.is_empty():
		return
	if lockstep_driver != null:
		lockstep_driver.advance(delta)
		_waiting_label.visible = lockstep_driver.is_waiting
	else:
		sim_clock.advance(state, delta)

func _on_desync_detected(tick: int) -> void:
	_desync_label.text = "Desync detected at tick %d — match halted." % tick

func _build_demo_state() -> MatchState:
	var demo_state := MatchState.new()
	demo_state.seed_rng(_world_seed)
	demo_state.troop_defs = DataLoader.load_dir("res://data/troops")
	demo_state.building_defs = DataLoader.load_dir("res://data/buildings")
	demo_state.base_defs = DataLoader.load_dir("res://data/bases")

	var result := MapGenerator.generate(_player_count, _world_seed, demo_state.base_defs, demo_state.building_defs, [], demo_state.troop_defs)
	demo_state.grid = result.grid
	demo_state.bases = result.bases
	demo_state.squads.append_array(result.squads)
	for troop_id in result.troops_by_id:
		demo_state.troops_by_id[troop_id] = result.troops_by_id[troop_id]
	demo_hexes = HexCoord.range_within(HexCoord.new(0, 0), TerrainGenerator.map_radius(_player_count) + Tuning.OCEAN_FRINGE_WIDTH)

	for player_index in range(_player_count):
		var owner := "p%d" % player_index
		var capital := _find_base(demo_state, result.capital_ids_by_player[player_index])
		if owner == _local_owner_id:
			_local_capital_hex = capital.hex_coord
			if not _local_capital_name.is_empty():
				capital.display_name = _local_capital_name

	return demo_state

func _find_base(demo_state: MatchState, base_id: String) -> BaseInstance:
	for base in demo_state.bases:
		if base.id == base_id:
			return base
	return null
