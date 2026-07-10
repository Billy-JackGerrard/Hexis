## Scene root for the Godot rendering scaffold (build-order item 2): builds a
## demo MatchState the same way tests/test_sim_orchestrator.gd does, then
## drives SimOrchestrator.resolve_tick() every frame. Everything under
## client/ only ever reads sim state or calls CommandProcessor — it never
## mutates MatchState directly (07-data-architecture.md section 8).
extends Node2D

const PLAYER_COUNT := 2
const WORLD_SEED := 20260709
const LOCAL_PLAYER := "p0"

var state: MatchState
var demo_hexes: Array[HexCoord] = []
var owner_colors := {
	"p0": Color(0.25, 0.55, 0.95),
	"p1": Color(0.9, 0.25, 0.25),
}

var board: Board
var base_view: BaseView
var squad_view: SquadView
var input_controller: InputController
var fog_of_war: FogOfWar
var camera_controller: CameraController
var hud_layer: HUDLayer
var build_preview: BuildPreview

var _local_capital_hex: HexCoord

func _ready() -> void:
	state = _build_demo_state()
	var bounds := _map_bounds()

	camera_controller = $Camera2D

	board = Board.new()
	add_child(board)
	board.setup(state.grid, demo_hexes)

	base_view = BaseView.new()
	add_child(base_view)
	base_view.setup(state.bases, owner_colors, state.standalone_buildings, state.building_defs, state.detections, LOCAL_PLAYER)

	squad_view = SquadView.new()
	add_child(squad_view)
	squad_view.setup(state.squads, state.regiments, owner_colors, state.grid, state.troop_defs, state.visions, state.detections, LOCAL_PLAYER)

	input_controller = InputController.new()
	add_child(input_controller)
	input_controller.setup(state, LOCAL_PLAYER, squad_view, camera_controller)

	build_preview = BuildPreview.new()
	add_child(build_preview)
	build_preview.setup(state, input_controller)

	# Added last so it draws over the board/base/squad views beneath it.
	fog_of_war = FogOfWar.new()
	add_child(fog_of_war)
	fog_of_war.setup(state.grid, demo_hexes, state.visions, LOCAL_PLAYER)

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
	SimOrchestrator.resolve_tick(state, delta)
	base_view.queue_redraw()

func _build_demo_state() -> MatchState:
	var demo_state := MatchState.new()
	demo_state.troop_defs = DataLoader.load_dir("res://data/troops")
	demo_state.building_defs = DataLoader.load_dir("res://data/buildings")
	demo_state.base_defs = DataLoader.load_dir("res://data/bases")

	var result := MapGenerator.generate(PLAYER_COUNT, WORLD_SEED, demo_state.base_defs, demo_state.building_defs, [], demo_state.troop_defs)
	demo_state.grid = result.grid
	demo_state.bases = result.bases
	demo_state.squads.append_array(result.squads)
	for troop_id in result.troops_by_id:
		demo_state.troops_by_id[troop_id] = result.troops_by_id[troop_id]
	demo_hexes = HexCoord.range_within(HexCoord.new(0, 0), TerrainGenerator.map_radius(PLAYER_COUNT) + TerrainGenerator.OCEAN_FRINGE_WIDTH)

	for player_index in range(PLAYER_COUNT):
		var owner := "p%d" % player_index
		var capital := _find_base(demo_state, result.capital_ids_by_player[player_index])
		if owner == LOCAL_PLAYER:
			_local_capital_hex = capital.hex_coord
		_spawn_squad(demo_state, owner, "rifleman", HexCoord.neighbor(capital.hex_coord, 0), 3)

	_spawn_demo_regiment(demo_state, _find_base(demo_state, result.capital_ids_by_player[0]).hex_coord)

	return demo_state

func _find_base(demo_state: MatchState, base_id: String) -> BaseInstance:
	for base in demo_state.bases:
		if base.id == base_id:
			return base
	return null

func _spawn_squad(demo_state: MatchState, owner: String, troop_type: String, hex: HexCoord, count: int) -> SquadInstance:
	var squad := SquadInstance.new(demo_state.next_squad_id(), owner, troop_type, hex)
	var hp: float = float(demo_state.troop_defs.get(troop_type, {}).get("hp", 100.0))
	for i in range(count):
		var troop := TroopInstance.new(demo_state.next_troop_id(), troop_type, owner, squad.id, hp)
		demo_state.troops_by_id[troop.id] = troop
		squad.add_member(troop.id)
	demo_state.squads.append(squad)
	return squad

## Demo-only: gives the local player a Commander regiment near its Capital so
## squad_view's regiment ring/lines (build order's deferred "regiment
## visuals") have something to draw — exercises RegimentInstance/
## CommandProcessor.assign_to_commander, not new sim logic.
func _spawn_demo_regiment(demo_state: MatchState, capital_hex: HexCoord) -> void:
	var commander := _spawn_squad(demo_state, LOCAL_PLAYER, "commander_vanguard", HexCoord.neighbor(capital_hex, 1), 1)
	var escort_a := _spawn_squad(demo_state, LOCAL_PLAYER, "rifleman", HexCoord.neighbor(capital_hex, 2), 3)
	var escort_b := _spawn_squad(demo_state, LOCAL_PLAYER, "rifleman", HexCoord.neighbor(capital_hex, 3), 3)
	CommandProcessor.assign_to_commander(demo_state, escort_a.id, commander.id, LOCAL_PLAYER)
	CommandProcessor.assign_to_commander(demo_state, escort_b.id, commander.id, LOCAL_PLAYER)
