## Per-base info panel (build order item 3): shown whenever
## InputController.selected_base_id is set (click precedence case 3 —
## clicking one of the local player's own base buildings, see
## input_controller.gd's header comment). Currently just the population
## indicator ("used/cap", per 09-ui-and-controls.md's Population indicator
## requirement — per-base, not a global HUD figure); the build menu and
## production queue sub-panels (items 4-5) extend this same panel. Polled
## every _process like every other client/ view.
class_name BasePanel
extends Control

var state: MatchState
var owner_id: String
var input_controller: InputController

const WIDTH := 220.0
const HEIGHT := 60.0
const MARGIN := 12.0
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.85)
const TEXT_COLOR := Color.WHITE
const FONT_SIZE := 16

func setup(p_state: MatchState, p_owner_id: String, p_input_controller: InputController) -> void:
	state = p_state
	owner_id = p_owner_id
	input_controller = p_input_controller
	# Top-right corner, just under the resource bar.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -WIDTH - MARGIN
	offset_right = -MARGIN
	offset_top = ResourceBar.HEIGHT + MARGIN
	offset_bottom = ResourceBar.HEIGHT + MARGIN + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _selected_base() -> BaseInstance:
	if input_controller.selected_base_id == "":
		return null
	return state.find_base(input_controller.selected_base_id)

func _draw() -> void:
	var base := _selected_base()
	if base == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), BG_COLOR, true)
	var font := get_theme_default_font()
	var used := Population.population_used(base, state.building_defs)
	var cap := Population.population_cap(base, state.building_defs)
	draw_string(font, Vector2(12.0, 24.0), base.base_def_id.capitalize(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
	draw_string(font, Vector2(12.0, 48.0), "Population: %d/%d" % [used, cap], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, TEXT_COLOR)
