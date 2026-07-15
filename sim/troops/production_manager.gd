## Advances ProductionQueue timers and deploys completed entries into squads,
## per 07-data-architecture.md section 3b. Stateless static logic, same split
## as SquadManager/SquadCap (data lives on ProductionQueue, this owns the
## timing/deploy/pause rules).
##
## The cap-pause rule: when entries[0] finishes, if an existing same-type
## squad in range has room, the troop joins it and production continues
## regardless of cap. Only when a brand-new squad would be needed does the
## squad cap (or, for a Command Centre, the Commander cap) gate it — over cap
## pauses the queue (entries[0] holds complete-but-undeployed) rather than
## dropping the troop. Re-calling pump() after capacity frees is what resumes
## it; there's no separate "resume" entry point.
##
## The fuel-deficit pause rule follows the same shape: entries[0] whose troop
## type has a fuelUpkeep > 0 (i.e. would draw on Fuel once deployed) holds
## undeployed — not joined, not spawned — for as long as the owner's Fuel
## pool is in deficit (ResourcePool.is_deficit, amount < 0), same as
## 03-resources.md's Deficit Consequences already bleeds troops for. A troop
## type with no fuel upkeep (e.g. Infantry) is unaffected and keeps deploying.
class_name ProductionManager
extends RefCounted

static func enqueue(queue: ProductionQueue, troop_type: String, troop_defs: Dictionary) -> void:
	var troop_def: Dictionary = troop_defs.get(troop_type, {})
	var production_time: float = float(troop_def.get("productionTime", 0.0))
	queue.entries.append({
		"troop_type": troop_type,
		"production_time": production_time,
		"remaining": production_time,
	})

## Inserts one more `troop_type` right after `index` — used for the per-entry
## +1 button, which keeps the new copy grouped with the run it was clicked
## from instead of jumping to the tail of the whole queue.
static func insert_after(queue: ProductionQueue, index: int, troop_type: String, troop_defs: Dictionary) -> void:
	var troop_def: Dictionary = troop_defs.get(troop_type, {})
	var production_time: float = float(troop_def.get("productionTime", 0.0))
	queue.entries.insert(index + 1, {
		"troop_type": troop_type,
		"production_time": production_time,
		"remaining": production_time,
	})

## Drops queue.entries[index] outright (used for the per-entry -1 button).
## Never call with index 0 — the actively-training entry can't be cancelled
## this way; see CommandProcessor.can_dequeue_production.
static func remove_at(queue: ProductionQueue, index: int) -> void:
	queue.entries.remove_at(index)

## Ticks down entries[0] only (FIFO — later entries wait their turn). No-op
## while paused or empty.
static func advance(queue: ProductionQueue, dt: float) -> void:
	if queue.paused or queue.is_empty():
		return
	var entry: Dictionary = queue.front()
	entry["remaining"] = max(0.0, float(entry.get("remaining", 0.0)) - dt)

## Deploys every already-complete front entry it can, stopping at the first
## one that needs a new squad the owner is over-cap for (which pauses the
## queue) or once the queue runs out of complete entries.
##
## - owner_id/spawn_hex/building_type: identify who/where/what is producing.
##   A brand-new squad (the join path below reuses the existing squad's own
##   hex instead) actually deploys at `_domain_spawn_hex(spawn_hex, ...)`, not
##   necessarily spawn_hex itself: a Naval troop_type searches outward from
##   spawn_hex for the nearest open, unoccupied water hex via `grid` (a Naval
##   production building — Shipyard/Port/Harbour — sits on the adjacent
##   Plains hex, not on water itself, so spawning right on top of it would
##   otherwise land the new ship on dry land). Every other domain spawns at
##   spawn_hex unchanged. `grid` is optional (null skips this correction) so
##   callers that don't care (e.g. cap-math-only tests) can omit it.
## - squads: the owner's live SquadInstance list; mutated in place (append on
##   new squad, add_member on join).
## - troops_by_id: id -> TroopInstance registry; mutated in place (a deployed
##   troop, joined or new, is registered here) — every consumer downstream
##   (CombatResolver, UpkeepSystem, ...) resolves a squad's member_ids through
##   this registry, so a troop pump() creates but never registers here would
##   read back as already-dead the very next tick.
## - owner_bases: every base the owner owns, for SquadCap's cap math.
## - current_commander_count: live count of the owner's Commander troops;
##   regiments/commanders aren't in a global registry the sim can derive this
##   from yet, so the caller supplies it.
## - next_troop_id/next_squad_id: Callables returning a fresh id String each
##   call — multiple entries can deploy in one pump() (e.g. a zero-duration
##   entry immediately following the one that just completed).
## - pool: owner_id's ResourcePool, for the fuel-deficit pause rule above.
##   Optional (null skips the check, same as `grid`) so cap-math-only callers
##   that don't care about Fuel can omit it.
static func pump(
	queue: ProductionQueue,
	owner_id: String,
	spawn_hex: HexCoord,
	building_type: String,
	squads: Array[SquadInstance],
	troops_by_id: Dictionary,
	owner_bases: Array[BaseInstance],
	building_defs: Dictionary,
	troop_defs: Dictionary,
	current_commander_count: int,
	next_troop_id: Callable,
	next_squad_id: Callable,
	grid: HexGrid = null,
	pool: ResourcePool = null,
) -> void:
	while queue.front_complete():
		var entry: Dictionary = queue.front()
		var troop_type: String = entry.get("troop_type", "")
		var troop_def: Dictionary = troop_defs.get(troop_type, {})
		var max_squad_size: int = int(troop_def.get("maxSquadSize", 1))

		if pool != null and float(troop_def.get("fuelUpkeep", 0.0)) > 0.0 and pool.is_deficit(ResourceType.Type.FUEL):
			queue.paused = true
			queue.pause_reason = "fuel_deficit"
			return

		var joinable: SquadInstance = SquadManager.find_joinable_squad(
			squads, owner_id, troop_type, spawn_hex, max_squad_size, Tuning.PRODUCTION_JOIN_RANGE_RADIUS
		)
		if joinable != null:
			var joined_troop := TroopInstance.new(next_troop_id.call(), troop_type, owner_id, joinable.id, float(troop_def.get("hp", 0.0)))
			troops_by_id[joined_troop.id] = joined_troop
			joinable.add_member(joined_troop.id)
			queue.entries.pop_front()
			queue.paused = false
			queue.pause_reason = ""
			continue

		if building_type == "command_centre":
			var max_commanders := SquadCap.max_commanders(owner_bases, building_defs)
			if current_commander_count >= max_commanders:
				queue.paused = true
				queue.pause_reason = "commander_cap"
				return
			current_commander_count += 1
		else:
			var owner_squad_count := 0
			for s in squads:
				if s.owner_id == owner_id:
					owner_squad_count += 1
			var max_squads := SquadCap.max_squads(owner_bases)
			if owner_squad_count >= max_squads:
				queue.paused = true
				queue.pause_reason = "squad_cap"
				return

		var deploy_hex := _domain_spawn_hex(spawn_hex, troop_def, grid, squads)
		var new_squad := SquadInstance.new(next_squad_id.call(), owner_id, troop_type, deploy_hex)
		var new_troop := TroopInstance.new(next_troop_id.call(), troop_type, owner_id, new_squad.id, float(troop_def.get("hp", 0.0)))
		troops_by_id[new_troop.id] = new_troop
		new_squad.add_member(new_troop.id)
		squads.append(new_squad)
		queue.entries.pop_front()
		queue.paused = false
		queue.pause_reason = ""

## `spawn_hex` unchanged unless `troop_def` is Naval-domain and `grid` is
## supplied, in which case this searches outward (HexGrid.
## nearest_passable_hex) for the nearest water hex not already sitting under
## another squad — see pump()'s doc comment above for why (a Naval building
## sits on land adjacent to water, not on water itself).
static func _domain_spawn_hex(spawn_hex: HexCoord, troop_def: Dictionary, grid: HexGrid, squads: Array[SquadInstance]) -> HexCoord:
	if grid == null:
		return spawn_hex
	if Terrain.domain_from_string(String(troop_def.get("domain", "Infantry"))) != Terrain.Domain.NAVAL:
		return spawn_hex
	return grid.nearest_passable_hex(spawn_hex, Terrain.Domain.NAVAL, func(h): return not _hex_has_squad(h, squads))

static func _hex_has_squad(hex: HexCoord, squads: Array[SquadInstance]) -> bool:
	for squad in squads:
		if squad.current_hex != null and squad.current_hex.equals(hex):
			return true
	return false
