## Placeholder rendering for base buildings: an owner-tinted rect per
## building at its hex (no sprites/art yet, per the build order's Art
## section — placeholder geometric shapes until the loop is validated).
## Standalone buildings (Tower/Landmine/Road/Bridge/Dock — no owning base)
## render as owner-tinted diamonds; Walls (edge-keyed via hex_a/hex_b, not
## a single hex) render as a thick line along their shared edge instead of
## a rect. Ruins darken their tint. Stealthed buildings (e.g. Landmine)
## only render for the local player or a detector that currently sees them.
class_name BaseView
extends Node2D

var bases: Array[BaseInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color
var standalone_buildings: Array[BuildingInstance] = []
var building_defs: Dictionary = {}
var detections: Dictionary = {}
var local_owner_id: String = ""

const BUILDING_SIZE := 20.0
const HQ_SIZE := 26.0
const WALL_WIDTH := 4.0
const RUIN_DARKEN := 0.6

func setup(p_bases: Array[BaseInstance], p_owner_colors: Dictionary, p_standalone_buildings: Array[BuildingInstance], p_building_defs: Dictionary, p_detections: Dictionary, p_local_owner_id: String) -> void:
	bases = p_bases
	owner_colors = p_owner_colors
	standalone_buildings = p_standalone_buildings
	building_defs = p_building_defs
	detections = p_detections
	local_owner_id = p_local_owner_id
	queue_redraw()

func _draw() -> void:
	for base in bases:
		var color: Color = owner_colors.get(base.owner_id, Color.WHITE)
		for building in base.buildings:
			_draw_building(building, base.owner_id, color, false)
	for building in standalone_buildings:
		var color: Color = owner_colors.get(building.owner_id, Color.WHITE)
		_draw_building(building, building.owner_id, color, true)

func _draw_building(building: BuildingInstance, owner_id: String, color: Color, is_standalone: bool) -> void:
	var is_ruin: bool = building.is_ruin or (building.max_hp > 0.0 and building.current_hp <= 0.0)
	if is_ruin:
		color = color.darkened(RUIN_DARKEN)

	if building.building_type == "wall":
		if building.hex_a == null or building.hex_b == null:
			return
		var segment := HexView.edge_segment(building.hex_a, building.hex_b)
		draw_line(segment[0], segment[1], color, WALL_WIDTH)
		return

	if building.hex == null:
		return

	if not _is_visible_to_local(building, owner_id):
		return

	var center := HexView.axial_to_pixel(building.hex)
	if is_standalone:
		_draw_diamond(center, BUILDING_SIZE, color)
	else:
		var size: float = HQ_SIZE if building.building_type == "hq" else BUILDING_SIZE
		var rect := Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size))
		draw_rect(rect, color, true)
		draw_rect(rect, Color.BLACK, false, 1.0)

func _draw_diamond(center: Vector2, size: float, color: Color) -> void:
	var half := size * 0.5
	var points := PackedVector2Array([
		center + Vector2(0, -half),
		center + Vector2(half, 0),
		center + Vector2(0, half),
		center + Vector2(-half, 0),
	])
	draw_colored_polygon(points, color)
	draw_polyline(points + PackedVector2Array([points[0]]), Color.BLACK, 1.0)

func _is_visible_to_local(building: BuildingInstance, owner_id: String) -> bool:
	if not BuildingStats.stealth(building_defs.get(building.building_type, {}), building_defs):
		return true
	if owner_id == local_owner_id:
		return true
	return DetectionSystem.detected_hexes_for(detections, local_owner_id).has(building.hex.to_key())
