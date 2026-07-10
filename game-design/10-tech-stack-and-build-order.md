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
   - [x] Ballistic projectile travel time + positional dodge for every
     combat troop and Defensive building, via `projectileSpeed` (a shot aims
     at a fixed hex, not a tracked target, so a repositioned target takes no
     damage) — every troop/building def with a nonzero attackSpeed and a
     non-empty canTarget now sets it, tuned per weapon archetype (fast
     small-arms high, slow siege/artillery low); non-combatants (Engineer,
     transports, etc.) never fire so it's a no-op for them, and Tank
     Obliterator's `lineAttack` beam stays instant on purpose (see below)
     (`sim/combat/projectile_instance.gd`, `sim/combat/projectile_system.gd`,
     `tests/test_projectiles.gd`).
   - [x] Traveling beam projectiles — a `lineAttack` unit that ALSO carries
     `projectileSpeed` (Wind Spire) sweeps its beam hex-by-hex over time
     instead of resolving the whole line in one instant tick, rolling
     statusEffectOnHit independently per victim as it passes each one
     (`CombatResolver._apply_line_attack`/`_resolve_beam_hex`,
     `ProjectileSystem._advance_beam`). A `lineAttack` unit with no
     `projectileSpeed` (Tank Obliterator) is unaffected — still fully
     instant, an instantaneous rail-gun beam having no obvious travel time
     to model.
2. **Godot rendering scaffold** — a minimal scene rendering one base,
   click-to-move wired to the sim core. New `client/` folder, sibling to
   `sim/`, never the reverse — `sim/` stays engine/scene-free per
   `07-data-architecture.md` section 8.
   - [x] `client/main.gd`/`main.tscn` — builds a demo `MatchState` (reusing
     the construction pattern already proven in
     `tests/test_sim_orchestrator.gd`) and drives
     `SimOrchestrator.resolve_tick()` every frame.
   - [x] `client/hex_view.gd` — axial↔pixel projection (flat-top). The one
     genuinely new piece of math this slice needs:
     `sim/hex/hex_coord.gd` explicitly leaves orientation as "a rendering
     concern, not decided here."
   - [x] `client/board.gd` — terrain as flat-color hex fills (`Terrain.Type`
     → color, drawn via `_draw()` rather than one `Polygon2D` node per hex),
     no `TileMap`, per the Rendering Notes in `01-map-and-terrain.md`.
   - [x] `client/base_view.gd` / `client/squad_view.gd` — one base's
     buildings and a squad of Riflemen as placeholder shapes, owner-tinted,
     position read from sim state each frame (`squad_view.gd` interpolates
     `current_hex` → `path[0]` over `edge_progress`, rendering-only per
     section 7/8's "counting up between ticks is visual only").
   - [x] `client/input_controller.gd` — click → hex, single-squad select,
     click-to-move calls `CommandProcessor.move_squad()` (already fully
     validated — no new sim logic needed).
   - [x] Fog-of-war overlay (`client/fog_of_war.gd`) — reads `state.visions`
     (already computed every tick by `VisionSystem.resolve_tick`), draws an
     opaque hex over unexplored tiles and a dimmed one over explored-but-not-
     currently-visible tiles, read-only like every other `client/` node.
   - [x] Multiple bases / full procedural map — the demo scene now calls
     `MapGenerator.generate()` for a 2-player map instead of a hand-built
     flat grid, rendering every Capital/Unique base it sites
     (`client/main.gd`).
   - [x] Camera pan/zoom (`client/camera_controller.gd`) — right-mouse-drag
     pans, scroll wheel zooms; left button stays exclusively
     `InputController`'s.
   - [x] Drag-select + control groups + regiment visuals
     (`client/input_controller.gd`, `client/squad_view.gd`) — left-drag a
     box to multi-select, shift-click/-drag to add, number keys 1-9 recall a
     control group (Ctrl+number assigns one); `SquadView` draws a ring
     around each Commander and a line to each of its escorts straight off
     `state.regiments`.
   - **Still deferred to a later rendering pass** (known and postponed, not
     forgotten): real art. Build menu, production queue UI, resource HUD,
     and minimap are item 3 below, not this slice.
3. **UI layer** — `Control`-node HUD (resources, build menu, minimap) bound to
   sim state via signals.
   - [x] `client/hud/hud_layer.gd` — screen-space `CanvasLayer` scaffold,
     added last in `main.gd` so every panel draws over the world-space
     views beneath it; every panel polls `_process` like the rest of
     `client/` (no sim-side signals exist to bind to — real Godot signals
     are used for HUD widget events instead, e.g. `Button.pressed`).
   - [x] `client/hud/resource_bar.gd` — Food/Steel/Fuel/Stone/Wood, a
     deficit resource renders in red (`ResourcePool.is_deficit`).
   - [x] Click-precedence rework in `client/input_controller.gd` — an enemy
     target under the cursor now issues `CommandProcessor.attack_target`
     instead of a move (the focus-fire/structure-targeting requirement,
     including Wall edges), a friendly base building selects that base, and
     a lightweight on-screen indicator distinguishes hovering a valid enemy
     troop/structure from open ground.
   - [x] `client/hud/base_panel.gd` — per-base population indicator
     (`Population.population_used/cap`).
   - [x] `client/hud/build_menu.gd` + `client/build_preview.gd` — per-base
     building list (`base_def.buildableBuildings`, already the correct
     Capital-superset-vs-Unique-fixed-list per base JSON, no filtering
     needed), placement-preview hex/edge highlighting
     (`BuildingPlacement.can_place`/`can_place_wall`), commits via
     `CommandProcessor.place_building`/`place_wall`.
   - [x] `client/hud/production_panel.gd` — per-building FIFO queue display
     + paused banner, unlocked-troop buttons
     (`CommandProcessor.enqueue_production`) — display-only for
     pause/resume, which is fully automatic per `07-data-architecture.md`.
   - [x] `client/hud/alerts_panel.gd` — under-attack
     (`CombatStateSystem.is_hex_in_combat`), production-paused
     (`ProductionQueue.paused`), and resource-deficit rows, one per base per
     type, clicking recenters the camera.
   - [x] `client/hud/minimap.gd` — terrain/base/squad overview + current
     viewport rectangle, click/drag recenters the camera.

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
