## Headless assertion suite for client/terrain/terrain_tile_resolver.gd. Run with:
##   godot --headless --script res://tests/test_terrain_tile_resolver.gd
extends SceneTree

var _failures: int = 0

## Self-contained copy of the resolver's own rotation math, kept local so
## these tests exercise the resolver's public resolve() contract rather than
## reaching into its private implementation.
func _rotate6(mask: int, steps: int) -> int:
	var s := steps % 6
	return ((mask << s) | (mask >> (6 - s))) & 0x3F

func _check(condition: bool, label: String) -> void:
	if condition:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)

func _init() -> void:
	print("Resolver against synthetic tables (isolated from real asset data)")
	_test_synthetic_popcounts()
	_test_synthetic_rotation_matching()
	_test_synthetic_no_match_fallback()
	_test_isolated_hex_fallback()
	print("Resolver against the real TerrainTileDefs tables")
	_test_real_tables_round_trip()
	_test_river_source_fallback_against_real_table()

	if _failures == 0:
		print("\nAll checks passed.")
	else:
		print("\n%d check(s) FAILED." % _failures)
	quit(1 if _failures > 0 else 0)

## A small synthetic table covering one mesh per popcount (0 has no entry —
## there's no true "isolated" mesh in either real set either; resolve()'s
## superset fallback handles that case generically instead, see below),
## independent of real asset data so these tests don't depend on (or need
## updating for) any future asset pack swap.
func _synthetic_table() -> Dictionary:
	return {
		"end": 0b000001, ## popcount 1
		"straight": 0b001001, ## popcount 2, bit-distance 3 (opposite)
		"corner_wide": 0b000101, ## popcount 2, bit-distance 2
		"corner_sharp": 0b000011, ## popcount 2, bit-distance 1 (adjacent)
		"triple": 0b010101, ## popcount 3, symmetric (every other bit)
		"quad": 0b001111, ## popcount 4
		"full": 0b111111, ## popcount 6
	}

func _test_synthetic_popcounts() -> void:
	var table := _synthetic_table()
	for mesh_name in table:
		var canonical: int = table[mesh_name]
		var result := TerrainTileResolver.resolve(canonical, table)
		_check(result.mesh_name == mesh_name and result.rotation_steps == 0, "unrotated canonical mask for '%s' resolves to itself at rotation_steps=0" % mesh_name)

func _test_synthetic_rotation_matching() -> void:
	var table := _synthetic_table()
	# Distinct bit-distance-2 popcount masks must not be confused with each
	# other under rotation — corner_wide (distance 2) rotated any amount
	# must never equal corner_sharp (distance 1) or straight (distance 3),
	# since bit-distance between the two set bits is rotation-invariant.
	for steps in range(6):
		var rotated := _rotate6(0b000101, steps) ## corner_wide
		var result := TerrainTileResolver.resolve(rotated, table)
		_check(result.mesh_name == "corner_wide", "corner_wide rotated by %d steps still resolves to corner_wide, not a different turn angle" % steps)
		_check(_rotate6(table[result.mesh_name], result.rotation_steps) == rotated, "resolved (mesh, rotation_steps) round-trips back to the exact live mask (steps=%d)" % steps)

	for steps in range(6):
		var rotated := _rotate6(0b001001, steps) ## straight (opposite pair)
		var result := TerrainTileResolver.resolve(rotated, table)
		_check(result.mesh_name == "straight", "straight (opposite-edge) mask rotated by %d steps still resolves to straight" % steps)

func _test_synthetic_no_match_fallback() -> void:
	# A set with no exact-match shape for a single real connection (bit 0) —
	# the fallback must still pick something that actually contains bit 0
	# (every genuine connection has to render), and among the two
	# candidates that do (straight and corner_sharp, both supersets of
	# {bit0}), prefer whichever adds fewer extra phantom connections:
	# corner_sharp (popcount 2, 1 extra bit) over straight... wait both are
	# popcount 2 here, so exercise a clearer case: a table offering one
	# popcount-2 and one popcount-4 superset, fallback must prefer the
	# popcount-2 one (fewer extra bits).
	var table := {
		"far_superset": 0b001111, ## contains bit0, 3 extra bits
		"close_superset": 0b000011, ## contains bit0, 1 extra bit — declared before "unrelated" below, so a tie resolves in its favor (resolve() keeps the first minimum found)
		"unrelated": 0b010100, ## bit-distance-2 pair — happens to also reach a 1-extra-bit superset of bit0 under one rotation, exercising the tie-break
	}
	var result := TerrainTileResolver.resolve(0b000001, table)
	_check((_rotate6(table[result.mesh_name], result.rotation_steps) & 0b000001) == 0b000001, "fallback never drops a real connection — resolved mesh's rotated mask always contains the live mask's bits")
	_check(result.mesh_name == "close_superset", "fallback prefers the superset with fewer extra phantom connections (first-found on a tie)")

func _test_isolated_hex_fallback() -> void:
	# A popcount-0 live mask trivially satisfies the superset check against
	# every candidate, so the fallback should land on whichever mesh in the
	# table has the fewest connections overall (fewest "extra" bits beyond
	# the empty live mask) — here, "end".
	var table := _synthetic_table()
	var result := TerrainTileResolver.resolve(0, table)
	_check(result.mesh_name == "end", "a popcount-0 (isolated) hex resolves to whichever mesh in the table has the fewest connections")

func _test_river_source_fallback_against_real_table() -> void:
	# Regression coverage for a real gap this pack has: the river set has no
	# dedicated 1-connection "source/end" mesh, but TerrainGenerator always
	# produces river paths whose actual source hex has exactly 1 connection
	# — resolve() must still return something usable (a superset), not crash
	# or silently drop the one real connection.
	for direction in range(6):
		var live_mask := 1 << direction
		var result := TerrainTileResolver.resolve(live_mask, TerrainTileDefs.RIVER_MASKS)
		_check(result != null, "a river source hex (direction %d) resolves to something" % direction)
		if result != null:
			var rotated := _rotate6(TerrainTileDefs.RIVER_MASKS[result.mesh_name], result.rotation_steps)
			_check((rotated & live_mask) == live_mask, "the resolved river mesh's rotated mask actually contains the source's one real connection (direction %d)" % direction)

## Sanity check against the real, checked-in tables: every canonical mask,
## fed straight back into resolve(), must round-trip to a (mesh,
## rotation_steps) pair whose own canonical mask rotated by rotation_steps
## reproduces the exact input — catches any future edit to
## terrain_tile_defs.gd that breaks this invariant, without hardcoding which
## exact mesh name wins among the known same-mask duplicates (hex_river_A
## vs hex_river_A_curvy; hex_river_I vs the two crossing variants — see that
## file's header comment).
func _test_real_tables_round_trip() -> void:
	for set_name in ["river", "road"]:
		var table: Dictionary = TerrainTileDefs.RIVER_MASKS if set_name == "river" else TerrainTileDefs.ROAD_MASKS
		var all_round_trip := true
		for mesh_name in table:
			var canonical: int = table[mesh_name]
			var result := TerrainTileResolver.resolve(canonical, table)
			if _rotate6(table[result.mesh_name], result.rotation_steps) != canonical:
				all_round_trip = false
				print("    mismatch: ", mesh_name, " canonical=", canonical, " resolved to ", result.mesh_name, "/", result.rotation_steps)
		_check(all_round_trip, "every canonical mask in the real %s table round-trips through resolve()" % set_name)
