## Placeholder rendering for squads: an owner-tinted circle per squad,
## positioned by lerping current_hex -> path[0] over edge_progress — pure
## rendering-side interpolation of the sim's per-tick integer-hex position,
## same "counting up between ticks is visual only" principle as the resource
## tick (07-data-architecture.md section 7/8). Sim logic only ever reads
## current_hex.
##
## Also draws regiment visuals (a ring around each Commander, a line to each
## of its escorts) straight off state.regiments/RegimentInstance.commander_id
## — no new sim state, just the missing visual for structure that already
## exists (build order item 2's deferred "control groups/regiment visuals").
##
## Enemy squads only render while currently visible and not hidden by
## stealth/detection (see _is_renderable); docked/boarded squads never
## render their own circle since their current_hex just mirrors their host.
##
## Squad shape is domain-coded (circle: Land/Infantry, triangle: Air,
## diamond: Naval) now that a real multi-base map mixes domains on screen.
## Selected squads additionally get a dotted path preview along squad.path
## and a faint attack-range ring, both placeholder art, no new sim state.
##
## A selected OR hovered squad also gets a "{troop name} N/cap" label (per
## 09-ui-and-controls.md) drawn via ThemeDB's fallback font — same
## Node2D-can't-use-get_theme_default_font() reasoning as base_view.gd's
## title/tooltip text.
class_name SquadView
extends Node2D

var squads: Array[SquadInstance] = []
var regiments: Array[RegimentInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color
## squad_id -> true. Multi-selection (drag-select/control groups), not a
## single id — InputController is the only mutator.
var selected_squad_ids: Dictionary = {}

var grid: HexGrid
var troop_defs: Dictionary = {}
var visions: Dictionary = {} ## owner_id -> PlayerVision
var detections: Dictionary = {} ## owner_id -> {hex_key: true}
var local_owner_id: String = ""

var state: MatchState

## Redraw throttle: everything this layer draws is either sim state that only
## changes on a fine tick (squad positions lerp off edge_progress, which is
## per-tick — between ticks squad_pixel_position is constant, so a 60fps redraw
## draws the exact same frame 5/6 times), the hover label (tracks the mouse,
## so redraw on hovered-hex change), or the selection highlight (redraw when
## selection actually changes — InputController mutates it, doesn't redraw us).
## This was the single heaviest map-wide layer redrawing unconditionally every
## frame — its _draw runs _is_renderable (vision + DetectionSystem lookups)
## over every squad twice — so gating it is the main frame-budget win.
var _last_drawn_tick: int = -1
var _last_hover_hex_key: String = ""
var _selection_revision: int = 0
var _last_drawn_selection_revision: int = -1

const RADIUS := 10.0
const SELECTION_COLOR := Color.YELLOW
const REGIMENT_RING_COLOR := Color(1.0, 0.85, 0.2, 0.8)
const REGIMENT_LINE_COLOR := Color(1.0, 0.85, 0.2, 0.45)
const PATH_DOT_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const PATH_DOT_RADIUS := 2.0
const PATH_DOT_SPACING := 10.0
const RANGE_RING_COLOR := Color(1.0, 1.0, 1.0, 0.25)
const INFO_LABEL_WIDTH := 140.0
const INFO_LABEL_COLOR := UITheme.TEXT

func setup(p_state: MatchState, p_squads: Array[SquadInstance], p_regiments: Array[RegimentInstance], p_owner_colors: Dictionary, p_grid: HexGrid, p_troop_defs: Dictionary, p_visions: Dictionary, p_detections: Dictionary, p_local_owner_id: String) -> void:
	state = p_state
	squads = p_squads
	regiments = p_regiments
	owner_colors = p_owner_colors
	grid = p_grid
	troop_defs = p_troop_defs
	visions = p_visions
	detections = p_detections
	local_owner_id = p_local_owner_id

func squad_pixel_position(squad: SquadInstance) -> Vector2:
	var from := HexView.axial_to_pixel(squad.current_hex)
	if squad.path.is_empty():
		return from
	var to := HexView.axial_to_pixel(squad.path[0])
	return from.lerp(to, squad.edge_progress)

## Every friendly (`for_owner_id`-owned) squad within click radius of `point`,
## in stable squads-array order — the stacked-hex candidate list select_next
## cycles through, since several same-hex squads all render on top of each
## other and a plain "first match" query would always return the same
## array-order-first one.
func owned_squads_at_pixel(point: Vector2, for_owner_id: String) -> Array[SquadInstance]:
	var result: Array[SquadInstance] = []
	for squad in squads:
		if squad.owner_id == for_owner_id and squad_pixel_position(squad).distance_to(point) <= RADIUS:
			result.append(squad)
	return result

## Selects the candidate right after whichever one is currently the sole
## selection (wrapping past the end back to candidates[0]) — re-clicking a
## hex with several stacked squads steps through them one at a time. Falls
## back to candidates[0] when there's no single current selection among
## `candidates` (nothing selected yet, multiple selected, or the current
## selection isn't one of this hex's squads).
func select_next(candidates: Array[SquadInstance]) -> void:
	if candidates.is_empty():
		return
	var next := candidates[0]
	if selected_squad_ids.size() == 1:
		var current_id: String = selected_squad_ids.keys()[0]
		for i in range(candidates.size()):
			if candidates[i].id == current_id:
				next = candidates[(i + 1) % candidates.size()]
				break
	select_only(next.id)

## Every squad whose current rendered position falls inside `rect` — the
## drag-select query. Rect is in the same world space as squad_pixel_position.
func squads_in_rect(rect: Rect2) -> Array[SquadInstance]:
	var result: Array[SquadInstance] = []
	for squad in squads:
		if rect.has_point(squad_pixel_position(squad)):
			result.append(squad)
	return result

func is_selected(squad_id: String) -> bool:
	return selected_squad_ids.has(squad_id)

func select_only(squad_id: String) -> void:
	selected_squad_ids = {squad_id: true}
	_selection_revision += 1

func select_set(squad_ids: Array) -> void:
	selected_squad_ids = {}
	for id in squad_ids:
		selected_squad_ids[id] = true
	_selection_revision += 1

func add_to_selection(squad_ids: Array) -> void:
	for id in squad_ids:
		selected_squad_ids[id] = true
	_selection_revision += 1

func toggle_selection(squad_id: String) -> void:
	if selected_squad_ids.has(squad_id):
		selected_squad_ids.erase(squad_id)
	else:
		selected_squad_ids[squad_id] = true
	_selection_revision += 1

func clear_selection() -> void:
	selected_squad_ids = {}
	_selection_revision += 1

func _squad_by_id(squad_id: String) -> SquadInstance:
	for squad in squads:
		if squad.id == squad_id:
			return squad
	return null

func _process(_delta: float) -> void:
	if state == null:
		return
	var hover_key := HexView.pixel_to_axial(get_global_mouse_position()).to_key()
	if state.tick == _last_drawn_tick and hover_key == _last_hover_hex_key and _selection_revision == _last_drawn_selection_revision:
		return
	_last_drawn_tick = state.tick
	_last_hover_hex_key = hover_key
	_last_drawn_selection_revision = _selection_revision
	queue_redraw()

## False for empty/docked squads always; for enemy squads also gates on
## current vision + stealth/detection so fog and stealth aren't leaked.
func _is_renderable(squad: SquadInstance) -> bool:
	if squad.member_ids.is_empty() or squad.is_docked():
		return false
	if squad.owner_id == local_owner_id:
		return true
	var pv: PlayerVision = visions.get(local_owner_id)
	if pv == null or not pv.is_visible(squad.current_hex):
		return false
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	if not DetectionSystem.is_squad_hidden(squad, def, grid):
		return true
	return DetectionSystem.detected_hexes_for(detections, local_owner_id).has(squad.current_hex.to_key())

## Maps a squad's troop def "domain" string to the shape dispatched by
## _draw_squad_shape; defaults to INFANTRY (circle) same as domain_from_string.
func _domain_of(squad: SquadInstance) -> Terrain.Domain:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	return Terrain.domain_from_string(String(def.get("domain", "Infantry")))

## Land/Infantry keep the plain circle; Air/Naval get a distinct silhouette
## so mixed-domain squads on a multi-base map read apart at a glance.
func _draw_squad_shape(pos: Vector2, domain: Terrain.Domain, color: Color) -> void:
	match domain:
		Terrain.Domain.AIR:
			var points := PackedVector2Array([
				pos + Vector2(0, -RADIUS),
				pos + Vector2(RADIUS * 0.87, RADIUS * 0.5),
				pos + Vector2(-RADIUS * 0.87, RADIUS * 0.5),
			])
			draw_colored_polygon(points, color)
		Terrain.Domain.NAVAL:
			var points := PackedVector2Array([
				pos + Vector2(0, -RADIUS),
				pos + Vector2(RADIUS, 0),
				pos + Vector2(0, RADIUS),
				pos + Vector2(-RADIUS, 0),
			])
			draw_colored_polygon(points, color)
		_:
			draw_circle(pos, RADIUS, color)

## Dotted line from the squad's rendered position through each upcoming
## path hex — draw_line/draw_polyline have no dashed style, so a row of
## small dots along each segment stands in for one (placeholder art).
func _draw_path_preview(squad: SquadInstance) -> void:
	if squad.path.is_empty():
		return
	var points: Array[Vector2] = [squad_pixel_position(squad)]
	for hex in squad.path:
		points.append(HexView.axial_to_pixel(hex))
	for i in range(points.size() - 1):
		_draw_dotted_segment(points[i], points[i + 1])

func _draw_dotted_segment(from: Vector2, to: Vector2) -> void:
	var length := from.distance_to(to)
	var steps: int = max(1, int(length / PATH_DOT_SPACING))
	for i in range(steps + 1):
		draw_circle(from.lerp(to, float(i) / float(steps)), PATH_DOT_RADIUS, PATH_DOT_COLOR)

## Faint circle of radius range*HEX_SIZE — hex distance isn't perfectly
## circular in pixel space, but it's a good enough placeholder to show reach.
func _draw_range_ring(squad: SquadInstance) -> void:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var attack_range := float(def.get("range", 0))
	if attack_range <= 0.0:
		return
	draw_arc(squad_pixel_position(squad), attack_range * HexView.HEX_SIZE, 0.0, TAU, 48, RANGE_RING_COLOR, 1.5)

## The frontmost renderable squad (any owner — used for hover, mirroring how
## enemy troops are still nameable when scouted) at `point`, or null.
func _renderable_squad_at_pixel(point: Vector2) -> SquadInstance:
	for squad in squads:
		if _is_renderable(squad) and squad_pixel_position(squad).distance_to(point) <= RADIUS:
			return squad
	return null

## "{troop name} N/cap" above a squad — shown for a selected squad or
## whichever one the mouse is hovering, per 09-ui-and-controls.md's squad
## info requirement. maxSquadSize is the same per-troop cap
## GarrisonFactory/ProductionManager already enforce.
func _draw_squad_info(squad: SquadInstance, pos: Vector2) -> void:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	var name: String = String(def.get("name", squad.troop_type.capitalize()))
	var cap: int = max(1, int(def.get("maxSquadSize", 1)))
	var text := "%s %d/%d" % [name, squad.member_ids.size(), cap]
	var label_pos := pos - Vector2(INFO_LABEL_WIDTH * 0.5, RADIUS + 22.0)
	UITheme.draw_world_label(self, ThemeDB.fallback_font, label_pos, text, ThemeDB.fallback_font_size, INFO_LABEL_COLOR, INFO_LABEL_WIDTH)

func _draw() -> void:
	var hovered_squad := _renderable_squad_at_pixel(get_global_mouse_position())

	for regiment in regiments:
		var commander := _squad_by_id(regiment.commander_id)
		if commander == null or not _is_renderable(commander):
			continue
		var commander_pos := squad_pixel_position(commander)
		draw_arc(commander_pos, RADIUS + 6.0, 0.0, TAU, 24, REGIMENT_RING_COLOR, 2.0)
		for squad_id in regiment.squad_ids:
			var escort := _squad_by_id(squad_id)
			if escort == null or not _is_renderable(escort):
				continue
			draw_line(commander_pos, squad_pixel_position(escort), REGIMENT_LINE_COLOR, 1.0)

	for squad in squads:
		if not _is_renderable(squad):
			continue
		var pos := squad_pixel_position(squad)
		var color: Color = owner_colors.get(squad.owner_id, Color.WHITE)
		_draw_squad_shape(pos, _domain_of(squad), color)
		var selected := is_selected(squad.id)
		if selected:
			draw_arc(pos, RADIUS + 3.0, 0.0, TAU, 24, SELECTION_COLOR, 2.0)
			_draw_path_preview(squad)
			_draw_range_ring(squad)
		if selected or squad == hovered_squad:
			_draw_squad_info(squad, pos)
