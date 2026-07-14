## Fixed-timestep driver for SimOrchestrator — decouples the sim from render
## framerate so movement/combat integrate at a constant cadence (nominally
## 100ms/10Hz per 07-data-architecture.md section 7) regardless of how fast
## frames render, matching the authoritative-server loop a network layer will
## later run. Rendering doesn't need to change to tolerate a coarser step:
## SquadView already interpolates squad position between ticks off
## edge_progress rather than assuming per-frame movement.
class_name SimClock
extends RefCounted

## Tick step and catch-up cap live in sim/tuning.gd as
## Tuning.SIM_TICK_SECONDS/MAX_STEPS_PER_ADVANCE.

var _accumulator: float = 0.0

## Feeds real elapsed `delta` in, running SimOrchestrator.resolve_tick a whole
## number of times at the fixed Tuning.SIM_TICK_SECONDS step.
func advance(state: MatchState, delta: float) -> void:
	_accumulator += delta
	var steps := 0
	while _accumulator >= Tuning.SIM_TICK_SECONDS and steps < Tuning.MAX_STEPS_PER_ADVANCE:
		SimOrchestrator.resolve_tick(state, Tuning.SIM_TICK_SECONDS)
		_accumulator -= Tuning.SIM_TICK_SECONDS
		steps += 1
