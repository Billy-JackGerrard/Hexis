## Pre-game entry screen: player name + Single Player/Multiplayer choice,
## shown as a CanvasLayer overlay (ignores world Camera2D like hud_layer.gd,
## and its full-rect background stops mouse input from reaching the world
## underneath while it's up). main.gd adds this first and defers building
## the demo MatchState/board/HUD until single_player_requested (SP) or
## NetManager.match_starting (MP, connected by main.gd itself since it's the
## one that owns/keeps the NetManager alive past this screen being freed).
##
## Multiplayer flow: Host Server calls NetManager.host() and immediately
## shows the lobby (the host is already roster[1]); Join Server calls
## NetManager.join(ip, port, ...) and shows the lobby once _sync_roster
## arrives.
## Only the host sees a Start Match button (disabled below 2 players) — it
## calls NetManager.start_match(), which broadcasts the seed/roster that
## turns into match_starting on every peer, main.gd included.
##
## Name/capital name edits stay live in the lobby: editing either field while
## connected calls NetManager.rename_self() on every keystroke, which updates
## the roster and rebroadcasts — every peer applies every owner's
## capital_name in main.gd's _build_demo_state, so base display names stay
## deterministic across peers (a bare "only rename my own capital locally"
## approach would desync the checksum, since to_dict() includes
## display_name). The host also de-duplicates both fields against every
## other roster entry (see NetManager._dedupe) so two players who never
## touch the name fields don't both end up "Unnamed Player"/"Unnamed Base".
class_name StartScreen
extends CanvasLayer

signal single_player_requested(player_name: String, capital_name: String)

const DEFAULT_NAME := "Unnamed Player"
const DEFAULT_CAPITAL_NAME := "Unnamed Base"
const DEFAULT_JOIN_IP := "127.0.0.1"
const MIN_MATCH_PLAYERS := 2

var _net: NetManager
var _lan_discovery: LanDiscovery

var _name_edit: LineEdit
var _capital_name_edit: LineEdit
var _mode_row: HBoxContainer
var _multiplayer_row: HBoxContainer
var _mp_setup_row: VBoxContainer
var _join_ip_edit: LineEdit
var _join_port_edit: LineEdit
var _server_list_container: VBoxContainer
var _lobby_panel: VBoxContainer
var _host_info_column: VBoxContainer
var _host_info_label: Label
var _players_header_label: Label
var _lobby_list_container: VBoxContainer
var _start_match_button: Button
var _status_label: Label

func setup(net_manager: NetManager) -> void:
	_net = net_manager
	_net.roster_updated.connect(_on_roster_updated)
	_net.connection_failed.connect(_on_connection_failed)
	_lan_discovery = LanDiscovery.new()
	add_child(_lan_discovery)
	_lan_discovery.servers_updated.connect(_on_servers_updated)
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = UITheme.create_theme()
	add_child(root)

	# Bright vertical candy-sky gradient rather than a flat fill.
	var gradient := Gradient.new()
	gradient.set_color(0, UITheme.BG.lightened(0.15))
	gradient.set_color(1, UITheme.BG.darkened(0.25))
	var gradient_texture := GradientTexture2D.new()
	gradient_texture.gradient = gradient
	gradient_texture.fill_from = Vector2(0, 0)
	gradient_texture.fill_to = Vector2(0, 1)
	var bg := TextureRect.new()
	bg.texture = gradient_texture
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	root.add_child(center)

	# A themed card so the menu reads as one styled surface, not loose controls.
	var card := UITheme.panel()
	center.add_child(card)
	UIJuice.pop_in(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(560.0, 0.0)
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := UITheme.title_label("HEXIS")
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	_start_title_wobble(title)

	var tagline := UITheme.subtitle_label("Hex-grid real-time strategy")
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(tagline)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = DEFAULT_NAME
	_name_edit.text_changed.connect(_on_identity_field_edited)
	vbox.add_child(_name_edit)

	_capital_name_edit = LineEdit.new()
	_capital_name_edit.placeholder_text = DEFAULT_CAPITAL_NAME
	_capital_name_edit.text_changed.connect(_on_identity_field_edited)
	vbox.add_child(_capital_name_edit)

	_mode_row = HBoxContainer.new()
	_mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_mode_row)

	var single_button := UITheme.action_button("Single Player", UITheme.PRIMARY)
	single_button.pressed.connect(_on_single_player_pressed)
	_mode_row.add_child(single_button)

	var multiplayer_button := UITheme.action_button("Multiplayer")
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_mode_row.add_child(multiplayer_button)

	# Hidden until Multiplayer is clicked. Holds both the Host/Join setup row
	# and the lobby panel (only one of the two is visible at a time), so Back
	# from either returns to the Single Player/Multiplayer row above.
	_multiplayer_row = HBoxContainer.new()
	_multiplayer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_multiplayer_row.add_theme_constant_override("separation", 12)
	_multiplayer_row.visible = false
	vbox.add_child(_multiplayer_row)

	# Vertical, not a packed HBox — Host/Join buttons + IP/Port fields all in
	# one row used to squeeze into ~340px, clipping "Host Server"/"Join
	# Server" down to nothing. Full-width rows give every control room, and
	# each field gets a label instead of a bare placeholder number.
	_mp_setup_row = VBoxContainer.new()
	_mp_setup_row.add_theme_constant_override("separation", 10)
	_mp_setup_row.visible = false
	vbox.add_child(_mp_setup_row)

	var host_button := UITheme.action_button("Host Server", UITheme.PRIMARY)
	host_button.pressed.connect(_on_host_pressed)
	_mp_setup_row.add_child(host_button)

	_server_list_container = VBoxContainer.new()
	_server_list_container.add_theme_constant_override("separation", 6)
	_mp_setup_row.add_child(_server_list_container)
	_refresh_server_list({})

	var divider := UITheme.subtitle_label("— or join one —")
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mp_setup_row.add_child(divider)

	var ip_row := HBoxContainer.new()
	ip_row.add_theme_constant_override("separation", 8)
	_mp_setup_row.add_child(ip_row)
	var ip_label := UITheme.body_label("Server IP")
	ip_label.custom_minimum_size = Vector2(70.0, 0.0)
	ip_row.add_child(ip_label)
	_join_ip_edit = LineEdit.new()
	_join_ip_edit.placeholder_text = DEFAULT_JOIN_IP
	_join_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_row.add_child(_join_ip_edit)

	var port_row := HBoxContainer.new()
	port_row.add_theme_constant_override("separation", 8)
	_mp_setup_row.add_child(port_row)
	var port_label := UITheme.body_label("Port")
	port_label.custom_minimum_size = Vector2(70.0, 0.0)
	port_row.add_child(port_label)
	_join_port_edit = LineEdit.new()
	_join_port_edit.placeholder_text = str(NetManager.DEFAULT_PORT)
	_join_port_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	port_row.add_child(_join_port_edit)

	var join_button := UITheme.action_button("Join Server")
	join_button.pressed.connect(_on_join_pressed)
	_mp_setup_row.add_child(join_button)

	var setup_back_button := UITheme.action_button("Back")
	setup_back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# clip_text (set by action_button) makes get_minimum_size() ignore text
	# width entirely — fine for EXPAND_FILL buttons that get stretched by
	# their row, but SHRINK_CENTER sizes this one to its own minimum, which
	# collapsed to just the stylebox margins and clipped "Back" to nothing.
	setup_back_button.clip_text = false
	setup_back_button.pressed.connect(_on_back_pressed)
	_mp_setup_row.add_child(setup_back_button)

	_lobby_panel = VBoxContainer.new()
	_lobby_panel.add_theme_constant_override("separation", 14)
	_lobby_panel.visible = false
	# _multiplayer_row is an HBoxContainer with ALIGNMENT_CENTER; without
	# EXPAND_FILL a lone non-expanding child just gets its own shrink-wrapped
	# minimum width and gets centered in the leftover space, instead of
	# claiming the row's actual width — starved every row below it
	# (including the Start Match/Leave Lobby buttons) of room.
	_lobby_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_multiplayer_row.add_child(_lobby_panel)

	var lobby_columns := HBoxContainer.new()
	lobby_columns.add_theme_constant_override("separation", 20)
	_lobby_panel.add_child(lobby_columns)

	# Left column: host connect info. Whole column hidden (not just the
	# label) for non-host peers, so the players column gets the full row
	# width instead of leaving an empty gap on the left.
	_host_info_column = VBoxContainer.new()
	_host_info_column.custom_minimum_size = Vector2(150.0, 0.0)
	_host_info_column.add_theme_constant_override("separation", 6)
	lobby_columns.add_child(_host_info_column)

	var host_info_header := UITheme.header_label("Connect Info")
	_host_info_column.add_child(host_info_header)

	# No autowrap here — the text is fixed once set (doesn't change while
	# typing a name), so it's safe to let it size to its own natural width.
	# Autowrap previously forced each manual line to re-wrap inside the
	# narrow column, splitting "IP: 1.2.3.4" across two lines.
	_host_info_label = UITheme.body_label("")
	_host_info_column.add_child(_host_info_label)

	# Right column: player list. Header text carries the live "(n/6)" count.
	var players_column := VBoxContainer.new()
	players_column.add_theme_constant_override("separation", 8)
	players_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lobby_columns.add_child(players_column)

	_players_header_label = UITheme.header_label("Players")
	players_column.add_child(_players_header_label)

	# Populated per-player in _refresh_lobby_list() — one boxed panel row
	# each, rebuilt from scratch on every roster change (join/leave/rename).
	_lobby_list_container = VBoxContainer.new()
	_lobby_list_container.add_theme_constant_override("separation", 6)
	players_column.add_child(_lobby_list_container)

	var lobby_buttons := HBoxContainer.new()
	lobby_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	lobby_buttons.add_theme_constant_override("separation", 12)
	_lobby_panel.add_child(lobby_buttons)

	_start_match_button = UITheme.action_button("Start Match", UITheme.PRIMARY)
	_start_match_button.pressed.connect(_on_start_match_pressed)
	lobby_buttons.add_child(_start_match_button)

	var leave_button := UITheme.action_button("Leave Lobby")
	leave_button.pressed.connect(_on_leave_lobby_pressed)
	lobby_buttons.add_child(leave_button)

	_status_label = UITheme.muted_label("")
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

## Idle "sticker wobble" for the title — a small back-and-forth rotation,
## looping forever. Pivot is set on the deferred call once CenterContainer/
## VBoxContainer layout has actually sized the label (it's 0-size the instant
## it's added).
func _start_title_wobble(title: Label) -> void:
	title.set_deferred("pivot_offset", title.size / 2.0)
	call_deferred("_loop_title_wobble", title)

func _loop_title_wobble(title: Label) -> void:
	var tween := title.create_tween()
	tween.set_loops()
	tween.tween_property(title, "rotation", deg_to_rad(-3.0), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(title, "rotation", deg_to_rad(3.0), 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _resolve_player_name() -> String:
	var player_name := _name_edit.text.strip_edges()
	return player_name if not player_name.is_empty() else DEFAULT_NAME

func _resolve_capital_name() -> String:
	var capital_name := _capital_name_edit.text.strip_edges()
	return capital_name if not capital_name.is_empty() else DEFAULT_CAPITAL_NAME

func _on_single_player_pressed() -> void:
	single_player_requested.emit(_resolve_player_name(), _resolve_capital_name())

## Fires on every keystroke in either field (text_changed, not focus_exited —
## a click on empty space doesn't necessarily move focus off a LineEdit, so
## waiting for focus loss meant the rename could silently never fire). Only
## matters once we're actually in a lobby (host or joined) — before that
## there's no roster entry to update yet, host()/join() read the fields
## fresh anyway.
func _on_identity_field_edited(_new_text: String) -> void:
	if _lobby_panel.visible:
		_net.rename_self(_resolve_player_name(), _resolve_capital_name())

func _on_multiplayer_pressed() -> void:
	_mode_row.visible = false
	_multiplayer_row.visible = true
	_mp_setup_row.visible = true
	_lobby_panel.visible = false
	_lan_discovery.start_browsing()

func _on_back_pressed() -> void:
	_multiplayer_row.visible = false
	_mp_setup_row.visible = false
	_mode_row.visible = true
	_status_label.text = ""
	_lan_discovery.stop_browsing()

func _on_host_pressed() -> void:
	var player_name := _resolve_player_name()
	var capital_name := _resolve_capital_name()
	var err := _net.host(NetManager.DEFAULT_PORT, player_name, capital_name)
	if err != OK:
		_status_label.text = "Failed to host (error %d)" % err
		return
	_lan_discovery.stop_browsing()
	_lan_discovery.start_announcing({
		"name": player_name,
		"capital_name": capital_name,
		"player_count": _net.roster.size(),
		"max_players": NetManager.MAX_PLAYERS,
		"port": NetManager.DEFAULT_PORT,
	})
	_show_lobby()

## Shared by the manual Join Server button and clicking a discovered-server
## row (_on_server_row_pressed) — same connect path either way.
func _join(ip: String, port: int) -> void:
	var err := _net.join(ip, port, _resolve_player_name(), _resolve_capital_name())
	if err != OK:
		_status_label.text = "Failed to connect (error %d)" % err
		return
	_status_label.text = "Connecting..."
	_lan_discovery.stop_browsing()
	_show_lobby()

func _on_join_pressed() -> void:
	var ip := _join_ip_edit.text.strip_edges()
	if ip.is_empty():
		ip = DEFAULT_JOIN_IP
	var port := NetManager.DEFAULT_PORT
	var port_text := _join_port_edit.text.strip_edges()
	if not port_text.is_empty():
		port = int(port_text)
	_join(ip, port)

func _on_server_row_pressed(ip: String, port: int) -> void:
	_join_ip_edit.text = ip
	_join_port_edit.text = str(port)
	_join(ip, port)

func _on_start_match_pressed() -> void:
	_lan_discovery.stop_announcing()
	_net.start_match(randi())

func _on_leave_lobby_pressed() -> void:
	var was_host := _net.is_host
	_net.leave()
	_status_label.text = ""
	_lobby_panel.visible = false
	_mp_setup_row.visible = true
	if was_host:
		_lan_discovery.stop_announcing()
	_lan_discovery.start_browsing()

func _show_lobby() -> void:
	_mp_setup_row.visible = false
	_lobby_panel.visible = true
	_start_match_button.visible = _net.is_host
	_host_info_column.visible = _net.is_host
	if _net.is_host:
		_host_info_label.text = "Give your friends —\nIP: %s\nPort: %d" % [NetManager.local_ip_hint(), NetManager.DEFAULT_PORT]
	_refresh_lobby_list()

func _on_roster_updated(_roster: Dictionary) -> void:
	_status_label.text = ""
	_refresh_lobby_list()
	if _net.is_host:
		_lan_discovery.update_announce_info({
			"name": _resolve_player_name(),
			"capital_name": _resolve_capital_name(),
			"player_count": _net.roster.size(),
			"max_players": NetManager.MAX_PLAYERS,
			"port": NetManager.DEFAULT_PORT,
		})

func _on_connection_failed(reason: String) -> void:
	_status_label.text = "Connection failed: %s" % reason
	_lobby_panel.visible = false
	_mp_setup_row.visible = true
	_lan_discovery.start_browsing()

## Discovered LAN hosts, minus ones you can't actually join: match already
## started (that host's announce would already have stopped, but a stale
## packet could still be in flight) or the roster is already full.
func _on_servers_updated(servers: Dictionary) -> void:
	var joinable := {}
	for key in servers:
		var info: Dictionary = servers[key]
		if int(info.get("player_count", 0)) < int(info.get("max_players", 0)):
			joinable[key] = info
	_refresh_server_list(joinable)

func _refresh_server_list(servers: Dictionary) -> void:
	for row in _server_list_container.get_children():
		row.queue_free()

	if servers.is_empty():
		_server_list_container.add_child(UITheme.muted_label("Searching for LAN servers…"))
		return

	var keys := servers.keys()
	keys.sort()
	for key in keys:
		var info: Dictionary = servers[key]
		var row := UITheme.action_button("%s — %s (%d/%d)" % [info["name"], info["capital_name"], info["player_count"], info["max_players"]])
		row.pressed.connect(_on_server_row_pressed.bind(info["ip"], int(info["port"])))
		_server_list_container.add_child(row)

func _refresh_lobby_list() -> void:
	for row in _lobby_list_container.get_children():
		row.queue_free()

	var owner_ids := _net.roster.values().map(func(entry): return entry["owner_id"])
	owner_ids.sort()
	for owner_id in owner_ids:
		for entry in _net.roster.values():
			if entry["owner_id"] == owner_id:
				var row := UITheme.panel()
				var row_label := UITheme.body_label("%s — %s" % [entry["name"], entry["capital_name"]])
				# Autowrap, not a bare single-line label — an unwrapped Label's
				# minimum width is its full rendered text, so a long
				# name/base-name would grow this row past the card's width
				# and CenterContainer would resize/recenter the whole panel
				# as you type (the exact bug this is guarding against).
				row_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				row.add_child(row_label)
				_lobby_list_container.add_child(row)
				break

	_players_header_label.text = "Players (%d/%d)" % [_net.roster.size(), NetManager.MAX_PLAYERS]
	_start_match_button.disabled = not (_net.is_host and _net.roster.size() >= MIN_MATCH_PLAYERS)
