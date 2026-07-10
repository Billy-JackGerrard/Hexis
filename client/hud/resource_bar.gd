## Top-of-screen resource bar (build order item 3): the local player's Food/
## Steel/Fuel/Stone/Wood totals, in the order 09-ui-and-controls.md's Implied
## Requirements list them. Reads state.pool_for(owner_id) — safe to call
## before the first 5-second economy tick, since ResourcePool self-seeds at
## ResourceType.STARTING on construction (see MatchState.pool_for/player_for).
## A resource currently in deficit (Food/Fuel only, per
## ResourceType.can_deficit_drain) renders in red instead of white. Polled
## every _process like every other client/ view — see hud_layer.gd's header
## comment on why this doesn't need signals.
class_name ResourceBar
extends Control

var state: MatchState
var owner_id: String

const HEIGHT := 32.0
const BG_COLOR := Color(0.05, 0.05, 0.08, 0.75)
const NORMAL_COLOR := Color.WHITE
const DEFICIT_COLOR := Color(1.0, 0.3, 0.3)
const COLUMN_WIDTH := 140.0
const FONT_SIZE := 16

## Display order + labels per 09-ui-and-controls.md's Resource HUD line,
## not ResourceType.ALL's declaration order (Food/Stone/Steel/Wood/Fuel).
const DISPLAY_ORDER: Array[Array] = [
	[ResourceType.Type.FOOD, "Food"],
	[ResourceType.Type.STEEL, "Steel"],
	[ResourceType.Type.FUEL, "Fuel"],
	[ResourceType.Type.STONE, "Stone"],
	[ResourceType.Type.WOOD, "Wood"],
]

func setup(p_state: MatchState, p_owner_id: String) -> void:
	state = p_state
	owner_id = p_owner_id
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = 0.0
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if state == null:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x, HEIGHT)), BG_COLOR, true)
	var pool := state.pool_for(owner_id)
	var font := get_theme_default_font()
	var x := 16.0
	for entry in DISPLAY_ORDER:
		var type: ResourceType.Type = entry[0]
		var label: String = entry[1]
		var amount := pool.get_amount(type)
		var color := DEFICIT_COLOR if pool.is_deficit(type) else NORMAL_COLOR
		var text := "%s: %d" % [label, int(round(amount))]
		draw_string(font, Vector2(x, HEIGHT * 0.5 + FONT_SIZE * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
		x += COLUMN_WIDTH
