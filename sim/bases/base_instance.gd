## Live per-match state for one owned base (see 07-data-architecture.md
## section 5). Walls live in `buildings` too (edge-keyed via hex_a/hex_b
## instead of `hex` — see BuildingInstance), not a separate registry.
## hexCoord/population are tracked here to drive BuildingPlacement/
## Population validation.
class_name BaseInstance
extends RefCounted

var id: String
var base_def_id: String
var owner_id: String
var hq_level: int
var hex_coord: HexCoord
var buildings: Array[BuildingInstance] = []

func _init(p_id: String, p_base_def_id: String, p_owner_id: String, p_hq_level: int = 1, p_hex_coord: HexCoord = null) -> void:
	id = p_id
	base_def_id = p_base_def_id
	owner_id = p_owner_id
	hq_level = p_hq_level
	hex_coord = p_hex_coord

func buildings_of_type(building_type: String) -> Array[BuildingInstance]:
	var result: Array[BuildingInstance] = []
	for b in buildings:
		if b.building_type == building_type:
			result.append(b)
	return result

## {hex_key: BuildingInstance} for every building with a hex — the source of
## truth for "is this hex occupied" (one building per hex) and for counting
## adjacent buildings during placement validation.
func occupied_hexes() -> Dictionary:
	var result: Dictionary = {}
	for b in buildings:
		if b.hex != null:
			result[b.hex.to_key()] = b
	return result

func to_dict() -> Dictionary:
	return {
		"id": id,
		"base_def_id": base_def_id,
		"owner_id": owner_id,
		"hq_level": hq_level,
		"hex_coord": hex_coord.to_key() if hex_coord != null else "",
		"buildings": buildings.map(func(b): return b.to_dict()),
	}

static func from_dict(d: Dictionary) -> BaseInstance:
	var hex_coord: HexCoord = HexCoord.from_key(d["hex_coord"]) if String(d["hex_coord"]) != "" else null
	var base := BaseInstance.new(d["id"], d["base_def_id"], d["owner_id"], int(d["hq_level"]), hex_coord)
	var buildings: Array[BuildingInstance] = []
	for building_dict in d["buildings"]:
		buildings.append(BuildingInstance.from_dict(building_dict))
	base.buildings = buildings
	return base
