## Small, stateless animation helpers ("juice") for the candy HUD — bouncy
## pop-ins, hover growth, punch feedback, and number count-ups. Pure Tween
## wiring, no colors/nodes of its own; pairs with client/ui/ui_theme.gd's
## factories. Costs nothing when idle (Tweens only run while animating).
class_name UIJuice
extends RefCounted

const POP_IN_DURATION := 0.28
const HOVER_SCALE := 1.06
const HOVER_DURATION := 0.1
const PUNCH_SCALE := 1.15
const PUNCH_DURATION := 0.12

## Ensures `pivot_offset` is centered so scale tweens grow/shrink in place
## instead of from the top-left corner. Safe to call every time (size may
## change between rebuilds).
static func _center_pivot(control: Control) -> void:
	control.pivot_offset = control.size / 2.0

## Bouncy scale-in, e.g. when a panel is (re)shown after a selection change.
static func pop_in(control: Control) -> void:
	_center_pivot(control)
	control.scale = Vector2(0.8, 0.8)
	var tween := control.create_tween()
	tween.tween_callback(_center_pivot.bind(control))
	tween.tween_property(control, "scale", Vector2.ONE, POP_IN_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A quick scale punch to draw the eye to a value change (e.g. a resource
## ticking up, an alert firing).
static func pop(control: Control) -> void:
	_center_pivot(control)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(PUNCH_SCALE, PUNCH_SCALE), PUNCH_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2.ONE, PUNCH_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

static func _grow(control: Control, target: Vector2) -> void:
	var tween := control.create_tween()
	tween.tween_property(control, "scale", target, HOVER_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

static func _shrink(control: Control) -> void:
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, HOVER_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

## Wires a Control (typically a Button) to grow slightly on hover — call once
## per control, e.g. from UITheme.action_button(). `horizontal_grow` false
## scales height only, keeping the control's width fixed — for buttons that
## already span their container's full width (e.g. action rows inside
## BuildingPanel/SquadPanel's clipping ScrollContainer), horizontal growth
## would push past the clip edge and get visibly cut off.
static func hover_grow(control: Control, horizontal_grow: bool = true) -> void:
	control.pivot_offset = control.size / 2.0
	control.resized.connect(_center_pivot.bind(control))
	var target := Vector2(HOVER_SCALE, HOVER_SCALE) if horizontal_grow else Vector2(1.0, HOVER_SCALE)
	control.mouse_entered.connect(_grow.bind(control, target))
	control.mouse_exited.connect(_shrink.bind(control))

## Arg order matters: Callable.bind() appends bound args after the ones
## passed at call time, and tween_method() calls with `v` first — so `v` must
## be the leading parameter here, with label/fmt bound on afterward.
static func _apply_count_step(v: float, label: Label, fmt: String) -> void:
	label.text = fmt % int(round(v))

## Tweens the integer value shown by `label` from `from` to `to` over
## `duration` seconds, formatting each step with `fmt` (a format string with
## one `%d`, e.g. "Food %d"). Fire-and-forget: safe to call repeatedly — a
## call while a previous tween on the same label is still running (e.g. a
## resource ticking every frame, faster than `duration`) kills that one
## first, so competing tweens never fight over `label.text` and leave it
## stuck on a stale value.
static func count_up(label: Label, from: int, to: int, fmt: String = "%d", duration: float = 0.4) -> void:
	if label.has_meta("_count_up_tween"):
		var prev: Tween = label.get_meta("_count_up_tween")
		if prev != null and prev.is_valid():
			prev.kill()
	if from == to:
		label.text = fmt % to
		return
	var tween := label.create_tween()
	label.set_meta("_count_up_tween", tween)
	var step := Callable(UIJuice, "_apply_count_step").bind(label, fmt)
	tween.tween_method(step, float(from), float(to), duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
