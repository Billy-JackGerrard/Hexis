## Real 3D squad rendering — the Node3D counterpart to squad_view.gd's flat
## placeholder shapes, same relationship BuildingView3D has to BaseView.
## squad_view.gd keeps ownership of everything that isn't the squad's own
## body (selection ring, path-preview dots, attack-range ring, the hover/
## selected info label) and stops drawing the domain shape (circle/triangle/
## diamond) now that every domain gets a real mesh here — see its own doc
## comment.
##
## Temporary mesh choice, not a real per-troop art pass: this asset pack has
## no dedicated unit-type meshes at all (it's a generic medieval army kit —
## unit/helmet/sword/cannon/ship/etc, not "grenadier"/"frost_tank"/whatever),
## so every troop_type sharing a Domain shares ONE mesh (or small fixed
## composite) for now, picked by MESH_NAME_BY_DOMAIN: Infantry -> "unit" (the
## pack's plain body mesh — a bare helmet floating with no body under it, an
## earlier pass's choice, read as broken rather than "soldier"), topped with a
## "helmet" instance (see _build_node) so it actually reads as a person in
## armor rather than a faceless peg. Land -> cannon (reads as "vehicle" better
## than a foot-soldier mesh would), Naval -> ship. Air has no aircraft mesh in
## this pack at all — banner is the stand-in (the tallest, most vertically
## distinct prop available), paired with a real hover-height offset so it
## visibly floats above the ground rather than just being a weirdly thin
## ground unit. All of this is meant to be swapped for real per-troop art
## later (see game-design/10-tech-stack-and-build-order.md's Art section).
##
## Poll-based like BuildingView3D/TerrainView3D (never hooked to command call
## sites — a remote peer's squad moves via LockstepDriver, never through local
## InputController), but unlike BuildingView3D's discrete per-building state,
## a squad's position changes continuously every tick (edge_progress lerp),
## so this splits the update in two: the mesh SUBTREE is only rebuilt when a
## squad's (troop_type, owner_id) signature changes (rare — composition
## changes don't affect which mesh a squad shows), while its transform
## (position/facing) updates every single frame regardless.
class_name SquadView3D
extends Node3D

var state: MatchState
var squads: Array[SquadInstance] = []
var grid: HexGrid
var troop_defs: Dictionary = {}
var visions: Dictionary = {}
var detections: Dictionary = {}
var local_owner_id: String = ""

var _nodes: Dictionary = {} ## squad.id -> Node3D (root; owns the mesh child, moved every frame)
var _signatures: Dictionary = {} ## squad.id -> "troop_type:owner_id", see _poll_one

const UNITS_DIR := "res://assets/units/"
const MESH_NAME_BY_DOMAIN := {
	Terrain.Domain.INFANTRY: "unit",
	Terrain.Domain.LAND: "cannon",
	Terrain.Domain.NAVAL: "ship",
	Terrain.Domain.AIR: "banner",
}
## Worn on top of the Infantry body (see MESH_NAME_BY_DOMAIN) — same pack,
## same shared local origin convention every unit prop in this directory is
## authored against, so instancing it as a plain sibling under the body node
## (no extra offset) seats it on the head.
const INFANTRY_HEADGEAR := "helmet"

## Uniform boost on top of the pack's native unit scale — helmet's native
## bounding box is only ~0.22 world units across (a hex's circumradius is
## ~1.15), which reads as a speck at normal zoom. Applied equally to every
## domain rather than per-mesh, so relative size differences between e.g. a
## soldier and a warship stay intentional rather than being flattened out.
const UNIT_SCALE := 2.2

## World Y a Domain.AIR squad hovers at, ABOVE whatever _ground_y computes for
## its hex — has to clear the tallest thing a squad could be flying over
## (a peak-tier mountain cluster, same reasoning as FogOfWar.PROP_HEIGHT_MIN)
## or it would visibly clip through hills.
const AIRCRAFT_HOVER_HEIGHT := 3.0

func setup(p_state: MatchState, p_squads: Array[SquadInstance], p_grid: HexGrid, p_troop_defs: Dictionary, p_visions: Dictionary, p_detections: Dictionary, p_local_owner_id: String) -> void:
	state = p_state
	squads = p_squads
	grid = p_grid
	troop_defs = p_troop_defs
	visions = p_visions
	detections = p_detections
	local_owner_id = p_local_owner_id

func _process(_delta: float) -> void:
	if state == null or grid == null:
		return
	var seen: Dictionary = {} ## squad.id -> true
	for squad in squads:
		_poll_one(squad, seen)
	for id in _nodes.keys():
		if not seen.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
			_signatures.erase(id)

## Same visibility rule as SquadView._is_renderable (enemy squads need live
## vision, gated by stealth/detection) — kept as its own copy rather than a
## shared helper since SquadView is a Node2D and this is a Node3D with no
## common base to hang it on, matching how BaseView/BuildingView3D each keep
## their own near-identical visibility check.
func _is_renderable(squad: SquadInstance) -> bool:
	if squad.member_ids.is_empty() or squad.is_docked():
		return false
	if squad.owner_id == local_owner_id:
		return true
	var pv: PlayerVision = visions.get(local_owner_id)
	if pv == null or not pv.is_visible(squad.current_hex):
		return false
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	if not DetectionSystem.is_squad_hidden(squad, def, grid):
		return true
	return DetectionSystem.detected_hexes_for(detections, local_owner_id).has(squad.current_hex.to_key())

func _domain_of(squad: SquadInstance) -> Terrain.Domain:
	var def: Dictionary = troop_defs.get(squad.troop_type, {})
	return Terrain.domain_from_string(String(def.get("domain", "Infantry")))

func _poll_one(squad: SquadInstance, seen: Dictionary) -> void:
	if not _is_renderable(squad):
		return
	seen[squad.id] = true
	var domain := _domain_of(squad)
	var sig := "%d:%s" % [domain, squad.owner_id]
	var root: Node3D = _nodes.get(squad.id)
	if root == null or _signatures.get(squad.id) != sig:
		if root != null:
			root.queue_free()
		root = _build_node(domain, squad.owner_id)
		if root == null:
			_nodes.erase(squad.id)
			_signatures.erase(squad.id)
			return
		add_child(root)
		_nodes[squad.id] = root
		_signatures[squad.id] = sig
	_place(root, squad, domain)

func _build_node(domain: Terrain.Domain, owner_id: String) -> Node3D:
	var mesh_path := _mesh_path_for(MESH_NAME_BY_DOMAIN.get(domain, MESH_NAME_BY_DOMAIN[Terrain.Domain.INFANTRY]), owner_id)
	var scene: PackedScene = load(mesh_path)
	if scene == null:
		push_error("SquadView3D: failed to load %s" % mesh_path)
		return null
	var root := Node3D.new()
	var mesh_node: Node3D = scene.instantiate()
	mesh_node.scale = Vector3.ONE * UNIT_SCALE
	root.add_child(mesh_node)
	if domain == Terrain.Domain.INFANTRY:
		var headgear_path := _mesh_path_for(INFANTRY_HEADGEAR, owner_id)
		var headgear_scene: PackedScene = load(headgear_path)
		if headgear_scene != null:
			mesh_node.add_child(headgear_scene.instantiate())
	return root

## Mirrors BuildingMeshDefs.color_folder_for's owner->folder mapping (p0-p3 ->
## blue/red/green/yellow, anything else -> neutral) rather than duplicating
## it — same 4-color pack convention, just a different asset directory.
## Unlike BUILDINGS_DIR's neutral set, this pack's units/neutral/ meshes have
## no "_full"/"_accent" suffix or trailing color name at all (just
## `helmet.gltf`, not `helmet_neutral_full.gltf`), so that path is built
## separately rather than by substitution.
func _mesh_path_for(name: String, owner_id: String) -> String:
	var folder := BuildingMeshDefs.color_folder_for(owner_id)
	if folder == "neutral":
		return "%s%s/%s.gltf" % [UNITS_DIR, folder, name]
	return "%s%s/%s_%s_full.gltf" % [UNITS_DIR, folder, name, folder]

## Half-width, in edge_progress units, of the "climbing" window centered on
## the shared edge (progress 0.5 — the midpoint of any two adjacent hexes'
## centers sits exactly on the edge between them) — see _place. 0.15 means
## 30% of the total edge crossing is spent climbing in place rather than
## walking, on a terrace edge with no visual ramp.
const CLIMB_WINDOW := 0.15

## Updates `root`'s transform for this tick — position (lerped the same way
## SquadView.squad_pixel_position is, but in world space with a real hex
## height) and a facing yaw toward wherever it's currently moving.
func _place(root: Node3D, squad: SquadInstance, domain: Terrain.Domain) -> void:
	var from := TerrainView3D.hex_to_world(grid, squad.current_hex)
	from.y = _ground_y(squad.current_hex, domain)
	var pos := from
	var facing := root.rotation.y ## holds its last facing when not moving, rather than snapping to 0
	if not squad.path.is_empty():
		var to := TerrainView3D.hex_to_world(grid, squad.path[0])
		to.y = _ground_y(squad.path[0], domain)
		var t := squad.edge_progress
		var xz_t := t
		var y_t := t
		# XZ and Y get SEPARATE, piecewise progress whenever this edge climbs
		# a terrace with no visual ramp between the two hexes (see
		# _has_visual_ramp) — everywhere else (a real ramp, same-height
		# ground, Air's hover) a plain lerp already tracks the real surface,
		# since TerrainView3D only ever slopes the FIRST step up from
		# lowland; every step above that is a flat plate with a sheer face
		# (see terrain_view_3d.gd's _ramp_low_direction doc comment) —
		# walkable by sim rule (for Infantry; Land vehicles are blocked from
		# this edge entirely, see Terrain.elevation_step_cost), but with no
		# surface in between for a linear Y lerp to follow. Lerping Y
		# straight through put mid-climb XZ positions (already over the FAR
		# hex's footprint well before edge_progress reached 1) at a height
		# still short of that hex's real plateau top — rendered *inside* the
		# solid terrace block, hidden behind its own opaque top surface for
		# most of the climb ("troops disappear going up the slope"). A plain
		# instant snap at the midpoint fixed the disappearing but still
		# teleported — visibly floating from one height to the other with no
		# motion to explain it. This instead treats the edge itself as a
		# short vertical climb: XZ walks normally up to the edge, FREEZES for
		# a CLIMB_WINDOW-wide band centered on it while Y eases from one
		# hex's height to the other's, then XZ resumes walking away from the
		# edge into the new hex — reading as "climb the ledge," not a pop.
		if domain != Terrain.Domain.AIR and from.y != to.y and not _has_visual_ramp(squad.current_hex, squad.path[0]):
			var lo := 0.5 - CLIMB_WINDOW
			var hi := 0.5 + CLIMB_WINDOW
			if t <= lo:
				xz_t = t
				y_t = 0.0
			elif t < hi:
				xz_t = lo ## frozen at the edge for the whole climbing band
				y_t = smoothstep(0.0, 1.0, (t - lo) / (hi - lo))
			else:
				# Rescaled so xz_t still reaches exactly 1.0 at t=1.0, having
				# covered only (1.0 - lo) of the total XZ distance over the
				# remaining (1.0 - hi) of progress.
				xz_t = lo + (t - hi) * (1.0 - lo) / (1.0 - hi)
				y_t = 1.0
		pos = Vector3(lerpf(from.x, to.x, xz_t), lerpf(from.y, to.y, y_t), lerpf(from.z, to.z, xz_t))
		var dir := to - from
		if dir.length_squared() > 0.0001:
			facing = atan2(dir.x, dir.z)
	root.position = pos
	root.rotation.y = facing

## True iff TerrainView3D actually renders a sloped surface connecting these
## two adjacent hexes — the exact same rule terrain_view_3d.gd's
## _ramp_low_direction uses (a ramp only ever runs from a Tuning.
## HILLS_RIM_ELEVATION hex down to a lowland one), duplicated rather than
## shared since that function needs a live TerrainView3D instance and this
## file only has the grid. Any other elevation difference (rim-to-peak, or a
## raw multi-level cliff) is a flat plate with a sheer face in the render
## regardless of what the sim allows a squad to climb.
func _has_visual_ramp(a: HexCoord, b: HexCoord) -> bool:
	var ea := grid.get_elevation(a)
	var eb := grid.get_elevation(b)
	return (ea == Tuning.HILLS_RIM_ELEVATION and eb == 0) or (eb == Tuning.HILLS_RIM_ELEVATION and ea == 0)

## Ground height a squad in `domain` should sit at over `hex`: the real
## terrain surface for Infantry/Land, dropped to the actual (visually
## recessed, see TerrainView3D.WATER_SURFACE_DROP) water line for Naval —
## surface_height alone reports land-level 0 for any Ocean/River hex, since
## HexGrid elevation never encodes that cosmetic drop — and hovering well
## above the terrain for Air regardless of what's underneath.
func _ground_y(hex: HexCoord, domain: Terrain.Domain) -> float:
	var y := TerrainView3D.surface_height(grid, hex)
	if domain == Terrain.Domain.AIR:
		return y + AIRCRAFT_HOVER_HEIGHT
	var terrain := grid.get_terrain(hex)
	if terrain == Terrain.Type.OCEAN or terrain == Terrain.Type.RIVER:
		y -= TerrainView3D.WATER_SURFACE_DROP
	return y
