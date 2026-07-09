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

## All hexes at exactly `radius` from `center` (the boundary of range_within,
## not the filled disk) — radius 0 returns just [center]. Standard ring-walk:
## start `radius` steps out in direction 4, then take `radius` steps in each
## of the 6 directions in turn.
static func ring(center: HexCoord, radius: int) -> Array[HexCoord]:
	if radius <= 0:
		return [center]
	var result: Array[HexCoord] = []
	var hex := HexCoord.new(center.q + DIRECTIONS[4].x * radius, center.r + DIRECTIONS[4].y * radius)
	for direction in range(6):
		for _step in range(radius):
			result.append(hex)
			hex = neighbor(hex, direction)
	return result

## The neighbor direction index (0-5) of `origin` that points furthest away
## from `from` — i.e. straight-line-away from an attacker's hex through the
## target's hex. Used by knockback (04-combat.md's statusEffectOnHit). Ties
## (e.g. `from` and `origin` on the same hex) resolve to direction 0.
static func direction_away(from: HexCoord, origin: HexCoord) -> int:
	var best_dir := 0
	var best_dist := -1
	for i in range(6):
		var d := distance(neighbor(origin, i), from)
		if d > best_dist:
			best_dist = d
			best_dir = i
	return best_dir

## The unbroken chain of hexes from `a` to `b` inclusive (length distance(a,b)+1),
## via cube-coordinate linear interpolation + rounding — the standard hex-line
## algorithm (each step is the nearest hex to the straight-line point at that
## fraction of the way from a to b). Used by HexGrid.is_line_blocked() for Wall
## line-of-sight (01-map-and-terrain.md: "an attack whose line from attacker-hex
## to target-hex crosses a walled edge is blocked"). A tiny per-axis epsilon is
## added before rounding so the line never lands exactly on a hex edge/vertex
## (which would make cube_round's tie-break ambiguous/inconsistent) — a well-
## known wrinkle of this algorithm, not a precision bug.
static func line(a: HexCoord, b: HexCoord) -> Array[HexCoord]:
	var n := distance(a, b)
	var result: Array[HexCoord] = []
	if n == 0:
		result.append(a)
		return result
	for i in range(n + 1):
		var t := float(i) / float(n)
		result.append(_cube_round(
			lerp(float(a.q), float(b.q), t) + 1e-6,
			lerp(float(a.r), float(b.r), t) + 2e-6,
			lerp(float(a.s()), float(b.s()), t) - 3e-6,
		))
	return result

## Rounds fractional cube coordinates to the nearest valid hex, per the
## standard technique: round each axis independently, then recompute whichever
## axis drifted furthest from its rounded value so q+r+s stays 0.
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
