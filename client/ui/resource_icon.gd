## Tiny procedural resource glyphs — a wheat sheaf (Food), stacked stone
## (Stone), a gear (Steel), a log (Wood), and a fuel drop (Fuel) — drawn with
## _draw() so no sprite assets are needed yet (see game-design/10, "placeholder
## art until the loop is fun"). Colored per UITheme.RESOURCE_COLOR with the
## same dark cartoon outline as the rest of the HUD. Used by resource_bar.gd
## and UITheme.cost_chips()/chip() wherever a resource needs a glyph, not just
## a color-coded label.
class_name ResourceIcon
extends Control

var resource_type: ResourceType.Type = ResourceType.Type.FOOD:
	set(value):
		resource_type = value
		queue_redraw()

func _init(type: ResourceType.Type = ResourceType.Type.FOOD, size: float = 20.0) -> void:
	resource_type = type
	custom_minimum_size = Vector2(size, size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var fill: Color = UITheme.RESOURCE_COLOR[resource_type]
	var outline := UITheme.PANEL_BORDER
	var r := size.x / 2.0
	var c := size / 2.0
	match resource_type:
		ResourceType.Type.FOOD:
			_draw_food(c, r, fill, outline)
		ResourceType.Type.STONE:
			_draw_stone(c, r, fill, outline)
		ResourceType.Type.STEEL:
			_draw_gear(c, r, fill, outline)
		ResourceType.Type.WOOD:
			_draw_log(c, r, fill, outline)
		ResourceType.Type.FUEL:
			_draw_drop(c, r, fill, outline)

## Wheat sheaf: three short strokes fanning up from a base point.
func _draw_food(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var base := c + Vector2(0, r * 0.7)
	var tips := [c + Vector2(-r * 0.55, -r * 0.7), c + Vector2(0, -r * 0.85), c + Vector2(r * 0.55, -r * 0.7)]
	for tip in tips:
		draw_line(base, tip, outline, 5.0)
		draw_line(base, tip, fill, 2.5)
	draw_circle(base, r * 0.18, outline)
	draw_circle(base, r * 0.11, fill)

## Two stacked rounded stone lumps.
func _draw_stone(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var bottom_rect := Rect2(c + Vector2(-r * 0.75, r * 0.05), Vector2(r * 1.5, r * 0.75))
	var top_rect := Rect2(c + Vector2(-r * 0.5, -r * 0.55), Vector2(r * 1.0, r * 0.65))
	draw_rect(bottom_rect.grow(2.0), outline, true)
	draw_rect(bottom_rect, fill, true)
	draw_rect(top_rect.grow(2.0), outline, true)
	draw_rect(top_rect, fill, true)

## Simple 6-tooth gear: ring + notches, dark hole in the middle.
func _draw_gear(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	draw_circle(c, r * 0.85, outline)
	draw_circle(c, r * 0.68, fill)
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var dir := Vector2(cos(angle), sin(angle))
		var tooth_center := c + dir * r * 0.85
		draw_circle(tooth_center, r * 0.22, outline)
		draw_circle(tooth_center, r * 0.14, fill)
	draw_circle(c, r * 0.28, outline)
	draw_circle(c, r * 0.18, UITheme.PANEL_BG)

## A short log: outer bark rectangle, inner rings on one cut end.
func _draw_log(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var rect := Rect2(c + Vector2(-r * 0.85, -r * 0.4), Vector2(r * 1.7, r * 0.8))
	draw_rect(rect.grow(2.0), outline, true)
	draw_rect(rect, fill, true)
	var end_center := c + Vector2(r * 0.6, 0)
	draw_circle(end_center, r * 0.32, outline)
	draw_circle(end_center, r * 0.24, fill.lightened(0.2))
	draw_circle(end_center, r * 0.1, outline)

## Fuel droplet: a rounded teardrop.
func _draw_drop(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var points := PackedVector2Array()
	var steps := 24
	for i in range(steps + 1):
		var t := float(i) / float(steps) * TAU
		# Teardrop: circle bottom, pinched point at top.
		var wobble: float = 1.0 - 0.5 * maxf(0.0, cos(t))
		var pt := c + Vector2(sin(t) * r * 0.7 * wobble, -cos(t) * r * 0.85)
		points.append(pt)
	draw_colored_polygon(points, outline)
	var inner := PackedVector2Array()
	for p in points:
		inner.append(c + (p - c) * 0.8)
	draw_colored_polygon(inner, fill)
