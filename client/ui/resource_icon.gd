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

## Wheat ear: a stem with paired kernels (pointed diamonds) tapering to a tip
## at top — reworked from the old three-line fan, which read as a shapeless
## asterisk at 22px and was hard to tell apart from the other glyphs.
func _draw_food(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var top := c + Vector2(0, -r * 0.95)
	var bottom := c + Vector2(0, r * 0.75)
	draw_line(bottom, top, outline, 4.0)
	draw_line(bottom, top, fill, 1.8)

	var pair_count := 3
	for i in range(pair_count):
		var t := float(i) / float(pair_count - 1) ## 0 (bottom pair) .. 1 (top pair)
		var y: float = lerp(bottom.y - r * 0.1, top.y + r * 0.28, t)
		var spread: float = r * 0.4 * (1.0 - t * 0.35)
		var kernel_size: float = r * 0.32 * (1.0 - t * 0.2)
		_draw_kernel(Vector2(c.x - spread, y), kernel_size, -0.5, fill, outline)
		_draw_kernel(Vector2(c.x + spread, y), kernel_size, 0.5, fill, outline)
	_draw_kernel(top, r * 0.28, 0.0, fill, outline)

## A single wheat kernel: a thin diamond, its long axis tilted `tilt` radians
## off vertical so paired kernels fan outward from the stem.
func _draw_kernel(pos: Vector2, size: float, tilt: float, fill: Color, outline: Color) -> void:
	var dir := Vector2(sin(tilt), -cos(tilt))
	var side := dir.orthogonal()
	var points := PackedVector2Array([
		pos + dir * size, pos + side * size * 0.4,
		pos - dir * size, pos - side * size * 0.4,
	])
	draw_colored_polygon(points, outline)
	var inner := PackedVector2Array()
	for p in points:
		inner.append(pos + (p - pos) * 0.6)
	draw_colored_polygon(inner, fill)

## A rock pile: three overlapping round boulders (biggest at the base) — a
## rounded-blob silhouette, deliberately not rectangular, so it doesn't read
## as the same block shape as the log at a glance (Stone vs Wood was the
## reported mix-up at small icon sizes).
func _draw_stone(c: Vector2, r: float, fill: Color, outline: Color) -> void:
	var boulders := [
		{"center": c + Vector2(-r * 0.4, r * 0.25), "radius": r * 0.5},
		{"center": c + Vector2(r * 0.35, r * 0.3), "radius": r * 0.45},
		{"center": c + Vector2(0.0, -r * 0.25), "radius": r * 0.42},
	]
	for b in boulders:
		draw_circle(b["center"], b["radius"] + 2.0, outline)
	for b in boulders:
		draw_circle(b["center"], b["radius"], fill)

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
