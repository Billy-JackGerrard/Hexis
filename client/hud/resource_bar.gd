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
## Clicking the bar drops a breakdown panel beneath it: each resource's live
## per-tick total (ProductionOutputSystem.compute_production, the same math
## the economy tick itself applies) plus a "2x Level 1 Mine, 3x Level 2 Mine"
## style count of the owner's producing buildings, grouped by (type, level).
## Clicking again collapses it. The root switches from IGNORE to STOP so this
## click doesn't also fall through to a world move order (hud_layer.gd's
## general "HUD panels swallow their own clicks" contract, which this view was
## the one exception to until it had something clickable).
class_name ResourceBar
extends Control

var state: MatchState
var owner_id: String

const HEIGHT := 72.0
const BREAKDOWN_WIDTH := 340.0
const BREAKDOWN_REFRESH_INTERVAL := 0.25
## UITheme.create_theme()'s PanelContainer stylebox uses a flat 16px content
## margin on every side — doubled here since we size the panel from its
## content's height, top + bottom.
const BREAKDOWN_PANEL_VERTICAL_PADDING := 32.0

## Display order + labels per 09-ui-and-controls.md's Resource HUD line.
const DISPLAY_ORDER: Array[Array] = [
	[ResourceType.Type.FOOD, "Food"],
	[ResourceType.Type.STEEL, "Steel"],
	[ResourceType.Type.FUEL, "Fuel"],
	[ResourceType.Type.STONE, "Stone"],
	[ResourceType.Type.WOOD, "Wood"],
]

var _res_labels: Dictionary = {} ## ResourceType.Type -> Label
var _squads_label: Label
var _commanders_label: Label

var _breakdown_panel: PanelContainer
var _breakdown_content: VBoxContainer
var _breakdown_expanded := false
var _breakdown_refresh_accum := 0.0

func setup(p_state: MatchState, p_owner_id: String) -> void:
	state = p_state
	owner_id = p_owner_id
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
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# IGNORE so hit-testing falls through to the root Control's own
	# _gui_input (the click-to-expand handler) instead of stopping here.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var label := UITheme.body_label("")
		label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
		row.add_child(label)
		_res_labels[type] = label

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_squads_label = UITheme.body_label("")
	_squads_label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
	row.add_child(_squads_label)

	_commanders_label = UITheme.body_label("")
	_commanders_label.add_theme_font_size_override("font_size", UITheme.FONT_BAR)
	row.add_child(_commanders_label)

	_breakdown_panel = UITheme.panel()
	_breakdown_panel.position = Vector2(0.0, HEIGHT)
	_breakdown_panel.custom_minimum_size = Vector2(BREAKDOWN_WIDTH, 0.0)
	_breakdown_panel.visible = false
	add_child(_breakdown_panel)

	_breakdown_content = VBoxContainer.new()
	_breakdown_content.add_theme_constant_override("separation", 8)
	_breakdown_panel.add_child(_breakdown_content)

## Left click toggles the breakdown dropdown; STOP (see class doc) means this
## is the only thing on the strip that ever sees mouse input.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_breakdown_expanded = not _breakdown_expanded
		_breakdown_panel.visible = _breakdown_expanded
		if _breakdown_expanded:
			_breakdown_refresh_accum = BREAKDOWN_REFRESH_INTERVAL
			accept_event()

func _process(delta: float) -> void:
	if state == null:
		return
	var pool := state.pool_for(owner_id)
	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var label: Label = _res_labels[type]
		label.text = "%s %d" % [entry[1], int(round(pool.get_amount(type)))]
		label.add_theme_color_override("font_color", UITheme.DANGER if pool.is_deficit(type) else UITheme.RESOURCE_COLOR[type])

	var owned_bases := state.bases_owned_by(owner_id)
	var squads_used := _owned_squad_count()
	var squads_max := SquadCap.max_squads(owned_bases)
	_squads_label.text = "Squads %d/%d" % [squads_used, squads_max]
	_squads_label.add_theme_color_override("font_color", UITheme.WARNING if squads_used >= squads_max else UITheme.TEXT)

	var commanders_max := SquadCap.max_commanders(owned_bases, state.building_defs)
	var commanders_used := state.commander_count(owner_id)
	_commanders_label.text = "Cmdrs %d/%d" % [commanders_used, commanders_max]
	_commanders_label.add_theme_color_override("font_color", UITheme.WARNING if commanders_used >= commanders_max and commanders_max > 0 else UITheme.TEXT)

	if _breakdown_expanded:
		_breakdown_refresh_accum += delta
		if _breakdown_refresh_accum >= BREAKDOWN_REFRESH_INTERVAL:
			_breakdown_refresh_accum = 0.0
			_refresh_breakdown()

## Rebuilds the dropdown's content: one block per resource type in
## DISPLAY_ORDER (its live per-tick total, colored the same as the bar's own
## label, then a muted line grouping its producing buildings by type+level).
## Rebuilt wholesale on every refresh tick rather than diffed in place — the
## same "just rebuild it, it's cheap" call building_panel's queue status makes
## — then the panel's height is recomputed from _breakdown_content's minimum
## size (not _breakdown_panel's own — PanelContainer.get_combined_minimum_size()
## reads a size cache that never gets invalidated while the panel is/was
## hidden, so it sticks at (0, 0) even after content is added and the panel is
## shown again; the inner VBoxContainer's own cache doesn't have this problem).
func _refresh_breakdown() -> void:
	var owned_bases := state.bases_owned_by(owner_id)
	var totals: Dictionary = ProductionOutputSystem.compute_production(owned_bases, state.base_defs, state.building_defs).get(owner_id, {})
	var groups_by_type := _compute_producer_groups(owned_bases)

	for child in _breakdown_content.get_children():
		child.queue_free()

	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var label_text: String = entry[1]
		var total := float(totals.get(type, 0.0))

		var total_label := UITheme.body_label("%s  %+.1f / tick" % [label_text, total])
		total_label.add_theme_color_override("font_color", UITheme.RESOURCE_COLOR[type])
		_breakdown_content.add_child(total_label)

		var groups: Array = groups_by_type.get(type, [])
		var buildings_label := UITheme.muted_label(_format_groups(groups))
		buildings_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_breakdown_content.add_child(buildings_label)

	var content_height := _breakdown_content.get_combined_minimum_size().y
	_breakdown_panel.size = Vector2(BREAKDOWN_WIDTH, content_height + BREAKDOWN_PANEL_VERTICAL_PADDING)

## "2x Level 1 Mine, 3x Level 2 Mine" (levels ascending), or "No producing
## buildings" once none of the owner's buildings output this resource.
func _format_groups(groups: Array) -> String:
	if groups.is_empty():
		return "No producing buildings"
	var parts: Array[String] = []
	for group in groups:
		parts.append("%dx Level %d %s" % [group["count"], group["level"], group["name"]])
	return ", ".join(parts)

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
