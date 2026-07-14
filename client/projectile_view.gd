## Placeholder rendering for in-flight ballistic shots (sim/combat/
## projectile_instance.gd, advanced by ProjectileSystem): a small owner-tinted
## dot per ProjectileInstance, positioned by lerping attacker_hex -> aim_hex
## over its travel time — same "sim owns integer state, the view interpolates
## it for display" split as squad_view.gd's edge_progress lerp. A traveling
## beam (non-empty beam_hexes, e.g. Wind Spire) instead sweeps along
## attacker_hex -> its last beam hex, driven by beam_elapsed rather than
## remaining_time. Falls back to a fixed red if the owner has no assigned
## color (shouldn't happen outside tests).
class_name ProjectileView
extends Node2D

var projectiles: Array[ProjectileInstance] = []
var owner_colors: Dictionary = {} ## owner_id -> Color

var state: MatchState

## Projectile positions lerp off remaining_time/beam_elapsed, both per-tick sim
## state (ProjectileSystem advances them on a fine tick) — so, like squad_view,
## a 60fps redraw draws identical frames between ticks. Gate on tick change.
var _last_drawn_tick: int = -1

const RADIUS := 4.0
const OUTLINE_COLOR := Color(0.0, 0.0, 0.0, 0.6)
const DEFAULT_COLOR := Color(0.9, 0.15, 0.1)

func setup(p_state: MatchState, p_projectiles: Array[ProjectileInstance], p_owner_colors: Dictionary) -> void:
	state = p_state
	projectiles = p_projectiles
	owner_colors = p_owner_colors

func _process(_delta: float) -> void:
	if state == null or state.tick == _last_drawn_tick:
		return
	_last_drawn_tick = state.tick
	queue_redraw()

func _draw() -> void:
	for projectile in projectiles:
		var color: Color = owner_colors.get(projectile.owner_id, DEFAULT_COLOR)
		var pos := _position_of(projectile)
		draw_circle(pos, RADIUS, color)
		draw_arc(pos, RADIUS, 0.0, TAU, 12, OUTLINE_COLOR, 1.0)

## Current world-space point along the shot's flight. A beam sweeps its front
## from attacker_hex to its last hex at `projectileSpeed` hexes/sec
## (beam_elapsed accumulates every ProjectileSystem tick); an ordinary point
## shot lerps attacker_hex -> aim_hex by elapsed/total travel time, recovered
## from remaining_time (ProjectileSystem only ever counts it down from the
## original distance/projectileSpeed — see CombatResolver._fire_or_apply).
func _position_of(projectile: ProjectileInstance) -> Vector2:
	var from := HexView.axial_to_pixel(projectile.attacker_hex)
	var speed := float(projectile.attacker_def.get("projectileSpeed", 0.0))

	if not projectile.beam_hexes.is_empty():
		var to := HexView.axial_to_pixel(projectile.beam_hexes[-1])
		var fraction := 1.0
		if speed > 0.0:
			fraction = clampf(projectile.beam_elapsed * speed / float(projectile.beam_hexes.size()), 0.0, 1.0)
		return from.lerp(to, fraction)

	var to := HexView.axial_to_pixel(projectile.aim_hex)
	if speed <= 0.0:
		return to
	var total_time := float(HexCoord.distance(projectile.attacker_hex, projectile.aim_hex)) / speed
	var fraction := 1.0 if total_time <= 0.0 else clampf(1.0 - projectile.remaining_time / total_time, 0.0, 1.0)
	return from.lerp(to, fraction)
