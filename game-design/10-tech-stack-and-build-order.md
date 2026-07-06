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
   - [x] Per-building troop production queue (`sim/instances/production_queue.gd`,
     `sim/units/production_manager.gd`) per `07-data-architecture.md` section 3b:
     one `ProductionQueue` per Production building keyed by building_id, FIFO
     `enqueue`/`advance` (accumulator countdown, not a global clock), and
     `pump()`'s deploy rules — a completed troop joins an in-range same-type
     squad with room (bypassing the cap), else forms a new squad, else pauses
     the queue at the squad cap (or Commander cap for a Command Centre) holding
     the completed-but-undeployed entry until capacity frees. Extends
     `tests/test_units.gd` (now covers ProductionQueue/ProductionManager).
   - [x] Combat resolution (auto-attack nearest in range, damage modifiers,
     splash — see `04-combat.md`): `CombatResolver.resolve_tick()`
     (`sim/units/combat_resolver.gd`) advances a per-squad / per-Defensive-building
     attack-speed accumulator (same "accumulator, not absolute time" pattern as
     `edge_progress`) and fires volleys. `CombatTargeting`
     (`sim/units/combat_targeting.gd`) does target selection per `04-combat.md`:
     `canTarget` filtering, the Tier-A (troops + Defensive buildings) over Tier-B
     (plain Structures) priority split, highest-qualifying-`damageDealtModifiers`-
     then-nearest ordering, and the directed `attack_target` order override.
     `CombatMath` (`sim/units/combat_math.gd`) resolves damage
     (`damageDealtModifiers` × `damageReceivedModifiers` × armor, `Piercing`
     bypass, ≥1 floor), splash hits enemies around the impact hex (no friendly
     fire), and the dead are pruned. Buildings became combatants: `BuildingInstance`
     now carries `current_hp`/`max_hp` (from `BuildingStats.max_hp()`,
     `sim/instances/building_stats.gd`, which applies the `growthRate` formula and
     resolves Turret-variant `extends`), Defensive buildings fire back, and a
     building at 0 HP is removed. A uniform `CombatTarget`
     (`sim/units/combat_target.gd`) lets targeting/damage treat squads and
     buildings identically. `tests/test_combat.gd`, 36 checks passing. **Deferred**:
     status effects (freeze/stun/knockback/emp), auras (Shield Tank, Ambulance
     heal, Disruptor suppress), stealth/detection visibility, terrain combat
     bonuses (hill defender, forest ambush), regiment lock-step movement, cargo,
     and HQ capture-flip + ruin state (a destroyed building is deleted, not
     captured/ruined, for now).
   - [x] Squad movement/pathing resolver — **prerequisite for the combat-slice
     items below.** `MovementResolver.resolve_tick()`
     (`sim/units/movement_resolver.gd`) advances every squad's `current_hex`/
     `path`/`edge_progress` per `01-map-and-terrain.md`'s Movement & Positioning
     model: motion is converted to elapsed *time*, not carried as a raw
     progress fraction, since consecutive edges can have different terrain
     cost (plains 1.0 vs. hills 2.0) — a fraction of one edge isn't the same
     fraction of another. `MovementResolver.issue_move()` is the order entry
     point (resolves a squad's Domain + `terrainOverrides` from its troop def,
     calls `HexGrid.find_path()`, strips the current hex, sets `path` and a
     `{type:"move", goal}` order symmetric with the existing `attack_target`
     order) and mid-route replanning (a wall raised after the order was issued
     reroutes once per tick, or halts cleanly if no detour exists). Boarded
     squads are skipped (cargo position-driving is deferred). Runs before
     `CombatResolver` in the not-yet-built top-level tick orchestrator.
     `HexGrid.edge_cost()`/`find_path()`/`passable_neighbors()` and
     `Terrain.effective_cost()` gained an optional `overrides` param
     (backward-compatible default `{}`) so a troop's `terrainOverrides`
     (`ignoresForestBlock`/`ignoresRiverBlock`, e.g. Quad-bike) are honored by
     pathing, not just Road/Bridge infrastructure; `Terrain.domain_from_string()`
     maps a troop def's `domain` string to `Terrain.Domain`.
     `tests/test_movement.gd`, 32 checks passing. **Deferred**: vision/
     fog-of-war (split into its own item below — it doesn't gate movement),
     regiment lock-step, cargo/carrier position-driving, and attack-move
     repathing toward a directed target.
   - [ ] Vision / fog-of-war: vision range tracked separately from engagement
     range per `04-combat.md` (a unit sees an enemy approaching before it's
     close enough to fight), per-player visibility sets. Split out from the
     movement item above since movement doesn't depend on it, but terrain
     bonuses/ambush and stealth/detection below do.
   - [ ] Terrain combat bonuses + stealth/detection: hill defender bonus,
     forest ambush (attacker hidden until engaging), Tower/Radar Array
     `detector`/`detectionRange`. Depends on the movement resolver above and
     the vision item above it.
   - [ ] Regiment lock-step movement: a move order on a Commander computes one
     shared path; every squad in the regiment (Commander included) advances
     it in sync, hex-by-hex, at the regiment's slowest-member speed
     (`RegimentInstance`, `sim/units/regiment_instance.gd`, currently only
     tracks membership). Depends on the movement resolver above.
   - [ ] Status effects (freeze/stun/knockback/emp) + auras: wires up
     `TroopInstance.active_buffs` (`sim/units/troop_instance.gd`) — currently
     a declared field nothing reads or writes. Covers Cold Turret's freeze,
     `stun`'s fixed -30% move/-30% attack-speed tail, Commander buff auras,
     Ice Spire's slow, Hospital's heal.
   - [ ] Cargo: `board`/`unload` orders, `cargoAllowedTags` gating, mid-combat
     launch for Aircraft Carrier/Transport Truck, carrier-death-kills-cargo.
     `SquadInstance.boarded_on_squad_id`/`cargo_squad_ids` are declared fields
     with no logic behind them yet.
   - [ ] HQ capture-flip, building ruin state, and out-of-combat HP regen:
     `CombatResolver._prune_dead()` currently deletes any building — HQ
     included — at 0 HP. Per `02-bases-and-buildings.md`, an HQ at 0 HP should
     instead flip the base to the attacker and respawn at full HP; an
     ordinary building (Farm, Barracks, Turret, etc.) should become a
     rebuildable ruin rather than vanish (Walls/standalone buildings are
     correctly spec'd to delete outright, so those stay as-is); and all
     buildings/walls should slowly regen HP once out of combat. Shares its
     ruin data model with the placement slice's "demolish/ruin state"
     deferral below — same ruin state, two different triggers (voluntary
     demolish vs. combat destruction).
   - [x] Base/building placement rules, hex-adjacency validation (see
     `02-bases-and-buildings.md`): `BuildingPlacement.can_place()`
     (`sim/instances/building_placement.gd`) checks base-type eligibility
     (`BaseDef.buildableBuildings`), `isFixed`/`isStandalone` gating,
     one-building-per-hex + ground-troop-occupancy (`ground_unit_hexes()` —
     Infantry/Land block, Air/Naval don't), `siteTerrain`/
     `adjacentTerrainRequired` (Plains-only by default, Treehouse/Windy Peaks
     Forest/Hill exceptions), the 2-adjacent-buildings expansion rule, HQ
     build radius (placeholder `hq_level*2+2`, tunable like
     `Terrain.HILLS_INFANTRY_COST`), and the population gate. `Population`
     (`sim/instances/population.gd`) derives `populationCap`/`populationUsed`
     from live buildings (House/HQ grant capacity rather than consume it).
     `BaseFactory.seed_base()` (`sim/instances/base_factory.gd`) places the
     mutually-adjacent HQ/Farm/Quarry seed cluster from `BaseDef.initialBuildings`.
     `BaseInstance`/`BuildingInstance` now carry `hex_coord`/`hex`.
     `tests/test_placement.gd`, 33 checks passing. **Deferred**: Walls
     (edge-keyed, 1-adjacent-building exception, no population cost — lands
     with the combat/line-of-sight slice), the Bridge-foothold adjacency
     exception, and demolish/ruin state.
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
