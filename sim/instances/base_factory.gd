## Seeds a fresh BaseInstance from its BaseDef's `initialBuildings`, per
## 02-bases-and-buildings.md's "Base Seeding" section: every base (new or
## captured) starts with HQ + Farm + Quarry, mutually adjacent, always on
## Plains regardless of base type. Authored placement, not player-driven, so
## it bypasses the isFixed/isStandalone/buildableBuildings menu gates that
## BuildingPlacement enforces for normal builds — it still requires Plains
## hexes to exist in the grid around hq_hex.
class_name BaseFactory
extends RefCounted

## Seed layout: HQ at the center, remaining initialBuildings fanned out one
## per neighbor hex (in HexCoord.DIRECTIONS order) so every seeded building
## ends up mutually adjacent to HQ and to each other for a 3-building cluster.
static func seed_base(id: String, base_def: Dictionary, owner_id: String, hq_hex: HexCoord, grid: HexGrid) -> BaseInstance:
	var base := BaseInstance.new(id, base_def.get("id", ""), owner_id, 1, hq_hex)

	var initial_buildings: Array = base_def.get("initialBuildings", [])
	var next_direction := 0
	var building_index := 0
	for entry in initial_buildings:
		var building_type: String = entry.get("buildingType")
		var material: String = entry.get("material", "")
		var count: int = int(entry.get("count", 1))
		for i in range(count):
			var hex: HexCoord = hq_hex if building_type == "hq" else HexCoord.neighbor(hq_hex, next_direction)
			if building_type != "hq":
				next_direction += 1
			base.buildings.append(BuildingInstance.new("%s_seed_%d" % [id, building_index], id, building_type, 1, material, hex))
			building_index += 1

	return base
