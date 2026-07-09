## Seeds a fresh BaseInstance from its BaseDef's `initialBuildings`, per
## 02-bases-and-buildings.md's "Base Seeding" section: every base (new or
## captured) starts with HQ + Farm + Quarry, mutually adjacent, on Plains by
## default or the base's terrainException terrain (Forest/Hill) when set —
## see sim/worldgen/base_site_selector.gd for the world-gen siting rules
## that pick hq_hex accordingly. Authored placement, not player-driven, so
## it bypasses the isFixed/isStandalone/buildableBuildings menu gates that
## BuildingPlacement enforces for normal builds — it still requires the
## correct terrain to already exist in the grid around hq_hex; seed_base
## itself performs no terrain validation.
class_name BaseFactory
extends RefCounted

## Seed layout: HQ at the center, remaining initialBuildings fanned out one
## per neighbor hex (in HexCoord.DIRECTIONS order) so every seeded building
## ends up mutually adjacent to HQ and to each other for a 3-building cluster.
## `building_defs` is optional: when supplied, each seeded building's combat HP
## is initialised from its def (BuildingStats.max_hp), so the base is fightable;
## omit it (cap-math/placement callers that don't need HP) and buildings seed
## with HP left at 0.
static func seed_base(id: String, base_def: Dictionary, owner_id: String, hq_hex: HexCoord, grid: HexGrid, building_defs: Dictionary = {}) -> BaseInstance:
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
			var building := BuildingInstance.new("%s_seed_%d" % [id, building_index], id, building_type, 1, material, hex)
			if building_defs.has(building_type):
				building.init_hp(building_defs[building_type], building_defs)
			base.buildings.append(building)
			building_index += 1

	return base
