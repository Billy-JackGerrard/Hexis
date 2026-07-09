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
   rendering exists. **Complete.** One line per slice, in build order:
   - [x] Godot project scaffold (`project.godot`).
   - [x] Hex-grid coordinate math (`sim/hex/hex_coord.gd`).
   - [x] Terrain/domain movement-cost table (`sim/hex/terrain_types.gd`).
   - [x] Hex grid + A* pathfinding, wall-edge blocking (`sim/hex/hex_grid.gd`).
   - [x] Road/Bridge infrastructure clearing Forest/River blocks (`sim/hex/`).
   - [x] Headless test suite (`tests/test_hex.gd`).
   - [x] Resource ticking — per-player pools, production/upkeep netting,
     deficit deaths (`sim/economy/`, `tests/test_resources.gd`).
   - [x] Troop/Squad/Regiment runtime state + squad/commander caps
     (`sim/units/`, `sim/data/data_loader.gd`, `tests/test_units.gd`).
   - [x] Per-building troop production queue, FIFO + deploy/pause rules
     (`sim/instances/production_queue.gd`, `sim/units/production_manager.gd`).
   - [x] Combat resolution — targeting, damage math, splash, buildings as
     combatants (`sim/units/combat_*.gd`, `tests/test_combat.gd`).
   - [x] Squad movement/pathing resolver + attack-move chase
     (`sim/units/movement_resolver.gd`, `tests/test_movement.gd`).
   - [x] Vision/fog-of-war — per-player visible/explored hex sets
     (`sim/vision/`, `tests/test_vision.gd`).
   - [x] Terrain combat bonuses (hill defender) + stealth/detection
     (Forest ambush, Tower/Radar Array/Landmine) (`tests/test_detection.gd`).
   - [x] Standalone building placement (Tower, Landmine, Road, Bridge, Dock)
     + Naval disembark-gating (`sim/instances/building_placement.gd`).
   - [x] Regiment lock-step movement + Commander-death disband
     (`sim/units/movement_resolver.gd`, `tests/test_movement.gd`).
   - [x] Status effects (freeze/stun/knockback/emp) + proximity auras
     (`sim/units/status_effect_system.gd`, `sim/units/aura_system.gd`).
   - [x] Cargo — board/unload, carrier capacity/tag gating, position mirroring
     (`sim/units/cargo_system.gd`, `tests/test_cargo.gd`).
   - [x] HQ capture-flip, building ruin state, out-of-combat HP regen
     (`sim/units/combat_resolver.gd`, `sim/units/building_regen_system.gd`).
   - [x] Base/building placement rules + Walls (edge-keyed, LOS-blocking) +
     Bridge-foothold adjacency exception (`sim/instances/building_placement.gd`).
   - [x] Top-level tick orchestrator (`sim/sim_orchestrator.gd`,
     `sim/match_state.gd`), command/order-issuing layer
     (`sim/command/command_processor.gd`), Wall LOS raycasting
     (`HexCoord.line()`, `HexGrid.is_line_blocked()`), and resource-cost
     enforcement on builds/training.
   - [x] Aircraft fuel rework + Hangar docking — airborne Air squads always
     pay Fuel; docking (carrier cargo or a Hangar) is the only way to stop
     the drain and hide from vision/detection (`SquadInstance.is_docked()`,
     `sim/movement/cargo_system.gd`).
   - [x] Cloudreach base, Covert Airfield + Hangar wired into
     `buildableBuildings`, and four new air troops (Cargocopter,
     Kleptocopter, Repair Drone, Shadowcopter) — closes the fuel-rework
     item's deferred "nothing can dock yet" gap.
   - [x] Procedural map/terrain generation — hexagon landmass + strategic
     ocean fringe, Forest/Hill biome clusters, rivers, and Capital/Unique
     base siting with spacing/terrain/uniqueness constraints
     (`sim/worldgen/`, `sim/map_generator.gd`, `tests/test_map_generation.gd`).
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
