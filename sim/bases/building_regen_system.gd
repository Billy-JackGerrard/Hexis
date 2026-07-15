## Slowly regenerates HP on damaged-but-surviving buildings once they haven't
## taken damage recently, per 06-building-stats-and-defenses.md's Regeneration
## rule: 5% of current max HP per 5-second tick. Stateless/static, same
## accumulator-over-dt shape as CombatResolver's attack_progress — banks dt
## toward the next regen tick rather than assuming a fixed external cadence.
##
## A ruin (BuildingInstance.is_ruin) never regens on its own — see that
## field's doc — and a building at full HP just resets its accumulator so a
## long, undamaged lull doesn't bank a huge burst for the first hit it takes.
class_name BuildingRegenSystem
extends RefCounted

## Tunables (out-of-combat delay, tick cadence, heal fraction) live in
## sim/tuning.gd (Tuning.BUILDING_REGEN_*) rather than here.

static func resolve_tick(dt: float, bases: Array[BaseInstance]) -> void:
	for base in bases:
		for building in base.buildings:
			_regen(building, dt)

static func _regen(building: BuildingInstance, dt: float) -> void:
	if building.max_hp <= 0.0 or building.is_ruin or building.current_hp <= 0.0:
		return
	building.time_since_damage += dt
	if building.current_hp >= building.max_hp:
		building.regen_progress = 0.0
		return
	if building.time_since_damage < Tuning.BUILDING_REGEN_OUT_OF_COMBAT_DELAY_SECONDS:
		return
	building.regen_progress += dt
	while building.regen_progress >= Tuning.BUILDING_REGEN_TICK_SECONDS and building.current_hp < building.max_hp:
		building.current_hp = min(building.max_hp, building.current_hp + building.max_hp * Tuning.BUILDING_REGEN_FRACTION_OF_MAX_HP)
		building.regen_progress -= Tuning.BUILDING_REGEN_TICK_SECONDS
