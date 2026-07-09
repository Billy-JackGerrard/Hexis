## Right-mouse-drag pan + scroll-wheel zoom for the board — the deferred
## "camera pan/zoom polish" item from the build order. Left button stays
## exclusively InputController's (select/move/drag-select), so panning uses
## the right button to avoid any conflict.
class_name CameraController
extends Camera2D

const MIN_ZOOM := 0.35
const MAX_ZOOM := 2.5
const ZOOM_STEP := 0.1

var _panning := false

func center_on(world_pos: Vector2) -> void:
	position = world_pos

func _ready() -> void:
	make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(-ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(ZOOM_STEP)
	elif event is InputEventMouseMotion and _panning:
		position -= event.relative * zoom

func _zoom_by(delta: float) -> void:
	var new_zoom: float = clampf(zoom.x + delta, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
