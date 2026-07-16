## Top-of-screen resource bar: the local player's Food/Steel/Fuel/Stone/Wood
## totals (09-ui-and-controls.md's order), each in its UITheme resource color,
## recolored to DANGER while in deficit (ResourceType.can_deficit_drain — Food/
## Fuel only). On the right, the squad and commander caps (SquadCap) — the one
## HUD spot they're surfaced — turning amber at the cap. Built from themed
## Control nodes (a UITheme panel + labels) rather than manual draw_string, so
## it never overflows and shares the HUD's look. Reads state.pool_for(owner_id)
## / SquadCap live every frame, same poll-don't-signal approach as every other
## client/ view.
##
## Clicking the bar grows it deeper: two extra rows appear under each resource
## column, in place — live per-tick total (ProductionOutputSystem.
## compute_production, the same math the economy tick itself applies) then a
## "2x Level 1 Mine, 3x Level 2 Mine" style count of producing buildings,
## grouped by (type, level). Clicking again collapses back to the single row.
## Fixed extra height (not measured from content) since the two rows are
## always exactly two single-line labels. Root switches from IGNORE to STOP so
## this click doesn't also fall through to a world move order (hud_layer.gd's
## general "HUD panels swallow their own clicks" contract, which this view was
## the one exception to until it had something clickable).
class_name ResourceBar
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController
var _last_map_click_count := 0

const HEIGHT := 72.0
const REFRESH_INTERVAL := 0.25
const COLUMN_WIDTH := 150.0
## Expanded height is measured from content, not fixed — a resource with
## several producer/consumer groups (e.g. "1x Lv1 Farm" + "2x Lv2 Farm" + ...,
## or "Rifleman: -3.0/tick" + "Tonk: -8.0/tick" + ...) lists one group per
## line instead of comma-joining onto one row (the comma-joined version
## clipped everything past the first group), so how tall the bar needs to be
## depends on whichever column has the most producer + consumer groups.
const EXPANDED_BASE_HEIGHT := 40.0 ## the "+N.N / tick" or "-N.N / tick used" row, always present (one of each)
const EXPANDED_LINE_HEIGHT := 16.0 ## one producer-group or consumer-group line
const EXPANDED_BOTTOM_PADDING := 10.0

## Display order + labels per 09-ui-and-controls.md's Resource HUD line.
const DISPLAY_ORDER: Array[Array] = [
	[ResourceType.Type.FOOD, "Food"],
	[ResourceType.Type.STEEL, "Steel"],
	[ResourceType.Type.FUEL, "Fuel"],
	[ResourceType.Type.STONE, "Stone"],
	[ResourceType.Type.WOOD, "Wood"],
]

var _res_labels: Dictionary = {} ## ResourceType.Type -> Label (top row, existing amount)
var _detail_labels: Dictionary = {} ## ResourceType.Type -> Label ("+N.N / tick")
var _building_boxes: Dictionary = {} ## ResourceType.Type -> VBoxContainer, one Label per producer group
var _usage_labels: Dictionary = {} ## ResourceType.Type -> Label, total troop upkeep ("-N.N / tick")
var _usage_boxes: Dictionary = {} ## ResourceType.Type -> VBoxContainer, one Label per consuming troop type
var _squads_label: Label
var _commanders_label: Label
var _status_label: Label ## centered overlay for match-status banners (waiting/desync)

var _prev_amount: Dictionary = {} ## ResourceType.Type -> int, last displayed value (for count-up)
var _prev_deficit: Dictionary = {} ## ResourceType.Type -> bool, last deficit state (for the pop-on-entry flash)

var _expanded := false
var _refresh_accum := 0.0

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller
	_last_map_click_count = input_controller.map_click_count
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 0.0
	offset_bottom = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_STOP

	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# IGNORE so hit-testing falls through to the root Control's own
	# _gui_input (the click-to-expand handler) instead of stopping here.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Fixed width so the expanded detail/building rows (which can be much
		# longer than "Food 1234") never widen the column and shove the other
		# resources apart — they clip/ellipsize instead, see below.
		col.custom_minimum_size.x = COLUMN_WIDTH

		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(UITheme.resource_icon(type, 22.0))

		var label := UITheme.body_label("")
		label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
		head.add_child(label)
		_res_labels[type] = label
		col.add_child(head)

		var detail := UITheme.muted_label("")
		detail.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		detail.visible = false
		detail.clip_text = true
		detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(detail)
		_detail_labels[type] = detail

		var buildings_box := VBoxContainer.new()
		buildings_box.add_theme_constant_override("separation", 0)
		buildings_box.visible = false
		buildings_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(buildings_box)
		_building_boxes[type] = buildings_box

		var usage := UITheme.muted_label("")
		usage.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		usage.visible = false
		usage.clip_text = true
		usage.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(usage)
		_usage_labels[type] = usage

		var usage_box := VBoxContainer.new()
		usage_box.add_theme_constant_override("separation", 0)
		usage_box.visible = false
		usage_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(usage_box)
		_usage_boxes[type] = usage_box

		row.add_child(col)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_squads_label = UITheme.body_label("")
	_squads_label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
	row.add_child(_squads_label)

	_commanders_label = UITheme.body_label("")
	_commanders_label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
	row.add_child(_commanders_label)

	# Match-status banner (waiting for players / desync halt). Overlaid centered
	# on top of the bar's own panel so it always has the opaque panel background
	# behind it — the old free-floating label sat over the world/fog and its
	# text was unreadable against the black unexplored area (set_status below is
	# what main.gd drives instead of a separate CanvasLayer). Added last so it
	# draws over the resource row; IGNORE mouse so the click-to-expand still
	# works through it.
	var status_center := CenterContainer.new()
	status_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(status_center)

	var status_box := UITheme.panel()
	status_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_box.visible = false
	status_center.add_child(status_box)

	_status_label = UITheme.body_label("")
	_status_label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_box.add_child(_status_label)

## Shows (or hides, on empty text) the centered status banner. `danger` recolors
## it DANGER for a halting condition (desync) versus normal text for a transient
## one (waiting for players). main.gd calls this instead of maintaining its own
## screen-space labels, so the message inherits the bar's opaque background and
## stays legible over any part of the map.
func set_status(text: String, danger: bool = false) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", UITheme.DANGER if danger else UITheme.TEXT)
	_status_label.get_parent().visible = not text.is_empty()

## Left click toggles the expanded rows; STOP (see class doc) means this is
## the only thing on the strip that ever sees mouse input.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_expanded(not _expanded)
		# This click never reaches InputController's _unhandled_input (STOP
		# swallows it here), so it can't double-count against map_click_count
		# — no need to bump _last_map_click_count.
		accept_event()

func _set_expanded(value: bool) -> void:
	_expanded = value
	# Exact height isn't known until _refresh_breakdown runs (it depends on
	# each column's producer-group count) — this is just a same-frame guess
	# (one line's worth) so the bar doesn't flash 0-height for a frame; the
	# forced refresh below corrects it before the player sees the expanded
	# rows render.
	offset_bottom = HEIGHT + (2.0 * EXPANDED_BASE_HEIGHT + 2.0 * EXPANDED_LINE_HEIGHT + EXPANDED_BOTTOM_PADDING if _expanded else 0.0)
	for type in _detail_labels:
		_detail_labels[type].visible = _expanded
		_building_boxes[type].visible = _expanded
		_usage_labels[type].visible = _expanded
		_usage_boxes[type].visible = _expanded
	if _expanded:
		_refresh_accum = REFRESH_INTERVAL

func _process(delta: float) -> void:
	if state == null:
		return
	if _expanded and input_controller.map_click_count != _last_map_click_count:
		_last_map_click_count = input_controller.map_click_count
		_set_expanded(false)
	var pool := state.pool_for(owner_id)
	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var label: Label = _res_labels[type]
		var amount := int(round(pool.get_amount(type)))
		var deficit := pool.is_deficit(type)
		label.add_theme_color_override("font_color", UITheme.DANGER if deficit else UITheme.RESOURCE_COLOR[type])

		# Bug fix: _prev_amount.get(type, amount) used to default the "previous"
		# value to `amount` itself when the key was still missing — so
		# prev_amount != amount could never be true on the very frame that
		# would've stored the key, and it's only ever stored inside that same
		# branch. Net effect: the label was set once (below, when text was
		# still empty) and then frozen forever, no matter how the pool changed.
		if not _prev_amount.has(type):
			_prev_amount[type] = amount
			label.text = "%d" % amount
		elif _prev_amount[type] != amount:
			UIJuice.count_up(label, _prev_amount[type], amount)
			_prev_amount[type] = amount

		if deficit and not _prev_deficit.get(type, false):
			UIJuice.pop(label.get_parent())
		_prev_deficit[type] = deficit

	var owned_bases := state.bases_owned_by(owner_id)
	var squads_used := _owned_squad_count()
	var squads_max := SquadCap.max_squads(owned_bases)
	_squads_label.text = "Squads %d/%d" % [squads_used, squads_max]
	_squads_label.add_theme_color_override("font_color", UITheme.WARNING if squads_used >= squads_max else UITheme.TEXT)

	var commanders_max := SquadCap.max_commanders(owned_bases, state.building_defs)
	var commanders_used := state.commander_count(owner_id)
	_commanders_label.text = "Cmdrs %d/%d" % [commanders_used, commanders_max]
	_commanders_label.add_theme_color_override("font_color", UITheme.WARNING if commanders_used >= commanders_max and commanders_max > 0 else UITheme.TEXT)

	if _expanded:
		_refresh_accum += delta
		if _refresh_accum >= REFRESH_INTERVAL:
			_refresh_accum = 0.0
			_refresh_breakdown(owned_bases)

## Updates the per-column detail row (live per-tick total) and rebuilds the
## producer-group list (one Label per line, not comma-joined onto a single
## row — a resource with several producer groups used to clip everything
## past the first) from the owner's live production total per resource plus
## a count of producing buildings grouped by (type, level). Also resizes the
## bar to fit however many lines the tallest column needs.
func _refresh_breakdown(owned_bases: Array[BaseInstance]) -> void:
	var summary := EconomySummary.compute(state, owner_id)
	var totals: Dictionary = summary["production"]
	var groups_by_type := _compute_producer_groups(owned_bases)
	var auras: Dictionary = summary["auras"]
	var upkeep_by_type: Dictionary = UpkeepSystem.compute_upkeep_by_troop_type(state.squads, state.troop_defs, auras).get(owner_id, {})
	var max_lines := 1
	var max_usage_lines := 1
	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var total := float(totals.get(type, 0.0))
		_detail_labels[type].text = "%+.1f / tick" % total
		var lines := _group_lines(groups_by_type.get(type, []))
		max_lines = max(max_lines, lines.size())
		_rebuild_building_lines(_building_boxes[type], lines)

		var by_troop: Dictionary = upkeep_by_type.get(type, {})
		var usage_total := 0.0
		for troop_amount in by_troop.values():
			usage_total += float(troop_amount)
		_usage_labels[type].text = "-%.1f / tick used" % usage_total
		var usage_lines := _usage_lines(by_troop)
		max_usage_lines = max(max_usage_lines, usage_lines.size())
		_rebuild_building_lines(_usage_boxes[type], usage_lines)
	if _expanded:
		offset_bottom = HEIGHT + 2.0 * EXPANDED_BASE_HEIGHT + float(max_lines + max_usage_lines) * EXPANDED_LINE_HEIGHT + EXPANDED_BOTTOM_PADDING

## One line per troop type drawing this resource, e.g. "Rifleman: -3.0/tick"
## (sorted by usage descending, biggest draw first), or a single "No usage"
## line once nothing owned consumes this resource — mirrors _group_lines'
## fallback for the production side.
func _usage_lines(by_troop: Dictionary) -> Array[String]:
	if by_troop.is_empty():
		return ["No usage"]
	var entries: Array = by_troop.keys()
	entries.sort_custom(func(a, b): return float(by_troop[a]) > float(by_troop[b]))
	var lines: Array[String] = []
	for troop_type in entries:
		var name := String(state.troop_defs.get(troop_type, {}).get("name", String(troop_type).capitalize()))
		lines.append("%s: -%.1f/tick" % [name, float(by_troop[troop_type])])
	return lines

## One line per group, e.g. "2x Lv1 Mine" / "3x Lv2 Mine" (levels ascending),
## or a single "No producers" line once none of the owner's buildings output
## this resource.
func _group_lines(groups: Array) -> Array[String]:
	if groups.is_empty():
		return ["No producers"]
	var lines: Array[String] = []
	for group in groups:
		lines.append("%dx Lv%d %s" % [group["count"], group["level"], group["name"]])
	return lines

## Clears `box` and adds one clipped/ellipsized muted Label per line — full
## rebuild rather than reusing labels since the group count varies tick to
## tick (same "torn down and rebuilt" pattern building_panel.gd already uses
## for its own variable-length lists).
func _rebuild_building_lines(box: VBoxContainer, lines: Array[String]) -> void:
	for child in box.get_children():
		child.queue_free()
	for line in lines:
		var lbl := UITheme.muted_label(line)
		lbl.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		lbl.clip_text = true
		lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(lbl)

## ResourceType.Type -> Array[{name, level, count}] (sorted by level ascending)
## for every Resource-category building the owner has that isn't a ruin,
## grouped by (building_type, level) the same way the display wants it
## collapsed. Ruin gate mirrors ProductionOutputSystem.compute_production's
## own (a ruin produces nothing, so it shouldn't count toward "producing").
func _compute_producer_groups(owned_bases: Array[BaseInstance]) -> Dictionary:
	var per_type: Dictionary = {} ## type -> {"building_type|level": {name, level, count}}
	for base in owned_bases:
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = state.building_defs.get(building.building_type, {})
			var output := BuildingStats.resource_output(def, building.level, state.building_defs)
			if output.is_empty():
				continue
			var name := String(def.get("name", building.building_type.capitalize()))
			for type in output:
				var groups: Dictionary = per_type.get(type, {})
				var key := "%s|%d" % [building.building_type, building.level]
				var group: Dictionary = groups.get(key, {"name": name, "level": building.level, "count": 0})
				group["count"] = int(group["count"]) + 1
				groups[key] = group
				per_type[type] = groups
	for type in per_type:
		var groups: Array = per_type[type].values()
		groups.sort_custom(func(a, b): return a["level"] < b["level"])
		per_type[type] = groups
	return per_type

func _owned_squad_count() -> int:
	var count := 0
	for squad in state.squads:
		if squad.owner_id == owner_id:
			count += 1
	return count
