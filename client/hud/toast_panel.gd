## Stacked, auto-expiring toast notifications for fire-once gameplay events
## (squad lost, base captured/lost, building destroyed, deficit death,
## barbarian outpost loot) — see sim/events/match_event.gd. Deliberately
## separate from alerts_panel.gd (a persistent row per currently-true
## CONDITION — under attack/paused/deficit — that clears itself once the
## condition clears, never one row per event, per that file's own header
## comment) and from resource_bar.gd's set_status() (a single last-write-wins
## banner reserved for connection/match-halt state, not gameplay events).
##
## Docked top-center, directly under the resource bar — the one screen region
## not already claimed by building_panel/squad_panel/troop_info_panel
## (left/right flip on selection), alerts_panel (bottom-left), or minimap
## (bottom-right).
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
const MAX_VISIBLE := 5

var _list: VBoxContainer
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
	# Generous fixed height for up to MAX_VISIBLE rows — the empty space below
	# however many rows are actually showing stays IGNORE, so it never blocks
	# a world click-to-move underneath it (same contract every other HUD
	# panel's dead space follows).
	offset_bottom = offset_top + MAX_VISIBLE * (ROW_HEIGHT + 6.0) + MARGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_list)

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

	var row := UITheme.panel()
	row.custom_minimum_size = Vector2(WIDTH, ROW_HEIGHT)
	var style: StyleBoxFlat = row.get_theme_stylebox("panel").duplicate()
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	row.add_theme_stylebox_override("panel", style)

	var label := UITheme.body_label(text)
	label.add_theme_color_override("font_color", formatted["color"])
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(label)

	var hex: HexCoord = formatted.get("hex")
	if hex != null:
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(input_event: InputEvent):
			if input_event is InputEventMouseButton and input_event.pressed and input_event.button_index == MOUSE_BUTTON_LEFT:
				camera_controller.center_on(HexView.axial_to_pixel(hex)))
	else:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_list.add_child(row)
	UIJuice.pop_in(row)
	_active.append({"control": row, "remaining": TOAST_DURATION})

	# Cap simultaneous rows so a big battle can't grow this panel unbounded —
	# expire the oldest early rather than letting the list keep stacking.
	while _active.size() > MAX_VISIBLE:
		var oldest: Dictionary = _active.pop_front()
		(oldest["control"] as Control).queue_free()

func _process(delta: float) -> void:
	for i in range(_active.size() - 1, -1, -1):
		_active[i]["remaining"] -= delta
		if _active[i]["remaining"] <= 0.0:
			(_active[i]["control"] as Control).queue_free()
			_active.remove_at(i)

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
