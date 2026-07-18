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

**Forest never generates small.** It rolls medium or large only, and any patch that
still finishes under `Tuning.MIN_FOREST_PATCH_SIZE` — because its growth ran out of room
against the coast, the map edge or an existing patch, or because a river later split it
in two — is reverted to Plains. A one-to-three-hex wood reads as litter rather than
terrain, and Forest's design role (blocking Land vehicles, concealing squads) needs
enough contiguous area to be worth pathing around at all. The coverage budget is
unchanged, so a higher size floor yields **fewer** forests, not more forest. Hills
deliberately keeps its small bucket: a lone hill is a legible landmark now that
elevation makes it physically stand up, where a lone tree isn't.

| Terrain | Infantry | Land Vehicles | Naval | Air | Vision | Buildable? |
|---|---|---|---|---|---|---|
| **Plains** | Normal | Normal | N/A | Normal | Normal | Yes (only buildable terrain, and majority of tiles) |
| **Forest** | Normal | **Blocked** unless a Road is built through it | N/A | Normal | **Reduced** (own tile halved; also blocks sightlines passing through it) | No (except Treehouse's buildings — forest tiles) |
| **Hills** | Slowed | Normal | N/A | Normal | **Extended** (see Elevation — height grants bonus range and clears sightlines over lower ground) | No (except Windy Peaks' buildings — hill tiles) |
| **River** | **Blocked** unless a Bridge is built | **Blocked** unless a Bridge is built | Fully passable | Normal | Normal | No |
| **Ocean** | **Blocked** | **Blocked** | Fully passable | Normal | Normal | No |

- **Resolved: "Coast" is not a distinct terrain type** — it was previously listed as
  its own row, but it's really just Plains at the edge of the map, directly adjacent to
  an Ocean or River tile. There's no separate shoreline tile type to generate or store.
  (Coastal land tiles *render* a sand beach, resolved from an Ocean-neighbour mask —
  purely a visual treatment of Plains/Forest, not a terrain type. Raised coastal tiles
  are skipped: those are headlands dropping into the sea, not beaches.)

### Elevation (slopes and cliffs)
Height is a **separate axis from terrain type**, stored per hex on `HexGrid`
(`sim/hex/hex_grid.gd`) and generated as the last worldgen phase
(`TerrainGenerator.generate_elevation`). Only Hills is ever raised; everything else sits
at lowland 0. Rivers run *before* elevation, so a channel carved through a hill range
stays at lowland height — water flows down, and the channel never has to climb.

Each contiguous Hills patch becomes a **rim** ring (any Hills hex touching non-Hills) at
level 1 and an interior **plateau** at level 2, so walking from lowland into the middle
of a range is two single-level climbs. A share of rim hexes is then promoted to plateau
height, which turns the edge they share with the lowland outside into a two-level drop.

What matters for play is the *difference* between adjacent hexes, not either one's own
height:

| Step | Effect on Infantry / Land | Air / Naval |
|---|---|---|
| Level, or downhill | Terrain cost only — descending is never *cheaper* than flat ground | Unaffected |
| **Up one level (slope)** | Terrain cost **plus** a flat ascent penalty — hills take longer to climb | Unaffected |
| **Up two levels (cliff)** | **Impassable.** No Road, Bridge or `terrainOverrides` flag clears it | Unaffected |

Cliffs are **directional**: the same edge is legal downhill. So a plateau can be sheer
on some sides and ramped on others — ground troops must walk around and come up from a
different direction, which is exactly the tactical shape cliffs exist to create, and it
makes Air genuinely more useful. Worldgen guarantees this is never a dead end: a repair
pass walks out from lowland and demotes anything it could not reach, so **every raised
hex is always climbable from somewhere**. That invariant is asserted per-seed in
`tests/test_map_generation.gd`.

Ascent cost is only ever *added*, never discounted below flat-ground cost — `find_path`'s
heuristic is plain hex distance and would stop being admissible if any step could cost
less than 1.0.
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
  actually cross. **Forest** is vision-obstructing: a troop/building standing on one
  sees at half its normal vision range, and any sightline passing through a Forest hex
  (even when neither viewer nor target is standing in it) loses additional range per
  hex crossed — the terrain blocks sight, not just the things hiding inside it.
  Treehouse's own buildings are exempt from both Forest penalties (their vision is
  never reduced by Forest, on their own tile or along their sightlines) since they're
  built into the forest rather than merely standing in it.
- **Hills no longer carry a vision penalty.** They previously did — halved own-tile
  vision plus a flat per-hex sightline penalty, identical to Forest — on the reasoning
  that "elevation blocks line of sight, it doesn't extend it". That was a workaround
  for there being no height axis to reason with; now that Hills have real elevation
  (below), the geometry does the job properly and in both directions: standing high
  grants bonus range and lets your sightline pass over lower ground, while a ridge you
  are looking *up* at silhouettes against your sightline and hides whatever is behind
  it. The same ridge now helps whoever holds it and hinders whoever doesn't, which the
  old flat penalty could not express (it punished a viewer standing on the ridge
  exactly as hard as one in the valley below). Windy Peaks' Hills vision exemption is
  consequently obsolete — its buildings simply get the elevation bonus instead.

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
  unless a Road/Bridge is present, or the unit has a matching `terrainOverrides` flag),
  **plus the elevation difference across the edge** (see Elevation above — an uphill
  step costs extra, a two-level step is impassable in that direction only). This is the
  one genuinely per-edge term: everything else in the cost depends only on the
  destination hex.
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
  added directly to the scene. No `SubViewport` is involved — the root Window
  viewport renders its `World3D` (the `Camera3D` in `main.tscn` + these meshes)
  first, then the 2D canvas (`squad_view.gd`/`projectile_view.gd`/HUD — still
  flat-color 2D placeholders — plus whatever `base_view.gd` still draws
  itself, see below) composites on top automatically. A `Node3D` under the
  `Node2D` scene root still renders into that shared `World3D`; only the
  `Camera3D`/light/`WorldEnvironment` matter, not the parent type. The
  `Camera3D` is orthographic and pitched a fixed `CAMERA_TILT_DEGREES` (18°,
  via `rotate_object_local` on the base top-down transform, applied once in
  `_start_game`) off pure top-down, so buildings (real 3D now, see below)
  show their fronts instead of just rooftops. A pitched ortho camera isn't
  a free change, though: it renders the ground plane as an *affine* of the
  flat top-down mapping — X scale unchanged, world-Z (screen-Y) scale
  foreshortened by exactly `cos(tilt)`, plus a screen-center shift (an exact
  fit, verified against `Camera3D.unproject_position` in
  `scratchpad/tilt_test3.gd`, not checked in). The 3D ortho camera CANNOT
  self-correct this: its `size` scales both screen axes by one factor, so
  shrinking it to undo the Z foreshortening equally shrinks X, leaving every
  flat 2D element (fog, hex grid, labels, selectors, build-menu radius)
  drifting horizontally more and more toward screen edges — exactly the
  "fog/labels are off" bug (a `size *= cos` attempt did this: it zeroed the
  Z error but grew an X error with distance). The cos foreshortening has to
  live where it can be per-axis: on the flat layer's own `Camera2D` (its
  `zoom` is a `Vector2`). So `main.gd`'s `_sync_camera_3d`, every frame:
  keeps `Camera3D.size` on the plain untilted formula (no cos) so its X
  scale matches `Camera2D`'s; pulls `Camera3D.position.z` back by
  `position.y * tan(tilt)` so the tilted forward ray centers on the same
  ground pixel `Camera2D` does; and sets `Camera2D.zoom.y = zoom.x *
  cos(tilt)` to compress the whole flat overlay vertically to match the
  tilted ground. `CameraController` does all its pan/zoom math on `zoom.x`
  and resets `zoom` uniformly on scroll, so re-applying `zoom.y` here every
  frame is safe (self-heals the frame after a scroll). Real height still
  parallax-leans under the tilt — a tall building's roof leans off its
  footprint — but that's intentional, it's the whole reason to tilt; only
  ground-level (y=0) content is guaranteed locked, not a mesh's full
  silhouette. **Elevated terrain is an accepted instance of that**: a raised
  hex's ground is no longer at y=0, so the flat overlay (grid outlines,
  selection rings) leans off it exactly the way a tall building's roof does.
  That's the deliberate trade for hills reading as real height —
  `TerrainView3D.WORLD_UNITS_PER_ELEVATION` can't grow without bound for this
  reason. Hex click-targeting needed its own fix on top of the camera
  compensation: `HexView.pixel_to_axial(get_global_mouse_position())`
  assumed pure top-down, so `input_controller.gd`'s `_reprojected_hex`
  ray-casts the actual screen cursor through `Camera3D` and intersects the
  ground, for every call site that resolves "which hex was clicked"
  (move/attack/build orders, own-building selection, hover). It intersects
  *elevated* ground correctly by iterating: a single y=0 intersection selects
  a hex "behind" every raised tile under the tilt, so it re-intersects at the
  height of the hex it just landed on until the answer stops changing —
  cheaper and simpler than putting physics colliders on every terrain tile.
  Squad/wall hit-testing deliberately still uses the flat 2D position
  directly — those stay 2D-rendered, unaffected by the tilt regardless.
  Squads/projectiles/HUD are still the "faked 2.5D via Sprite2D + Y-sort"
  approach described below whenever their own art lands — a deliberately
  separate, not-yet-started follow-up.
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
  `hex_water`. Ocean/River plates are seated `WATER_SURFACE_DROP` below
  lowland ground: the pack already recesses its water surface slightly, but
  not enough to read as water sitting *in* the land, so the coastline looked
  like a colour change rather than an edge. The extra drop turns shorelines
  and river banks into visible lips you look down over, and gives the beach
  tiles' sand shelf something to slope into. Purely visual — `HexGrid`
  elevation for water stays 0, so no movement cost, cliff check or sightline
  is affected. Kept small deliberately: land plates only model their own top
  1.0 unit, so a deeper drop would let you see under the coast at grazing
  angles.
- **Ground surface**: every land plate is rendered with
  `terrain/ground_detail.gdshader` rather than its imported material. The
  pack's atlas is a flat colour-swatch sheet — each tile is one uniform fill
  with no grain whatsoever — which left Plains, the majority of the board, as
  a large area of dead colour. The shader samples that same atlas (so UVs, the
  seasonal variant, and each tile's own painted details like river channels
  and beach sand all still work) and modulates it with two octaves of value
  noise evaluated in **world** space. World space matters: every hex shares
  one small atlas region, so UV-space noise would stamp an identical pattern
  on every tile and read as an obvious repeat, whereas world space makes the
  grain continuous across tile boundaries. Its strengths are much higher than
  "subtle detail" would suggest because the art is flat-shaded and fully
  saturated — there is no shading gradient for a gentle modulation to ride on,
  and at ~10% the variation was measurably present but visually invisible.
  On top of that, a minority of hexes swap to one of the pack's seasonal atlas
  recolors (`hexagons_medieval_Fall.png`/`_Summer.png` — same UV layout,
  genuinely different colour grading, not a multiply-tint), chosen from the
  tails of one low-frequency noise field so they form contiguous regions
  rather than scattered single hexes; Winter's atlas is excluded (a literal
  snow-white recolor, would read as random snow patches). The two compose:
  broad seasonal regions, with per-surface grain inside them.
- **Biome decoration**: Forest/Hills get a `decoration/nature/` cluster mesh on
  top of the ground plate — Hills picks among 6 variants (`hills_{A,B,C}` +
  their `_trees` siblings) purely per-hex, swapping to the larger `mountain_*`
  set on plateau-height tiles. Forest separates its two axes: **species**
  (`trees_A_*` vs `trees_B_*`) is picked once per contiguous patch, from that
  patch's canonical member hex, because a real wood is one kind of tree and
  mixing species hex-by-hex made a single stand read as two overlapping
  forests; **density** tiers by depth into the patch
  (`TerrainView3D._compute_forest_depth`, a multi-source BFS run once in
  `setup()` — edge hexes get sparse `*_large`, one-deep get `*_medium`,
  two-or-more-deep get dense `*_small`), so a forest
  reads as one coherent stand thickening toward its center instead of
  random-looking large/small trees sitting next to each other. All of this
  per-hex picking goes through `RenderUtil.pick2d`/`roll2d` (a proper integer
  spatial hash keyed on hex `(q, r)` + a decision-specific salt), not
  Godot's generic string `hash()` — the naive string-keyed version visibly
  clustered same-choice patches across neighboring hexes, since a generic
  hash isn't guaranteed to fully decorrelate a mostly-identical formatted
  key. A Bridge (on a River hex) renders as a single fixed, non-directional
  mesh regardless of the river's own shape there — a known cosmetic gap on a
  river corner/crossing hex specifically, not yet solved. Decoration meshes
  get NO per-instance tilt correction: they are real 3D objects placed at
  their hex center on the real 3D ground tile, so the camera renders each
  cluster over its own tile automatically, exactly as it does buildings —
  a tall tree's crown reading higher on screen is honest perspective. (An
  earlier attempt to "cancel" that with a `height * tan(tilt)` world-Z
  offset was wrong: it physically shoved decoration off its own tile onto
  the neighbor, which is what made Forest hexes look bare and Plains hexes
  look forested — the offset was removed.)
- **Sparse decoration scatter**: Ocean hexes roll a small per-hex chance
  (`RenderUtil.roll2d`, ~12%) for one prop from `decoration/nature/`+
  `decoration/props/` — waterlilies, waterplants, an occasional boat.
  **Plains rolls nothing.** It briefly carried a one-to-three-prop scatter to
  fix "the majority terrain is a bare plate", and that genuinely was the
  problem, but props on most of the board read as clutter: they competed with
  the things a player has to read quickly (squads, buildings, selection rings,
  order feedback) and made real obstacles harder to pick out. The boredom is a
  *surface* problem and is now solved on the surface — see the ground detail
  shader below — leaving the board itself clear. A flowing River hex
  rolls the same way (~20%) for shore plants along its edge; a River hex
  that's a dead end instead — `river_connection_mask` popcount ≤ 1, a
  source/mouth this pack has no dedicated spring/waterfall mesh for, so the
  channel just stops flat against the hex edge — always (not rolled) gets 2
  shore props, dressing the abrupt cut up as a marshy pond instead. None of
  this is true geometric bank blending: this pack has no land/water
  transition mesh (`hex_transition.gltf`'s blend behavior is unconfirmed and
  unused), so it's a cheap visual mitigation, not a fix. On top of the rolled
  decor, **every river-to-land edge now gets banks unconditionally** — shore
  props laid along the seam itself rather than scattered on the hex, so the
  hard line where the channel meets grass reads as a silted, reedy edge. Not
  rolled against a chance: banks appearing on only some edges read as a bug
  rather than as variety. **`tiles/coast/` is no longer out of scope** — those
  meshes now render beaches on Ocean-adjacent lowland land, resolved through
  the same `TerrainTileResolver` as river/road tiles against a new
  `TerrainTileDefs.COAST_MASKS` (derived by `tools/analyze_terrain_meshes.gd`,
  which now analyses the coast set too). That set is sparse — 2-, 3- and
  6-edge shapes only — so a hex with a single Ocean neighbour falls back to
  the resolver's superset match and renders one extra sand edge abutting land;
  cheap, and it never hides a real shoreline. A river's actual
  *path* being mechanically straight in places is a separate, sim-side
  worldgen concern (`sim/worldgen/`, not this rendering layer) — noted here
  as a known follow-up, not yet addressed.
- **Buildings are real 3D too**: `client/buildings/building_view_3d.gd`
  (`BuildingView3D`, poll-based Node3D renderer, same pattern as
  `TerrainView3D`) instances a mesh from `assets/buildings/{blue,green,red,
  yellow,neutral}/` for every building_type that has one — the mapping is a
  large judgment call, checked into `client/buildings/building_mesh_defs.gd`
  since this pack has far fewer distinct building models than this game has
  building types (most entries reuse the closest thematic mesh, several
  tinted via `RenderUtil.apply_tint`). Wall (needs its own corner/straight
  connection-mask resolver, not built yet) and Landmine (stealthed — a
  visible 3D prop would leak a hidden mine past its detection gate) stay 2D,
  drawn by `base_view.gd` as before; Road/Bridge are already 3D via
  `TerrainView3D`'s own infrastructure poll. A building's level shows up
  visually two ways: a small universal scale bump on every mesh, and — per
  this doc's Harbour/Farm/Mine visual spec (`02-bases-and-buildings.md`) —
  extra decoration props scattered around it as it levels up (Harbour's own
  boat count uses that doc's exact `count == level` spec instead). Dock/
  Harbour/Port/Shipyard (all water-adjacent by placement rule) offset their
  mesh partway toward their water neighbor hex and face it, reading as a
  pier extending into the water without needing new pier geometry.
  Owner-color meshes only exist for 4 colors (`blue/green/red/yellow`);
  `NetManager.MAX_PLAYERS`/`main.gd`'s `OWNER_COLOR_PALETTE` are temporarily
  capped to 4 to match. `"neutral"`-owned buildings (unconquered Unique
  bases, barbarian outposts) don't have their own building roster in this
  pack's actual `neutral/` folder either (that only has bridges/walls/
  fences/a couple of generic props) — they borrow one of the 4 real color
  folders instead, picked deterministically per `building_type` so every
  barbarian Tower matches, desaturated via `BuildingMeshDefs.NEUTRAL_TINT`
  so it still reads as unclaimed. Every ruined building — any type,
  captured or not — renders as the same `neutral/building_destroyed.gltf`
  rubble mesh instead of its usual one; what it used to be stops mattering
  once it's destroyed. `BuildingView3D`'s per-building signature includes
  owner_id specifically so an HQ capture-flip (which changes `base.
  owner_id`, not the `BuildingInstance` itself) still triggers every one of
  that base's meshes to rebuild in the new owner's color.
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
