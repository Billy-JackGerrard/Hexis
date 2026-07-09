## Plain data holder returned by MapGenerator.generate() — same "state on
## the instance, no logic" style as BaseInstance/Player. Attaching this into
## a live MatchState is a one-line caller concern (state.grid = result.grid;
## state.bases = result.bases), not this class's job.
class_name MapGenerationResult
extends RefCounted

var grid: HexGrid
var bases: Array[BaseInstance] = []
var capital_ids_by_player: Dictionary = {} ## player_index (int) -> base id
## The seed that actually produced this result — may differ from the
## requested seed if MapGenerator retried with a derived seed after a
## constrained-placement dead end. See MapGenerator.generate().
var seed_used: int

func _init(p_grid: HexGrid, p_bases: Array[BaseInstance], p_capital_ids_by_player: Dictionary, p_seed_used: int) -> void:
	grid = p_grid
	bases = p_bases
	capital_ids_by_player = p_capital_ids_by_player
	seed_used = p_seed_used
