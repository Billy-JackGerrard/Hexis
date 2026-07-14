## World-space placement-preview overlay for build order item 4's build menu:
## while InputController.pending_building_type is set, highlights every hex
## (or, for Wall — edge-keyed, no single hex of its own — every edge) within
## the selected base's BuildingPlacement.hq_build_radius that
## BuildingPlacement.can_place/can_place_wall currently allows, same per-hex
## overlay approach as fog_of_war.gd. Read-only, like every other client/
## node.
##
## The valid set is only recomputed when the pending building/base changes,
## not every frame — can_place loops over every existing building for its
## adjacency check, the same per-frame-cost concern input_controller.gd's
## hover throttling and alerts_panel.gd's polling interval both already flag
## for on-demand sim queries.
class_name BuildPreview
extends Node2D

var state: MatchState
var input_controller: InputController

const VALID_COLOR := Color(0.2, 1.0, 0.3, 0.35)
const VALID_EDGE_COLOR := Color(0.2, 1.0, 0.3, 0.9)
const EDGE_WIDTH := 4.0

## Faint fill for the selected HQ's build radius (client/hud/building_panel.gd
## selection, not a pending placement) — the same hex-distance disc around the
## HQ's own hex that BuildingPlacement.hq_build_radius/can_place enforce.
const RADIUS_COLOR := Color(0.5, 0.8, 1.0, 0.10)

var _cache_key: String = ""
var _valid_hexes: Array[HexCoord] = []
var _valid_edges: Array = [] ## Array of [HexCoord, HexCoord] pairs

var _radius_cache_key: String = ""
var _radius_hexes: Array[HexCoord] = []

func setup(p_state: MatchState, p_input_controller: InputController) -> void:
	state = p_state
	input_controller = p_input_controller

func _process(_delta: float) -> void:
	_refresh_if_needed()
	_refresh_radius_if_needed()
	queue_redraw()

func _refresh_if_needed() -> void:
	var key := "%s|%s" % [input_controller.pending_base_id, input_controller.pending_building_type]
	if key == _cache_key:
		return
	_cache_key = key
	_valid_hexes = []
	_valid_edges = []
	if input_controller.pending_building_type == "":
		return
	var base := state.find_base(input_controller.pending_base_id)
	if base == null:
		return
	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})
	var radius := BuildingPlacement.hq_build_radius(base.hq_level)
	var candidates := HexCoord.range_within(base.hex_coord, radius)
	if input_controller.pending_building_type == "wall":
		_refresh_valid_edges(base, base_def, candidates)
		return
	var occupied_unit_hexes := BuildingPlacement.ground_unit_hexes(state.squads, state.troop_defs)
	for hex in candidates:
		var result := BuildingPlacement.can_place(base, base_def, input_controller.pending_building_type, hex, state.grid, state.building_defs, occupied_unit_hexes)
		if result == BuildingPlacement.Result.OK:
			_valid_hexes.append(hex)

## Recomputed only when the selected building changes (client/hud/
## building_panel.gd's InputController.selected_building_id) — shows the max
## build distance from an HQ the moment it's selected, without needing to
## also be actively placing something.
func _refresh_radius_if_needed() -> void:
	var key := input_controller.selected_building_id
	if key == _radius_cache_key:
		return
	_radius_cache_key = key
	_radius_hexes = []
	if key == "":
		return
	var found := state.find_base_building(key)
	if found.is_empty():
		return
	var building: BuildingInstance = found["building"]
	if building.building_type != "hq" or building.is_ruin or building.hex == null:
		return
	var base: BaseInstance = found["base"]
	var radius := BuildingPlacement.hq_build_radius(base.hq_level)
	_radius_hexes = HexCoord.range_within(building.hex, radius)

## Every candidate hex's 6 edges, each checked once (seen_keys dedupes the
## shared edge two adjacent candidate hexes would otherwise both enumerate).
func _refresh_valid_edges(base: BaseInstance, base_def: Dictionary, candidates: Array[HexCoord]) -> void:
	var seen_keys: Dictionary = {}
	for hex in candidates:
		for direction in range(6):
			var neighbor := HexCoord.neighbor(hex, direction)
			var key := "%s|%s" % [hex.to_key(), neighbor.to_key()] if hex.to_key() < neighbor.to_key() else "%s|%s" % [neighbor.to_key(), hex.to_key()]
			if seen_keys.has(key):
				continue
			seen_keys[key] = true
			if BuildingPlacement.can_place_wall(base, base_def, hex, neighbor, state.grid, state.building_defs) == BuildingPlacement.Result.OK:
				_valid_edges.append([hex, neighbor])

func _draw() -> void:
	var corners := HexView.corners()
	for hex in _radius_hexes:
		var center := HexView.axial_to_pixel(hex)
		var points := PackedVector2Array()
		for corner in corners:
			points.append(center + corner)
		draw_colored_polygon(points, RADIUS_COLOR)

	if input_controller.pending_building_type == "":
		return
	if input_controller.pending_building_type == "wall":
		for edge in _valid_edges:
			var segment := HexView.edge_segment(edge[0], edge[1])
			draw_line(segment[0], segment[1], VALID_EDGE_COLOR, EDGE_WIDTH)
		return
	for hex in _valid_hexes:
		var center := HexView.axial_to_pixel(hex)
		var points := PackedVector2Array()
		for corner in corners:
			points.append(center + corner)
		draw_colored_polygon(points, VALID_COLOR)
