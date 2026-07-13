## Per-base build menu (build order item 4): one Button per
## base_def.buildableBuildings entry (minus isFixed ones — HQ/Command Centre/
## Ice Spire/Radar Array can never be freshly built from a menu, per
## data/buildings/schema.json's isFixed note) for the currently selected
## base — shown as-is otherwise, no greyed-out "unavailable here" entries,
## per 09-ui-and-controls.md's Build Menu (Unique Bases) resolution (Capital's
## list is the full non-Unique superset; each Unique base's is its own
## shorter fixed list — already exactly what each base JSON's
## buildableBuildings array contains, so this widget does no filtering of its
## own beyond isFixed). Only shown when the specific building clicked is the
## HQ (input_controller.selected_building_id, not just selected_base_id) — per
## the same click that opens client/hud/base_panel.gd, but gated one level
## tighter so clicking a Farm/Barracks/etc. doesn't also pop the build menu.
## Anchored to a fixed vertical band that stops short of the minimap
## (client/hud/minimap.gd) regardless of screen height, with the button list
## in a ScrollContainer so a long list (Capital's, currently 14 non-fixed
## entries) scrolls instead of spilling into/behind it.
##
## Pressing a button hands off to InputController.start_placement(), which
## owns the actual placement-mode click handling and the world-space
## valid-hex highlight (client/build_preview.gd) — this widget only ever
## issues that one call, consistent with every other client/ node never
## touching sim state directly. A successful placement, re-clicking the HQ,
## right-clicking, or selecting a squad all clear
## InputController.selected_building_id, which is what actually closes this
## menu (see input_controller.gd's _clear_building_selection).
class_name BuildMenu
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

var _scroll: ScrollContainer
var _list: VBoxContainer
var _shown_for_building_id: String = ""

const WIDTH := 240.0
const MARGIN := 12.0
const TOP := ResourceBar.HEIGHT + MARGIN + BasePanel.HEIGHT + MARGIN
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller

	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = TOP
	# Leaves a clear band above Minimap's bottom-right footprint regardless of
	# viewport height, instead of growing downward past it (the overlap this
	# was previously reported to cause).
	offset_bottom = -(Minimap.SIZE.y + Minimap.MARGIN + MARGIN)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_scroll = ScrollContainer.new()
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_left = 4.0
	_scroll.offset_top = 4.0
	_scroll.offset_right = -4.0
	_scroll.offset_bottom = -4.0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(WIDTH - 16.0, 0.0)
	_scroll.add_child(_list)

func _process(_delta: float) -> void:
	if input_controller.selected_building_id == _shown_for_building_id:
		return
	_shown_for_building_id = input_controller.selected_building_id
	_rebuild()

func _rebuild() -> void:
	for child in _list.get_children():
		child.queue_free()
	visible = false
	if _shown_for_building_id == "":
		return
	var found := state.find_base_building(_shown_for_building_id)
	if found.is_empty():
		return
	var building: BuildingInstance = found["building"]
	if building.building_type != "hq":
		return
	var base: BaseInstance = found["base"]
	visible = true

	var base_def: Dictionary = state.base_defs.get(base.base_def_id, {})
	var building_types: Array = base_def.get("buildableBuildings", [])
	for building_type in building_types:
		var def: Dictionary = state.building_defs.get(building_type, {})
		if def.get("isFixed", false):
			continue
		var button := Button.new()
		button.text = "%s (%s)" % [String(building_type).capitalize(), _cost_text(building_type, def)]
		button.pressed.connect(_on_building_pressed.bind(base.id, building_type))
		_list.add_child(button)
	queue_redraw()

## Level-1 build cost formatted for a button label, e.g. "Stone 50, Steel
## 20" — BuildingStats.base_cost's dict keys are already the plain
## data/*.json resource names (see its own doc comment), so no ResourceType
## round-trip is needed just to display them. Multi-material buildings (Wall/
## Tower/Dock/Bridge) show their first authored material's cost as a
## representative figure — this menu doesn't offer material selection yet.
func _cost_text(building_type: String, def: Dictionary) -> String:
	var materials: Array = def.get("materials", [])
	var material: String = String(materials[0]) if not materials.is_empty() else ""
	var cost := BuildingStats.base_cost(def, material, state.building_defs)
	if cost.is_empty():
		return "Free"
	var parts: Array[String] = []
	for key in cost:
		parts.append("%s %d" % [String(key).capitalize(), int(cost[key])])
	return ", ".join(parts)

func _on_building_pressed(base_id: String, building_type: String) -> void:
	input_controller.start_placement(base_id, building_type)

func _draw() -> void:
	if visible:
		draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
