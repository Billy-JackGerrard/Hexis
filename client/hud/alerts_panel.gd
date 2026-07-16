## Alerts panel (build order item 6, 09-ui-and-controls.md's Alerts Panel):
## one persistent row per base per alert type — under attack
## (CombatStateSystem.is_hex_in_combat), production paused
## (ProductionQueue.paused, same field production_panel.gd already reads),
## resource deficit (ResourcePool.is_deficit) — clearing automatically once
## the underlying condition clears, never spamming one row per event.
##
## Resource deficit is the one type that doesn't actually key to a specific
## base: 03-resources.md/sim/economy/resource_pool.gd both make the resource
## pool a single player-wide total (Player.resources), not per-base, so
## "that base is contributing to a deficit" has no single base to point at.
## This renders it as one row per deficient resource type instead, clicking
## it recenters on the player's first base (arbitrary but stable) rather
## than a base it doesn't actually belong to.
##
## is_hex_in_combat/paused are only re-checked every ALERT_POLL_SECONDS, not
## every frame — is_hex_in_combat rebuilds the full CombatResolver target
## list per call, the same per-call cost input_controller.gd's hover
## throttling and combat_state_system.gd's own header comment both already
## flag as too expensive unthrottled.
class_name AlertsPanel
extends Control

var state: MatchState
var owner_id: String
var camera_controller: CameraController

var _panel: PanelContainer
var _list: VBoxContainer
var _poll_accumulator: float = 0.0
var _shown_keys: Array = []

const WIDTH := 320.0
const MARGIN := 12.0
const ALERT_POLL_SECONDS := 0.5
const UNDER_ATTACK_COLOR := UITheme.DANGER
const PAUSED_COLOR := UITheme.WARNING
const DEFICIT_COLOR := UITheme.WARNING

func setup(p_state: MatchState, p_owner_id: String, p_camera_controller: CameraController) -> void:
	state = p_state
	owner_id = p_owner_id
	camera_controller = p_camera_controller

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = MARGIN
	offset_right = MARGIN + WIDTH
	offset_bottom = -MARGIN
	offset_top = -MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	_panel = UITheme.panel()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	# Default panel stylebox's 16px content margin reads as a cream/white
	# border ring around this panel's small toast rows — tighten it here
	# rather than shrinking the shared UITheme panel margin every other
	# (larger) panel also uses.
	var style: StyleBoxFlat = _panel.get_theme_stylebox("panel").duplicate()
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_panel.add_theme_stylebox_override("panel", style)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_panel.add_child(_list)

func _process(delta: float) -> void:
	_poll_accumulator += delta
	if _poll_accumulator < ALERT_POLL_SECONDS:
		return
	_poll_accumulator = 0.0
	_refresh()

## {key: "<base_id>|<kind>", label, color, target_hex} for every currently-
## active alert, in a stable order (bases in state.bases order, then
## attack/paused/deficit) so the row list doesn't reshuffle between polls.
func _compute_alerts() -> Array[Dictionary]:
	var alerts: Array[Dictionary] = []
	var owned_bases := state.bases_owned_by(owner_id)
	for base in owned_bases:
		if CombatStateSystem.is_hex_in_combat(base.hex_coord, owner_id, state.squads, state.bases, state.troop_defs, state.building_defs):
			alerts.append({"key": "%s|attack" % base.id, "label": "%s under attack" % base.base_def_id.capitalize(), "color": UNDER_ATTACK_COLOR, "hex": base.hex_coord})
		for building in base.buildings:
			var queue: ProductionQueue = state.production_queues.get(building.id)
			if queue != null and queue.paused:
				var reason_suffix := " (%s)" % String(queue.pause_reason).replace("_", " ") if queue.pause_reason != "" else ""
				alerts.append({"key": "%s|paused" % base.id, "label": "%s production paused%s" % [base.base_def_id.capitalize(), reason_suffix], "color": PAUSED_COLOR, "hex": base.hex_coord})
				break
	if not owned_bases.is_empty():
		var pool := state.pool_for(owner_id)
		for type in [ResourceType.Type.FOOD, ResourceType.Type.FUEL]:
			if pool.is_deficit(type):
				var label := "Food" if type == ResourceType.Type.FOOD else "Fuel"
				alerts.append({"key": "deficit|%d" % type, "label": "%s deficit" % label, "color": DEFICIT_COLOR, "hex": owned_bases[0].hex_coord})
	return alerts

func _refresh() -> void:
	var alerts := _compute_alerts()
	var keys: Array = []
	for alert in alerts:
		keys.append(alert["key"])
	if keys == _shown_keys:
		return
	_shown_keys = keys
	for child in _list.get_children():
		child.queue_free()
	for alert in alerts:
		var button := UITheme.action_button(alert["label"])
		# action_button() already clips (no overrun marker); a long label like
		# "Kraken Point production paused" was getting hard-cut mid-word at
		# this panel's width, unreadable. Ellipsis reads as "yes it's cut,
		# here's an indicator" instead of just cutting silently.
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.add_theme_color_override("font_color", alert["color"])
		button.add_theme_color_override("font_hover_color", alert["color"])
		button.add_theme_color_override("font_pressed_color", alert["color"])
		var hex: HexCoord = alert["hex"]
		button.pressed.connect(func(): camera_controller.center_on(HexView.axial_to_pixel(hex)))
		_list.add_child(button)
	visible = not alerts.is_empty()
	# Grows upward from the fixed bottom margin — row count varies with the
	# alert count, same "recompute the anchored-corner extent on rebuild"
	# approach the old dynamic button-list panels used.
	offset_top = -MARGIN - alerts.size() * 40.0 - 16.0
	if visible:
		UIJuice.pop_in(_panel)
