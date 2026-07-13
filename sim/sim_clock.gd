## Fixed-timestep driver for SimOrchestrator — decouples the sim from render
## framerate so movement/combat integrate at a constant cadence (nominally
## 100ms/10Hz per 07-data-architecture.md section 7) regardless of how fast
## frames render, matching the authoritative-server loop a network layer will
## later run. Rendering doesn't need to change to tolerate a coarser step:
## SquadView already interpolates squad position between ticks off
## edge_progress rather than assuming per-frame movement.
class_name SimClock
extends RefCounted

const SIM_TICK_SECONDS: float = 0.1

## Caps fixed steps taken per advance() call so a huge real-time delta (e.g.
## after a debugger pause or the window losing focus) can't spiral into an
## ever-growing catch-up loop — banked time beyond this is simply dropped.
const MAX_STEPS_PER_ADVANCE: int = 10

var _accumulator: float = 0.0

## Feeds real elapsed `delta` in, running SimOrchestrator.resolve_tick a whole
## number of times at the fixed SIM_TICK_SECONDS step.
func advance(state: MatchState, delta: float) -> void:
	_accumulator += delta
	var steps := 0
	while _accumulator >= SIM_TICK_SECONDS and steps < MAX_STEPS_PER_ADVANCE:
		SimOrchestrator.resolve_tick(state, SIM_TICK_SECONDS)
		_accumulator -= SIM_TICK_SECONDS
		steps += 1
