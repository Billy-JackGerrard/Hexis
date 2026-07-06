## Applies a BaseDef's `resourceModifiers` list to a building's raw output.
##
## Per 07-data-architecture.md section 5: entries are `{ scope, buildingType,
## multiplier }` (only `scope: "building"` is used by any base so far),
## applied multiplicatively, building-scoped first then base-scoped. There's
## no BaseDef data yet, so this takes the modifier list directly rather than
## a base object.
class_name ResourceModifier
extends RefCounted

## `modifiers` is the BaseDef's `resourceModifiers` array of
## `{ scope: String, buildingType: String, multiplier: float }` dicts.
static func apply(base_output: float, building_type: String, modifiers: Array) -> float:
	var result := base_output
	for entry in modifiers:
		if entry.get("scope") == "building" and entry.get("buildingType") == building_type:
			result *= float(entry.get("multiplier"))
	for entry in modifiers:
		if entry.get("scope") == "base":
			result *= float(entry.get("multiplier"))
	return result
