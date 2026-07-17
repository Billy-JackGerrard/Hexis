## Headless analysis tool: derives, from raw mesh geometry, which of the 6
## hex boundary directions each river/road tile mesh connects to. Run by
## hand (not part of any build/CI step) whenever the terrain asset pack is
## replaced or extended:
##
##   godot --headless --script res://tools/analyze_terrain_meshes.gd
##
## How it works: every hex_river_*/hex_road_* mesh in this pack shares one
## full-hex-silhouette "skirt" band (the lowest-Y vertex band) that's always
## a complete, gap-free hexagon regardless of which letter it is — that
## band exists purely for seamless tiling with neighbors, not to encode
## shape. The actual channel/path shape is painted via vertex color on that
## same band instead: a water/path swatch (checked via the texture atlas'
## sampled color having a high Blue channel — confirmed empirically: land
## colors in this pack's palette all sit at B<0.35, water/path swatches all
## sit at B>0.35, regardless of which of the two look otherwise very
## different, e.g. blue water vs. tan dirt path) versus a land/grass swatch.
## For each skirt-band vertex classified as water/path, round its angle
## (atan2(z,x), degrees) to the nearest multiple of 60 — the mesh's 6
## edge-normal directions are exactly 0/60/120/180/240/300 in local space
## (see calibration note in client/terrain/terrain_tile_resolver.gd), and
## corners (the only ambiguous points) sit exactly at the 30-degree
## midpoints between them, so "nearest multiple of 60" is an unambiguous
## voronoi assignment for every non-corner sample. That gives a 6-bit local
## mask per mesh (bit m set iff local edge-normal direction m touches
## water/path).
##
## The local mask is then converted to a HexCoord-direction-indexed
## "canonical mask" (bit j0 set iff this mesh, placed at the fixed
## calibration rotation derived in terrain_tile_resolver.gd, connects
## toward HexCoord.DIRECTIONS[j0]) via j0 = (6 - m) % 6 — see that file's
## header comment for the full derivation of why this particular mapping is
## correct (empirically verified against Godot's own Basis/rotation math,
## not assumed).
class_name TerrainMeshAnalyzer
extends SceneTree

const RIVER_DIR := "res://assets/tiles/rivers/"
const RIVER_WATERLESS_DIR := "res://assets/tiles/rivers/waterless/"
const ROAD_DIR := "res://assets/tiles/roads/"

const RIVER_NAMES := [
	"hex_river_A", "hex_river_A_curvy", "hex_river_B", "hex_river_C", "hex_river_D",
	"hex_river_E", "hex_river_F", "hex_river_G", "hex_river_H", "hex_river_I",
	"hex_river_J", "hex_river_K", "hex_river_L",
	"hex_river_crossing_A", "hex_river_crossing_B",
]
const ROAD_NAMES := [
	"hex_road_A", "hex_road_B", "hex_road_C", "hex_road_D", "hex_road_E",
	"hex_road_F", "hex_road_G", "hex_road_H", "hex_road_I", "hex_road_J",
	"hex_road_K", "hex_road_L", "hex_road_M",
]

func _init() -> void:
	print("=== River set ===")
	var river_masks := _analyze_set(RIVER_DIR, RIVER_NAMES)
	_report_collisions(river_masks)
	print("\n=== Road set ===")
	var road_masks := _analyze_set(ROAD_DIR, ROAD_NAMES)
	_report_collisions(road_masks)
	quit(0)

func _analyze_set(dir: String, names: Array) -> Dictionary:
	var masks: Dictionary = {} ## mesh name -> canonical 6-bit mask
	for mesh_name_variant in names:
		var mesh_name: String = mesh_name_variant
		var path: String = dir + mesh_name + ".gltf"
		if not ResourceLoader.exists(path):
			print("  (skip, not found: ", path, ")")
			continue
		var mask := _canonical_mask_for(path)
		masks[mesh_name] = mask
		print("  ", mesh_name, " -> local=", _mask_to_binary(_canonical_to_local(mask)), " canonical=", _mask_to_binary(mask), " (", _popcount(mask), " connections)")
	return masks

func _canonical_to_local(canonical_mask: int) -> int:
	var local := 0
	for j0 in range(6):
		if canonical_mask & (1 << j0) != 0:
			var m := (6 - j0) % 6
			local |= 1 << m
	return local

func _mask_to_binary(mask: int) -> String:
	var s := ""
	for i in range(5, -1, -1):
		s += "1" if mask & (1 << i) != 0 else "0"
	return s

func _popcount(mask: int) -> int:
	var n := 0
	var m := mask
	while m > 0:
		n += m & 1
		m >>= 1
	return n

## Loads `path`, finds the lowest-Y ("skirt") band, classifies each of its
## vertices as water/path (sampled atlas color Blue channel > 0.35) or land,
## rounds water/path vertices' angle to the nearest local edge-normal
## direction (multiple of 60 degrees), and returns the resulting mask
## converted into HexCoord-direction-indexed (canonical) space.
func _canonical_mask_for(path: String) -> int:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("failed to load " + path)
		return 0
	var root := scene.instantiate()
	var local_mask := _scan(root)
	root.free()
	var canonical := 0
	for m in range(6):
		if local_mask & (1 << m) != 0:
			var j0 := (6 - m) % 6
			canonical |= 1 << j0
	return canonical

func _scan(node: Node) -> int:
	var mask := 0
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		if mesh:
			for i in range(mesh.get_surface_count()):
				mask |= _surface_local_mask(mesh, i)
	for child in node.get_children():
		mask |= _scan(child)
	return mask

func _surface_local_mask(mesh: Mesh, surface_idx: int) -> int:
	var mat := mesh.surface_get_material(surface_idx)
	var tex: Texture2D = mat.albedo_texture if mat is BaseMaterial3D else null
	var img: Image = tex.get_image() if tex else null
	if img:
		img.decompress()
	var arrays := mesh.surface_get_arrays(surface_idx)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var min_y := INF
	for v in verts:
		min_y = min(min_y, v.y)
	var mask := 0
	for idx in range(verts.size()):
		var v: Vector3 = verts[idx]
		if v.y > min_y + 0.005:
			continue
		# The lowest Y band mixes two different vertex groups sharing the
		# same height: the side-wall rim (which genuinely traces the tile's
		# boundary shape, normals pointing horizontally outward) and a
		# downward-facing bottom cap that closes off the tile's underside
		# with its own, connectivity-irrelevant flat color (normals pointing
		# straight down, ~(0,-1,0), confirmed by direct inspection this
		# session — every corner of that cap happened to sample a shade with
		# Blue>0.35 too, which without this filter got misread as the tile
		# connecting in directions it doesn't). Only the outward-facing rim
		# is direction-indicative.
		if normals.size() > idx and normals[idx].y < -0.5:
			continue
		# Skip the shared center/hub vertex (and anything else well inside
		# the tile) — its angle is meaningless (near-origin floating-point
		# noise rounds to an arbitrary direction) and every connected shape
		# has one regardless of which edges it actually touches. Only
		# vertices out near the rim (radius > 0.5, well past the halfway
		# point to the boundary at radius ~1.0-1.15) are direction-indicative.
		if Vector2(v.x, v.z).length() < 0.5:
			continue
		if not _is_feature_colored(v, uvs[idx] if idx < uvs.size() else Vector2(-1, -1), img):
			continue
		var angle := rad_to_deg(atan2(v.z, v.x))
		var m := int(roundf(angle / 60.0)) % 6
		if m < 0:
			m += 6
		mask |= 1 << m
	return mask

func _is_feature_colored(_v: Vector3, uv: Vector2, img: Image) -> bool:
	if img == null:
		return false
	var px := int(clampf(uv.x, 0.0, 0.999) * img.get_width())
	var py := int(clampf(uv.y, 0.0, 0.999) * img.get_height())
	var color := img.get_pixel(px, py)
	return color.b > 0.35

## Self-check: within a set, every mesh's canonical mask must be distinct
## from every other's under all 6 rotations. A collision means either two
## visual duplicates (fine, dedupe) or a missed connection (bug above).
func _report_collisions(masks: Dictionary) -> void:
	var names := masks.keys()
	var collisions := 0
	for i in range(names.size()):
		for j in range(i + 1, names.size()):
			var a: int = masks[names[i]]
			var b: int = masks[names[j]]
			for s in range(6):
				if _rotate6(a, s) == b:
					print("  COLLISION: ", names[i], " == ", names[j], " rotated by ", s, " steps")
					collisions += 1
					break
	if collisions == 0:
		print("  no mask collisions within this set")
	else:
		print("  ", collisions, " collision(s) found - review above")

func _rotate6(mask: int, steps: int) -> int:
	var s := steps % 6
	return ((mask << s) | (mask >> (6 - s))) & 0x3F
