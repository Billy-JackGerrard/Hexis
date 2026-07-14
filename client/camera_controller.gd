## Right-mouse-drag pan + scroll-wheel zoom for the board — the deferred
## "camera pan/zoom polish" item from the build order. Left button stays
## exclusively InputController's (select/move/drag-select), so panning uses
## the right button to avoid any conflict. Optional bounds (set_bounds) keep
## panning/center_on from wandering past the map edge; zoom is left unclamped.
class_name CameraController
extends Camera2D

const MIN_ZOOM := 0.6
const MAX_ZOOM := 2.5
const ZOOM_STEP := 0.1
const PAN_SPEED := 0.55 ## scales right-drag pan distance; 1.0 tracked the mouse 1:1 and felt too fast

var _panning := false
var _bounds_min := Vector2.ZERO
var _bounds_max := Vector2.ZERO
var _has_bounds := false

func center_on(world_pos: Vector2) -> void:
	position = world_pos
	if _has_bounds:
		position = position.clamp(_bounds_min, _bounds_max)

func set_bounds(bounds_min: Vector2, bounds_max: Vector2) -> void:
	_bounds_min = bounds_min
	_bounds_max = bounds_max
	_has_bounds = true
	position = position.clamp(_bounds_min, _bounds_max)

func _ready() -> void:
	make_current()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_STEP)
	elif event is InputEventMouseMotion and _panning:
		position -= event.relative * zoom * PAN_SPEED
		if _has_bounds:
			position = position.clamp(_bounds_min, _bounds_max)

func _zoom_by(delta: float) -> void:
	var new_zoom: float = clampf(zoom.x + delta, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
