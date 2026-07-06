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
   - [x] Vision / fog-of-war: per-player currently-visible and persistently-
     explored hex sets (`sim/vision/player_vision.gd`'s `PlayerVision`),
     recomputed each tick by `VisionSystem.resolve_tick()`
     (`sim/vision/vision_system.gd`) from every live squad's and base
     building's `visionRange`, mirroring `MovementResolver`/`CombatResolver`'s
     stateless-resolver-over-flat-arrays shape. Scope is deliberately kept to
     squads + base-attached buildings only, matching `CombatResolver`'s
     existing boundary (see Deferred below), and this slice deliberately does
     **not** touch stealth/detection or terrain combat bonuses at all — that's
     the next item below, which consumes this system's output rather than
     being part of it. `explored_hexes` only ever
     grows (the "explored but not currently visible" fade); `visible_hexes` is
     fully recomputed every tick. `Terrain.vision_bonus()`
     (`sim/hex/terrain_types.gd`) adds a flat, tunable `PLAINS_VISION_BONUS`
     (placeholder like `HILLS_INFANTRY_COST`) for a source standing on Plains,
     per `01-map-and-terrain.md`'s "extended vision + extends fog-of-war
     clearing." `BuildingStats.vision_range()`/`.global_vision_bonus()`
     (`sim/instances/building_stats.gd`) resolve a building's vision the same
     three-shape way `max_hp()` already does (materialStats for Tower,
     nonProductionUpgrade for Radar Array, flat `defensiveStats.visionRange`
     un-leveled for Turret/Missile Launcher/Landmine — matching how
     `CombatResolver` already reads those buildings' `defensiveStats`
     un-leveled) plus Radar Array's `globalVisionRangeBonus`, applied on top
     of every one of that owner's vision sources map-wide, not just its own
     tile. `tests/test_vision.gd`, 32 checks passing. **Deferred**: standalone-
     building vision (Tower/Landmine) — `BuildingInstance` has no `owner_id`
     for a standalone instance to key vision by yet, the same boundary
     `CombatResolver` already stops at; and consuming this system for
     stealth/detection + terrain combat bonuses (the next item below).
   - [x] Terrain combat bonuses + stealth/detection: hill defender bonus
     (`Terrain.HILLS_DEFENDER_BONUS`/`.defense_bonus()`,
     `sim/hex/terrain_types.gd` — a received-damage multiplier folded into
     `CombatMath.resolve_damage()` via `CombatTarget.defense_multiplier`,
     computed live off the target's hex each tick, same treatment as
     `vision_bonus()`). Forest ambush unified with the troop/building
     schema's `stealth`/`revealRange`/`revealsOnAttack`/`detector`/
     `detectionRange` fields — previously authored in data (Ghost Tank,
     Submarine, Sniper, Commander Nightfall, Tower, Radar Array, Landmine)
     but unconsumed by any sim code until now: an Infantry squad standing on
     Forest is treated as hidden the same way an authored-`stealth` unit is,
     via `DetectionSystem.is_squad_hidden()`/`.squad_reveal_range()`
     (`sim/vision/detection_system.gd`), gated in
     `CombatTargeting.candidates()` against a `reveal_range` proximity check
     and the `detections` map `DetectionSystem.resolve_tick()` produces
     (mirrors `VisionSystem`'s shape — recomputed fresh every call, no
     persistence, unlike `PlayerVision.explored_hexes`). Attacking breaks
     either kind of hidden state for a cooldown
     (`SquadInstance.reveal_cooldown_remaining`, decremented/reset by
     `CombatResolver`). `BuildingStats.detector()`/`.detection_range()`/
     `.stealth()`/`.reveal_range()` (`sim/instances/building_stats.gd`)
     resolve Tower/Radar Array/Landmine's schema fields. `tests/test_combat.gd`
     (extended, 58 checks) + new `tests/test_detection.gd` (16 checks).
     **Deferred**: standalone detector buildings (Tower) — see the new
     standalone-building-placement item below, which this depends on; and
     regiment-wide stealth auras (Commander Nightfall's `grant_stealth` aura),
     which lands with the aura system.
   - [x] Standalone building placement (Engineer-built-anywhere Tower,
     Landmine, Road, Bridge, Dock): `BuildingInstance` gained `owner_id`
     (trailing optional constructor param, defaulting to `""` and unused for
     base-attached buildings, which keep deriving ownership from
     `base.owner_id`). `BuildingPlacement.can_place_standalone()`
     (`sim/instances/building_placement.gd`) is the base-free validator —
     unlike `can_place()`'s implicit Plains default, it only enforces
     `siteTerrain`/`adjacentTerrainRequired` when the def actually specifies
     one (Tower/Landmine have neither and are placeable on any terrain, per
     their "anywhere" notes), and skips every base-menu-only check
     (buildableBuildings/population/2-adjacency/HQ-radius).
     `standalone_occupied_hexes()` unions base-occupied hexes with existing
     standalone buildings' hexes so the two placement domains can't overlap.
     `place_standalone_building()` appends to a plain `Array[BuildingInstance]`
     (no new manager/registry class, matching the array-of-instances +
     stateless-resolver pattern used everywhere else) and, for Road/Bridge,
     calls `grid.set_infrastructure()` — the first placement path to ever do
     so outside tests. `VisionSystem.resolve_tick()` and
     `DetectionSystem.resolve_tick()` (`sim/vision/`) each gained a
     `standalone_buildings` parameter and a loop keyed by
     `building.owner_id` instead of `base.owner_id`, closing both
     previously-deferred gaps — Tower's `detector`/`detectionRange` now
     reaches `DetectionSystem`, and Tower/Landmine's `visionRange` now
     reaches `VisionSystem` (Road/Bridge/Dock have neither field, so they
     naturally contribute nothing to either system). `tests/test_placement.gd`
     (new standalone-placement section), `tests/test_vision.gd`,
     `tests/test_detection.gd`, and `tests/test_combat.gd` (signature-only
     update) all extended/updated accordingly. **Deferred**: Engineer-must-
     issue-this enforcement (`canBuildInfrastructure` — no command/order-
     issuing layer exists yet to check who's calling the placement
     function), Dock's actual Naval disembark-gating movement logic,
     CombatResolver targeting standalone buildings, and building-side
     stealth/detection (Landmine-as-a-hidden-object) — squad-side already
     exists, buildings don't yet.
   - [x] Regiment lock-step movement: `MovementResolver.issue_regiment_move()`
     computes one shared path from the Commander's squad and mirrors it onto
     every member squad (clearing any ad hoc split); `resolve_regiment_tick()`
     advances the Commander along that path at a flat speed cap — the
     slowest member's speed stat, per `04-combat.md` — using the Commander's
     own domain/`terrainOverrides` to resolve terrain cost (the shared-path
     anchor), then mirrors the resulting `current_hex`/`path`/`edge_progress`
     onto every lock-step member rather than each squad re-deriving its own
     cost (`sim/units/movement_resolver.gd`). A member given a temporary ad
     hoc order (`{type:"move"}`, per `09-ui-and-controls.md`) is left for the
     ordinary per-squad `resolve_tick()` to advance instead — which now skips
     any squad whose order is `{type:"regiment_move"}` to avoid double-
     advancing — and automatically converts back to `regiment_move` (re-
     syncing onto the Commander's current path/hex) once its ad hoc path
     drains empty. `RegimentInstance` itself is unchanged (still just
     membership bookkeeping); the resolver takes already-resolved
     `SquadInstance` objects rather than ids, consistent with `issue_move()`,
     since the command/order-issuing layer that would resolve
     `commanderId`/`squadIds` into live objects doesn't exist yet (same
     deferral as `assign_to_commander`/`leave_regiment` elsewhere in this
     doc). `tests/test_movement.gd` (new Regiment lock-step section, 41
     checks total). **Deferred**: Commander-death regiment disband (still a
     combat-side concern), cargo-boarded regiment members.
   - [x] Status effects (freeze/stun/knockback/emp) + auras:
     `StatusEffectSystem` (`sim/units/status_effect_system.gd`) rolls and
     applies a hit's `statusEffectOnHit` to the PRIMARY target only (splash
     victims never carry one — a scoping choice): `freeze`/`stun` set
     `lockout_remaining` (full move+attack lockout; `stun` also queues
     `stun_tail_queued`, armed into `stun_tail_remaining`'s -30%/-30% tail the
     instant the lockout crosses to 0, with leftover dt correctly carried into
     the tail's first tick rather than wasted); `knockback` shoves the target
     `magnitude` hexes straight away from the attacker
     (`HexCoord.direction_away()`), clamped at the grid edge; `emp` is
     domain-conditional (Land: `move_lockout_remaining`, can still attack;
     Air: instant destroy via `CombatTarget.kill_squad()`; Infantry/Naval: no
     effect; `empImmune` troops unaffected). Lives on `SquadInstance`/
     `BuildingInstance` directly (not `TroopInstance.active_buffs` — see that
     field's updated comment) since lockout/aura coverage is squad-wide, not
     per-troop. `AuraSystem` (`sim/units/aura_system.gd`) resolves proximity-
     radius auras fresh each tick from every live troop/building source
     (`BuildingStats.auras()` applies Hospital's leveled `healMagnitude` the
     same way `max_hp()`/`vision_range()` already scale): `speed_boost`/`slow`
     and `attack_speed_boost` multiply into `MovementResolver`/
     `CombatResolver`'s speed math (stacking multiplicatively across sources,
     same "every modifier applies" rule as `CombatMath`), `damage_reduction`
     reaches `CombatMath.resolve_damage()` via a new
     `CombatTarget.aura_damage_reduction_mult`, `heal_over_time` applies as
     flat HP regen via `AuraSystem.apply_heals()`, and `suppress_targeting`
     makes `CombatResolver` skip a covered Defensive building's turn entirely.
     `tests/test_status_effects.gd` (30 checks) and `tests/test_auras.gd` (21
     checks), plus a CombatResolver/MovementResolver integration check in
     each. **Deferred**: Commander buff auras (Vanguard/Nightfall/Warden) —
     their `own_regiment`/`own_regiment_and_self` filter is regiment
     MEMBERSHIP, not proximity, which needs `RegimentInstance.commanderId`/
     `squadIds` resolved into live squad references — the same
     command/order-issuing-layer gap already deferred for
     `assign_to_commander` above; `upkeep_reduction` (Mule) is computed but has
     no consumer yet, since troop Food/Fuel upkeep itself isn't wired in
     anywhere (see the Resource ticking item above); standalone-building aura
     sources (none authored today, but `AuraSystem` only loops base-attached
     buildings, matching `CombatResolver`/`VisionSystem`'s existing boundary).
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
