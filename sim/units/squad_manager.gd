## Squad-formation rule from 07-data-architecture.md section 4a: a freshly
## produced troop joins the nearest same-type squad with room in its spawn
## hex's neighborhood, or forms a new squad of 1. Doesn't own squad cap
## enforcement itself (see SquadCap) — needs_new_squad tells a caller whether
## a cap check even applies before spending a slot.
class_name SquadManager
extends RefCounted

static func find_joinable_squad(squads: Array[SquadInstance], owner_id: String, troop_type: String, spawn_hex: HexCoord, max_squad_size: int, radius: int = 1) -> SquadInstance:
	for squad in squads:
		if squad.owner_id != owner_id or squad.troop_type != troop_type:
			continue
		if squad.is_full(max_squad_size):
			continue
		if HexCoord.distance(squad.current_hex, spawn_hex) <= radius:
			return squad
	return null

## True if no existing joinable squad has room — i.e. producing this troop
## would need a brand-new squad, which is what the squad-cap-pause check
## (section 3b) actually gates on.
static func needs_new_squad(squads: Array[SquadInstance], owner_id: String, troop_type: String, spawn_hex: HexCoord, max_squad_size: int, radius: int = 1) -> bool:
	return find_joinable_squad(squads, owner_id, troop_type, spawn_hex, max_squad_size, radius) == null
