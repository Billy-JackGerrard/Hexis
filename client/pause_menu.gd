## In-match pause overlay: darkens the game behind it and shows a "Paused"
## card with a live stats readout (match time, local resources + production/
## upkeep rates, base counts by owner) plus Resume/Exit Game buttons.
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
var _bases_box: VBoxContainer

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
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(360.0, 0.0)
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := UITheme.warning_label("Paused")
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_time_label = UITheme.subtitle_label("")
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_time_label)

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 4)
	vbox.add_child(stats_box)

	var resources_header := UITheme.header_label("Resources")
	stats_box.add_child(resources_header)
	for type in ResourceType.ALL:
		var row := UITheme.body_label("")
		stats_box.add_child(row)
		_resource_labels[type] = row

	var bases_header := UITheme.header_label("Bases")
	stats_box.add_child(bases_header)
	_bases_box = VBoxContainer.new()
	_bases_box.add_theme_constant_override("separation", 2)
	stats_box.add_child(_bases_box)

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
	var production: Dictionary = ProductionOutputSystem.compute_production(owned_bases, _state.base_defs, _state.building_defs).get(_local_owner_id, {})
	var auras := AuraSystem.resolve_tick(_state.squads, _state.bases, _state.troop_defs, _state.building_defs, _state.regiments)
	var upkeep: Dictionary = UpkeepSystem.compute_upkeep(_state.squads, _state.troop_defs, auras).get(_local_owner_id, {})
	var pool := _state.pool_for(_local_owner_id)
	for type in ResourceType.ALL:
		var amount := int(round(pool.get_amount(type)))
		var net := float(production.get(type, 0.0)) - float(upkeep.get(type, 0.0))
		var label: Label = _resource_labels[type]
		label.text = "%s: %d (%+.1f / tick)" % [UITheme.RESOURCE_LABEL[type], amount, net]
		label.add_theme_color_override("font_color", UITheme.DANGER if pool.is_deficit(type) else UITheme.RESOURCE_COLOR[type])

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
