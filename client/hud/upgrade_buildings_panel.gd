## Modal overview opened from the HQ's BuildingPanel body ("Upgrade Buildings"
## button, HQ-only) — every building the local player owns across every base
## plus their standalone buildings, grouped by category then building_type,
## one row per building instance with its own Upgrade button. Exists because
## BuildingPanel's own Level/Upgrade row only ever covers the one currently
## selected building; this is the "upgrade everything from one place" view.
## Centered overlay rather than docked like BuildingPanel/TroopInfoPanel/
## SquadPanel, since it isn't tied to a map selection.
##
## The owning base's name is shown once, as a subtitle under the header, only
## when every listed building belongs to that single base (the common case) —
## repeating it on every row would be pure noise. A player with multiple bases
## instead gets it back per-row, since it's the only thing telling those rows
## apart. Either way a standalone building (Tower, ...) still says
## "Standalone" on its own row — that's real information, not repetition.
class_name UpgradeBuildingsPanel
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

const WIDTH := 520.0
const MARGIN := 40.0
const REFRESH_INTERVAL := 0.25

## Category grouping/order + display labels, same idea as BuildingPanel's
## _BUILD_CATEGORY_ORDER/_BUILD_CATEGORY_LABELS but extended with
## "Infrastructure" (Road/Bridge/Dock — never shown in the BUILD menu since
## they're HQ-ordered/standalone, but they're still ownable, upgradable
## buildings that belong somewhere in this list).
const _CATEGORY_ORDER := ["Resource", "Support", "Defensive", "Production", "Infrastructure"]
const _CATEGORY_LABELS := {
	"Resource": "RESOURCES",
	"Defensive": "DEFENCE",
	"Production": "TROOPS",
	"Support": "SUPPORT",
	"Infrastructure": "INFRASTRUCTURE",
}

var _content: VBoxContainer
var _scroll: ScrollContainer
var _reason_label: Label
var _header_subtitle: Label
var _option_updaters: Array = []

const SCROLL_STEP := 40

func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.scroll_vertical -= SCROLL_STEP
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.scroll_vertical += SCROLL_STEP
			get_viewport().set_input_as_handled()

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller

	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -WIDTH / 2.0
	offset_right = WIDTH / 2.0
	offset_top = -MARGIN * 6.0
	offset_bottom = MARGIN * 6.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	main_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	panel.add_child(main_vbox)

	var header_row := HBoxContainer.new()
	header_row.mouse_filter = Control.MOUSE_FILTER_PASS
	var title := UITheme.title_label("UPGRADE BUILDINGS")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	var close_button := UITheme.action_button("Close", "")
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_button.custom_minimum_size = Vector2(120, 0)
	close_button.pressed.connect(close)
	header_row.add_child(close_button)
	main_vbox.add_child(header_row)

	_header_subtitle = UITheme.subtitle_label("")
	_header_subtitle.visible = false
	main_vbox.add_child(_header_subtitle)

	main_vbox.add_child(HSeparator.new())

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Scrolled manually (see _on_scroll_gui_input), same reason as
	# BuildingPanel's own _scroll: ScrollContainer's built-in wheel handling
	# doesn't consume the event once it's at the top/bottom of the list, so an
	# unhandled wheel tick there falls through to the world camera's zoom.
	_scroll.gui_input.connect(_on_scroll_gui_input)
	main_vbox.add_child(_scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_scroll.add_child(_content)

	_reason_label = UITheme.danger_label("")
	_reason_label.visible = false
	main_vbox.add_child(_reason_label)

func open() -> void:
	visible = true
	_rebuild()

func close() -> void:
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

var _refresh_accum := 0.0

func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_eligibility()

func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	_option_updaters.clear()
	_reason_label.visible = false
	_reason_label.text = ""
	_refresh_accum = 0.0

	# category -> building_type -> [{building, base}], base null for a
	# standalone building.
	var by_category: Dictionary = {}
	var category_order: Array[String] = []
	var seen_bases: Dictionary = {} ## base.id -> BaseInstance, only for bases that actually contributed a row

	for base in state.bases_owned_by(owner_id):
		for building in base.buildings:
			_bucket(by_category, category_order, building, base, seen_bases)
	for building in state.standalone_buildings:
		if building.owner_id != owner_id:
			continue
		_bucket(by_category, category_order, building, null, seen_bases)

	if category_order.is_empty():
		_header_subtitle.visible = false
		_content.add_child(UITheme.muted_label("No buildings owned"))
		return

	# Repeating the base's name on every single row is only useful once
	# there's more than one base to tell rows apart by — with just one (the
	# common case), it's shown once up top instead and rows just say "Lvl N".
	var show_location := seen_bases.size() > 1
	if seen_bases.size() == 1:
		var only_base: BaseInstance = seen_bases.values()[0]
		_header_subtitle.text = only_base.display_name if only_base.display_name != "" else only_base.base_def_id.capitalize()
		_header_subtitle.visible = true
	else:
		_header_subtitle.visible = false

	category_order.sort_custom(func(a, b): return _category_rank(a) < _category_rank(b))
	for category in category_order:
		_content.add_child(UITheme.header_label(_CATEGORY_LABELS.get(category, String(category).to_upper())))
		var by_type: Dictionary = by_category[category]
		var types: Array = by_type.keys()
		types.sort()
		for building_type in types:
			var def: Dictionary = state.building_defs.get(building_type, {})
			_content.add_child(UITheme.subheader_label(String(def.get("name", String(building_type).capitalize()))))
			for entry in by_type[building_type]:
				_add_building_row(entry["building"], entry["base"], def, show_location)

	_refresh_eligibility()

## Ruined buildings can't be upgraded (can_upgrade_building rejects them
## outright — they need Rebuild instead, from the building's own panel) so
## this list — upgrade candidates only — just omits them entirely.
func _bucket(by_category: Dictionary, category_order: Array[String], building: BuildingInstance, base: BaseInstance, seen_bases: Dictionary) -> void:
	if building.is_ruin:
		return
	var def: Dictionary = state.building_defs.get(building.building_type, {})
	var category := String(def.get("category", ""))
	if not by_category.has(category):
		by_category[category] = {}
		category_order.append(category)
	var by_type: Dictionary = by_category[category]
	if not by_type.has(building.building_type):
		by_type[building.building_type] = []
	(by_type[building.building_type] as Array).append({"building": building, "base": base})
	if base != null:
		seen_bases[base.id] = base

static func _category_rank(category: String) -> int:
	var idx := _CATEGORY_ORDER.find(category)
	return idx if idx != -1 else _CATEGORY_ORDER.size()

func _add_building_row(building: BuildingInstance, base: BaseInstance, def: Dictionary, show_location: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_PASS

	var status := "Lvl %d" % building.level
	var label_text: String
	if base == null:
		label_text = "Standalone  -  %s" % status
	elif show_location:
		var location := base.display_name if base.display_name != "" else base.base_def_id.capitalize()
		label_text = "%s  -  %s" % [location, status]
	else:
		label_text = status
	var label := UITheme.body_label(label_text)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var building_id := building.id
	var button := UITheme.action_button("Upgrade", UITheme.PRIMARY)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.custom_minimum_size = Vector2(160, 0)
	var reason_fn := func(): return UIEligibility.upgrade_reason(state, building_id, owner_id)
	var action := func(): input_controller.submitter.submit("upgrade_building", [building_id, owner_id], owner_id)
	button.pressed.connect(func(): _handle_press(reason_fn, action))
	row.add_child(button)
	_content.add_child(row)
	_option_updaters.append({"button": button, "variation": UITheme.PRIMARY, "reason_fn": reason_fn})

func _handle_press(reason_fn: Callable, action: Callable) -> void:
	var reason := String(reason_fn.call())
	if reason != "":
		_reason_label.text = reason
		_reason_label.visible = true
		return
	_reason_label.visible = false
	action.call()
	_rebuild()

func _refresh_eligibility() -> void:
	for entry in _option_updaters:
		var reason := String((entry["reason_fn"] as Callable).call())
		var button: Button = entry["button"]
		button.theme_type_variation = UITheme.MUTED if reason != "" else String(entry["variation"])
