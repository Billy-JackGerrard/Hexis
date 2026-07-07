## The five tradeable resource types and their per-match starting amounts.
##
## Source of truth: game-design/03-resources.md's Resource List and
## Starting Resources sections.
class_name ResourceType
extends RefCounted

enum Type { FOOD, STONE, STEEL, WOOD, FUEL }

const ALL: Array[Type] = [Type.FOOD, Type.STONE, Type.STEEL, Type.WOOD, Type.FUEL]

## Food 100, Stone 100, Steel 50, Wood 0, Fuel 0 — Wood/Fuel start at zero
## deliberately, since a bare starting Capital has no Forest-adjacent Lumber
## Mill or built Oil Rig yet.
const STARTING := {
	Type.FOOD: 100.0,
	Type.STONE: 100.0,
	Type.STEEL: 50.0,
	Type.WOOD: 0.0,
	Type.FUEL: 0.0,
}

## Only Food and Fuel drive the per-squad troop-death deficit consequence
## (see 03-resources.md's Deficit Consequences) — Stone/Steel/Wood shortages
## just block construction, they don't kill troops.
static func can_deficit_drain(type: Type) -> bool:
	return type == Type.FOOD or type == Type.FUEL

## Maps a data/*.json cost-dict key (lowercase resource name, e.g. "stone" in
## a buildingDef's baseCost or a troopDef's cost) to this module's Type enum.
static func from_string(name: String) -> Type:
	match name:
		"food": return Type.FOOD
		"stone": return Type.STONE
		"steel": return Type.STEEL
		"wood": return Type.WOOD
		"fuel": return Type.FUEL
		_:
			push_error("ResourceType.from_string: unrecognized resource '%s'" % name)
			return Type.FOOD

## Converts a data/*.json-shaped cost dict ({"stone": 40, "steel": 20, ...})
## into a Type -> float dict, the shape ResourcePool.add()/BuildingInstance.
## total_resources_spent expect.
static func dict_from_named(named: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in named:
		result[from_string(String(key))] = float(named[key])
	return result
