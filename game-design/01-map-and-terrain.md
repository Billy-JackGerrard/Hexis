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
  type (Fort Irongrad, Tinder Box, Windy Peaks, Treehouse, Kraken Point, Sky Fortress,
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
| **Forest** | Normal | **Blocked** unless a Road is built through it | N/A | Normal | **Reduced** (own tile halved; also blocks sightlines passing through it) | No (except Treehouse's buildings — forest tiles) |
| **Hills** | Slowed | Normal | N/A | Normal | **Reduced** (own tile halved; also blocks sightlines passing through it) | No (except Windy Peaks' buildings — hill tiles) |
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
- Built by the **Engineer** troop anywhere within its build range, or ordered directly
  from an owner's own **HQ** within its build radius (same radius normal base
  construction uses) — either way the result is the same standalone, public structure;
  only the authorization path differs. The Engineer can additionally build **anywhere**,
  including behind enemy lines (high risk/high reward play — an unescorted Engineer is
  easy to kill), which the HQ-radius path can't reach.
- Once built, these are **public** — any player's troops can use a Road, Bridge, or Dock,
  not just the builder's. This creates natural contested chokepoints.
- **Destroying** a Road/Bridge/Dock: any troop can do it, but only after all
  defenders on/near it have been cleared first.
- **Dock**: standalone structure, allows ship landing only. Can be placed anywhere on
  coast/riverbank, not tied to a base.
- **Bridge material vs. vehicle weight**: a Bridge is Wood or Stone (see
  `06-building-stats-and-defenses.md`'s Wood Material Option section for cost/HP/Fire
  tradeoffs and their separate HQ-level unlocks). A **Heavy** land vehicle (see
  `08-troop-roster.md`'s Light/Heavy split) cannot cross a Wood Bridge at all — too
  light to bear it — and needs a Stone one; Infantry and Light land vehicles cross
  either freely. Naval is unaffected either way (a Bridge doesn't interact with Naval
  at all).

## Fog of War
- **Full fog** until scouted.
- Standard "explored but not currently visible" fade — persistent reveal of terrain
  shape, but current troop positions/base composition require live vision.
- Plains are vision-neutral: purely economic/buildable terrain, with no vision edge
  that would make ambushes (e.g. landmines) unreliable on the tile type most squads
  actually cross. Forests and Hills are both vision-obstructing, and identically so:
  a troop/building standing on either sees at half its normal vision range, and any
  sightline passing through a Forest or Hills hex (even when neither viewer nor
  target is standing in it) loses additional range per hex crossed — both terrains
  block sight, not just (for Forest) the things hiding inside it. Treehouse's own
  buildings are exempt from both Forest penalties (their vision is never reduced by
  Forest, on their own tile or along their sightlines) since they're built into the
  forest rather than merely standing in it; Windy Peaks' own buildings get the same
  exemption from Hills.

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
  (Divide by cost, not multiply — multiplying would make harder terrain move units
  *faster*, the opposite of the intent.)
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
- **Buildings block ground movement, Air and Infantry excepted**: no Land vehicle or
  Naval unit can enter a hex occupied by a standing building (base-attached or
  standalone) — Air ignores it same as it ignores every other terrain rule, and
  Infantry can walk through/over standing buildings, friendly or enemy, same as it
  walks any other terrain (Naval never actually encounters this in practice, since
  buildings only stand on buildable land terrain). Two exceptions for Land vehicles:
  **Road/Bridge** hexes stay traversable (they're infrastructure meant to be driven
  over, not obstacles), and a **ruin** (a destroyed, not-yet-rebuilt building — see
  `06-building-stats-and-defenses.md`'s Destruction & Ruins) no longer blocks either,
  since nothing is actually standing there anymore.
- **Standing buildings block line of sight for single-target attacks, same as a
  Wall**: an attack whose straight line from attacker-hex to target-hex passes through
  a hex holding another standing building (any owner) is blocked — a House parked in
  front of an HQ protects it from being shot at until the House falls (a ruin no
  longer blocks, same as the movement rule above). Troops never block each other's
  LOS this way, only buildings do (e.g. a multi-turret Tower can still independently
  clear several enemy squads lined up in front of it). Air-domain attackers ignore
  this entirely, same as every other terrain/LOS rule, and so does any attacker with a
  `minRange` above 0 (an indirect-fire piece — Earthshaker is the first user — arcs its
  shot in over intervening obstacles). This is separate from `lineAttack`'s own
  building-stopping rule (see `04-combat.md`), which is about the beam's own path
  once it's already firing, not whether the attacker can fire at all.

## Rendering Notes
- **Superseded: terrain is real 3D, not 2D sprite-based.** The original "2.5D
  Cartoon Style" plan below (Sprite2D + Y-sort) was replaced once a 3D hex asset
  pack (`assets/tiles/`, GLTF meshes) was adopted: terrain renders via
  `client/terrain/terrain_view_3d.gd`, a `Node3D` populated with real meshes
  and instanced into a `SubViewport`/`Camera3D` layer, composited behind the
  rest of the client's existing 2D views (`base_view.gd`/`squad_view.gd`/HUD,
  all untouched — they stay flat-color 2D placeholders drawn on top of the 3D
  layer). Bases/squads/projectiles are not part of this change; they remain
  the "faked 2.5D via Sprite2D + Y-sort" approach described below whenever
  their own art lands.
- Hex math (`sim/hex/`) is exactly as unaffected by this as the paragraph
  below always intended it to be — `HexView.axial_to_pixel`'s pixel-space
  output is what both the old 2D board and the new 3D terrain layer derive
  their placement from (the 3D layer applies one additional fixed scale +
  rotation calibration on top, documented in
  `client/terrain/terrain_tile_resolver.gd`'s header).
- **River/Road tile selection**: both are directional mesh sets (river:
  `hex_river_A`-`L` + 2 crossing variants; road: `hex_road_A`-`M`) — which
  variant + rotation renders at a given hex is resolved live from
  `HexGrid.river_connection_mask`/`road_connection_mask` (which of a hex's 6
  neighbors also have River terrain / Road infrastructure — computed fresh
  from grid state every time, never cached, so placing a Road immediately
  reads correctly from every affected neighbor's side too) via
  `client/terrain/terrain_tile_resolver.gd`. Canonical per-mesh masks are
  checked into `client/terrain/terrain_tile_defs.gd`, derived by
  `tools/analyze_terrain_meshes.gd` (a color-based analysis of each mesh's
  own geometry — re-run that tool by hand if the asset pack is ever
  replaced).
- **Base terrain**: Plains/Ocean map 1:1 to this pack's `hex_grass`/
  `hex_water`. Forest/Hills currently also render as flat `hex_grass` — this
  pack has no dedicated ground mesh for either (Forest/Hills are meant to be
  conveyed via `decoration/nature/` props scattered on top of grass, not a
  differently-colored tile), and that prop-scattering pass hasn't been done
  yet. A Bridge (on a River hex) renders as a single fixed, non-directional
  mesh regardless of the river's own shape there — a known cosmetic gap on a
  river corner/crossing hex specifically, not yet solved.
- **Resolved: hex tiles are NOT drawn via Godot's `TileMap` node**, including its
  hexagonal tile-shape support. Terrain tiles are plain nodes, positioned by
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
- Fog of war as a shader/overlay pass (darkened/desaturated unexplored, grayed "explored
  but not visible") — a 2D concern (`client/fog_of_war.gd`), unaffected by the
  terrain layer's move to 3D since it composites over everything regardless.

### Original 2.5D plan (superseded for terrain — see above; still the plan for bases/squads/projectiles)
- **Godot, 2D sprite-based** (see `10-tech-stack-and-build-order.md` for the engine
  decision/rationale). The isometric look is faked with `Sprite2D` nodes drawn in
  isometric projection plus `Node2D`'s Y-sort depth ordering (draw order by
  y-position) — the same approach genre precedents like Clash of Clans / Boom Beach
  use, rather than a real 3D engine.
- Forests/hills/props as 2D sprites layered on top of terrain tiles, not 3D geometry
  — this line no longer applies to terrain itself (see above) but still describes
  the plan for whatever isn't terrain.
