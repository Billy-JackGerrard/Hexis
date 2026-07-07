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
class_name ProductionManager
extends RefCounted

const RANGE_RADIUS := 1

static func enqueue(queue: ProductionQueue, troop_type: String, troop_defs: Dictionary) -> void:
	var troop_def: Dictionary = troop_defs.get(troop_type, {})
	var production_time: float = float(troop_def.get("productionTime", 0.0))
	queue.entries.append({
		"troop_type": troop_type,
		"production_time": production_time,
		"remaining": production_time,
	})

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
) -> void:
	while queue.front_complete():
		var entry: Dictionary = queue.front()
		var troop_type: String = entry.get("troop_type", "")
		var troop_def: Dictionary = troop_defs.get(troop_type, {})
		var max_squad_size: int = int(troop_def.get("maxSquadSize", 1))

		var joinable: SquadInstance = SquadManager.find_joinable_squad(
			squads, owner_id, troop_type, spawn_hex, max_squad_size, RANGE_RADIUS
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

		var new_squad := SquadInstance.new(next_squad_id.call(), owner_id, troop_type, spawn_hex)
		var new_troop := TroopInstance.new(next_troop_id.call(), troop_type, owner_id, new_squad.id, float(troop_def.get("hp", 0.0)))
		troops_by_id[new_troop.id] = new_troop
		new_squad.add_member(new_troop.id)
		squads.append(new_squad)
		queue.entries.pop_front()
		queue.paused = false
		queue.pause_reason = ""
