## Pre-game entry screen: player name + Single Player/Multiplayer choice,
## shown as a CanvasLayer overlay (ignores world Camera2D like hud_layer.gd,
## and its full-rect background stops mouse input from reaching the world
## underneath while it's up). main.gd adds this first and defers building
## the demo MatchState/board/HUD until single_player_requested fires.
## Multiplayer isn't implemented yet (07-data-architecture.md section 8 —
## networking is deliberately deferred), so clicking Multiplayer only swaps
## in Host Server/Join Server buttons that show a "not implemented" status
## line rather than doing anything.
class_name StartScreen
extends CanvasLayer

signal single_player_requested(player_name: String)

const BG_COLOR := Color(0.05, 0.05, 0.08, 0.92)
const DEFAULT_NAME := "Unnamed Player"

var _name_edit: LineEdit
var _mode_row: HBoxContainer
var _multiplayer_row: HBoxContainer
var _status_label: Label

func setup() -> void:
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(root)

	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bg)

	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320.0, 0.0)
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Hexis"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = DEFAULT_NAME
	vbox.add_child(_name_edit)

	_mode_row = HBoxContainer.new()
	_mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_row.add_theme_constant_override("separation", 12)
	vbox.add_child(_mode_row)

	var single_button := Button.new()
	single_button.text = "Single Player"
	single_button.pressed.connect(_on_single_player_pressed)
	_mode_row.add_child(single_button)

	var multiplayer_button := Button.new()
	multiplayer_button.text = "Multiplayer"
	multiplayer_button.pressed.connect(_on_multiplayer_pressed)
	_mode_row.add_child(multiplayer_button)

	# Hidden until Multiplayer is clicked; Host/Join are stubs (see header
	# comment) and Back returns to the Single Player/Multiplayer row above.
	_multiplayer_row = HBoxContainer.new()
	_multiplayer_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_multiplayer_row.add_theme_constant_override("separation", 12)
	_multiplayer_row.visible = false
	vbox.add_child(_multiplayer_row)

	var host_button := Button.new()
	host_button.text = "Host Server"
	host_button.pressed.connect(_on_multiplayer_stub_pressed)
	_multiplayer_row.add_child(host_button)

	var join_button := Button.new()
	join_button.text = "Join Server"
	join_button.pressed.connect(_on_multiplayer_stub_pressed)
	_multiplayer_row.add_child(join_button)

	var back_button := Button.new()
	back_button.text = "Back"
	back_button.pressed.connect(_on_back_pressed)
	_multiplayer_row.add_child(back_button)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_status_label)

func _on_single_player_pressed() -> void:
	var player_name := _name_edit.text.strip_edges()
	if player_name.is_empty():
		player_name = DEFAULT_NAME
	single_player_requested.emit(player_name)

func _on_multiplayer_pressed() -> void:
	_mode_row.visible = false
	_multiplayer_row.visible = true

func _on_back_pressed() -> void:
	_multiplayer_row.visible = false
	_mode_row.visible = true
	_status_label.text = ""

func _on_multiplayer_stub_pressed() -> void:
	_status_label.text = "Multiplayer not implemented yet"
