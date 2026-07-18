## Recomputes per-player visibility each tick, per 01-map-and-terrain.md's Fog
## of War section and 04-combat.md's "vision range and engagement range are
## separate" rule. Stateless/static, same split as MovementResolver/
## CombatResolver (data on the instances + PlayerVision, timing/rules here).
##
## Scope: squads + base-attached buildings + standalone buildings (Tower,
## Landmine, Road, Bridge, Dock), keyed by building.owner_id since they have
## no owning BaseInstance. Standalone buildings still aren't wired into
## combat (CombatResolver._build_targets only iterates base.buildings) —
## that's a separate, not-yet-addressed gap.
##
## Deliberately does NOT touch stealth/detection or terrain combat bonuses —
## those are the next build-order item and consume this system's output,
## rather than being part of it.
class_name VisionSystem
extends RefCounted

## Sentinel for "no terrain exemption" passed to _reveal/vision_multiplier —
## never equal to any Terrain.Type value.
const NO_EXEMPT_TERRAIN := -1

## squads/bases: every player's live state (read-only here).
## standalone_buildings: buildings with no owning base (base_id == ""),
## keyed by their own owner_id instead of a base's. visions: owner_id ->
## PlayerVision, created lazily for owners not yet seen. visible_hexes is
## fully recomputed this call; explored_hexes only ever grows. base_defs
## resolves a base's terrainException (Treehouse == "Forest", Windy Peaks ==
## "Hill") so that base's own buildings are exempt from the matching terrain's
## vision penalty below — both the own-tile halving and the through-terrain
## LOS reduction — since they're built into the Forest/Hills rather than
## merely standing on it.
## los_cache memoizes _reveal's revealed-hex-key set per [center_hex_key,
## vision_range, exempt_terrain] — see MatchState.vision_los_cache's own
## doc comment. Defaults to a fresh dict (i.e. no caching across calls) so
## every existing test call site keeps working unchanged; only
## sim_orchestrator.gd threads through the match-lifetime one.
static func resolve_tick(squads: Array[SquadInstance], bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, visions: Dictionary, base_defs: Dictionary = {}, los_cache: Dictionary = {}) -> void:
	var global_bonus_by_owner := _global_vision_bonus_by_owner(bases, building_defs)

	for pv in visions.values():
		pv.visible_hexes = {}

	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		# Boarded/docked squads have no independent authoritative position
		# while carried/landed (they move with the carrier/host building) and
		# are hidden inside it — same skip MovementResolver applies to
		# advancement.
		if squad.is_docked():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var vision := float(def.get("visionRange", 0.0))
		if vision <= 0.0:
			continue
		var own_terrain := grid.get_terrain(squad.current_hex)
		vision *= Terrain.vision_multiplier(own_terrain)
		vision += Terrain.elevation_vision_bonus(grid.get_elevation(squad.current_hex))
		vision += global_bonus_by_owner.get(squad.owner_id, 0.0)
		_reveal(visions, squad.owner_id, squad.current_hex, vision, grid, NO_EXEMPT_TERRAIN, los_cache)

	for base in bases:
		var exempt_terrain := _exempt_terrain_for(base_defs.get(base.base_def_id, {}))
		for building in base.buildings:
			# A ruin (CombatResolver-set is_ruin, or any building at 0 HP)
			# no longer functions — it doesn't see anything.
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			var vision := BuildingStats.vision_range(def, building.level, building.material, building_defs)
			if vision <= 0.0:
				continue
			var own_terrain := grid.get_terrain(building.hex)
			vision *= Terrain.vision_multiplier(own_terrain, exempt_terrain)
			vision += Terrain.elevation_vision_bonus(grid.get_elevation(building.hex))
			vision += global_bonus_by_owner.get(base.owner_id, 0.0)
			_reveal(visions, base.owner_id, building.hex, vision, grid, exempt_terrain, los_cache)

	for building in standalone_buildings:
		var def: Dictionary = building_defs.get(building.building_type, {})
		var vision := BuildingStats.vision_range(def, building.level, building.material, building_defs)
		if vision <= 0.0:
			continue
		var own_terrain := grid.get_terrain(building.hex)
		vision *= Terrain.vision_multiplier(own_terrain)
		vision += Terrain.elevation_vision_bonus(grid.get_elevation(building.hex))
		vision += global_bonus_by_owner.get(building.owner_id, 0.0)
		_reveal(visions, building.owner_id, building.hex, vision, grid, NO_EXEMPT_TERRAIN, los_cache)

static func vision_for(visions: Dictionary, owner_id: String) -> PlayerVision:
	if not visions.has(owner_id):
		visions[owner_id] = PlayerVision.new(owner_id)
	return visions[owner_id]

## Maps a base's terrainException string ("Forest" for Treehouse, "Hill" for
## Windy Peaks) to the Terrain.Type its own buildings are exempt from the
## vision penalty of; NO_EXEMPT_TERRAIN for a base with no exception.
static func _exempt_terrain_for(base_def: Dictionary) -> int:
	match String(base_def.get("terrainException", "")):
		"Forest":
			return Terrain.Type.FOREST
		"Hill":
			return Terrain.Type.HILLS
		_:
			return NO_EXEMPT_TERRAIN

## Sum of every owned building's globalVisionRangeBonus (Radar Array today),
## keyed by owner_id — applied on top of every one of that owner's vision
## sources, not just the granting building's own tile.
static func _global_vision_bonus_by_owner(bases: Array[BaseInstance], building_defs: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for base in bases:
		for building in base.buildings:
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			var bonus := BuildingStats.global_vision_bonus(def, building.level, building_defs)
			if bonus > 0.0:
				result[base.owner_id] = result.get(base.owner_id, 0.0) + bonus
	return result

## `vision_range` is the source's full budget after its own-tile terrain
## penalty and elevation bonus; each candidate hex is additionally re-checked
## against a sightline-specific budget that subtracts
## FOREST_LOS_RANGE_PENALTY_PER_HEX per Forest hex the line from `center` to it
## crosses (excluding both endpoints — standing in or looking directly at one
## is covered by the own-tile multiplier/detection-hidden mechanics, not this),
## and against the elevation silhouette test in _is_elevation_blocked.
## `exempt_terrain` skips the per-hex foliage check for one terrain entirely
## (a Treehouse building's own vision).
static func _reveal(visions: Dictionary, owner_id: String, center: HexCoord, vision_range: float, grid: HexGrid, exempt_terrain: int, los_cache: Dictionary) -> void:
	var pv := vision_for(visions, owner_id)
	var cache_key := [center.to_key(), vision_range, exempt_terrain]
	if not los_cache.has(cache_key):
		los_cache[cache_key] = _compute_revealed_keys(center, vision_range, grid, exempt_terrain)
	var revealed_keys: Array = los_cache[cache_key]
	for key in revealed_keys:
		pv.visible_hexes[key] = true
		pv.explored_hexes[key] = true

## The actual per-hex Forest/Hills-LOS scan _reveal used to redo from scratch
## every tick for every source — terrain never mutates after worldgen (see
## MatchState.vision_los_cache's doc comment), so this only ever needs to run
## once per distinct (center, vision_range, exempt_terrain) for the whole
## match; _reveal's los_cache memoizes the result.
static func _compute_revealed_keys(center: HexCoord, vision_range: float, grid: HexGrid, exempt_terrain: int) -> Array:
	var result: Array = []
	var max_radius := int(ceil(vision_range))
	for coord in HexCoord.range_within(center, max_radius):
		if not grid.has_hex(coord):
			continue
		if HexCoord.distance(center, coord) > vision_range:
			continue
		var effective_range := vision_range - _los_penalty(center, coord, grid, exempt_terrain)
		if HexCoord.distance(center, coord) > effective_range:
			continue
		if _is_elevation_blocked(center, coord, grid):
			continue
		result.append(coord.to_key())
	return result

## Forest hexes strictly between `center` and `target` on their hex line (both
## endpoints excluded) — total range lost from a sightline "passing through"
## foliage en route, not counting standing in or looking straight at one.
## `exempt_terrain` (a Treehouse source) skips the penalty for that terrain.
##
## Hills are deliberately absent: they obstruct via _is_elevation_blocked
## instead, which is a geometric test rather than a flat subtraction. See
## Terrain's comment where HILLS_LOS_RANGE_PENALTY_PER_HEX used to be.
static func _los_penalty(center: HexCoord, target: HexCoord, grid: HexGrid, exempt_terrain: int) -> float:
	var path := HexCoord.line(center, target)
	var penalty := 0.0
	for i in range(1, path.size() - 1):
		var terrain := grid.get_terrain(path[i])
		if terrain == exempt_terrain:
			continue
		if terrain == Terrain.Type.FOREST:
			penalty += Terrain.FOREST_LOS_RANGE_PENALTY_PER_HEX
	return penalty

## Silhouette test: does any hex strictly between `center` and `target` stand
## tall enough to break the straight line drawn from the viewer's eye to the
## target's? Eye heights at both ends come from Terrain.sightline_height (the
## hex's own elevation plus a fixed eye offset), the obstacle's height from
## Terrain.obstacle_height (ground level plus canopy), and the sightline's
## height above each intermediate hex is a straight lerp between the two ends.
##
## This is what makes elevation cut both ways. A viewer on a peak looking down
## has a sightline that starts high and stays above the intervening ridge, so
## high ground genuinely sees further; the same viewer down in the valley has a
## flat low sightline that the ridge silhouettes against, so the ground behind
## it stays dark. A ridge between two units on the same ridge blocks neither.
static func _is_elevation_blocked(center: HexCoord, target: HexCoord, grid: HexGrid) -> bool:
	var path := HexCoord.line(center, target)
	if path.size() <= 2:
		return false
	var from_height := Terrain.sightline_height(grid.get_elevation(center))
	var to_height := Terrain.sightline_height(grid.get_elevation(target))
	var steps := float(path.size() - 1)
	for i in range(1, path.size() - 1):
		var hex: HexCoord = path[i]
		if not grid.has_hex(hex):
			continue
		var line_height: float = lerp(from_height, to_height, float(i) / steps)
		if Terrain.obstacle_height(grid.get_terrain(hex), grid.get_elevation(hex)) > line_height:
			return true
	return false
