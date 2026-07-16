## Derives a player's maxSquads/maxCommanders caps from their owned bases
## (see 07-data-architecture.md sections 4c/4d) — neither cap is stored, both
## are computed fresh from live BaseInstance/BuildingInstance state.
class_name SquadCap
extends RefCounted

## maxSquads = sum(hqLevel across every owned base) * SQUAD_CAP_PER_HQ_LEVEL + SQUAD_CAP_BASE.
static func max_squads(bases: Array[BaseInstance]) -> int:
	var sum_hq_level := 0
	for base in bases:
		sum_hq_level += base.hq_level
	return sum_hq_level * Tuning.SQUAD_CAP_PER_HQ_LEVEL + Tuning.SQUAD_CAP_BASE

## Same shape as max_squads, its own separate pool for Support-tagged troops
## — see Tuning.SUPPORT_SQUAD_CAP_*.
static func max_support_squads(bases: Array[BaseInstance]) -> int:
	var sum_hq_level := 0
	for base in bases:
		sum_hq_level += base.hq_level
	return sum_hq_level * Tuning.SUPPORT_SQUAD_CAP_PER_HQ_LEVEL + Tuning.SUPPORT_SQUAD_CAP_BASE

## True for a Commander-tagged troop def (maxSquadsLed > 0) — gated purely by
## max_commanders, never by max_squads/max_support_squads. Checked first in
## is_support below since a Commander (e.g. Warden) can also carry the
## "Support" trait tag without being a Support-cap unit.
static func is_commander(troop_def: Dictionary) -> bool:
	return int(troop_def.get("maxSquadsLed", 0)) > 0

## True for a non-Commander troop def carrying the "Support" trait tag
## (Engineer, Mule, Ambulance, ...) — gated by max_support_squads instead of
## the general max_squads pool, so combat squads never compete with them for
## a slot. See CommandProcessor.can_enqueue_production.
static func is_support(troop_def: Dictionary) -> bool:
	if is_commander(troop_def):
		return false
	return (troop_def.get("tags", []) as Array).has("Support")

## maxCommanders = sum(commanderSlots across every owned Command Centre, at
## its current level). `building_defs` is the DataLoader.load_dir result for
## data/buildings, used to read command_centre's commanderProgression table.
static func max_commanders(bases: Array[BaseInstance], building_defs: Dictionary) -> int:
	var command_centre_def: Dictionary = building_defs.get("command_centre", {})
	var progression: Dictionary = command_centre_def.get("commanderProgression", {})

	var total := 0
	for base in bases:
		for command_centre in base.buildings_of_type("command_centre"):
			if command_centre.is_ruin:
				continue
			total += CommanderProgression.slots_at_level(progression, command_centre.level)
	return total
