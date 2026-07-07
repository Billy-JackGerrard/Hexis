## Live per-match state for one player (see 07-data-architecture.md section 5).
## Resources live here, not per-base — `resources` is the single pool the
## economy tick and CommandProcessor both read/write for this owner_id.
## ownedBaseIds/maxSquads from the design doc aren't stored here: base
## ownership stays on BaseInstance.owner_id (the existing single source of
## truth — see MatchState.bases_owned_by), so this doesn't duplicate it.
class_name Player
extends RefCounted

var id: String
var resources: ResourcePool

func _init(p_id: String) -> void:
	id = p_id
	resources = ResourcePool.new()
