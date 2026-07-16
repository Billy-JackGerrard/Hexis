## In-match pause overlay: darkens the game behind it and shows a "Paused"
## card with a live stats readout (match time, local resources + production/
## upkeep rates, base counts by owner, squad counts by troop type) plus
## Resume/Exit Game buttons.
##
## Unlike start_screen.gd (built once, freed after use), this is instantiated
## once per match (client/main.gd) and toggles visibility repeatedly via
## open()/close()/toggle() — the same show/hide-in-place convention
## building_panel/squad_panel already use for their own root Control.
##
## Deliberately SP/MP-agnostic: it never checks lockstep_driver. Whether
## Escape opening this actually freezes the sim (singleplayer only) is
## decided by main.gd's _process gate, not here — in multiplayer this is
## purely a local darken+popup while everyone else keeps playing.
class_name PauseMenu
extends CanvasLayer

signal exit_requested
## Fired every time the menu opens (not on refresh) — main.gd uses this to
## close whatever else was open (building/squad selection, resource_bar's
## expanded view) so nothing is left interactable behind the overlay.
signal opened

const REFRESH_INTERVAL := 0.25

var is_open: bool = false

var _state: MatchState
var _local_owner_id: String
var _owner_names: Dictionary

var _root: Control
var _card: PanelContainer
var _refresh_accum := 0.0

var _time_label: Label
var _resource_labels: Dictionary = {} ## ResourceType.Type -> Label
var _production_labels: Dictionary = {} ## ResourceType.Type -> Label, "+N.N / tick"
var _usage_labels: Dictionary = {} ## ResourceType.Type -> Label, "-N.N / tick used"
var _bases_box: VBoxContainer
var _squads_cap_label: Label
var _squads_box: VBoxContainer

func setup(state: MatchState, local_owner_id: String, owner_names: Dictionary) -> void:
	_state = state
	_local_owner_id = local_owner_id
	_owner_names = owner_names

	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = UITheme.create_theme()
	_root.visible = false
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	_root.add_child(center)

	_card = UITheme.panel()
	center.add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(480.0, 0.0)
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := UITheme.warning_label("Paused")
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_time_label = UITheme.subtitle_label("")
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_time_label)

	# Scrolls rather than growing the card unboundedly — the squads section
	# below has one row per troop type the local player fields, which can run
	# long (same reasoning as squad_panel.gd's own ScrollContainer).
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 420.0)
	vbox.add_child(scroll)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 4)
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stats_box)

	var resources_header := UITheme.header_label("Resources")
	stats_box.add_child(resources_header)
	for type in ResourceType.ALL:
		var row := UITheme.body_label("")
		stats_box.add_child(row)
		_resource_labels[type] = row

		# Same "+N.N / tick" produced / "-N.N / tick used" split resource_bar.gd's
		# expanded view shows, indented under the amount row.
		var detail_row := HBoxContainer.new()
		detail_row.add_theme_constant_override("separation", 12)
		stats_box.add_child(detail_row)
		var production_label := UITheme.muted_label("")
		detail_row.add_child(production_label)
		_production_labels[type] = production_label
		var usage_label := UITheme.muted_label("")
		detail_row.add_child(usage_label)
		_usage_labels[type] = usage_label

	var bases_header := UITheme.header_label("Bases")
	stats_box.add_child(bases_header)
	_bases_box = VBoxContainer.new()
	_bases_box.add_theme_constant_override("separation", 2)
	stats_box.add_child(_bases_box)

	var squads_header := UITheme.header_label("Squads")
	stats_box.add_child(squads_header)
	_squads_cap_label = UITheme.body_label("")
	stats_box.add_child(_squads_cap_label)
	_squads_box = VBoxContainer.new()
	_squads_box.add_theme_constant_override("separation", 2)
	stats_box.add_child(_squads_box)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	var resume_button := UITheme.action_button("Resume", UITheme.PRIMARY)
	resume_button.pressed.connect(close)
	button_row.add_child(resume_button)

	var exit_button := UITheme.action_button("Exit Game")
	exit_button.pressed.connect(func(): exit_requested.emit())
	button_row.add_child(exit_button)

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	_root.visible = true
	_refresh_accum = 0.0
	_refresh_stats()
	UIJuice.pop_in(_card)
	opened.emit()

func close() -> void:
	is_open = false
	_root.visible = false

func _process(delta: float) -> void:
	if not is_open:
		return
	_refresh_accum += delta
	if _refresh_accum >= REFRESH_INTERVAL:
		_refresh_accum = 0.0
		_refresh_stats()

func _refresh_stats() -> void:
	var total_seconds := int(_state.tick * Tuning.SIM_TICK_SECONDS)
	_time_label.text = "Match time: %02d:%02d" % [total_seconds / 60, total_seconds % 60]

	var owned_bases := _state.bases_owned_by(_local_owner_id)
	var summary := EconomySummary.compute(_state, _local_owner_id)
	var production: Dictionary = summary["production"]
	var upkeep: Dictionary = summary["upkeep"]
	var pool := _state.pool_for(_local_owner_id)
	for type in ResourceType.ALL:
		var amount := int(round(pool.get_amount(type)))
		var label: Label = _resource_labels[type]
		label.text = "%s: %d" % [UITheme.RESOURCE_LABEL[type], amount]
		label.add_theme_color_override("font_color", UITheme.DANGER if pool.is_deficit(type) else UITheme.RESOURCE_COLOR[type])
		_production_labels[type].text = "%+.1f / tick" % float(production.get(type, 0.0))
		_usage_labels[type].text = "-%.1f / tick used" % float(upkeep.get(type, 0.0))

	for row in _bases_box.get_children():
		row.queue_free()
	var counts_by_owner: Dictionary = {}
	for base in _state.bases:
		counts_by_owner[base.owner_id] = int(counts_by_owner.get(base.owner_id, 0)) + 1

	_bases_box.add_child(UITheme.body_label("You: %d" % int(counts_by_owner.get(_local_owner_id, 0))))
	var other_owner_ids := counts_by_owner.keys().filter(func(id): return id != _local_owner_id and id != "neutral")
	other_owner_ids.sort()
	for owner_id in other_owner_ids:
		var label_name: String = _owner_names.get(owner_id, owner_id)
		_bases_box.add_child(UITheme.body_label("%s: %d" % [label_name, counts_by_owner[owner_id]]))
	_bases_box.add_child(UITheme.body_label("Neutral: %d" % int(counts_by_owner.get("neutral", 0))))

	var squads_used := 0
	var squads_by_type: Dictionary = {} ## troop_type -> {"squads": int, "troops": int}
	for squad in _state.squads:
		if squad.owner_id != _local_owner_id:
			continue
		squads_used += 1
		var entry: Dictionary = squads_by_type.get(squad.troop_type, {"squads": 0, "troops": 0})
		entry["squads"] = int(entry["squads"]) + 1
		entry["troops"] = int(entry["troops"]) + squad.member_ids.size()
		squads_by_type[squad.troop_type] = entry
	var squads_max := SquadCap.max_squads(owned_bases)
	_squads_cap_label.text = "Total: %d/%d" % [squads_used, squads_max]

	for row in _squads_box.get_children():
		row.queue_free()
	var troop_types := squads_by_type.keys()
	troop_types.sort_custom(func(a, b): return _troop_display_name(a) < _troop_display_name(b))
	for troop_type in troop_types:
		var entry: Dictionary = squads_by_type[troop_type]
		_squads_box.add_child(UITheme.body_label("%s: %d squads (%d troops)" % [_troop_display_name(troop_type), entry["squads"], entry["troops"]]))

func _troop_display_name(troop_type: String) -> String:
	var def: Dictionary = _state.troop_defs.get(troop_type, {})
	return String(def.get("name", troop_type))
