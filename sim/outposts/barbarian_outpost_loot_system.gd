## One-shot reward resolver for barbarian outposts (see BarbarianOutpostInstance/
## BarbarianOutpostPlacer) — called once per fine tick from SimOrchestrator,
## after CombatResolver/ProjectileSystem have had a chance to mark an
## outpost's tower_destroyed this tick (see CombatResolver._prune_dead).
##
## Waits on BOTH the tower and the garrison being dead, independently, in
## EITHER order, before paying out — not just "tower died". With no roaming/
## aggro AI, a player can order a direct attack on the tower from outside the
## garrison's engagement range, killing it while guards are still alive; a
## single "tower death" trigger would pay out before the "kill the garrison +
## tower" camp is actually cleared. tower_destroyed persists on the
## BarbarianOutpostInstance (set once, never unset) so this only has to check
## "is every guard_squad_id gone" each tick, not re-derive tower state itself.
class_name BarbarianOutpostLootSystem
extends RefCounted

static func resolve_tick(barbarian_outposts: Array[BarbarianOutpostInstance], squads: Array[SquadInstance], pool_for: Callable, events: Array[MatchEvent] = []) -> void:
	if barbarian_outposts.is_empty():
		return

	var living_squad_ids: Dictionary = {}
	for squad in squads:
		living_squad_ids[squad.id] = true

	for i in range(barbarian_outposts.size() - 1, -1, -1):
		var outpost := barbarian_outposts[i]
		if not outpost.tower_destroyed:
			continue
		var garrison_cleared := true
		for guard_id in outpost.guard_squad_ids:
			if living_squad_ids.has(guard_id):
				garrison_cleared = false
				break
		if not garrison_cleared:
			continue

		# tower_killer can be "" if the tower died to something with no
		# attributable owner (shouldn't currently happen — every damage source
		# is a squad/building with an owner_id — but no killer means no one to
		# pay, not an error).
		if outpost.tower_killer != "":
			var pool: ResourcePool = pool_for.call(outpost.tower_killer)
			for key in outpost.loot:
				pool.add(ResourceType.from_string(key), outpost.loot[key])
			events.append(MatchEvent.new(MatchEvent.Type.OUTPOST_LOOT, outpost.tower_killer, {"loot": outpost.loot.duplicate()}))
		barbarian_outposts.remove_at(i)
