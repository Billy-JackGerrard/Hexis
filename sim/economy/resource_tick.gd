## Applies one 5-second economy tick to a ResourcePool.
##
## Per 07-data-architecture.md section 7: sum production, subtract upkeep,
## apply the net delta, then report which resources are left in deficit.
## Production/upkeep are supplied as plain `ResourceType.Type -> float`
## dictionaries computed by the caller (base/building output, troop/base
## upkeep) — those systems don't exist yet, so this class only owns the
## netting + deficit-detection step, not sourcing the numbers.
class_name ResourceTick
extends RefCounted

## Mutates `pool` in place and returns the subset of ResourceType.Type
## (restricted to Food/Fuel, per ResourceType.can_deficit_drain) that ended
## this tick in deficit — the caller is responsible for acting on that (the
## per-squad troop-death consequence in 03-resources.md), since squads don't
## exist in the sim yet.
static func apply(pool: ResourcePool, production: Dictionary, upkeep: Dictionary) -> Array[ResourceType.Type]:
	for type in ResourceType.ALL:
		var produced: float = production.get(type, 0.0)
		var consumed: float = upkeep.get(type, 0.0)
		pool.add(type, produced - consumed)

	var deficits: Array[ResourceType.Type] = []
	for type in ResourceType.ALL:
		if ResourceType.can_deficit_drain(type) and pool.is_deficit(type):
			deficits.append(type)
	return deficits
