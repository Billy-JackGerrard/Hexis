## Terrain-tagged hex map plus A* pathfinding over it.
##
## Owns terrain per hex, wall state per hex-edge (walls block movement and
## line-of-sight across the specific edge they occupy, per
## 01-map-and-terrain.md), and infrastructure (Road/Bridge) per hex, and
## answers the domain-aware movement queries the simulation needs
## (passability, cost, adjacency). Rendering/scene state is out of scope here
## entirely.
class_name HexGrid
extends RefCounted

var _terrain: Dictionary = {} ## String key (HexCoord.to_key) -> Terrain.Type
## Walled edges, stored as an unordered pair key so either direction of
## traversal finds the same wall: "<min_key>|<max_key>".
var _walled_edges: Dictionary = {}
## Road/Bridge, keyed by the single hex they're built on (see
## Terrain.Infrastructure) — unlike walls, this is per-hex, not per-edge.
var _infrastructure: Dictionary = {}

func set_terrain(coord: HexCoord, terrain: Terrain.Type) -> void:
	_terrain[coord.to_key()] = terrain

func get_terrain(coord: HexCoord) -> Terrain.Type:
	return _terrain.get(coord.to_key(), Terrain.Type.OCEAN)

func has_hex(coord: HexCoord) -> bool:
	return _terrain.has(coord.to_key())

static func _edge_key(a: HexCoord, b: HexCoord) -> String:
	var ka := a.to_key()
	var kb := b.to_key()
	return ka + "|" + kb if ka < kb else kb + "|" + ka

func set_wall(a: HexCoord, b: HexCoord, walled: bool) -> void:
	var key := _edge_key(a, b)
	if walled:
		_walled_edges[key] = true
	else:
		_walled_edges.erase(key)

func is_walled_edge(a: HexCoord, b: HexCoord) -> bool:
	return _walled_edges.has(_edge_key(a, b))

func set_infrastructure(coord: HexCoord, infrastructure: Terrain.Infrastructure) -> void:
	if infrastructure == Terrain.Infrastructure.NONE:
		_infrastructure.erase(coord.to_key())
	else:
		_infrastructure[coord.to_key()] = infrastructure

func get_infrastructure(coord: HexCoord) -> Terrain.Infrastructure:
	return _infrastructure.get(coord.to_key(), Terrain.Infrastructure.NONE)

## Movement cost to cross from `from` into `to` for the given domain, or
## Terrain.INF if blocked by terrain/a wall/a standing building, after
## accounting for any Road/Bridge on `to` clearing a terrain block. Air
## ignores walls too, same as every other terrain rule (01-map-and-terrain.md).
## `overrides` is a troop def's `terrainOverrides` dict (05-troop-stat-schema.md),
## forwarded to Terrain.effective_cost — never clears a Wall, only terrain
## blocks. `blocked_land_hexes` is a caller-supplied {hex_key: true} set (see
## BuildingPlacement.land_blocking_hexes) of hexes a standing building
## occupies — only consulted for Domain.LAND, same Domain-gated shape as the
## wall check above; Infantry/Air/Naval never block on a building.
func edge_cost(from: HexCoord, to: HexCoord, domain: Terrain.Domain, overrides: Dictionary = {}, blocked_land_hexes: Dictionary = {}) -> float:
	if not has_hex(to):
		return Terrain.INF
	if domain != Terrain.Domain.AIR and is_walled_edge(from, to):
		return Terrain.INF
	if domain == Terrain.Domain.LAND and blocked_land_hexes.has(to.to_key()):
		return Terrain.INF
	return Terrain.effective_cost(get_terrain(to), domain, get_infrastructure(to), overrides)

func passable_neighbors(coord: HexCoord, domain: Terrain.Domain, overrides: Dictionary = {}, blocked_land_hexes: Dictionary = {}) -> Array[HexCoord]:
	var result: Array[HexCoord] = []
	for n in HexCoord.neighbors(coord):
		if edge_cost(coord, n, domain, overrides, blocked_land_hexes) != Terrain.INF:
			result.append(n)
	return result

## True if the straight hex-line from `a` to `b` (HexCoord.line) crosses any
## walled edge, per 01-map-and-terrain.md's Wall line-of-sight rule ("an attack
## whose line from attacker-hex to target-hex crosses a walled edge is
## blocked"). Checked against every consecutive pair along the line, not just
## the endpoints, so a wall anywhere between attacker and target blocks the
## shot, not only a wall adjacent to one of them. Air-domain exemption is the
## caller's job (CombatTargeting), same as every other terrain rule.
func is_line_blocked(a: HexCoord, b: HexCoord) -> bool:
	var hexes := HexCoord.line(a, b)
	for i in range(hexes.size() - 1):
		if is_walled_edge(hexes[i], hexes[i + 1]):
			return true
	return false

## Standard hex A*, edge cost per `edge_cost`. Returns [] if no path exists.
## Path is computed once per order per the design (not re-planned every tick);
## callers own re-invoking this when blocked or re-ordered.
func find_path(start: HexCoord, goal: HexCoord, domain: Terrain.Domain, overrides: Dictionary = {}, blocked_land_hexes: Dictionary = {}) -> Array[HexCoord]:
	if not has_hex(start) or not has_hex(goal):
		return []
	if start.equals(goal):
		return [start]

	var open: Dictionary = {start.to_key(): true}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start.to_key(): 0.0}
	var f_score: Dictionary = {start.to_key(): HexCoord.distance(start, goal)}
	var coord_by_key: Dictionary = {start.to_key(): start}

	while not open.is_empty():
		var current_key: String = ""
		var best_f: float = INF
		for k in open.keys():
			if f_score.get(k, INF) < best_f:
				best_f = f_score[k]
				current_key = k
		var current: HexCoord = coord_by_key[current_key]

		if current.equals(goal):
			var path: Array[HexCoord] = [current]
			var k: String = current_key
			while came_from.has(k):
				k = came_from[k]
				path.push_front(coord_by_key[k])
			return path

		open.erase(current_key)
		for neighbor in HexCoord.neighbors(current):
			var step_cost := edge_cost(current, neighbor, domain, overrides, blocked_land_hexes)
			if step_cost == Terrain.INF:
				continue
			var neighbor_key := neighbor.to_key()
			var tentative_g: float = g_score[current_key] + step_cost
			if tentative_g < g_score.get(neighbor_key, INF):
				coord_by_key[neighbor_key] = neighbor
				came_from[neighbor_key] = current_key
				g_score[neighbor_key] = tentative_g
				f_score[neighbor_key] = tentative_g + HexCoord.distance(neighbor, goal)
				open[neighbor_key] = true

	return []
