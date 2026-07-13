## Click/drag handling for this scaffold slice: left-click a friendly squad
## to select it, shift-click to add/remove from selection, left-drag a box
## over friendly squads to select all of them. Number keys 1-9 recall a
## control group; Ctrl+number assigns the current selection to one. Resolves
## clicks/drags to hexes/squads/groups only — every actual mutation goes
## through CommandProcessor, the sim's single action-stream entry point
## (07-data-architecture.md section 8); this node never touches sim state
## directly. Tab/Shift+Tab cycles the camera through the local player's
## bases; failed orders get a short-lived red X ping at the attempted
## destination.
##
## Left-click precedence (build order item 3, 09-ui-and-controls.md's
## Focus-fire/structure-targeting requirement), checked in order:
## 0. Build-menu placement mode in progress (pending_building_type set) ->
##    every click commits/pings against that instead of anything below.
## 1. A friendly squad under the cursor -> select it (unchanged).
## 2. An enemy CombatTarget (troop/squad, building, or Wall edge) under the
##    cursor, with squads currently selected -> CommandProcessor.attack_target
##    for each selected squad instead of a move order — this is also how a
##    building/HQ siege or Wall breach is directed, since auto-targeting only
##    ever picks the nearest enemy troop.
## 3. One of the local player's own base buildings under the cursor ->
##    selects that base (`selected_base_id`, polled by client/hud/base_panel.gd)
##    instead of issuing a move order — same as clicking a city in Civ.
## 4. Otherwise, move order for the current selection (unchanged).
## Hover (no button held) mirrors the same precedence for a lightweight
## on-screen indicator distinguishing "valid enemy troop", "valid enemy
## structure", and "open ground", per 09-ui-and-controls.md — no custom
## cursor art exists yet (placeholder-art rules apply), so this is a drawn
## marker at the mouse position rather than an OS cursor swap.
class_name InputController
extends Node2D

var state: MatchState
var owner_id: String
var squad_view: SquadView
var camera_controller: CameraController

## Set when a left-click lands on one of the local player's own base
## buildings (see precedence case 3 above); "" when nothing is selected.
## Purely a UI selection — never mutates sim state.
var selected_base_id: String = ""
## The specific building clicked (see selected_base_id) — "" whenever
## selected_base_id is "". client/hud/build_menu.gd keys off this (not just
## selected_base_id) so the build menu only ever shows for an actual HQ click,
## not any building on the base.
var selected_building_id: String = ""
## Set alongside selected_base_id, but only when the clicked building is
## Production-category (has its own ProductionQueue) — "" otherwise, even
## while selected_base_id stays set (e.g. clicking the HQ).
var selected_production_building_id: String = ""

## Build-menu placement mode (build order item 4): set by
## client/hud/build_menu.gd's start_placement() when the player picks a
## building from the menu. While non-empty, a left-click takes top priority
## over every other case above — it either commits CommandProcessor.
## place_building at the clicked hex (success clears placement mode) or pings
## red and stays in placement mode so the player can retry a different hex.
## Escape cancels outright. client/build_preview.gd (world-space, mirrors
## fog_of_war.gd's per-hex overlay approach) reads these two fields to
## highlight every currently-valid hex.
var pending_building_type: String = ""
var pending_base_id: String = ""

var _drag_active := false
var _drag_start := Vector2.ZERO
var _drag_current := Vector2.ZERO
## Control groups: group number (1-9) -> Array of squad ids, same convention
## as most RTS games. Squads that no longer exist are dropped lazily on
## recall rather than eagerly on death — this node never listens for squad
## removal.
var _control_groups: Dictionary = {}
var _owned_base_index := 0

## Pings for orders CommandProcessor rejected (unreachable, docked, etc.) so
## the player gets some feedback instead of a silently swallowed click.
var _failed_pings: Array = []

## Hover-preview state: only recomputed when the mouse crosses into a new
## hex (via _hover_hex_key), not every frame — CombatResolver.build_targets
## rebuilds the full target list, same cost CombatStateSystem's header
## comment already flags as too expensive to call every frame unthrottled.
var _hover_hex_key: String = ""
var _hover_kind: int = HoverKind.NONE

enum HoverKind { NONE, ENEMY_TROOP, ENEMY_STRUCTURE }

const DRAG_THRESHOLD := 6.0
const DRAG_FILL_COLOR := Color(1.0, 1.0, 1.0, 0.12)
const DRAG_BORDER_COLOR := Color(1.0, 1.0, 1.0, 0.8)
const FAILED_PING_DURATION := 0.6
const FAILED_PING_COLOR := Color(1.0, 0.25, 0.25, 0.9)
const FAILED_PING_RADIUS := 12.0
const HOVER_TROOP_COLOR := Color(1.0, 0.3, 0.3, 0.9)
const HOVER_STRUCTURE_COLOR := Color(1.0, 0.65, 0.15, 0.9)
const HOVER_RADIUS := 14.0
const WALL_CLICK_RADIUS := 10.0

func setup(p_state: MatchState, p_owner_id: String, p_squad_view: SquadView, p_camera_controller: CameraController) -> void:
	state = p_state
	owner_id = p_owner_id
	squad_view = p_squad_view
	camera_controller = p_camera_controller

func _process(delta: float) -> void:
	if not _drag_active:
		_update_hover(get_global_mouse_position())
	if _failed_pings.is_empty():
		return
	var i := _failed_pings.size() - 1
	while i >= 0:
		_failed_pings[i]["remaining"] -= delta
		if _failed_pings[i]["remaining"] <= 0.0:
			_failed_pings.remove_at(i)
		i -= 1
	if not _failed_pings.is_empty():
		queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	# Right-click never issues an order here (CameraController owns the right
	# button for panning) — it's purely a cancel: drop any in-progress
	# build-menu placement and close whatever building panel is open, per
	# 09-ui-and-controls.md's build-menu cancel affordance.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		pending_building_type = ""
		pending_base_id = ""
		_clear_building_selection()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_active = true
			_drag_start = get_global_mouse_position()
			_drag_current = _drag_start
		else:
			_on_left_release(event)
		queue_redraw()
		return
	if event is InputEventMouseMotion and _drag_active:
		_drag_current = get_global_mouse_position()
		queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			_jump_to_base(event.shift_pressed)
			return
		if event.keycode == KEY_ESCAPE and pending_building_type != "":
			pending_building_type = ""
			pending_base_id = ""
			return
		_handle_control_group_key(event)

## Called by client/hud/build_menu.gd when the player picks a building from
## the selected base's build menu — enters placement mode instead of
## building immediately, so the player can see/pick a valid hex first.
func start_placement(base_id: String, building_type: String) -> void:
	pending_base_id = base_id
	pending_building_type = building_type

func _on_left_release(event: InputEventMouseButton) -> void:
	_drag_active = false
	var release_pos := get_global_mouse_position()
	var shift := event.shift_pressed

	# Case 0 (highest priority): build-menu placement mode in progress —
	# every click either commits or pings until Escape/success clears it.
	# Wall is edge-keyed (no single hex of its own, see CombatTarget's own
	# hex_b doc comment), so it resolves the clicked edge instead of a hex.
	if pending_building_type == "wall":
		var edge := _edge_at_pixel(release_pos)
		var result: BuildingPlacement.Result = state.command_queue.submit(state, "place_wall", [pending_base_id, edge[0], edge[1], "", owner_id], owner_id) if not edge.is_empty() else BuildingPlacement.Result.OUT_OF_HEX_BOUNDS
		if result == BuildingPlacement.Result.OK:
			pending_building_type = ""
			pending_base_id = ""
			_clear_building_selection()
		else:
			_failed_pings.append({"pos": release_pos, "remaining": FAILED_PING_DURATION})
		return
	if pending_building_type != "":
		var hex := HexView.pixel_to_axial(release_pos)
		var result: BuildingPlacement.Result = state.command_queue.submit(state, "place_building", [pending_base_id, pending_building_type, hex, "", owner_id], owner_id)
		if result == BuildingPlacement.Result.OK:
			pending_building_type = ""
			pending_base_id = ""
			_clear_building_selection()
		else:
			_failed_pings.append({"pos": release_pos, "remaining": FAILED_PING_DURATION})
		return

	if _drag_start.distance_to(release_pos) > DRAG_THRESHOLD:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(release_pos)
		var friendly_ids: Array = []
		for squad in squad_view.squads_in_rect(rect):
			if squad.owner_id == owner_id:
				friendly_ids.append(squad.id)
		if not friendly_ids.is_empty():
			_clear_building_selection()
			if shift:
				squad_view.add_to_selection(friendly_ids)
			else:
				squad_view.select_set(friendly_ids)
		elif not shift:
			squad_view.clear_selection()
		return

	var clicked_squad := squad_view.squad_at_pixel(release_pos)
	if clicked_squad != null and clicked_squad.owner_id == owner_id:
		_clear_building_selection()
		if shift:
			squad_view.toggle_selection(clicked_squad.id)
		else:
			squad_view.select_only(clicked_squad.id)
		return

	# Case 2: an enemy target under the cursor with squads selected issues a
	# directed attack order instead of a move, per 09-ui-and-controls.md.
	var enemy_target := _target_at_pixel(release_pos)
	if enemy_target != null and not squad_view.selected_squad_ids.is_empty():
		var target_id := enemy_target.target_id()
		for squad_id in squad_view.selected_squad_ids.keys():
			var result: CommandProcessor.Result = state.command_queue.submit(state, "attack_target", [squad_id, target_id, owner_id], owner_id)
			if result != CommandProcessor.Result.OK:
				_failed_pings.append({"pos": release_pos, "remaining": FAILED_PING_DURATION})
		return

	# Case 3: one of the local player's own base buildings under the cursor
	# selects that base (build menu/population panel); if the specific
	# building clicked is a Production-category one, also selects it for
	# client/hud/production_panel.gd (its queue, its unlocked-troop buttons).
	# Re-clicking the already-selected building instead toggles it closed.
	# Clicking anywhere else clears both (click-away-to-close, same as case 4
	# falling through below).
	var found := _own_building_at(HexView.pixel_to_axial(release_pos))
	if not found.is_empty():
		var base: BaseInstance = found["base"]
		var building: BuildingInstance = found["building"]
		if building.id == selected_building_id:
			_clear_building_selection()
			return
		selected_base_id = base.id
		selected_building_id = building.id
		var def: Dictionary = state.building_defs.get(building.building_type, {})
		selected_production_building_id = building.id if def.get("category", "") == "Production" else ""
		return
	_clear_building_selection()

	if squad_view.selected_squad_ids.is_empty():
		return
	var target_hex := HexView.pixel_to_axial(release_pos)

	## Escorts of a commander that's also selected are skipped: the
	## commander's move_squad call already lock-steps the whole regiment
	## (see CommandProcessor.move_squad), so issuing them an individual
	## move too would fight with that lock-step move.
	var skip_ids: Dictionary = {}
	for regiment in state.regiments:
		if squad_view.selected_squad_ids.has(regiment.commander_id):
			for member_id in regiment.squad_ids:
				skip_ids[member_id] = true

	var index := 0
	for squad_id in squad_view.selected_squad_ids.keys():
		if skip_ids.has(squad_id):
			continue
		var goal := _formation_hex(target_hex, index)
		var result: CommandProcessor.Result = state.command_queue.submit(state, "move_squad", [squad_id, goal, owner_id], owner_id)
		if result != CommandProcessor.Result.OK:
			_failed_pings.append({"pos": HexView.axial_to_pixel(goal), "remaining": FAILED_PING_DURATION})
		index += 1
	# A move order (unlike an attack order) deselects afterward — the player
	# asked to click-select, click-to-move, then be done, rather than keep
	# babysitting the same selection.
	squad_view.clear_selection()

## Clears every building/base UI-selection field together (never partially —
## a stale selected_building_id with selected_base_id/
## selected_production_building_id already blanked would leave build_menu.gd/
## production_panel.gd unable to tell "nothing selected" from "selected build
## is gone"). Used by every deselect path: right-click, selecting a squad, a
## successful build-menu placement, and re-clicking an already-selected
## building.
func _clear_building_selection() -> void:
	selected_base_id = ""
	selected_building_id = ""
	selected_production_building_id = ""

## The live enemy CombatTarget (troop/squad, building, or Wall edge) at
## `pos`, or null. Rebuilds the full target list fresh — acceptable on a
## click/hex-change, not a per-frame cost (see _update_hover's throttling).
## Wall edges have no single occupied hex, so they're matched by proximity to
## their drawn segment (HexView.edge_segment, same geometry base_view.gd
## already draws walls with) rather than by hex equality.
func _target_at_pixel(pos: Vector2) -> CombatTarget:
	var targets := CombatResolver.build_targets(state.squads, state.bases, state.troops_by_id, state.grid, state.troop_defs, state.building_defs, {}, state.standalone_buildings)
	var hex := HexView.pixel_to_axial(pos)
	for target in targets:
		if target.owner_id == owner_id or not target.is_alive():
			continue
		if target.hex_b != null:
			var segment := HexView.edge_segment(target.hex, target.hex_b)
			if Geometry2D.get_closest_point_to_segment(pos, segment[0], segment[1]).distance_to(pos) <= WALL_CLICK_RADIUS:
				return target
			continue
		if target.hex.equals(hex):
			return target
	return null

## The two hexes bordering the edge nearest `pos` — the hex under the cursor
## paired with whichever of its 6 neighbors' shared edge segment is closest,
## same Geometry2D.get_closest_point_to_segment proximity test
## _target_at_pixel already uses for an existing Wall's click hit-test.
## Always resolves to some edge (used only while already in Wall placement
## mode, where any click should snap to its nearest edge) — [] only if
## somehow called with no grid.
func _edge_at_pixel(pos: Vector2) -> Array:
	var hex := HexView.pixel_to_axial(pos)
	var best_neighbor: HexCoord = null
	var best_dist := INF
	for direction in range(6):
		var neighbor := HexCoord.neighbor(hex, direction)
		var segment := HexView.edge_segment(hex, neighbor)
		var dist := Geometry2D.get_closest_point_to_segment(pos, segment[0], segment[1]).distance_to(pos)
		if dist < best_dist:
			best_dist = dist
			best_neighbor = neighbor
	if best_neighbor == null:
		return []
	return [hex, best_neighbor]

## {"base": BaseInstance, "building": BuildingInstance} for the local
## player's own base building (any type) occupying `hex`, or {} if none.
## Standalone buildings/Walls have no owning base and never match.
func _own_building_at(hex: HexCoord) -> Dictionary:
	for base in state.bases:
		if base.owner_id != owner_id:
			continue
		for building in base.buildings:
			if building.hex != null and building.hex.equals(hex):
				return {"base": base, "building": building}
	return {}

## Recomputes _hover_kind only when the mouse has crossed into a different
## hex since the last check — see the field's own doc comment on why this
## isn't done unconditionally every frame.
func _update_hover(pos: Vector2) -> void:
	var hex := HexView.pixel_to_axial(pos)
	var key := hex.to_key()
	if key == _hover_hex_key:
		return
	_hover_hex_key = key
	var target := _target_at_pixel(pos)
	if target == null:
		_hover_kind = HoverKind.NONE
	elif target.kind == CombatTarget.Kind.SQUAD:
		_hover_kind = HoverKind.ENEMY_TROOP
	else:
		_hover_kind = HoverKind.ENEMY_STRUCTURE
	queue_redraw()

func _handle_control_group_key(event: InputEventKey) -> void:
	var group := _digit_for_keycode(event.keycode)
	if group == -1:
		return
	if event.ctrl_pressed:
		_control_groups[group] = squad_view.selected_squad_ids.keys()
		return
	var live_ids: Array = []
	for id in _control_groups.get(group, []):
		if state.find_squad(id) != null:
			live_ids.append(id)
	_control_groups[group] = live_ids
	squad_view.select_set(live_ids)

func _digit_for_keycode(keycode: int) -> int:
	if keycode >= KEY_1 and keycode <= KEY_9:
		return keycode - KEY_1 + 1
	return -1

## Cycles the camera through the local player's own bases; Shift reverses
## direction. Wraps via wrapi so Tab past either end loops around.
func _jump_to_base(reverse: bool) -> void:
	var owned_bases: Array[BaseInstance] = []
	for base in state.bases:
		if base.owner_id == owner_id:
			owned_bases.append(base)
	if owned_bases.is_empty():
		return
	_owned_base_index = wrapi(_owned_base_index + (-1 if reverse else 1), 0, owned_bases.size())
	camera_controller.center_on(HexView.axial_to_pixel(owned_bases[_owned_base_index].hex_coord))

## Distinct nearby destination for the i-th squad in a multi-move so a group
## doesn't stack onto one tile — index 0 keeps the exact clicked hex, later
## indices ring outward via HexCoord.neighbor().
func _formation_hex(target_hex: HexCoord, index: int) -> HexCoord:
	if index == 0:
		return target_hex
	var ring := (index - 1) / 6 + 1
	var direction := (index - 1) % 6
	var hex := target_hex
	for i in range(ring):
		hex = HexCoord.neighbor(hex, direction)
	return hex

func _draw() -> void:
	if _drag_active and _drag_start.distance_to(_drag_current) > DRAG_THRESHOLD:
		var rect := Rect2(_drag_start, Vector2.ZERO).expand(_drag_current)
		draw_rect(rect, DRAG_FILL_COLOR, true)
		draw_rect(rect, DRAG_BORDER_COLOR, false, 1.0)

	for ping in _failed_pings:
		var alpha: float = clampf(float(ping["remaining"]) / FAILED_PING_DURATION, 0.0, 1.0)
		var color := FAILED_PING_COLOR
		color.a *= alpha
		var pos: Vector2 = ping["pos"]
		draw_line(pos + Vector2(-FAILED_PING_RADIUS, -FAILED_PING_RADIUS), pos + Vector2(FAILED_PING_RADIUS, FAILED_PING_RADIUS), color, 2.0)
		draw_line(pos + Vector2(-FAILED_PING_RADIUS, FAILED_PING_RADIUS), pos + Vector2(FAILED_PING_RADIUS, -FAILED_PING_RADIUS), color, 2.0)

	if _hover_kind != HoverKind.NONE:
		var color: Color = HOVER_TROOP_COLOR if _hover_kind == HoverKind.ENEMY_TROOP else HOVER_STRUCTURE_COLOR
		draw_arc(get_global_mouse_position(), HOVER_RADIUS, 0.0, TAU, 20, color, 2.0)
