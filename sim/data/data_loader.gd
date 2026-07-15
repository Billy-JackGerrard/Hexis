## Generic loader for the `data/*.json` definition files (troops, buildings,
## bases — see 07-data-architecture.md). Each file is a single def object with
## an "id" field; this just walks a directory and keys the parsed dicts by
## that id, skipping schema.json. No validation against the JSON Schema files
## themselves — those are for human/editor tooling, not enforced at load time.
class_name DataLoader
extends RefCounted

static func load_dir(path: String) -> Dictionary:
	var result: Dictionary = {}
	var dir := DirAccess.open(path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_names: Array = []
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json") and file_name != "schema.json":
			file_names.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Directory listing order is OS/filesystem-dependent; sort so def load
	# order (and anything downstream that iterates the result, e.g. worldgen
	# unique-base assignment) is identical across machines. Without this,
	# two peers loading the same files can build differing base_defs order
	# and desync from tick 0 despite an identical RNG seed.
	file_names.sort()
	for name in file_names:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path.path_join(name)))
		if parsed is Dictionary and parsed.has("id"):
			result[parsed["id"]] = parsed

	return result
