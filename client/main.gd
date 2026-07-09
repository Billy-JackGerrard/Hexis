## Scene root for the Godot rendering scaffold (build-order item 2): builds a
## demo MatchState the same way tests/test_sim_orchestrator.gd does, then
## drives SimOrchestrator.resolve_tick() every frame. Everything under
## client/ only ever reads sim state or calls CommandProcessor — it never
## mutates MatchState directly (07-data-architecture.md section 8).
extends Node2D

const GRID_RADIUS := 6
const LOCAL_PLAYER := "p1"

var state: MatchState
var demo_hexes: Array[HexCoord] = []
var owner_colors := {
	"p1": Color(0.25, 0.55, 0.95),
	"p2": Color(0.9, 0.25, 0.25),
}

var board: Board
var base_view: BaseView
var squad_view: SquadView
var input_controller: InputController

func _ready() -> void:
	state = _build_demo_state()

	board = Board.new()
	add_child(board)
	board.setup(state.grid, demo_hexes)

	base_view = BaseView.new()
	add_child(base_view)
	base_view.setup(state.bases, owner_colors)

	squad_view = SquadView.new()
	add_child(squad_view)
	squad_view.setup(state.squads, owner_colors)

	input_controller = InputController.new()
	add_child(input_controller)
	input_controller.setup(state, LOCAL_PLAYER, squad_view)

func _process(delta: float) -> void:
	SimOrchestrator.resolve_tick(state, delta)
	base_view.queue_redraw()

func _build_demo_state() -> MatchState:
	var demo_state := MatchState.new()
	demo_state.troop_defs = DataLoader.load_dir("res://data/troops")
	demo_state.building_defs = DataLoader.load_dir("res://data/buildings")
	demo_state.base_defs = DataLoader.load_dir("res://data/bases")
	demo_state.grid = _build_flat_grid(GRID_RADIUS)

	var base := BaseFactory.seed_base(
		demo_state.next_id("base"),
		demo_state.base_defs["capital"],
		LOCAL_PLAYER,
		HexCoord.new(0, 0),
		demo_state.grid,
		demo_state.building_defs,
	)
	demo_state.bases.append(base)

	_spawn_squad(demo_state, LOCAL_PLAYER, "rifleman", HexCoord.new(4, 0), 3)

	return demo_state

func _build_flat_grid(radius: int) -> HexGrid:
	var grid := HexGrid.new()
	demo_hexes = HexCoord.range_within(HexCoord.new(0, 0), radius)
	for hex in demo_hexes:
		grid.set_terrain(hex, Terrain.Type.PLAINS)
	return grid

func _spawn_squad(demo_state: MatchState, owner: String, troop_type: String, hex: HexCoord, count: int) -> void:
	var squad := SquadInstance.new(demo_state.next_squad_id(), owner, troop_type, hex)
	var hp: float = float(demo_state.troop_defs.get(troop_type, {}).get("hp", 100.0))
	for i in range(count):
		var troop := TroopInstance.new(demo_state.next_troop_id(), troop_type, owner, squad.id, hp)
		demo_state.troops_by_id[troop.id] = troop
		squad.add_member(troop.id)
	demo_state.squads.append(squad)
