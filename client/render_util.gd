## Small shared helpers for the 3D client render layer (TerrainView3D,
## BuildingView3D) — material recoloring and deterministic per-hex cosmetic
## randomness. Nothing here touches sim state: `pick`/`roll` are pure
## functions of a caller-supplied string key (typically hex coordinates),
## so every client derives the identical "random" cosmetic choice
## independently — no need to sync any of this over the network, and zero
## desync risk since MatchState is never read or written here.
class_name RenderUtil
extends RefCounted

## Recolors every surface of every MeshInstance3D under `node` by multiplying
## its material's albedo with `tint` (a duplicated per-surface material
## override — the original imported material, shared across every instance
## of that mesh, is left untouched).
static func apply_tint(node: Node, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for i in range(mesh_instance.mesh.get_surface_count()):
			var mat := mesh_instance.mesh.surface_get_material(i)
			if mat == null or not (mat is BaseMaterial3D):
				continue
			var tinted: BaseMaterial3D = mat.duplicate()
			tinted.albedo_color = tint
			mesh_instance.set_surface_override_material(i, tinted)
	for child in node.get_children():
		apply_tint(child, tint)

## Deterministically picks one of `options` from `seed_key` — same key
## always yields the same choice, on every client, with no shared RNG state.
static func pick(seed_key: String, options: Array) -> Variant:
	return options[hash(seed_key) % options.size()]

## Deterministic pseudo-random float in [0, 1) from `seed_key`.
static func roll(seed_key: String) -> float:
	return float(hash(seed_key) % 100000) / 100000.0

## Deterministic angle in [0, TAU) from `seed_key` — for decoration rotation
## that doesn't need to snap to the 60°-stepped river/road convention.
static func angle(seed_key: String) -> float:
	return roll(seed_key) * TAU

## Integer avalanche mix (a compact variant of the well-known Squirrel/
## MurmurHash3 finalizer) — unlike Godot's built-in `hash()` on a formatted
## string key (e.g. "plains_decor_mesh:%d,%d" % [q, r]), this decorrelates
## neighboring integers properly. String-hashing small-delta coordinate keys
## visibly clustered (whole patches of hexes all rolling the same variant —
## a real reported bug, not a hypothetical one), because a generic string
## hash isn't guaranteed to have full avalanche over a mostly-identical tail.
static func _mix(x: int) -> int:
	x = (x ^ (x >> 16)) * 0x45d9f3b
	x = (x ^ (x >> 16)) * 0x45d9f3b
	x = x ^ (x >> 16)
	return x

## `salt` separates independent random streams for the same hex (e.g. "which
## mesh" vs. "did this hex roll a decoration at all" vs. "what rotation") so
## they don't correlate with each other.
static func spatial_hash(q: int, r: int, salt: int) -> int:
	var h := q * 374761393 + r * 668265263 + salt * 2147483647
	return _mix(h) & 0x7fffffff

static func pick2d(q: int, r: int, salt: int, options: Array) -> Variant:
	return options[spatial_hash(q, r, salt) % options.size()]

static func roll2d(q: int, r: int, salt: int) -> float:
	return float(spatial_hash(q, r, salt) % 100000) / 100000.0

static func angle2d(q: int, r: int, salt: int) -> float:
	return roll2d(q, r, salt) * TAU
