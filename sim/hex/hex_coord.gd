## Axial/cube hex-coordinate math. No rendering or Godot-node dependency —
## pure math, per game-design/01-map-and-terrain.md's Rendering Notes
## ("standalone hex-math module... zero dependency on [the renderer]").
##
## Coordinates are axial (q, r); cube's implicit s = -q - r wherever needed.
## Flat-top or pointed-top orientation is a rendering concern, not decided here.
class_name HexCoord
extends RefCounted

var q: int
var r: int

func _init(p_q: int = 0, p_r: int = 0) -> void:
	q = p_q
	r = p_r

func s() -> int:
	return -q - r

func equals(other: HexCoord) -> bool:
	return q == other.q and r == other.r

func to_key() -> String:
	return "%d,%d" % [q, r]

func _to_string() -> String:
	return "HexCoord(%d, %d)" % [q, r]

static func from_key(key: String) -> HexCoord:
	var parts := key.split(",")
	return HexCoord.new(int(parts[0]), int(parts[1]))

static func add(a: HexCoord, b: HexCoord) -> HexCoord:
	return HexCoord.new(a.q + b.q, a.r + b.r)

## The six axial neighbor directions, in a fixed winding order.
const DIRECTIONS := [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]

static func neighbor(coord: HexCoord, direction: int) -> HexCoord:
	var d: Vector2i = DIRECTIONS[direction % 6]
	return HexCoord.new(coord.q + d.x, coord.r + d.y)

static func neighbors(coord: HexCoord) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	for i in range(6):
		result.append(neighbor(coord, i))
	return result

## Integer hex-distance (cube-coordinate formula) — used directly for
## range/vision/engagement checks per 01-map-and-terrain.md.
static func distance(a: HexCoord, b: HexCoord) -> int:
	return int((abs(a.q - b.q) + abs(a.r - b.r) + abs(a.s() - b.s())) / 2)

## All hexes within `radius` of `center`, inclusive (radius 0 -> just center).
static func range_within(center: HexCoord, radius: int) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	for dq in range(-radius, radius + 1):
		var r_min: int = max(-radius, -dq - radius)
		var r_max: int = min(radius, -dq + radius)
		for dr in range(r_min, r_max + 1):
			result.append(HexCoord.new(center.q + dq, center.r + dr))
	return result
