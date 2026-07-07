# Map & Terrain

## Shape
- Map is a large **hexagon** made of hex tiles.
- Outer edge is a fixed **coastline**; a bit of open ocean extends beyond it for scale/
  visual purposes (not strategically significant).
- Generation: **organic/hand-crafted feel**, produced via procedural generation with
  balance constraints (e.g. every Capital Base guarantees at least 2 viable expansion
  paths). Not symmetric/mirrored.
- **Every base's seed hex (HQ/Farm/Quarry cluster) is always sited on Plains**,
  regardless of base type — this holds even for Treehouse and Windy Peaks. Only their
  *specialty* buildings deviate from the Plains-only rule (placeable on Forest/Hill
  respectively); the base's core is always on Plains like every other base.

## Base Density (scalable)
- Ratio: roughly **2 Unique (neutral city-state) bases per player**, plus 1 Capital Base
  per player.
  - 2 players → 2 Capitals + 4 Unique = 6 bases
  - 4 players → 4 Capitals + 8 Unique = 12 bases
  - 6 players → 6 Capitals + 12 Unique = 18 bases
- Capitals are placed defensively (spread out) to avoid trivial early rushes.
- **Minimum base spacing**: generation enforces a minimum hex-distance between *any*
  two bases (Capital or Unique) so bases never seed close enough for their build/vision
  radii to overlap or for one squad to threaten two bases at once.
- **Capital-to-Capital spacing**: Capitals additionally enforce a larger minimum
  hex-distance from every *other* Capital — substantially bigger than the general
  minimum spacing above — which is what "placed defensively" concretely means: no two
  players can start close enough for an early rush to reach an enemy Capital before a
  defense can be organized.
- **Every Unique base is genuinely unique**: at most one instance of each Unique base
  type (Fort Irongrad, Firebase, Windy Peaks, Treehouse, Kraken Point, Sky Fortress,
  Winter Forge, ...) can exist on a map at any time — no duplicates. This means the
  2-Unique-bases-per-player ratio is drawn from the collective pool of distinct types,
  not "2 of whichever type," so whoever secures a given Unique base has an exclusive
  hold on its perks (Wood access via a forest-adjacent Lumber Mill is no longer
  capture-gated the same way — see `02-bases-and-buildings.md` — but heavy-tank access,
  for instance, is genuinely a monopoly on whoever holds Fort Irongrad/Winter Forge).
  **Open scaling question**: this requires the authored roster of Unique base types to
  be at least as large as `2 x player count` for a given match size — as more player
  counts are supported, more Unique base types need to be authored (this is already the
  plan; see `02-bases-and-buildings.md`'s Unique Bases section, which is actively
  growing).

## Terrain Types
Terrain forms **biome clusters/patches** (varying sizes — small/medium/large), not
scattered single tiles, e.g. a proper forest region rather than one random forest tile.

| Terrain | Infantry | Land Vehicles | Naval | Air | Vision | Buildable? |
|---|---|---|---|---|---|---|
| **Plains** | Normal | Normal | N/A | Normal | Normal | Yes (only buildable terrain, and majority of tiles) |
| **Forest** | Normal | **Blocked** unless a Road is built through it | N/A | Normal | Normal | No (except Treehouse's buildings — forest tiles) |
| **Hills** | Slowed | Normal | N/A | Normal | **Extended vision + extends fog-of-war clearing** (elevation) | No (except Windy Peaks' buildings — hill tiles) |
| **River** | **Blocked** unless a Bridge is built | **Blocked** unless a Bridge is built | Fully passable | Normal | Normal | No |
| **Ocean** | **Blocked** | **Blocked** | Fully passable | Normal | Normal | No |

- **Resolved: "Coast" is not a distinct terrain type** — it was previously listed as
  its own row, but it's really just Plains at the edge of the map, directly adjacent to
  an Ocean or River tile. There's no separate shoreline tile type to generate or store.
- **"Water" adjacency is a single unified concept**: anywhere a building's
  `placementRequirement.adjacentTerrainRequired: "Water"` is checked (Port, Shipyard,
  Harbour, a non-Treehouse Lumber Mill's Forest-adjacency is separate — see below), it's
  satisfied by a neighboring **Ocean tile or a River tile** — whichever is present,
  interchangeably. A base built beside a river qualifies for a Port exactly like one
  beside the open sea; there's no separate "riverside" vs. "coastal" placement rule.
- **Ocean** is open water beyond the landmass: impassable to Infantry/Land Vehicles,
  fully passable to Naval, ignored by Air — same rules as River water tiles. Docks and
  water-adjacent Ports/Shipyards/Harbours front onto it (or onto a River tile) from an
  adjacent Plains hex.
- **Air units** ignore all terrain restrictions entirely.
- **Vision range vs. engagement range are separate** — you can see an enemy approaching
  before they're in attack range, giving a reaction window.

## Naval / Coastline Rules
- Naval troops can travel the **outer coastline ring** all the way around the map, and
  can sail up any **river** — rivers are automatically navigable from the sea at their
  mouth (no port/dock required just to sail).
- Naval troops can **only disembark onto land at a Dock, a Port/Shipyard, or a
  Harbour** — they cannot land anywhere else along a coast or riverbank. The
  same rule gates boarding: ground troops can only board a Naval carrier from
  one of these hexes (or from open water they're already standing in/on).
- **Fuel**: ships use very little Fuel (negligible compared to aircraft).

## Public Infrastructure (Roads, Bridges, Docks)
- Built only by the **Engineer** troop.
- Buildable **anywhere**, including behind enemy lines (high risk/high reward play —
  an unescorted Engineer is easy to kill).
- Once built, these are **public** — any player's troops can use a Road, Bridge, or Dock,
  not just the builder's. This creates natural contested chokepoints.
- **Destroying** a Road/Bridge/Dock: any troop can do it, but only after all
  defenders on/near it have been cleared first.
- **Dock**: standalone structure, allows ship landing only. Can be placed anywhere on
  coast/riverbank, not tied to a base.

## Fog of War
- **Full fog** until scouted.
- Standard "explored but not currently visible" fade — persistent reveal of terrain
  shape, but current troop positions/base composition require live vision.
- Hills extend both sight radius and how far fog clears (elevation advantage) — hills
  are good vantage/watchtower points despite being unbuildable and slowing Infantry.
  Plains are vision-neutral: purely economic/buildable terrain, with no vision edge
  that would make ambushes (e.g. landmines) unreliable on the tile type most squads
  actually cross. Forests are where sneaky plays happen (see stealth mechanics).

## Movement & Positioning
**Resolved: the game is fully hex-based — there is no continuous open-field
position.** A squad (the atomic move/select unit — see `04-combat.md`/
`07-data-architecture.md`, including a lone unit, which is just a squad of 1) always
occupies a hex, and moves hex-to-hex:

- **Position**: a squad's authoritative position is `currentHex` plus `edgeProgress`
  (0-1, how far it's advanced from `currentHex` toward the next hex in its `path`).
  `edgeProgress` exists purely to animate movement smoothly between hexes on screen —
  every game-logic check (range, vision, engagement, adjacency) uses `currentHex`
  (an integer hex coordinate), never a sub-hex position.
- **Pathfinding**: standard hex A* over the axial/cube coordinate grid (the same
  hex-math module referenced in Rendering Notes below), edge cost derived from the
  moving unit's Domain and the terrain table above (e.g. Hills cost more for Infantry
  only; Forest/River edges are infinite-cost — impassable — for the relevant Domain
  unless a Road/Bridge is present, or the unit has a matching `terrainOverrides` flag).
  A path is computed once when a move/attack-target order is issued, and only
  recomputed if it becomes blocked mid-move (e.g. a Wall goes up on its route) or a
  new order is issued — not continuously re-planned every tick.
- **Movement rate**: `speed` (on the troop schema) is defined in **hexes per second**.
  Each movement/combat simulation tick (100ms = 0.1s — see `07-data-architecture.md`),
  `edgeProgress` advances by `(speed / terrainCostMultiplier) * tickDuration` — dividing
  by the terrain cost, not multiplying, since `terrainCostMultiplier` is the same
  edge-cost value pathfinding uses (**>1 = slower**, e.g. Hills for Infantry; `1.0` =
  normal terrain). A unit on cost-2 terrain covers ground at half its normal `speed`. On
  reaching 1.0, `currentHex` becomes the next hex in `path`, `path` shifts, and
  `edgeProgress` resets to 0.
  - **Resolved bug fix**: this doc previously read `speed * terrainCostMultiplier *
    tickDuration`, which (a) multiplied cost *up* into speed instead of dividing it
    down, making harder terrain move units faster, and (b) if `speed` were also
    "hexes per tick" rather than "hexes per second," the extra `* tickDuration` would
    double-count and make every unit move 10x too slowly. Fixed by pinning `speed` to
    hexes/second and inverting the terrain-cost term.
- **Stacking**: any number of squads/troops may occupy the same hex — there's no
  per-hex unit cap or collision to resolve. Combat and positioning play out at the
  squad/front level, consistent with the "positioning over micromanagement" pillar,
  not via individual-unit collision.
- **Range/vision/engagement distance**: always the standard hex-distance (cube
  coordinate) formula between two squads' `currentHex`, snapping to the hex a moving
  squad is departing from until it fully arrives at the next one. This keeps every
  distance check a simple integer comparison, consistent with adjacency-based building
  placement elsewhere in the design.
- **Walls block movement and line-of-sight/projectiles** across the specific hex edge
  they occupy — pathfinding treats a walled edge as impassable, and an attack whose
  line from attacker-hex to target-hex crosses a walled edge is blocked, forcing an
  attacker to path around or destroy the wall first. Air-domain units/attacks ignore
  Walls entirely, same as every other terrain rule.

## Rendering Notes (2.5D Cartoon Style)
- **Resolved: Godot, 2D sprite-based, not true 3D** (see `10-tech-stack-and-build-order.md`
  for the full engine decision/rationale). The isometric look is faked with `Sprite2D`
  nodes drawn in isometric projection plus `Node2D`'s Y-sort depth ordering (draw order
  by y-position) — the same approach genre precedents like Clash of Clans / Boom Beach
  use, rather than a real 3D engine (Three.js/Unity/Godot 3D).
- **Resolved: hex tiles are NOT drawn via Godot's `TileMap` node**, including its
  hexagonal tile-shape support. Terrain tiles are plain `Sprite2D` nodes, positioned by
  a standalone hex-math module (axial/cube coordinates, per the standard Red Blob Games
  reference implementation — neighbors, distance, pathfinding) that has zero dependency
  on Godot's scene tree (see `sim/hex/` — implemented and unit-tested headlessly ahead of
  any rendering, per the build order). Reasoning: `TileMap`'s hex mode only helps with
  drawing/culling, not the adjacency/pathfinding/terrain-cost logic the simulation needs
  anyway (that's hand-written regardless, and already exists independent of the engine);
  its natural workflow (paint tiles in the editor / import a tileset) fights against this
  game's procedurally generated map; and the map is small/bounded enough that `TileMap`'s
  main real benefit (off-screen culling) isn't needed. Hex math was never a
  rendering-library problem to begin with.
- Forests/hills/props as 2D sprites layered on top of terrain tiles, not 3D geometry.
- Fog of war as a shader/overlay pass (darkened/desaturated unexplored, grayed "explored
  but not visible").
