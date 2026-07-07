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
## fully recomputed this call; explored_hexes only ever grows.
static func resolve_tick(squads: Array[SquadInstance], bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, visions: Dictionary) -> void:
	var global_bonus_by_owner := _global_vision_bonus_by_owner(bases, building_defs)

	for pv in visions.values():
		pv.visible_hexes = {}

	for squad in squads:
		if squad.member_ids.is_empty():
			continue
		# Boarded squads have no independent authoritative position while
		# carried (they move with the carrier) — same skip MovementResolver
		# applies to advancement.
		if squad.boarded_on_squad_id != "":
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		var vision := float(def.get("visionRange", 0.0))
		if vision <= 0.0:
			continue
		vision += Terrain.vision_bonus(grid.get_terrain(squad.current_hex))
		vision += global_bonus_by_owner.get(squad.owner_id, 0.0)
		_reveal(visions, squad.owner_id, squad.current_hex, int(vision), grid)

	for base in bases:
		for building in base.buildings:
			# A ruin (CombatResolver-set is_ruin, or any building at 0 HP)
			# no longer functions — it doesn't see anything.
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			var vision := BuildingStats.vision_range(def, building.level, building.material, building_defs)
			if vision <= 0.0:
				continue
			vision += Terrain.vision_bonus(grid.get_terrain(building.hex))
			vision += global_bonus_by_owner.get(base.owner_id, 0.0)
			_reveal(visions, base.owner_id, building.hex, int(vision), grid)

	for building in standalone_buildings:
		var def: Dictionary = building_defs.get(building.building_type, {})
		var vision := BuildingStats.vision_range(def, building.level, building.material, building_defs)
		if vision <= 0.0:
			continue
		vision += Terrain.vision_bonus(grid.get_terrain(building.hex))
		vision += global_bonus_by_owner.get(building.owner_id, 0.0)
		_reveal(visions, building.owner_id, building.hex, int(vision), grid)

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

static func _reveal(visions: Dictionary, owner_id: String, center: HexCoord, radius: int, grid: HexGrid) -> void:
	var pv := vision_for(visions, owner_id)
	for coord in HexCoord.range_within(center, radius):
		if not grid.has_hex(coord):
			continue
		var key := coord.to_key()
		pv.visible_hexes[key] = true
		pv.explored_hexes[key] = true
