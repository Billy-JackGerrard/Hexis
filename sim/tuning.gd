## Central home for every "placeholder" gameplay tuning number in sim/ —
## constants with no exact value pinned by a game-design doc, only a
## design-doc-described relationship (a formula, a rough fraction, "tune
## freely") that some file had to pick a concrete starting point for.
## Mirrors sim/hex/terrain_types.gd's long-standing precedent (Terrain.
## HILLS_DEFENDER_BONUS etc.) of keeping such guesses named and commented
## instead of buried as bare literals — this file just extends that same
## treatment across the rest of sim/ instead of leaving each guess local to
## the one class that happens to use it, so a full pass over "what did we
## make up and might want to rebalance" is one file, not ten.
##
## Data that IS pinned by an authored source stays where it already lives:
## per-troop/per-building/per-base stats in data/*.json (read via
## troop_defs/building_defs/base_defs throughout sim/), and terrain's own
## movement/vision/defense bonuses in sim/hex/terrain_types.gd (predates this
## file and is referenced by name in several comments below).
class_name Tuning
extends RefCounted

## --- World generation (sim/worldgen/terrain_generator.gd) ---

## map_radius(player_count) = MAP_RADIUS_BASE + player_count * MAP_RADIUS_PER_PLAYER.
## Sized so CAPITAL_MIN_SPACING comfortably fits every
## player's Capital spread near the outer ring, with room left for Unique
## bases plus biomes/rivers.
const MAP_RADIUS_BASE: int = 30
const MAP_RADIUS_PER_PLAYER: int = 12

## Ring of Ocean beyond the coastline. Narrow, but strategically real — Ocean
## is already fully Naval-passable, so ships can actually sail the fringe and
## the outer coastline ring, not just look at it.
const OCEAN_FRINGE_WIDTH: int = 2

## Biome seed points are kept at least this far inside the coastline, so
## coastal Plains stays generally clear (a soft bias on seed placement only —
## growth itself can still reach the edge organically).
const BIOME_EDGE_BUFFER: int = 2

## Interior-area coverage budgets. Kept low enough that Plains stays the clear
## majority tile even after rivers add a few more percent, per
## 01-map-and-terrain.md's "Plains ... majority of tiles".
const FOREST_COVERAGE_FRACTION: float = 0.12
const HILLS_COVERAGE_FRACTION: float = 0.08

const SMALL_PATCH_RANGE: Vector2i = Vector2i(4, 8)
const MEDIUM_PATCH_RANGE: Vector2i = Vector2i(9, 16)
const LARGE_PATCH_RANGE: Vector2i = Vector2i(17, 28)
const PATCH_SIZE_WEIGHTS: Array[float] = [0.4, 0.4, 0.2] ## small, medium, large

## Probability of skipping an otherwise-valid frontier neighbor during blob
## growth — produces organic, non-circular patch shapes instead of a perfect
## disk.
const BIOME_GROWTH_JITTER: float = 0.25
const MIN_BIOME_SEED_SPACING: int = 3
const MAX_BIOME_SEED_ATTEMPTS: int = 200

## num_rivers(player_count) = RIVER_BASE_COUNT + (player_count - 2) / 2 (int
## division): 2p->2, 4p->3, 6p->4.
const RIVER_BASE_COUNT: int = 2

const RIVER_MIN_LENGTH: int = 8 ## hexes; also the source's min inset from the coastline
const MIN_RIVER_SOURCE_SPACING: int = 8
const RIVER_STRAIGHTNESS: float = 0.65 ## chance of taking the most-outward-progress step vs. a random valid one
const RIVER_MAX_STEPS_MULTIPLIER: int = 2 ## safety cap = map_radius * this
const MAX_RIVER_SOURCE_ATTEMPTS_PER_RIVER: int = 20

## --- Base siting (sim/worldgen/base_site_selector.gd) ---

## ~2x a level-1 HQ build radius (HQ_BUILD_RADIUS_BASE + 1 * HQ_BUILD_RADIUS_PER_LEVEL == 4)
## plus margin, so two fresh bases' starting build radii can't overlap and a
## freshly spawned player never lands within sight/striking distance of a
## neutral Unique base.
const MIN_BASE_SPACING: int = 16

## Enforced ADDITIONALLY between two Capitals specifically (on top of
## MIN_BASE_SPACING) — "Capitals are placed defensively/spread out" per
## 01-map-and-terrain.md. 6 Capitals spread near a ring of this radius around
## the map center stay >= this far apart from each other.
const CAPITAL_MIN_SPACING: int = 22

const MAX_SITE_CANDIDATES_SCANNED: int = 500

## Candidate flower's distance from map center must be within this many hexes
## of map_radius to count as "ocean edge" for Kraken Point.
const KRAKEN_EDGE_INSET: int = 3

## Treehouse "surrounded by forest" proxy: most (not all — jittered organic
## patch growth leaves occasional gaps even inside a large patch) of the
## hexes within this many rings of the candidate must also be Forest — only a
## reasonably compact medium/large patch can satisfy the coverage bar.
const TREEHOUSE_FOREST_DEPTH: int = 2
const TREEHOUSE_FOREST_COVERAGE_FRACTION: float = 0.8

## Capital expansion-viability heuristic (has_viable_expansion): bounded
## Land-domain flood-fill radius, min reachable hexes per sextant to count as
## "viable", and how many of the 6 sextants must clear that bar.
const EXPANSION_CHECK_RADIUS: int = 8
const EXPANSION_SEXTANT_MIN_HEXES: int = 5
const EXPANSION_MIN_VIABLE_SEXTANTS: int = 2

## Sky Fortress moat: a ring at this hex-distance from its HQ hex is
## force-converted to Ocean. Requires at least this fraction of the ring to
## actually be convertible, checked BEFORE committing to the site. Pushed out
## to 4 (rather than sitting right past the flower at 2) so the base actually
## has buildable Plains between its flower and the moat, instead of the moat
## boxing it in with zero expansion room.
const MOAT_INNER_RADIUS: int = 4
const MOAT_MIN_COVERAGE_FRACTION: float = 0.7

## Caps how far a carved connectivity channel is allowed to dig before a
## candidate site is rejected instead — pre-existing water is rarely much
## further than this from an interior point given the river spacing tunables
## above.
const MOAT_CHANNEL_MAX_LENGTH: int = 16

## --- Map generation retry (sim/map_generator.gd) ---

## Whole-pipeline (terrain + siting) retry cap before generation gives up and
## reports failure.
const MAX_GENERATION_ATTEMPTS: int = 5

## --- Base/building seeding (sim/bases/base_factory.gd) ---

## How far a seeded base's non-Wall/non-HQ buildings are willing to
## ring-search outward from hq_hex for a free (and, for an
## adjacency-requiring building, terrain-qualifying) hex before giving up and
## taking whatever's closest.
const MAX_SEED_SEARCH_RING: int = 4

## --- Building placement (sim/bases/building_placement.gd) ---

## Max hex-distance between the building Engineer and a standalone build site
## (Road/Bridge/Dock/Tower/Landmine) — an Engineer must travel next to a site
## rather than dropping infrastructure anywhere on the map. 1 = adjacent-only.
const STANDALONE_BUILD_RANGE: int = 1

## Minimum adjacent existing buildings required for a normal (non-Wall)
## placement, per the Expansion Rule.
const MIN_ADJACENT_BUILDINGS: int = 2

## Minimum adjacent existing buildings required for a Wall — per
## 02-bases-and-buildings.md, only ONE (not MIN_ADJACENT_BUILDINGS's two).
const MIN_ADJACENT_BUILDINGS_FOR_WALL: int = 1

## hq_build_radius(hq_level) = HQ_BUILD_RADIUS_BASE + hq_level * HQ_BUILD_RADIUS_PER_LEVEL.
## Design doc pins the scaling relationship but not the exact number.
const HQ_BUILD_RADIUS_BASE: int = 2
const HQ_BUILD_RADIUS_PER_LEVEL: int = 2

## --- Building regeneration (sim/bases/building_regen_system.gd) ---

## 5% of current max HP per 5-second tick, per
## 06-building-stats-and-defenses.md's Regeneration rule. The design doc says
## regen starts once a building "hasn't taken damage recently" without
## pinning an exact delay.
const BUILDING_REGEN_OUT_OF_COMBAT_DELAY_SECONDS: float = 5.0
const BUILDING_REGEN_TICK_SECONDS: float = 5.0
const BUILDING_REGEN_FRACTION_OF_MAX_HP: float = 0.05

## --- Command (sim/command/command_processor.gd) ---

## Flat refund fraction on voluntary demolish, applied to a building's
## total_resources_spent. Deliberately distinct from the data-driven
## rebuildCost field (data/buildings/*.json) — this is demolish's own ratio,
## not a proxy for rebuild pricing.
const DEMOLISH_REFUND_FRACTION: float = 0.5

## --- Economy (sim/economy/resource_type.gd) ---

## Per-match starting resource pool, per game-design/03-resources.md's
## Starting Resources section. Wood/Fuel start at zero deliberately, since a
## bare starting Capital has no Forest-adjacent Lumber Mill or built Oil Rig
## yet.
const STARTING_FOOD: float = 100.0
const STARTING_STONE: float = 100.0
const STARTING_STEEL: float = 50.0
const STARTING_WOOD: float = 0.0
const STARTING_FUEL: float = 0.0

## --- Troops (sim/troops/) ---

## Garrison squads are placed on the ring this many hexes out from hq_hex —
## BaseFactory.seed_base already fans initialBuildings across ring 1, so ring
## 2 keeps garrison squads clear of the seeded building footprint.
const GARRISON_RING_RADIUS: int = 2

## How far past the garrison ring a domain-corrected search is willing to
## wander looking for a qualifying hex — generous enough to reach open water
## from a coastal ring hex without drifting into another base's territory
## (MIN_BASE_SPACING comfortably clears this).
const GARRISON_SEARCH_RADIUS: int = 6

## Range within which a freshly-produced troop can join an existing
## same-type squad instead of forming a new one.
const PRODUCTION_JOIN_RANGE_RADIUS: int = 1

## maxSquads = sum(hqLevel across every owned base) * SQUAD_CAP_PER_HQ_LEVEL + SQUAD_CAP_BASE.
const SQUAD_CAP_BASE: int = 2
const SQUAD_CAP_PER_HQ_LEVEL: int = 2

## --- Combat (sim/combat/) ---

## Stun's fixed trailing debuff: -30% move AND attack speed while
## stun_tail_remaining > 0. A global rule tied to the `stun` status-effect
## type itself, not a per-instance authored number.
const STUN_TAIL_SPEED_MULT: float = 0.7

## Warden's heal_out_of_combat note says "hasn't taken damage recently"
## without pinning an exact delay; mirrors
## BUILDING_REGEN_OUT_OF_COMBAT_DELAY_SECONDS.
const AURA_OUT_OF_COMBAT_HEAL_DELAY_SECONDS: float = 5.0

## --- Vision / stealth (sim/vision/detection_system.gd) ---

## Schema's revealsOnAttack says stealth breaks "until a few seconds pass
## without attacking" but never pins an exact duration.
const STEALTH_REVEAL_COOLDOWN_SECONDS: float = 3.0

## 04-combat.md's "hidden until engaging" is read literally as no proximity
## reveal at all for forest ambush (unlike authored stealth units, which use
## their own revealRange).
const FOREST_AMBUSH_REVEAL_RANGE: float = 0.0

## --- Tick rates (sim/sim_clock.gd, sim/sim_orchestrator.gd) ---

## Fixed simulation timestep, nominally 100ms/10Hz per
## 07-data-architecture.md section 7.
const SIM_TICK_SECONDS: float = 0.1

## Caps fixed steps taken per SimClock.advance() call so a huge real-time
## delta (e.g. after a debugger pause or the window losing focus) can't
## spiral into an ever-growing catch-up loop — banked time beyond this is
## simply dropped.
const MAX_STEPS_PER_ADVANCE: int = 10

## Economy tick cadence (banked accumulator) — 07-data-architecture.md
## section 7's coarser 5-second resource/upkeep pass.
const ECONOMY_TICK_SECONDS: float = 5.0
