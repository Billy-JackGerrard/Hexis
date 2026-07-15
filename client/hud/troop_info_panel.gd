## A small panel immediately left of BuildingPanel showing one troop's stats
## and description (client/hud/troop_stats_view.gd — the same block SquadPanel
## shows for a selected squad on the map). Opened by clicking a troop's name
## in a Production building's TRAIN menu (see BuildingPanel._on_troop_name_pressed)
## instead of training it outright; training now happens via the row's
## separate Train button. Owns no state of its own beyond which troop_type is
## shown — BuildingPanel drives visibility/content via show_troop/hide_panel
## and clears it whenever the underlying selection stops being that troop
## (building deselected, TRAIN menu no longer shown, ...).
class_name TroopInfoPanel
extends Control

var state: MatchState

const WIDTH := 320.0
const MARGIN := 12.0

var _content: VBoxContainer
var _shown_troop_type: String = ""

func setup(p_state: MatchState) -> void:
	state = p_state

	# Same right-hand band as BuildingPanel, shifted one further MARGIN+WIDTH
	# to the left so it sits immediately beside it with a matching gap.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_right = -(BuildingPanel.WIDTH + 2 * MARGIN)
	offset_left = -(BuildingPanel.WIDTH + 2 * MARGIN + WIDTH)
	offset_top = ResourceBar.HEIGHT + MARGIN
	offset_bottom = -(Minimap.SIZE.y + Minimap.MARGIN + MARGIN)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var panel := UITheme.panel()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)

## No-op if `troop_type` is already shown (BuildingPanel re-calls this on
## every rebuild — including ones triggered by an unrelated queue mutation —
## to keep the panel in sync; toggling closed on a repeat click is
## BuildingPanel._on_troop_name_pressed's job, via hide_panel(), not this one's).
func show_troop(troop_type: String) -> void:
	if troop_type == _shown_troop_type and visible:
		return
	_shown_troop_type = troop_type
	_rebuild()
	visible = true

func hide_panel() -> void:
	visible = false
	_shown_troop_type = ""

func _rebuild() -> void:
	for child in _content.get_children():
		child.queue_free()
	var def: Dictionary = state.troop_defs.get(_shown_troop_type, {})
	_content.add_child(UITheme.title_label(String(def.get("name", _shown_troop_type.capitalize()))))
	_content.add_child(HSeparator.new())
	TroopStatsView.build(_content, def)
