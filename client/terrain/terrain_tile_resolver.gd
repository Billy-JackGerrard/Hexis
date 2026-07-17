## Pure mask-to-mesh resolver for directional River/Road tiles — no Godot
## scene/node dependency, mirrors sim/hex/'s "pure math" convention. Given a
## live 6-bit connection mask (HexGrid.river_connection_mask/
## road_connection_mask) and which set to search, finds a checked-in
## canonical mask (TerrainTileDefs) that matches under some multiple of a
## fixed 60-degree rotation, and returns which mesh plus how many 60-degree
## steps to rotate it by.
##
## --- Calibration (Step 0a — derived via Godot's own Basis/rotated() math,
## not assumed; verified empirically this session, not just on paper) ---
##
## HexView (client/hex_view.gd) places flat-top hex vertex 0 at pixel-angle
## 0 degrees; HexCoord.DIRECTIONS[i] maps through HexView.axial_to_pixel to
## pixel angle (30 - 60*i) degrees (i.e. dir0=30, dir1=-30, dir2=-90, ...).
## These are hex EDGE-NORMAL angles (edges sit between consecutive 60-degree-
## apart vertices, so edge-normals are the 30-degree-offset complementary
## set).
##
## The terrain mesh pack's own local edge-normals sit at LOCAL angle
## (atan2(local_z, local_x)) 0, 60, 120, 180, 240, 300 degrees — confirmed by
## direct vertex inspection of hex_grass.gltf/hex_river_A.gltf this session
## (flat sides at local X=+-1, hex points/vertices at local Z=+-1.1547).
##
## Placing a mesh in the world with Godot's `node.rotation.y = R` (radians)
## behaves, confirmed empirically via `Vector3(1,0,0).rotated(Vector3.UP, R)`,
## as: world_angle = local_angle - R (a +90 degree rotation took local angle 0
## to world angle -90, i.e. +X toward -Z, the standard right-hand-rule
## result for a rotation around +Y).
##
## Choosing the world-axis mapping world.x = pixel.x * K, world.z = pixel.y *
## K (a free, consistent choice — the only residual ambiguity this leaves is
## a global mirror/chirality choice that affects which way asymmetric
## corner-type tiles visually curve, NOT whether connections line up
## correctly between neighbors, which holds under either choice) makes
## "pixel angle" and "world angle" numerically identical.
##
## Solving world_angle(local_angle, R) == pixel_angle(direction) for the
## rotation needed to align a mesh's local-angle-0 edge with
## HexCoord.DIRECTIONS[0] gives R = -30 degrees. Generalizing (full algebra
## in the session's derivation, verified against Godot's rotated() output):
## a mesh's local direction index m (local angle 60*m), placed at total
## rotation R_total = ROTATION_BASE_DEGREES + 60*rotation_steps, connects
## toward HexCoord direction j = (rotation_steps - m) mod 6 when
## rotation_steps=0 specifically, j0 = (6 - m) mod 6 (used by
## tools/analyze_terrain_meshes.gd to build TerrainTileDefs' canonical
## masks, which are already expressed in this j0/HexCoord-direction-indexed
## space, not local-m space). Re-deriving in that space: connects toward
## HexCoord direction (j0 + rotation_steps) mod 6 — i.e. TerrainTileDefs'
## canonical masks bit-rotate by a plain cyclic left-rotate of
## `rotation_steps` positions as rotation_steps increases. That's exactly
## what `_rotate6` below implements.
class_name TerrainTileResolver
extends RefCounted

## Fixed placement rotation (degrees) applied to every mesh before its own
## per-hex rotation_steps*60 — see header derivation. Not tunable per-hex;
## a single global constant every TerrainView3D placement uses.
const ROTATION_BASE_DEGREES: float = -30.0

## Result of a successful resolve: which mesh, and how many 60-degree steps
## (applied on top of ROTATION_BASE_DEGREES) to rotate it by.
class Result:
	var mesh_name: String
	var rotation_steps: int
	func _init(p_mesh_name: String, p_rotation_steps: int) -> void:
		mesh_name = p_mesh_name
		rotation_steps = p_rotation_steps

## Finds a mesh in `masks` (TerrainTileDefs.RIVER_MASKS or .ROAD_MASKS) whose
## canonical mask matches `live_mask` under some rotation_steps in 0..5.
## Deterministic: iterates `masks` in dictionary-declaration order and
## returns the first exact match — TerrainTileDefs.gd's header notes which
## entries intentionally share a mask (visual-variety alternates / the
## crossing-shapes-are-rotations-of-each-other case), so "first match" is a
## stable, defined choice rather than an arbitrary one.
##
## Falls back to a best-effort match when no exact one exists — this set may
## simply have no dedicated mesh for this exact shape (e.g. neither the
## river nor road set is guaranteed to cover every possible popcount; the
## river set specifically has no 1-connection "source/end" mesh at all, and
## a generated river's actual source hex always has exactly 1 connection).
## The fallback picks whichever (mesh, rotation_steps) pair's rotated
## canonical mask is a superset of live_mask with the fewest extra bits —
## every real connection still renders correctly, and the only cosmetic
## cost is an extra channel/path stub toward a direction that doesn't
## actually connect. A live_mask of 0 (an isolated hex) is just the
## superset search's degenerate case: every mesh's rotated mask trivially
## "contains" the empty set, so this naturally picks whichever mesh in the
## table has the fewest connections overall — no separate isolated-hex case
## needed.
static func resolve(live_mask: int, masks: Dictionary) -> Result:
	for mesh_name in masks:
		var canonical: int = masks[mesh_name]
		for steps in range(6):
			if _rotate6(canonical, steps) == live_mask:
				return Result.new(mesh_name, steps)

	var best: Result = null
	var best_extra_bits := 7
	for mesh_name in masks:
		var canonical: int = masks[mesh_name]
		for steps in range(6):
			var rotated := _rotate6(canonical, steps)
			if (rotated & live_mask) != live_mask:
				continue ## not a superset — missing a real connection, never acceptable
			var extra := _popcount(rotated & ~live_mask & 0x3F)
			if extra < best_extra_bits:
				best_extra_bits = extra
				best = Result.new(mesh_name, steps)
	if best != null:
		return best

	push_error("TerrainTileResolver.resolve: mask table is empty, nothing to resolve live_mask %s against" % _to_binary(live_mask))
	return null

static func _rotate6(mask: int, steps: int) -> int:
	var s := steps % 6
	return ((mask << s) | (mask >> (6 - s))) & 0x3F

static func _popcount(mask: int) -> int:
	var n := 0
	var m := mask
	while m > 0:
		n += m & 1
		m >>= 1
	return n

static func _to_binary(mask: int) -> String:
	var s := ""
	for i in range(5, -1, -1):
		s += "1" if mask & (1 << i) != 0 else "0"
	return s
