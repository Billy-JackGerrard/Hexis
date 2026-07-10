## Axial (flat-top) hex <-> pixel-space projection for the rendering layer.
## Pure math, deliberately kept out of sim/hex/hex_coord.gd — that file notes
## orientation is "a rendering concern, not decided here"; this is where that
## decision lives. Flat-top was picked because its canonical neighbor order
## matches HexCoord.DIRECTIONS exactly (Red Blob Games' flat-top reference).
class_name HexView
extends RefCounted

const HEX_SIZE: float = 32.0
const SQRT3: float = 1.7320508075688772

static func axial_to_pixel(coord: HexCoord, size: float = HEX_SIZE) -> Vector2:
	var x := size * (1.5 * coord.q)
	var y := size * (SQRT3 * 0.5 * coord.q + SQRT3 * coord.r)
	return Vector2(x, y)

static func pixel_to_axial(point: Vector2, size: float = HEX_SIZE) -> HexCoord:
	var q := (2.0 / 3.0 * point.x) / size
	var r := (-1.0 / 3.0 * point.x + SQRT3 / 3.0 * point.y) / size
	return _cube_round(q, r, -q - r)

## Standard cube-round technique (round each axis, then recompute whichever
## axis drifted furthest so q+r+s stays 0) — mirrors HexCoord._cube_round,
## kept as a local copy rather than reaching into that internal method.
static func _cube_round(q: float, r: float, s: float) -> HexCoord:
	var rq: float = roundf(q)
	var rr: float = roundf(r)
	var rs: float = roundf(s)
	var q_diff: float = absf(rq - q)
	var r_diff: float = absf(rr - r)
	var s_diff: float = absf(rs - s)
	if q_diff > r_diff and q_diff > s_diff:
		rq = -rr - rs
	elif r_diff > s_diff:
		rr = -rq - rs
	return HexCoord.new(int(rq), int(rr))

## Flat-top hex corner offsets around a center, for drawing a Polygon2D.
static func corners(size: float = HEX_SIZE) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle_deg := 60.0 * i
		var angle_rad := deg_to_rad(angle_deg)
		points.append(Vector2(size * cos(angle_rad), size * sin(angle_rad)))
	return points

## World-space endpoints of the edge SHARED between two ADJACENT hexes —
## used for wall rendering (Walls are edge-keyed: BuildingInstance.hex_a/
## hex_b, not a single hex). Undefined for non-adjacent a/b.
static func edge_segment(a: HexCoord, b: HexCoord, size: float = HEX_SIZE) -> PackedVector2Array:
	var center := axial_to_pixel(a, size)
	var towards := axial_to_pixel(b, size) - center
	var angle_deg := rad_to_deg(towards.angle())
	if angle_deg < 0.0:
		angle_deg += 360.0
	var corner_index := int(roundf((angle_deg - 30.0) / 60.0)) % 6
	if corner_index < 0:
		corner_index += 6
	var hex_corners := corners(size)
	return PackedVector2Array([center + hex_corners[corner_index], center + hex_corners[(corner_index + 1) % 6]])
