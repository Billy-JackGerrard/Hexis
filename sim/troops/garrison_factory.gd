## Seeds a base's `initialGarrison` as standing SquadInstances near its HQ,
## per 02-bases-and-buildings.md's "Initial Garrison (Unique Bases)" section:
## garrison troops are never part of the BaseInstance itself — a garrison is
## just squads standing nearby, each independently owned (see SquadInstance/
## TroopInstance.owner_id vs. BaseInstance.owner_id) so they don't change
## hands on capture. Capitals have no initialGarrison entries so this is a
## no-op for them.
##
## Placed on the ring 2 hexes out from hq_hex — BaseFactory.seed_base already
## fans initialBuildings across the ring at radius 1, so radius 2 keeps
## garrison squads clear of the seeded building footprint. When `grid` is
## supplied, each squad's ring candidate is domain-corrected via
## HexGrid.nearest_passable_hex before being used (a Naval garrison entry —
## e.g. Kraken Point's Destroyers/Submarine — searches outward from its ring
## hex for the nearest actual water tile instead of landing on Plains; a
## Land/Infantry/Air entry almost always already qualifies at its ring hex
## unchanged, since the flower + Tuning.GARRISON_RING_RADIUS are on-site terrain).
## `grid` is optional (null skips domain correction entirely, seeding at the
## raw ring hex like before) so callers that don't care about terrain realism
## (e.g. siting-only tests) can omit it.
class_name GarrisonFactory
extends RefCounted

## Ring radius/search-radius tunables live in sim/tuning.gd as
## Tuning.GARRISON_RING_RADIUS/GARRISON_SEARCH_RADIUS.

## Splits each initialGarrison entry into squads capped at that troop type's
## maxSquadSize (ceil(count / max_squad_size) squads, last one partial),
## appends the new SquadInstances to `squads` and registers their members in
## `troops_by_id` — both mutated in place, mirroring ProductionManager.pump's
## caller-owns-the-registries convention. `next_troop_id`/`next_squad_id` are
## Callables returning a fresh id String each call, same shape as
## ProductionManager.pump's.
static func seed_garrison(
	base_def: Dictionary,
	owner_id: String,
	hq_hex: HexCoord,
	troop_defs: Dictionary,
	squads: Array[SquadInstance],
	troops_by_id: Dictionary,
	next_troop_id: Callable,
	next_squad_id: Callable,
	grid: HexGrid = null,
) -> void:
	var garrison: Array = base_def.get("initialGarrison", [])
	if garrison.is_empty():
		return

	var ring := HexCoord.ring(hq_hex, Tuning.GARRISON_RING_RADIUS)
	var ring_index := 0
	var used_hexes: Dictionary = {}

	for entry in garrison:
		var troop_type: String = entry.get("troopId", "")
		var count: int = int(entry.get("count", 0))
		var troop_def: Dictionary = troop_defs.get(troop_type, {})
		var max_squad_size: int = max(1, int(troop_def.get("maxSquadSize", 1)))
		var hp: float = float(troop_def.get("hp", 0.0))
		var domain := Terrain.domain_from_string(String(troop_def.get("domain", "Infantry")))

		var remaining := count
		while remaining > 0:
			var squad_size: int = min(remaining, max_squad_size)
			var candidate: HexCoord = ring[ring_index % ring.size()]
			ring_index += 1

			var hex := candidate
			if grid != null:
				hex = grid.nearest_passable_hex(candidate, domain, func(h): return not used_hexes.has(h.to_key()), Tuning.GARRISON_SEARCH_RADIUS)
			used_hexes[hex.to_key()] = true

			var squad := SquadInstance.new(next_squad_id.call(), owner_id, troop_type, hex)
			for i in range(squad_size):
				var troop := TroopInstance.new(next_troop_id.call(), troop_type, owner_id, squad.id, hp)
				troops_by_id[troop.id] = troop
				squad.add_member(troop.id)
			squads.append(squad)

			remaining -= squad_size
