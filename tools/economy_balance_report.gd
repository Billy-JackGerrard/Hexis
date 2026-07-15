## Per-level cost/output table for every Resource-category building
## (data/buildings/*.json), for manual economy-balance passes. Run:
##   godot --headless --script res://tools/economy_balance_report.gd
extends SceneTree

const MAX_LEVEL := 10

const RESOURCE_NAMES := {
	ResourceType.Type.FOOD: "food",
	ResourceType.Type.STONE: "stone",
	ResourceType.Type.STEEL: "steel",
	ResourceType.Type.WOOD: "wood",
	ResourceType.Type.FUEL: "fuel",
}

func _init() -> void:
	var building_defs := DataLoader.load_dir("res://data/buildings")
	var resource_ids: Array = []
	for id in building_defs:
		if building_defs[id].get("category", "") == "Resource":
			resource_ids.append(id)
	resource_ids.sort()

	for id in resource_ids:
		_print_building(building_defs[id], building_defs)

	quit()

func _print_building(def: Dictionary, building_defs: Dictionary) -> void:
	print("\n== %s (%s) ==" % [def.get("name", def.get("id", "")), def.get("id", "")])
	print("%-5s %-24s %-16s %-16s %-8s %-10s" % ["Lvl", "Cost(cumulative)", "Cost(marginal)", "Output/tick", "HP", "Cost/Output"])

	var cumulative: Dictionary = {}
	for level in range(1, MAX_LEVEL + 1):
		var marginal_cost: Dictionary
		if level == 1:
			marginal_cost = BuildingStats.base_cost(def, "", building_defs)
		else:
			marginal_cost = BuildingStats.upgrade_cost(def, level - 1, "", building_defs)
		for key in marginal_cost:
			cumulative[key] = cumulative.get(key, 0.0) + float(marginal_cost[key])

		var output := BuildingStats.resource_output(def, level, building_defs)
		var hp := BuildingStats.max_hp(def, level, "", building_defs)

		var cumulative_total := 0.0
		for key in cumulative:
			cumulative_total += cumulative[key]
		var output_total := 0.0
		for key in output:
			output_total += output[key]
		var ratio := cumulative_total / output_total if output_total > 0.0 else 0.0

		print("%-5d %-24s %-16s %-16s %-8s %-10s" % [
			level,
			_fmt_named(cumulative),
			_fmt_named(marginal_cost),
			_fmt_named(_output_named(output)),
			"%.0f" % hp,
			"%.2f" % ratio,
		])

func _output_named(output: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in output:
		result[RESOURCE_NAMES[key]] = output[key]
	return result

func _fmt_named(d: Dictionary) -> String:
	if d.is_empty():
		return "-"
	var parts: Array = []
	for key in d:
		parts.append("%s:%.0f" % [key, float(d[key])])
	return ", ".join(parts)
