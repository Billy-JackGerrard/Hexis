## Plain data holder returned by MapGenerator.generate() — same "state on
## the instance, no logic" style as BaseInstance/Player. Attaching this into
## a live MatchState is a one-line caller concern (state.grid = result.grid;
## state.bases = result.bases), not this class's job.
class_name MapGenerationResult
extends RefCounted

var grid: HexGrid
var bases: Array[BaseInstance] = []
var capital_ids_by_player: Dictionary = {} ## player_index (int) -> base id
## Standing garrison squads GarrisonFactory seeded from each base's
## `initialGarrison` (empty for Capitals, which have none) — independent of
## `bases`, per 02-bases-and-buildings.md's "garrison troops are not part of
## the base" rule.
var squads: Array[SquadInstance] = []
var troops_by_id: Dictionary = {} ## id -> TroopInstance, members of `squads`
## The seed that actually produced this result — may differ from the
## requested seed if MapGenerator retried with a derived seed after a
## constrained-placement dead end. See MapGenerator.generate().
var seed_used: int

func _init(p_grid: HexGrid, p_bases: Array[BaseInstance], p_capital_ids_by_player: Dictionary, p_seed_used: int, p_squads: Array[SquadInstance] = [], p_troops_by_id: Dictionary = {}) -> void:
	grid = p_grid
	bases = p_bases
	capital_ids_by_player = p_capital_ids_by_player
	seed_used = p_seed_used
	squads = p_squads
	troops_by_id = p_troops_by_id
