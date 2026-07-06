# Tech Stack & Build Order

## Engine
**Godot** (GDScript). Chosen over Phaser: this project's UI surface is heavy
(per-base build menus, per-building production queues, resource HUD, minimap,
fog-of-war overlay — see `09-ui-and-controls.md`), and Godot's built-in `Control`
node UI toolkit covers that directly instead of hand-rolling an HTML/CSS overlay.
Godot also ships a high-level multiplayer API (ENet), which matters since
`07-data-architecture.md` already targets a simulation/rendering split for
multiplayer-readiness. No Tilemap plugin — hex grid is custom axial/cube-coordinate
math, not a built-in tile layer.

## Build Order
Backend/simulation before frontend/UI implementation — not before UI *design*.
Wireframing and mockups don't depend on the engine and can happen anytime;
writing real UI code does, and it also needs actual game state to bind to.

1. **Headless simulation core** — plain GDScript classes with no scene or
   rendering dependency, validated via tests/console output before any
   rendering exists.
   - [x] Godot project scaffold (`project.godot`) — no scenes yet, just enough
     for `godot --headless --script` to resolve `res://` and `class_name` globals.
   - [x] Hex-grid coordinate utility (`sim/hex/hex_coord.gd`) — axial/cube
     coordinate math: neighbors, distance, range queries.
   - [x] Terrain/domain movement-cost table (`sim/hex/terrain_types.gd`), per
     `01-map-and-terrain.md`'s terrain table.
   - [x] Hex grid + A* pathfinding, wall-edge blocking (`sim/hex/hex_grid.gd`).
   - [x] Road/Bridge infrastructure — hex-keyed (not edge-keyed like Walls),
     clears Forest's Land block / River's Infantry+Land block per
     `01-map-and-terrain.md` (`Terrain.Infrastructure`, `Terrain.effective_cost()`
     in `sim/hex/terrain_types.gd`; `HexGrid.set_infrastructure()`/
     `get_infrastructure()` in `sim/hex/hex_grid.gd`). Dock (disembark-location
     gating) intentionally deferred to the Building/placement work below —
     it doesn't affect movement cost, just where Naval can land.
   - [x] Headless test suite (`tests/test_hex.gd`), run via
     `godot --headless --script res://tests/test_hex.gd` — 40 checks passing.
   - [x] Resource ticking (`sim/economy/resource_pool.gd`,
     `sim/economy/resource_tick.gd`, `sim/economy/resource_modifier.gd`) —
     per-player pool, production/upkeep netting, deficit detection, and
     BaseDef `resourceModifiers` (e.g. Capital's Oil Rig -50%). `ResourceTick`
     only nets whatever `production`/`upkeep` dicts the caller hands it —
     troop Food/Fuel upkeep isn't sourced or wired in anywhere yet, and
     squad-level troop death under deficit isn't wired up either, since
     squads don't exist until the next item.
   - [x] Troop/Squad/Regiment runtime state (`sim/units/troop_instance.gd`,
     `sim/units/squad_instance.gd`, `sim/units/regiment_instance.gd`,
     `sim/units/squad_manager.gd`), backed by a generic `data/*.json` loader
     (`sim/data/data_loader.gd`) per `07-data-architecture.md`'s schemas.
     Ahead of full base/building placement, a minimal `BaseInstance`/
     `BuildingInstance` shell (`sim/instances/`) tracks just `hqLevel` and
     Command Centre levels, enough for `sim/units/squad_cap.gd` to compute
     real `maxSquads`/`maxCommanders` caps rather than stubbing them —
     `tests/test_units.gd`, 25 checks passing.
   - [ ] Combat resolution (auto-attack nearest in range, damage modifiers,
     splash — see `04-combat.md`).
   - [ ] Base/building placement rules, hex-adjacency validation (see
     `02-bases-and-buildings.md`).
2. **Godot rendering scaffold** — a minimal scene rendering one base,
   click-to-move wired to the sim core.
   - [ ] Not started.
3. **UI layer** — `Control`-node HUD (resources, build menu, minimap) bound to
   sim state via signals.
   - [ ] Not started.

## Art
Placeholder art until the core loop (movement, combat resolution, base capture)
is validated as fun — final art is expensive to redo if mechanics change, so
don't invest in it early.

- **Hex tiles/terrain**: flat-color or simple-gradient hexes per terrain type
  (Plains/Forest/Hill/etc.) — `Polygon2D` is enough to playtest fog-of-war and
  adjacency rules, no textures needed.
- **Troops/buildings**: colored geometric shapes or free CC0 asset packs
  (itch.io has many "top-down strategy" packs), one stand-in per troop/building
  type, tinted by owner.
- **UI**: Godot's default theme; no custom skin yet.
- **Asset naming/folders**: structure placeholder sprites so real art is a
  drop-in swap later — one file per troop/building `id` (matching the `data/`
  JSON keys), e.g. `assets/sprites/troops/<id>.png`,
  `assets/sprites/buildings/<id>.png`, referenced by id rather than hardcoded
  paths in scenes, so swapping the file later requires no code changes.

Commission vs. asset-pack vs. draw-it-yourself for the final "cartoon-style
2.5D" look (see `00-overview.md`) is a bigger scope/cost decision to make once
the loop is validated, not now.
