## Placeholder rendering for base buildings: an owner-tinted rect per
## building at its hex (no sprites/art yet, per the build order's Art
## section — placeholder geometric shapes until the loop is validated).
## Standalone buildings (Tower/Landmine/Road/Bridge/Dock — no owning base)
## render as owner-tinted diamonds; Walls (edge-keyed via hex_a/hex_b, not
## a single hex) render as a thick line along their shared edge instead of
## a rect. Ruins darken their tint. Stealthed buildings (e.g. Landmine)
## only render for the local player or a detector that currently sees them.
##
## Also draws two lightweight text overlays, both using ThemeDB's fallback
## font since this is a Node2D (world space), not a Control — Godot's
## get_theme_default_font() only resolves via the Control/Theme system:
## - A base name / owner name title above every visible HQ (so a multi-base
##   board reads at a glance whose base is whose and which is still neutral).
## - A "name (Lv N)" tooltip over whatever building is currently under the
##   mouse, mirroring squad_view.gd's hover treatment for squads.
class_name BaseView
extends Node2D

var bases: Array[BaseInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color
var owner_names: Dictionary = {} ## owner_id -> display name
var standalone_buildings: Array[BuildingInstance] = []
var building_defs: Dictionary = {}
var detections: Dictionary = {}
var local_owner_id: String = ""

const BUILDING_SIZE := 20.0
const HQ_SIZE := 26.0
const WALL_WIDTH := 4.0
const RUIN_DARKEN := 0.6
const TITLE_WIDTH := 140.0
const TITLE_COLOR := Color.WHITE
const TITLE_SUBTEXT_COLOR := Color(0.8, 0.8, 0.8)
const TOOLTIP_COLOR := Color.WHITE

func setup(p_bases: Array[BaseInstance], p_owner_colors: Dictionary, p_standalone_buildings: Array[BuildingInstance], p_building_defs: Dictionary, p_detections: Dictionary, p_local_owner_id: String, p_owner_names: Dictionary = {}) -> void:
	bases = p_bases
	owner_colors = p_owner_colors
	standalone_buildings = p_standalone_buildings
	building_defs = p_building_defs
	detections = p_detections
	local_owner_id = p_local_owner_id
	owner_names = p_owner_names
	queue_redraw()

func _draw() -> void:
	for base in bases:
		var color: Color = owner_colors.get(base.owner_id, Color.WHITE)
		for building in base.buildings:
			_draw_building(building, base.owner_id, color, false)
	for building in standalone_buildings:
		var color: Color = owner_colors.get(building.owner_id, Color.WHITE)
		_draw_building(building, building.owner_id, color, true)
	for base in bases:
		_draw_base_title(base)
	_draw_hover_tooltip()

## The base's own HQ, or null (every base is seeded with exactly one — see
## BaseFactory.seed_base — but a captured/ruined base is never deleted so
## this stays a defensive lookup rather than an assumed [0]).
func _find_hq(base: BaseInstance) -> BuildingInstance:
	for building in base.buildings:
		if building.building_type == "hq":
			return building
	return null

func _draw_base_title(base: BaseInstance) -> void:
	var hq := _find_hq(base)
	if hq == null or hq.hex == null or not _is_visible_to_local(hq, base.owner_id):
		return
	var top := HexView.axial_to_pixel(hq.hex) - Vector2(0.0, HQ_SIZE * 0.5 + 28.0)
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var base_name := String(base.base_def_id).capitalize()
	var player_name := String(owner_names.get(base.owner_id, base.owner_id))
	draw_string(font, top - Vector2(TITLE_WIDTH * 0.5, 14.0), base_name, HORIZONTAL_ALIGNMENT_CENTER, TITLE_WIDTH, font_size, TITLE_COLOR)
	draw_string(font, top - Vector2(TITLE_WIDTH * 0.5, 0.0), player_name, HORIZONTAL_ALIGNMENT_CENTER, TITLE_WIDTH, font_size - 2, TITLE_SUBTEXT_COLOR)

## "name (Lv N)" over whichever building (base-attached or standalone) sits
## under the mouse, if any and if visible to the local player — Walls have no
## single hex of their own (hex_a/hex_b) so they're simply not covered here.
func _draw_hover_tooltip() -> void:
	var hex := HexView.pixel_to_axial(get_global_mouse_position())
	for base in bases:
		for building in base.buildings:
			if building.hex != null and building.hex.equals(hex) and _is_visible_to_local(building, base.owner_id):
				_draw_building_tooltip(building)
				return
	for building in standalone_buildings:
		if building.hex != null and building.hex.equals(hex) and _is_visible_to_local(building, building.owner_id):
			_draw_building_tooltip(building)
			return

func _draw_building_tooltip(building: BuildingInstance) -> void:
	var def: Dictionary = building_defs.get(building.building_type, {})
	var name: String = String(def.get("name", building.building_type.capitalize()))
	var pos := HexView.axial_to_pixel(building.hex) + Vector2(-TITLE_WIDTH * 0.5, -HQ_SIZE)
	draw_string(ThemeDB.fallback_font, pos, "%s (Lv %d)" % [name, building.level], HORIZONTAL_ALIGNMENT_CENTER, TITLE_WIDTH, ThemeDB.fallback_font_size, TOOLTIP_COLOR)

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
