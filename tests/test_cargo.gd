## Headless assertion suite for the cargo slice (sim/units/cargo_system.gd,
## the boarded-squad mirroring in sim/units/movement_resolver.gd, and the
## carrier-death-kills-cargo pruning in sim/units/combat_resolver.gd).
## Run with:
##   godot --headless --script res://tests/test_cargo.gd
extends SceneTree

var _failures: int = 0
var _troop_defs: Dictionary
var _building_defs: Dictionary
var _next_id: int = 0

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	_troop_defs = DataLoader.load_dir("res://data/troops")
	_building_defs = DataLoader.load_dir("res://data/buildings")

	print("CargoSystem.board")
	_test_board()
	print("CargoSystem.unload")
	_test_unload()
	print("MovementResolver boarded-squad mirroring")
	_test_movement_mirroring()
	print("CombatResolver carrier-death-kills-cargo")
	_test_carrier_death_kills_cargo()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## --- helpers -------------------------------------------------------------

func _make_squad(owner: String, troop_type: String, hex: HexCoord, count: int = 1, troops: Dictionary = {}) -> SquadInstance:
	_next_id += 1
	var squad := SquadInstance.new("sq%d" % _next_id, owner, troop_type, hex)
	var use_hp: float = float(_troop_defs.get(troop_type, {}).get("hp", 0.0))
	for i in range(count):
		_next_id += 1
		var tid := "tr%d" % _next_id
		troops[tid] = TroopInstance.new(tid, troop_type, owner, squad.id, use_hp)
		squad.add_member(tid)
	return squad

func _line_grid(terrains: Array) -> HexGrid:
	var grid := HexGrid.new()
	for i in range(terrains.size()):
		grid.set_terrain(HexCoord.new(i, 0), terrains[i])
	return grid

## --- CargoSystem.board -----------------------------------------------------

func _test_board() -> void:
	var troops: Dictionary = {}
	var hex := HexCoord.new(0, 0)

	# Transport Truck: cargoCapacity 1, cargoAllowedTags [Infantry].
	var truck := _make_squad("p1", "transport_truck", hex, 1, troops)
	var rifles := _make_squad("p1", "rifleman", hex, 4, troops)

	_check(CargoSystem.can_board(truck, rifles, _troop_defs), "Rifleman squad (Infantry) can board a Transport Truck")
	_check(CargoSystem.board(truck, rifles, _troop_defs), "board() succeeds")
	_check(rifles.boarded_on_squad_id == truck.id, "boarded squad's boarded_on_squad_id set to carrier")
	_check(truck.cargo_squad_ids.has(rifles.id), "carrier's cargo_squad_ids records the boarded squad")
	_check(rifles.path.is_empty(), "boarding clears the boarded squad's path")

	# Capacity 1 is already full: a second squad can't board.
	var rifles2 := _make_squad("p1", "rifleman", hex, 1, troops)
	_check(not CargoSystem.can_board(truck, rifles2, _troop_defs), "Transport Truck at capacity rejects a second boarder")

	# Tag mismatch: a Naval squad can't board a Land-only Transport Truck.
	var boat := _make_squad("p1", "hms_cuddles", hex, 1, troops)
	var truck2 := _make_squad("p1", "transport_truck", hex, 1, troops)
	_check(not CargoSystem.can_board(truck2, boat, _troop_defs), "Naval squad cannot board Transport Truck (cargoAllowedTags: [Infantry])")

	# Different owner can't board.
	var enemy_rifles := _make_squad("p2", "rifleman", hex, 1, troops)
	var truck3 := _make_squad("p1", "transport_truck", hex, 1, troops)
	_check(not CargoSystem.can_board(truck3, enemy_rifles, _troop_defs), "a different owner's squad cannot board")

	# Already-boarded squad can't board again elsewhere.
	var truck4 := _make_squad("p1", "transport_truck", hex, 1, troops)
	_check(not CargoSystem.can_board(truck4, rifles, _troop_defs), "an already-boarded squad cannot board a second carrier")

	# A non-carrier (cargoCapacity 0) can't hold cargo.
	var rifles_a := _make_squad("p1", "rifleman", hex, 1, troops)
	var rifles_b := _make_squad("p1", "rifleman", hex, 1, troops)
	_check(not CargoSystem.can_board(rifles_a, rifles_b, _troop_defs), "a non-carrier troop cannot hold cargo")

	# Tank Carrier: cargoCapacity 2, cargoAllowedTags [Land, Infantry].
	var tank_carrier := _make_squad("p1", "tank_carrier", hex, 1, troops)
	var quad_bike := _make_squad("p1", "quad_bike", hex, 1, troops)
	var rifles_c := _make_squad("p1", "rifleman", hex, 1, troops)
	_check(CargoSystem.board(tank_carrier, quad_bike, _troop_defs), "Land squad boards Tank Carrier")
	_check(CargoSystem.board(tank_carrier, rifles_c, _troop_defs), "Infantry squad also boards the same Tank Carrier (capacity 2)")
	var rifles_d := _make_squad("p1", "rifleman", hex, 1, troops)
	_check(not CargoSystem.can_board(tank_carrier, rifles_d, _troop_defs), "Tank Carrier rejects a third boarder past capacity 2")

## --- CargoSystem.unload ----------------------------------------------------

func _test_unload() -> void:
	var troops: Dictionary = {}
	var hex := HexCoord.new(0, 0)
	var grid := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS])

	# Aircraft Carrier can launch mid-combat.
	var carrier := _make_squad("p1", "aircraft_carrier", hex, 1, troops)
	var glider := _make_squad("p1", "glider", hex, 1, troops)
	CargoSystem.board(carrier, glider, _troop_defs)
	_check(CargoSystem.can_unload(carrier, glider, _troop_defs, true), "Aircraft Carrier can unload mid-combat (canLaunchCargoMidCombat: true)")
	_check(CargoSystem.unload(carrier, glider, hex, grid, _troop_defs, true), "unload() succeeds mid-combat onto the carrier's own hex")
	_check(glider.boarded_on_squad_id == "", "unloaded squad's boarded_on_squad_id cleared")
	_check(glider.current_hex.equals(hex), "unloaded squad's current_hex set to target hex")
	_check(not carrier.cargo_squad_ids.has(glider.id), "carrier's cargo_squad_ids no longer references the unloaded squad")

	# HMS Cuddles cannot launch mid-combat.
	var cuddles := _make_squad("p1", "hms_cuddles", hex, 1, troops)
	var rifles := _make_squad("p1", "rifleman", hex, 1, troops)
	CargoSystem.board(cuddles, rifles, _troop_defs)
	_check(not CargoSystem.can_unload(cuddles, rifles, _troop_defs, true), "HMS Cuddles cannot unload mid-combat (canLaunchCargoMidCombat: false)")
	_check(not CargoSystem.unload(cuddles, rifles, hex, grid, _troop_defs, true), "unload() rejected mid-combat for HMS Cuddles")
	_check(CargoSystem.can_unload(cuddles, rifles, _troop_defs, false), "HMS Cuddles can unload while idle/not in combat")

	# Naval carrier (HMS Cuddles) disembarking onto bare land with no Dock/
	# Port/Shipyard is rejected, per 01-map-and-terrain.md's Naval/Coastline
	# Rules — a ship can't put troops ashore anywhere along the coast.
	_check(not CargoSystem.unload(cuddles, rifles, HexCoord.new(1, 0), grid, _troop_defs, false), "Naval carrier cannot disembark onto a bare Plains hex")

	# The same disembark onto a hex with a standalone Dock succeeds.
	var dock_buildings: Array[BuildingInstance] = [BuildingInstance.new("dock1", "", "dock", 1, "stone", HexCoord.new(1, 0), "p1")]
	var no_bases: Array[BaseInstance] = []
	_check(CargoSystem.unload(cuddles, rifles, HexCoord.new(1, 0), grid, _troop_defs, false, no_bases, dock_buildings), "unload() succeeds onto a Dock hex while idle")
	_check(rifles.current_hex.equals(HexCoord.new(1, 0)), "unloaded onto the requested Dock hex")

	# Unloading a squad that isn't actually boarded there fails.
	var truck := _make_squad("p1", "transport_truck", hex, 1, troops)
	var loose_rifles := _make_squad("p1", "rifleman", hex, 1, troops)
	_check(not CargoSystem.unload(truck, loose_rifles, hex, grid, _troop_defs), "unload() rejected for a squad never boarded on this carrier")

	# Unloading more than one hex away from the carrier fails.
	var far_grid := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])
	var truck2 := _make_squad("p1", "transport_truck", HexCoord.new(0, 0), 1, troops)
	var rifles2 := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	CargoSystem.board(truck2, rifles2, _troop_defs)
	_check(not CargoSystem.unload(truck2, rifles2, HexCoord.new(2, 0), far_grid, _troop_defs), "unload() rejected onto a hex >1 away from the carrier")

## --- MovementResolver boarded-squad mirroring ------------------------------

func _test_movement_mirroring() -> void:
	var troops: Dictionary = {}
	var grid := _line_grid([Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS, Terrain.Type.PLAINS])

	var truck := _make_squad("p1", "transport_truck", HexCoord.new(0, 0), 1, troops)
	var rifles := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 1, troops)
	CargoSystem.board(truck, rifles, _troop_defs)

	MovementResolver.issue_move(truck, grid, HexCoord.new(4, 0), _troop_defs)
	MovementResolver.resolve_tick(1.0, [truck, rifles], grid, _troop_defs)

	_check(rifles.current_hex.equals(truck.current_hex), "boarded squad's current_hex mirrors its carrier's after a tick")
	_check(rifles.path.is_empty(), "boarded squad never accumulates its own path")

## --- CombatResolver carrier-death-kills-cargo ------------------------------

func _test_carrier_death_kills_cargo() -> void:
	var troops: Dictionary = {}
	var bases: Array[BaseInstance] = []
	var grid := HexGrid.new()
	grid.set_terrain(HexCoord.new(0, 0), Terrain.Type.PLAINS)

	var truck := _make_squad("p1", "transport_truck", HexCoord.new(0, 0), 1, troops)
	var rifles := _make_squad("p1", "rifleman", HexCoord.new(0, 0), 4, troops)
	CargoSystem.board(truck, rifles, _troop_defs)

	# Kill every member of the carrier squad directly.
	for member_id in truck.member_ids:
		troops[member_id].current_hp = 0.0

	var squads: Array[SquadInstance] = [truck, rifles]
	CombatResolver.resolve_tick(0.1, squads, bases, troops, grid, _troop_defs, _building_defs)

	_check(not squads.any(func(s): return s.id == truck.id), "destroyed carrier squad is pruned")
	_check(not squads.any(func(s): return s.id == rifles.id), "boarded squad is pruned along with its destroyed carrier")
	for member_id in rifles.member_ids:
		_check(not troops.has(member_id), "boarded squad's troop members removed from the registry too")
