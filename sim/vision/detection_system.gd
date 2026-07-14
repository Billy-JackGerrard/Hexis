## Resolves stealth/ambush hidden-state and detector coverage, per
## 04-combat.md's "forest ambush" bullet and the troop/building schemas'
## stealth/detector/detectionRange/revealRange/revealsOnAttack fields —
## the item VisionSystem's header explicitly deferred to here.
##
## Unifies two hidden-state sources under one query: a unit authored with
## `stealth: true` (Ghost Tank, Submarine, Sniper), and an Infantry squad
## standing on a Forest hex (04-combat.md's ambush bonus — "attacker hidden
## until engaging"). Both break on attacking and re-arm after a cooldown,
## sharing SquadInstance.reveal_cooldown_remaining, since "hidden until
## engaging" is the same shape as schema's `revealsOnAttack`.
##
## Detector coverage (detections dict) is fully recomputed every call — no
## fog-of-war-style persistence, unlike PlayerVision.explored_hexes, since
## detection is momentary ("can currently see through stealth"), not memory.
##
## Scope: base-attached troops/buildings, plus standalone detector buildings
## (Tower), keyed by building.owner_id since they have no owning BaseInstance.
## Landmine-as-a-hidden-object is wired too: CombatTarget.for_building()'s
## is_hidden/reveal_range (sourced from BuildingStats.stealth()/.reveal_range())
## and CombatTargeting.candidates()'s target.is_hidden gate are Kind-agnostic,
## shared with squad-side stealth (is_squad_hidden above) — no separate
## building-side query needed here.
class_name DetectionSystem
extends RefCounted

## Reveal-cooldown and forest-ambush-range tunables live in sim/tuning.gd as
## Tuning.STEALTH_REVEAL_COOLDOWN_SECONDS/FOREST_AMBUSH_REVEAL_RANGE.

## True if this squad is currently hidden from enemies: authored stealth,
## Commander Nightfall's `grant_stealth` regiment aura (AuraSystem), or an
## Infantry squad ambushing from a Forest hex — and not mid-reveal-cooldown
## from having attacked recently. `auras` defaults to {} (no granted stealth)
## so existing callers keep compiling.
static func is_squad_hidden(squad: SquadInstance, troop_def: Dictionary, grid: HexGrid, auras: Dictionary = {}) -> bool:
	if squad.reveal_cooldown_remaining > 0.0:
		return false
	if troop_def.get("stealth", false):
		return true
	if AuraSystem.is_granted_stealth(auras, squad.id):
		return true
	if String(troop_def.get("domain", "")) != "Infantry":
		return false
	return grid.get_terrain(squad.current_hex) == Terrain.Type.FOREST

## Range within which an enemy sees this squad despite being hidden, without
## needing a detector — authored revealRange for schema-stealth units, the
## granting Commander's own revealRange for a Nightfall-granted cloak (same
## revealRange/revealsOnAttack convention as Nightfall's own stealth, per
## commander_nightfall.json's notes), or the forest-ambush placeholder
## otherwise.
static func squad_reveal_range(squad: SquadInstance, troop_def: Dictionary, grid: HexGrid, auras: Dictionary = {}) -> float:
	if troop_def.get("stealth", false):
		return float(troop_def.get("revealRange", 0.0))
	if AuraSystem.is_granted_stealth(auras, squad.id):
		return AuraSystem.granted_stealth_reveal_range(auras, squad.id)
	return Tuning.FOREST_AMBUSH_REVEAL_RANGE

## Recomputes detector coverage from scratch: detections[owner_id] ->
## {hex_key: true} for every hex within a detector's detectionRange (falling
## back to full visionRange if omitted, per schema). Base-attached
## troops/buildings only; boarded/docked squads have no independent position.
static func resolve_tick(squads: Array[SquadInstance], bases: Array[BaseInstance], standalone_buildings: Array[BuildingInstance], grid: HexGrid, troop_defs: Dictionary, building_defs: Dictionary, detections: Dictionary) -> void:
	detections.clear()

	for squad in squads:
		if squad.member_ids.is_empty() or squad.is_docked():
			continue
		var def: Dictionary = troop_defs.get(squad.troop_type, {})
		if not def.get("detector", false):
			continue
		var range := float(def["detectionRange"]) if def.has("detectionRange") else float(def.get("visionRange", 0.0))
		if range > 0.0:
			_mark(detections, squad.owner_id, squad.current_hex, int(range), grid)

	for base in bases:
		for building in base.buildings:
			# A ruin (or any building at 0 HP) no longer detects anything.
			if building.max_hp > 0.0 and building.current_hp <= 0.0:
				continue
			var def: Dictionary = building_defs.get(building.building_type, {})
			if not BuildingStats.detector(def, building_defs):
				continue
			var range := BuildingStats.detection_range(def, building.level, building.material, building_defs)
			if range > 0.0:
				_mark(detections, base.owner_id, building.hex, int(range), grid)

	for building in standalone_buildings:
		var def: Dictionary = building_defs.get(building.building_type, {})
		if not BuildingStats.detector(def, building_defs):
			continue
		var range := BuildingStats.detection_range(def, building.level, building.material, building_defs)
		if range > 0.0:
			_mark(detections, building.owner_id, building.hex, int(range), grid)

static func detected_hexes_for(detections: Dictionary, owner_id: String) -> Dictionary:
	return detections.get(owner_id, {})

static func _mark(detections: Dictionary, owner_id: String, center: HexCoord, radius: int, grid: HexGrid) -> void:
	if not detections.has(owner_id):
		detections[owner_id] = {}
	var owned: Dictionary = detections[owner_id]
	for coord in HexCoord.range_within(center, radius):
		if grid.has_hex(coord):
			owned[coord.to_key()] = true
