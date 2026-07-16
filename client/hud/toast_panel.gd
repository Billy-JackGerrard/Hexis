## Docked top-center, directly under the resource bar — the one screen region
## not already claimed by building_panel/squad_panel/troop_info_panel
## (left/right flip on selection) or minimap (bottom-right). The single HUD
## notification system — every kind of alert/toast renders through the same
## _build_row() (a themed panel + colored label, click-to-center only when a
## hex applies), so a connection banner, a paused-production alert, and a
## squad-lost toast all read as one visual family instead of three ad hoc
## widgets. Two stacked sections in one panel:
##
## - Alerts (top section): one persistent row per condition — connection/
##   match-status (set_connection_status(), called by main.gd instead of
##   maintaining its own banner — see that method's doc), under attack
##   (CombatStateSystem.is_hex_in_combat), production paused
##   (ProductionQueue.paused, same field production_panel.gd already reads),
##   resource deficit (ResourcePool.is_deficit) — clearing automatically once
##   the underlying condition clears, never spamming one row per event.
##   Resource deficit doesn't key to a specific base (03-resources.md/
##   sim/economy/resource_pool.gd make the resource pool a single player-wide
##   total, not per-base), so it renders as one row per deficient resource
##   type, clicking it recenters on the player's first base (arbitrary but
##   stable) rather than a base it doesn't actually belong to. The sim-derived
##   alerts (attack/paused/deficit) are re-checked every ALERT_POLL_SECONDS,
##   not every frame — is_hex_in_combat rebuilds the full CombatResolver
##   target list per call, the same per-call cost input_controller.gd's hover
##   throttling and combat_state_system.gd's own header comment both already
##   flag as too expensive unthrottled. The connection alert instead rebuilds
##   on a dirty flag (set_connection_status only actually changes on a real
##   connection-state transition, not every frame main.gd calls it), so it
##   updates immediately without forcing the expensive poll to run early.
##
## - Toasts (bottom section): stacked, auto-expiring fire-once event
##   notifications (squad lost, base captured/lost, building destroyed,
##   deficit death, barbarian outpost loot) — see sim/events/match_event.gd.
##   Deliberately distinct lifecycle from the alerts section above (one row
##   per event, always expires) — not a different visual, just a different
##   set() vs push()-and-expire lifecycle.
##
## drain() must be called exactly once per RENDERED FRAME, not once per sim
## tick — see its own doc comment.
class_name ToastPanel
extends Control

var state: MatchState
var owner_id: String
var camera_controller: CameraController

const WIDTH := 380.0
const ROW_HEIGHT := 40.0
const MARGIN := 12.0
const TOAST_DURATION := 5.0
const MAX_VISIBLE_TOASTS := 5
const ALERT_POLL_SECONDS := 0.5
const UNDER_ATTACK_COLOR := UITheme.DANGER
const PAUSED_COLOR := UITheme.WARNING
const DEFICIT_COLOR := UITheme.WARNING
## Generous cap on simultaneous persistent alert rows, used only to size this
## panel's fixed dead-space extent (see setup) — not an enforced limit on how
## many alerts can actually show at once.
const MAX_ALERT_ROWS := 6

var _alerts_list: VBoxContainer
var _toasts_list: VBoxContainer
var _shown_alert_keys: Array = []
var _poll_accumulator: float = 0.0
var _connection_status: String = ""
var _connection_danger: bool = false
var _connection_dirty: bool = false
## [{control: Control, remaining: float}], oldest first (append order == VBox
## display order, so the oldest toast is always both index 0 and visually the
## topmost row).
var _active: Array = []

func setup(p_state: MatchState, p_owner_id: String, p_camera_controller: CameraController) -> void:
	state = p_state
	owner_id = p_owner_id
	camera_controller = p_camera_controller

	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = ResourceBar.HEIGHT + MARGIN
	# Generous fixed height for up to MAX_ALERT_ROWS alert rows plus
	# MAX_VISIBLE_TOASTS toast rows — the empty space below however many rows
	# are actually showing stays IGNORE, so it never blocks a world
	# click-to-move underneath it (same contract every other HUD panel's dead
	# space follows).
	offset_bottom = offset_top + (MAX_ALERT_ROWS + MAX_VISIBLE_TOASTS) * (ROW_HEIGHT + 6.0) + MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	root_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_vbox)

	_alerts_list = VBoxContainer.new()
	_alerts_list.add_theme_constant_override("separation", 4)
	_alerts_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(_alerts_list)

	_toasts_list = VBoxContainer.new()
	_toasts_list.add_theme_constant_override("separation", 6)
	_toasts_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_vbox.add_child(_toasts_list)

func _process(delta: float) -> void:
	_poll_accumulator += delta
	if _poll_accumulator >= ALERT_POLL_SECONDS or _connection_dirty:
		_poll_accumulator = 0.0
		_connection_dirty = false
		_refresh_alerts()

	for i in range(_active.size() - 1, -1, -1):
		_active[i]["remaining"] -= delta
		if _active[i]["remaining"] <= 0.0:
			(_active[i]["control"] as Control).queue_free()
			_active.remove_at(i)

## main.gd calls this instead of maintaining its own status label — replaces
## the old resource_bar.gd set_status() overlay so connection/match-halt
## state (waiting for players, connection lost, desync halt) renders through
## the same alert row as every sim-derived condition below, instead of a
## separately-styled banner living in a different file. Cheap early-return on
## an unchanged value since main.gd calls this every frame regardless of
## whether the underlying state actually transitioned; only a real change
## marks the panel dirty so the next _process forces an immediate rebuild
## (see _process) rather than waiting up to ALERT_POLL_SECONDS to appear.
func set_connection_status(text: String, danger: bool = false) -> void:
	if text == _connection_status and danger == _connection_danger:
		return
	_connection_status = text
	_connection_danger = danger
	_connection_dirty = true

# --- Alerts (persistent per-condition rows) ---------------------------------

## {key: "<base_id>|<kind>", label, color, target_hex} for every currently-
## active alert, in a stable order (connection status first, then bases in
## state.bases order, then attack/paused/deficit) so the row list doesn't
## reshuffle between polls.
func _compute_alerts() -> Array[Dictionary]:
	var alerts: Array[Dictionary] = []
	if _connection_status != "":
		alerts.append({"key": "connection", "label": _connection_status, "color": UITheme.DANGER if _connection_danger else UITheme.TEXT, "hex": null})
	var owned_bases := state.bases_owned_by(owner_id)
	for base in owned_bases:
		if CombatStateSystem.is_hex_in_combat(base.hex_coord, owner_id, state.squads, state.bases, state.troop_defs, state.building_defs):
			alerts.append({"key": "%s|attack" % base.id, "label": "%s under attack" % base.base_def_id.capitalize(), "color": UNDER_ATTACK_COLOR, "hex": base.hex_coord})
		# One row per base (not per building) to avoid spam, but naming every
		# paused building rather than the base itself — "production paused"
		# alone didn't say what was paused when a base runs several queues.
		var paused_names: Array[String] = []
		var paused_reason := ""
		for building in base.buildings:
			var queue: ProductionQueue = state.production_queues.get(building.id)
			if queue != null and queue.paused:
				var building_def: Dictionary = state.building_defs.get(building.building_type, {})
				paused_names.append(String(building_def.get("name", building.building_type.capitalize())))
				if paused_reason == "" and queue.pause_reason != "":
					paused_reason = String(queue.pause_reason).replace("_", " ")
		if not paused_names.is_empty():
			var reason_suffix := " (%s)" % paused_reason if paused_reason != "" else ""
			alerts.append({"key": "%s|paused" % base.id, "label": "%s production paused%s" % [", ".join(paused_names), reason_suffix], "color": PAUSED_COLOR, "hex": base.hex_coord})
	if not owned_bases.is_empty():
		var pool := state.pool_for(owner_id)
		for type in [ResourceType.Type.FOOD, ResourceType.Type.FUEL]:
			if pool.is_deficit(type):
				var label := "Food" if type == ResourceType.Type.FOOD else "Fuel"
				alerts.append({"key": "deficit|%d" % type, "label": "%s deficit" % label, "color": DEFICIT_COLOR, "hex": owned_bases[0].hex_coord})
	return alerts

func _refresh_alerts() -> void:
	var alerts := _compute_alerts()
	var keys: Array = []
	for alert in alerts:
		keys.append(alert["key"])
	if keys == _shown_alert_keys:
		return
	_shown_alert_keys = keys
	for child in _alerts_list.get_children():
		child.queue_free()
	for alert in alerts:
		var label_text: String = alert["label"]
		if label_text == "":
			continue
		var row := _build_row(label_text, alert["color"], alert.get("hex"))
		_alerts_list.add_child(row)
	if not alerts.is_empty():
		UIJuice.pop_in(_alerts_list)

# --- Toasts (fire-once expiring rows) ----------------------------------------

## Reads every event from this tick's-worth-of-ticks batch relevant to this
## player, pushes a toast row for each, then clears state.events outright —
## called once per rendered frame (client/main.gd's _process, after
## sim_clock.advance()/lockstep_driver.advance() for that frame have already
## run every tick they're going to). SimClock can run up to
## Tuning.MAX_STEPS_PER_ADVANCE ticks in one advance() call, so draining
## per-tick instead of per-frame would need to happen inside that loop; doing
## it here once, after all of a frame's ticks, is simpler and loses nothing —
## events from every tick this frame are still all present in state.events
## when this runs.
func drain() -> void:
	if state == null:
		return
	for event in state.events:
		if event.owner_id == owner_id:
			_push(event)
	state.events.clear()

func _push(event: MatchEvent) -> void:
	var formatted := _format(event)
	var text: String = formatted["text"]
	if text == "":
		return

	var row := _build_row(text, formatted["color"], formatted.get("hex"))
	_toasts_list.add_child(row)
	UIJuice.pop_in(row)
	_active.append({"control": row, "remaining": TOAST_DURATION})

	# Cap simultaneous rows so a big battle can't grow this panel unbounded —
	# expire the oldest early rather than letting the list keep stacking.
	while _active.size() > MAX_VISIBLE_TOASTS:
		var oldest: Dictionary = _active.pop_front()
		(oldest["control"] as Control).queue_free()

## Shared visual + click wiring for every row this panel shows — persistent
## alerts, fire-once toasts, and the connection-status banner alike — so all
## three read as one notification system instead of separately built
## widgets. Fixed WIDTH via custom_minimum_size (not size_flags) since
## _alerts_list/_toasts_list are plain VBoxContainers with nothing else
## forcing them to this panel's declared WIDTH; each row has to claim its own
## width instead of relying on a stretch that never happens. Click-to-center
## only when `hex` is non-null — the connection banner and a few toast kinds
## (deficit death, outpost loot) have no single relevant map location.
func _build_row(text: String, color: Color, hex) -> Control:
	var row := UITheme.panel()
	row.custom_minimum_size = Vector2(WIDTH, ROW_HEIGHT)
	var style: StyleBoxFlat = row.get_theme_stylebox("panel").duplicate()
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var label := UITheme.body_label(text)
	label.add_theme_color_override("font_color", color)
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)

	if hex != null:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(input_event: InputEvent):
			if input_event is InputEventMouseButton and input_event.pressed and input_event.button_index == MOUSE_BUTTON_LEFT:
				camera_controller.center_on(HexView.axial_to_pixel(hex)))
	else:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return row

## {text, color, hex} for one event — hex is null (no click-to-center) for
## events with no single relevant map location (deficit death, outpost loot).
func _format(event: MatchEvent) -> Dictionary:
	match event.type:
		MatchEvent.Type.SQUAD_LOST:
			var troop_type := String(event.payload.get("troop_type", ""))
			var name := String(state.troop_defs.get(troop_type, {}).get("name", troop_type.capitalize()))
			return {"text": "%s squad destroyed" % name, "color": UITheme.DANGER, "hex": event.payload.get("hex")}
		MatchEvent.Type.BASE_CAPTURED:
			var base_name := String(event.payload.get("base_def_id", "")).capitalize()
			var previous_owner := String(event.payload.get("previous_owner", ""))
			var suffix := ""
			if previous_owner != "" and previous_owner != BaseSiteSelector.NEUTRAL_OWNER_ID:
				suffix = " from %s" % previous_owner
			return {"text": "Captured %s%s" % [base_name, suffix], "color": UITheme.ACCENT, "hex": event.payload.get("hex")}
		MatchEvent.Type.BASE_LOST:
			var lost_base_name := String(event.payload.get("base_def_id", "")).capitalize()
			var captured_by := String(event.payload.get("captured_by", ""))
			return {"text": "%s was captured by %s" % [lost_base_name, captured_by], "color": UITheme.DANGER, "hex": event.payload.get("hex")}
		MatchEvent.Type.BUILDING_DESTROYED:
			var building_type := String(event.payload.get("building_type", ""))
			var building_name := String(state.building_defs.get(building_type, {}).get("name", building_type.capitalize()))
			return {"text": "%s destroyed" % building_name, "color": UITheme.DANGER, "hex": event.payload.get("hex")}
		MatchEvent.Type.DEFICIT_DEATH:
			var count := int(event.payload.get("troop_count", 0))
			var resource_types: Array = event.payload.get("resource_types", [])
			var labels: Array[String] = []
			for type in resource_types:
				labels.append(String(UITheme.RESOURCE_LABEL.get(type, "resource")))
			var resource_text := ", ".join(labels) if not labels.is_empty() else "resource"
			return {"text": "%d troop%s lost to %s shortage" % [count, "" if count == 1 else "s", resource_text], "color": UITheme.DANGER, "hex": null}
		MatchEvent.Type.OUTPOST_LOOT:
			var loot: Dictionary = event.payload.get("loot", {})
			var parts: Array[String] = []
			for key in loot:
				parts.append("+%d %s" % [int(loot[key]), String(key).capitalize()])
			return {"text": "Barbarian camp destroyed: %s" % ", ".join(parts), "color": UITheme.ACCENT, "hex": null}
		_:
			return {"text": "", "color": UITheme.TEXT, "hex": null}
