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

const HEIGHT := 72.0
const EXPANDED_EXTRA_HEIGHT := 54.0
const REFRESH_INTERVAL := 0.25

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
var _building_labels: Dictionary = {} ## ResourceType.Type -> Label ("2x Level 1 Mine, ...")
var _squads_label: Label
var _commanders_label: Label

var _prev_amount: Dictionary = {} ## ResourceType.Type -> int, last displayed value (for count-up)
var _prev_deficit: Dictionary = {} ## ResourceType.Type -> bool, last deficit state (for the pop-on-entry flash)

var _expanded := false
var _refresh_accum := 0.0

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
		col.add_child(detail)
		_detail_labels[type] = detail

		var buildings := UITheme.muted_label("")
		buildings.add_theme_font_size_override("font_size", UITheme.FONT_SMALL)
		buildings.visible = false
		col.add_child(buildings)
		_building_labels[type] = buildings

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

## Left click toggles the expanded rows; STOP (see class doc) means this is
## the only thing on the strip that ever sees mouse input.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_expanded = not _expanded
		offset_bottom = HEIGHT + (EXPANDED_EXTRA_HEIGHT if _expanded else 0.0)
		for type in _detail_labels:
			_detail_labels[type].visible = _expanded
			_building_labels[type].visible = _expanded
		if _expanded:
			_refresh_accum = REFRESH_INTERVAL
		accept_event()

func _process(delta: float) -> void:
	if state == null:
		return
	var pool := state.pool_for(owner_id)
	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var label: Label = _res_labels[type]
		var amount := int(round(pool.get_amount(type)))
		var deficit := pool.is_deficit(type)
		label.add_theme_color_override("font_color", UITheme.DANGER if deficit else UITheme.RESOURCE_COLOR[type])

		var prev_amount: int = _prev_amount.get(type, amount)
		if prev_amount != amount:
			UIJuice.count_up(label, prev_amount, amount)
			_prev_amount[type] = amount
		elif label.text.is_empty():
			label.text = "%d" % amount

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

## Updates the two per-column detail rows in place (no node rebuild needed —
## the labels are permanent, only their text changes) from the owner's live
## production total per resource plus a count of producing buildings grouped
## by (type, level).
func _refresh_breakdown(owned_bases: Array[BaseInstance]) -> void:
	var totals: Dictionary = ProductionOutputSystem.compute_production(owned_bases, state.base_defs, state.building_defs).get(owner_id, {})
	var groups_by_type := _compute_producer_groups(owned_bases)
	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var total := float(totals.get(type, 0.0))
		_detail_labels[type].text = "%+.1f / tick" % total
		_building_labels[type].text = _format_groups(groups_by_type.get(type, []))

## "2x Level 1 Mine, 3x Level 2 Mine" (levels ascending), or "No producers"
## once none of the owner's buildings output this resource.
func _format_groups(groups: Array) -> String:
	if groups.is_empty():
		return "No producers"
	var parts: Array[String] = []
	for group in groups:
		parts.append("%dx Lv%d %s" % [group["count"], group["level"], group["name"]])
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
