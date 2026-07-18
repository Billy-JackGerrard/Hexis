## Building rendering: most building_types now get a real 3D mesh from
## client/buildings/building_view_3d.gd, so this Node2D's own flat-rect/
## diamond drawing is restricted to FLAT_SHAPE_TYPES (currently just Wall
## and Landmine — see that const's comment). Every other building still
## goes through here for its hover tooltip, base title, and 1-2 letter
## BUILDING_LABELS tag (kept even without a flat shape — it still reads
## well floating over the 3D mesh). Walls (edge-keyed via hex_a/hex_b, not
## a single hex) render as a thick line along their shared edge instead of
## a rect. Ruins darken their tint here (Wall/Landmine only — every other
## ruined building_type renders as BuildingView3D's uniform rubble-heap
## mesh instead, regardless of its original type). Stealthed buildings
## (e.g. Landmine) only render for the local player or a detector that
## currently sees them.
##
## Also draws a lightweight hover-only text overlay using ThemeDB's fallback
## font since this is a Node2D (world space), not a Control — Godot's
## get_theme_default_font() only resolves via the Control/Theme system:
## a two-line name / "Lv N" tooltip over whatever building is currently
## under the mouse (name and level split so a long name's width doesn't
## also have to fit "(Lv N)", and raised clear of squad_view.gd's own
## hover/selected info label in case a squad sits on the same hex) — except
## the HQ, which shows a base name / owner name title instead (see
## _draw_base_title). Hover-gated rather than always-on so the title doesn't
## permanently cover the hex above every HQ, which made it annoying to click.
class_name BaseView
extends Node2D

var state: MatchState
var bases: Array[BaseInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color
var owner_names: Dictionary = {} ## owner_id -> display name
var standalone_buildings: Array[BuildingInstance] = []
var building_defs: Dictionary = {}
var base_defs: Dictionary = {}
var detections: Dictionary = {}
var local_owner_id: String = ""

## Redraw throttle: building geometry only changes on a sim tick, but the
## hover tooltip (_draw_hover_tooltip) must track the mouse live — gating
## purely on tick (main.gd used to force this every frame, then a tick-only
## throttle) either wasted a full-map redraw 60x/sec for no reason or added
## up to a whole tick's delay before a hovered building's title appeared.
## Redrawing on tick change OR hovered-hex change gets both: cheap most
## frames (a hex-key string compare), instant on actual hover changes.
var _last_drawn_tick: int = -1
var _last_hover_hex_key: String = ""

## Every building_type except these two now gets a real mesh from
## client/buildings/building_view_3d.gd — drawing the flat rect/diamond too
## would double them up. Landmine stays flat (a visible 3D prop would leak a
## hidden mine's presence past its stealth gate); Wall stays flat because a
## real wall mesh needs its own corner/straight connection-mask resolver,
## deferred as a follow-up (see BuildingView3D's header comment).
const FLAT_SHAPE_TYPES := ["wall", "landmine"]
const BUILDING_SIZE := 20.0
const HQ_SIZE := 26.0
const WALL_WIDTH := 4.0
const RUIN_DARKEN := 0.6
## Widened from 140 — same draw_string clipping TOOLTIP_WIDTH's comment
## below describes, cutting off both a longer custom base name and
## "Unnamed Base" itself.
const TITLE_WIDTH := 200.0
const TITLE_COLOR := UITheme.TEXT
const TOOLTIP_COLOR := UITheme.TEXT
## Wider than TITLE_WIDTH — draw_string clips text past its width, and names
## like "Missile Launcher" ran past 140px and got cut off.
const TOOLTIP_WIDTH := 220.0
const TOOLTIP_LEVEL_COLOR := UITheme.TEXT_MUTED
## 1-2 letter tag drawn centered on each building's shape so same-color
## squares/diamonds (no art yet) are visually distinguishable at a glance.
## First letter alone where a building_type's initial is unique; expanded
## (not always to its literal 2nd letter — picked for readability, e.g.
## "Fa"/"Fm" for Factory/Farm) wherever two-plus types collide on the same
## first letter. Wall has no entry — it renders as an edge line, not a
## shape with room for a label. Keep sorted to match data/buildings/*.json.
const BUILDING_LABELS := {
	"barracks": "Ba", "blazeworks": "Bl", "bridge": "Br",
	"cold_turret": "Co", "command_centre": "Cm", "covert_airfield": "CA", "covert_works": "CW",
	"demolition_plant": "De", "dock": "Do",
	"emp_turret": "EM",
	"factory": "Fa", "farm": "Fm", "flame_turret": "Fl", "ford_yard": "Fd", "forest_yard": "Fs", "frostworks": "Fw",
	"grenade_turret": "Gr",
	"hangar": "Ha", "harbour": "Hr", "healing_spire": "He", "house": "Ho", "hq": "HQ",
	"ice_spire": "Ic", "iron_aviary": "Ir",
	"landmine": "La", "lumber_mill": "Lu",
	"mine": "Mi", "missile_launcher": "ML",
	"oil_rig": "Oi",
	"port": "Po",
	"quarry": "Qu",
	"radar_array": "Ra", "road": "Rd",
	"salvage_works": "Sa", "shipyard": "Sh", "sniper_turret": "Sn", "stone_works": "St", "supply_depot": "Su",
	"tank_plant": "Ta", "tower": "To", "turret": "Tu",
	"water_turret": "Wa", "wind_sanctuary": "Ws", "wind_spire": "Wi", "wood_turret": "Wo",
}
const LABEL_FONT_SIZE := 12
const LABEL_COLOR := Color.WHITE
const LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 0.9)
const LABEL_OUTLINE_SIZE := 2
## Kept close to the building itself rather than clearing squad_view.gd's own
## hover/selected INFO_LABEL zone (anchored RADIUS+22 above a squad, roughly
## -48..-28px) — these used to sit up at -70/-50 specifically to dodge that,
## but that pushed the tooltip up into the hex directly above the building's
## own hex, which made that tile annoying to click. A rare visual overlap
## with a garrisoned squad's own label (same hex, both hovered at once) is an
## accepted tradeoff for staying off the tile above.
const TOOLTIP_NAME_OFFSET := 36.0
const TOOLTIP_LEVEL_OFFSET := 20.0

func setup(p_state: MatchState, p_bases: Array[BaseInstance], p_owner_colors: Dictionary, p_standalone_buildings: Array[BuildingInstance], p_building_defs: Dictionary, p_detections: Dictionary, p_local_owner_id: String, p_owner_names: Dictionary = {}, p_base_defs: Dictionary = {}) -> void:
	state = p_state
	bases = p_bases
	owner_colors = p_owner_colors
	standalone_buildings = p_standalone_buildings
	building_defs = p_building_defs
	detections = p_detections
	local_owner_id = p_local_owner_id
	owner_names = p_owner_names
	base_defs = p_base_defs
	queue_redraw()

func _process(_delta: float) -> void:
	if state == null:
		return
	var hover_key := HexView.pixel_to_axial(get_global_mouse_position()).to_key()
	if state.tick == _last_drawn_tick and hover_key == _last_hover_hex_key:
		return
	_last_drawn_tick = state.tick
	_last_hover_hex_key = hover_key
	queue_redraw()

func _draw() -> void:
	for base in bases:
		var color: Color = owner_colors.get(base.owner_id, Color.WHITE)
		for building in base.buildings:
			_draw_building(building, base.owner_id, color, false)
	for building in standalone_buildings:
		var color: Color = owner_colors.get(building.owner_id, Color.WHITE)
		_draw_building(building, building.owner_id, color, true)
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
	var top := HexView.axial_to_pixel(hq.hex) - Vector2(0.0, HQ_SIZE * 0.5 + 14.0)
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var base_name := base.display_name if not base.display_name.is_empty() else String(base.base_def_id).capitalize()
	var player_name := String(owner_names.get(base.owner_id, base.owner_id))
	# Base name in the owner's color (blue/red) for identity; player name in the
	# HUD's muted text color. Both drawn via UITheme.draw_world_label's dark halo
	# so they stay readable over any terrain.
	var player_color: Color = owner_colors.get(base.owner_id, UITheme.TEXT_MUTED)
	UITheme.draw_world_label(self, font, top - Vector2(TITLE_WIDTH * 0.5, 20.0), base_name, font_size + 6, player_color, TITLE_WIDTH)
	UITheme.draw_world_label(self, font, top - Vector2(TITLE_WIDTH * 0.5, 0.0), player_name, font_size, TITLE_COLOR, TITLE_WIDTH)

## "name (Lv N)" over whichever building (base-attached or standalone) sits
## under the mouse, if any and if visible to the local player — Walls have no
## single hex of their own (hex_a/hex_b) so they're simply not covered here.
## Hovering any building that belongs to a base also shows that base's title
## (see _draw_base_title, anchored above its HQ regardless of which of its
## buildings is hovered) — so a multi-base board reads whose base it is from
## any of its buildings, not just its HQ. Skipped for the HQ itself since its
## own tooltip would draw at the exact same anchor as the title.
func _draw_hover_tooltip() -> void:
	var hex := HexView.pixel_to_axial(get_global_mouse_position())
	for base in bases:
		for building in base.buildings:
			if building.hex != null and building.hex.equals(hex) and _is_visible_to_local(building, base.owner_id):
				_draw_base_title(base)
				if building.building_type != "hq":
					_draw_building_tooltip(building)
				return
	for building in standalone_buildings:
		if building.hex != null and building.hex.equals(hex) and _is_visible_to_local(building, building.owner_id):
			_draw_building_tooltip(building)
			return

func _draw_building_tooltip(building: BuildingInstance) -> void:
	var def: Dictionary = building_defs.get(building.building_type, {})
	var name: String = String(def.get("name", building.building_type.capitalize()))
	var anchor := HexView.axial_to_pixel(building.hex)
	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var name_pos := anchor + Vector2(-TOOLTIP_WIDTH * 0.5, -TOOLTIP_NAME_OFFSET)
	var level_pos := anchor + Vector2(-TOOLTIP_WIDTH * 0.5, -TOOLTIP_LEVEL_OFFSET)
	UITheme.draw_world_label(self, font, name_pos, name, font_size, TOOLTIP_COLOR, TOOLTIP_WIDTH)
	UITheme.draw_world_label(self, font, level_pos, "Lv %d" % building.level, font_size - 3, TOOLTIP_LEVEL_COLOR, TOOLTIP_WIDTH)

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
	if FLAT_SHAPE_TYPES.has(building.building_type):
		if is_standalone:
			_draw_diamond(center, BUILDING_SIZE, color)
		else:
			var size: float = HQ_SIZE if building.building_type == "hq" else BUILDING_SIZE
			var rect := Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size))
			draw_rect(rect, color, true)
			draw_rect(rect, Color.BLACK, false, 1.0)
	_draw_building_label(center, building.building_type)

func _draw_building_label(center: Vector2, building_type: String) -> void:
	var label: String = BUILDING_LABELS.get(building_type, "")
	if label.is_empty():
		return
	var font := ThemeDB.fallback_font
	# draw_string's y is the text baseline, not its top, so nudging down by
	# ~35% of the font size roughly centers the glyphs vertically on `center`.
	var pos := center + Vector2(0.0, LABEL_FONT_SIZE * 0.35)
	var width := BUILDING_SIZE * 2.0
	pos.x -= width * 0.5
	draw_string_outline(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, width, LABEL_FONT_SIZE, LABEL_OUTLINE_SIZE, LABEL_OUTLINE)
	draw_string(font, pos, label, HORIZONTAL_ALIGNMENT_CENTER, width, LABEL_FONT_SIZE, LABEL_COLOR)

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
