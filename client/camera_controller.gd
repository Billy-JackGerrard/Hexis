## Right-mouse-drag pan + scroll-wheel zoom for the board — the deferred
## "camera pan/zoom polish" item from the build order. Left button stays
## exclusively InputController's (select/move/drag-select), so panning uses
## the right button to avoid any conflict. Optional bounds (set_bounds) clamp
## the *visible edge* of the viewport to the map extents, not just the camera
## center — clamping center alone let half the screen hang off the map at
## the near-max-zoom-out end of MIN_ZOOM.
class_name CameraController
extends Camera2D

const MIN_ZOOM := 0.85
const MAX_ZOOM := 2.5
const ZOOM_STEP := 0.1
const PAN_SPEED := 0.55 ## scales right-drag pan distance; 1.0 tracked the mouse 1:1 and felt too fast

var _panning := false
var _bounds_min := Vector2.ZERO
var _bounds_max := Vector2.ZERO
var _has_bounds := false

## Set by main.gd once PauseMenu exists. While it's open, pan/zoom input is
## ignored — relying solely on PauseMenu's full-rect Control to swallow the
## event via mouse_filter STOP wasn't enough (scroll wheel still reached this
## Node2D's _unhandled_input even with the mouse off the popup), so this
## polls the flag directly instead.
var pause_menu: PauseMenu

func is_panning() -> bool:
	return _panning

func center_on(world_pos: Vector2) -> void:
	position = _clamped_position(world_pos)

func set_bounds(bounds_min: Vector2, bounds_max: Vector2) -> void:
	_bounds_min = bounds_min
	_bounds_max = bounds_max
	_has_bounds = true
	position = _clamped_position(position)

func _ready() -> void:
	make_current()

func _unhandled_input(event: InputEvent) -> void:
	if pause_menu != null and pause_menu.is_open:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_by(ZOOM_STEP)
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_by(-ZOOM_STEP)
	elif event is InputEventMouseMotion and _panning:
		position = _clamped_position(position - event.relative / zoom * PAN_SPEED)

func _zoom_by(delta: float) -> void:
	var new_zoom: float = clampf(zoom.x + delta, MIN_ZOOM, MAX_ZOOM)
	zoom = Vector2(new_zoom, new_zoom)
	# Zooming out grows the viewport's world-space half-extent, so a position
	# that was in-bounds a moment ago can now hang the screen edge past the
	# map — reclamp with the new zoom applied.
	position = _clamped_position(position)

## Clamps so the viewport's visible edge stays within the map bounds, not
## just the camera center. Falls back to centering on the map's midpoint on
## whichever axis the viewport is currently wider than the map itself (can't
## keep both edges in-bounds at once there).
func _clamped_position(pos: Vector2) -> Vector2:
	if not _has_bounds:
		return pos
	var half_extent := get_viewport().get_visible_rect().size / (2.0 * zoom.x)
	var eff_min := _bounds_min + half_extent
	var eff_max := _bounds_max - half_extent
	var result := pos
	result.x = clampf(pos.x, eff_min.x, eff_max.x) if eff_min.x <= eff_max.x else (_bounds_min.x + _bounds_max.x) * 0.5
	result.y = clampf(pos.y, eff_min.y, eff_max.y) if eff_min.y <= eff_max.y else (_bounds_min.y + _bounds_max.y) * 0.5
	return result
