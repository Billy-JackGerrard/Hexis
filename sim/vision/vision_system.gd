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

## squads/bases: every player's live state (read-only here).
## standalone_buildings: buildings with no owning base (base_id == ""),
## keyed by their own owner_id instead of a base's. visions: owner_id ->
## PlayerVision, created lazily for owners not yet seen. visible_hexes is
## fully recomputed this call; explored_hexes only ever grows. base_defs
## resolves a base's terrainException (Treehouse == "Forest") so a Treehouse
## base's own buildings are exempt from every Forest vision penalty below —
## both the own-tile halving and the through-forest LOS reduction — since
## they're built into the forest rather than merely standing on it.
static func resolve_tick(squads: Array[SquadInstance], bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, visions: Dictionary, base_defs: Dictionary = {}) -> void:
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
		vision += Terrain.vision_bonus(own_terrain)
		vision += global_bonus_by_owner.get(squad.owner_id, 0.0)
		_reveal(visions, squad.owner_id, squad.current_hex, vision, grid, false)

	for base in bases:
		var ignores_forest := String(base_defs.get(base.base_def_id, {}).get("terrainException", "")) == "Forest"
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
			if not ignores_forest:
				vision *= Terrain.vision_multiplier(own_terrain)
			vision += Terrain.vision_bonus(own_terrain)
			vision += global_bonus_by_owner.get(base.owner_id, 0.0)
			_reveal(visions, base.owner_id, building.hex, vision, grid, ignores_forest)

	for building in standalone_buildings:
		var def: Dictionary = building_defs.get(building.building_type, {})
		var vision := BuildingStats.vision_range(def, building.level, building.material, building_defs)
		if vision <= 0.0:
			continue
		var own_terrain := grid.get_terrain(building.hex)
		vision *= Terrain.vision_multiplier(own_terrain)
		vision += Terrain.vision_bonus(own_terrain)
		vision += global_bonus_by_owner.get(building.owner_id, 0.0)
		_reveal(visions, building.owner_id, building.hex, vision, grid, false)

static func vision_for(visions: Dictionary, owner_id: String) -> PlayerVision:
	if not visions.has(owner_id):
		visions[owner_id] = PlayerVision.new(owner_id)
	return visions[owner_id]

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
## penalty/bonus; each candidate hex is additionally re-checked against a
## sightline-specific budget that subtracts FOREST_LOS_RANGE_PENALTY_PER_HEX
## per Forest hex the line from `center` to it crosses (excluding both
## endpoints — standing in or looking directly at Forest is covered by the
## own-tile multiplier/detection-hidden mechanics, not this). `ignore_forest_los`
## skips that per-hex check entirely (a Treehouse building's own vision).
static func _reveal(visions: Dictionary, owner_id: String, center: HexCoord, vision_range: float, grid: HexGrid, ignore_forest_los: bool) -> void:
	var pv := vision_for(visions, owner_id)
	var max_radius := int(ceil(vision_range))
	for coord in HexCoord.range_within(center, max_radius):
		if not grid.has_hex(coord):
			continue
		var effective_range := vision_range
		if not ignore_forest_los:
			effective_range -= float(_forest_crossings(center, coord, grid)) * Terrain.FOREST_LOS_RANGE_PENALTY_PER_HEX
		if HexCoord.distance(center, coord) > effective_range:
			continue
		var key := coord.to_key()
		pv.visible_hexes[key] = true
		pv.explored_hexes[key] = true

## Forest hexes strictly between `center` and `target` on their hex line
## (both endpoints excluded) — how many times a sightline "passes through"
## forest en route, not counting standing in or looking straight at one.
static func _forest_crossings(center: HexCoord, target: HexCoord, grid: HexGrid) -> int:
	var path := HexCoord.line(center, target)
	var count := 0
	for i in range(1, path.size() - 1):
		if grid.get_terrain(path[i]) == Terrain.Type.FOREST:
			count += 1
	return count
