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
     troop Food/Fuel upkeep sourcing and squad-level troop death under
     deficit are now wired in by `UpkeepSystem`
     (`sim/economy/upkeep_system.gd`, `tests/test_resources.gd`): a Land
     vehicle only pays Fuel while under a move order (empty `path` = idle),
     an Air unit pays no Fuel while idle and within 1 hex of one of its
     owner's own base buildings (the "leash range" fuel-free rule), and
     Naval/Infantry upkeep is always flat, straight off each troop def's
     `foodUpkeep`/`fuelUpkeep`. `apply_deficit_deaths()` kills a deficit-
     affected squad's weakest member per tick, disbanding an emptied squad,
     per `03-resources.md`'s Deficit Consequences.
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
     regiment lock-step, cargo/carrier position-driving (both landed further
     down this list). Attack-move repathing toward a directed target now
     lands too: `MovementResolver.resolve_attack_move()` chases a squad's
     `{type:"attack_target"}` order when the target is out of the attacker's
     range and it isn't already mid-chase — a fresh path toward the target's
     CURRENT hex via a new `_path_toward()` helper `issue_move()` was
     refactored to share, since `issue_move` itself would've clobbered the
     `attack_target` order with `{type:"move"}`. Once the target comes into
     range, any in-progress chase path is cleared so the squad holds
     position and fights rather than overshooting — movement and combat
     still resolve independently each tick (this file's own header comment),
     so this only decides *whether* to chase, never whether to fire.
     `targets: Array[CombatTarget]` is the same caller-computed-once array
     `CombatResolver` already builds each tick. `tests/test_movement.gd`
     extended (new section).
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
     update) all extended/updated accordingly. Dock's Naval disembark-gating
     is now wired: `BuildingPlacement.is_naval_landing_hex()` (Dock/Port/
     Shipyard, base-attached or standalone) is consumed by
     `CargoSystem.unload()` — a Naval-domain carrier disembarking cargo onto
     a non-Naval-passable hex (bare land) is rejected unless that hex
     carries one of those three building types; non-Naval carriers
     (Transport Truck, Aircraft Carrier) are untouched by the check.
     `tests/test_cargo.gd` extended. `CombatResolver` now targets standalone
     buildings too: `resolve_tick()`/`_build_targets()` take a
     `standalone_buildings` array, owner_id comes from the building's own
     `owner_id` (not a base's), and `_prune_dead()` deletes a standalone
     building outright at 0 HP rather than ruining it (Tower/Landmine only —
     Road/Bridge/Dock carry no combat HP). Fixing this exposed a real,
     previously-untested gap: `BuildingStats.defensive_stats()` only ever
     read the top-level `defensiveStats` block, which for multi-material
     Tower holds just the material-invariant `detector`/`detectionRange` —
     its actual damage/attackSpeed/range/canTarget/damageTypes/splashRadius
     live per-material under `materialStats[material]` (schema's own note:
     "each material restates its own full canTarget... the building-level
     defensiveStats block still holds the traits that are truly invariant
     across materials"), so a Tower could never actually fire. `defensive_stats`
     now takes `level`/`material` and merges the level-scaled per-material
     attack stats on top of the invariant block, the same `_hp_model`-style
     shape `max_hp()` already uses. `tests/test_combat.gd` extended (new
     standalone-Tower-combat section plus a `BuildingStats.defensive_stats`
     materialStats-merge section). Building-side stealth/detection
     (Landmine-as-a-hidden-object) turned out to already be wired — once
     standalone buildings became live `CombatTarget`s (above),
     `CombatTarget.for_building()`'s existing `is_hidden`/`reveal_range`
     fields (sourced from `BuildingStats.stealth()`/`.reveal_range()`) and
     `CombatTargeting.candidates()`'s existing `target.is_hidden` gate — both
     already Kind-agnostic, shared with squad-side stealth — just needed
     exercising end-to-end; confirmed with a new integration section in
     `tests/test_detection.gd`. **Deferred**: Engineer-must-issue-this
     enforcement (`canBuildInfrastructure` — no command/order-issuing layer
     exists yet to check who's calling the placement function).
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
     checks total). Commander-death regiment disband is now wired, in
     `CombatResolver` (a combat-side concern, as noted, so it landed there
     rather than in `MovementResolver`):
     `_disband_regiments_for_dead_commanders()` runs at the end of
     `_prune_dead()`, taking a new optional `regiments: Array[RegimentInstance]`
     param on `resolve_tick()` — a regiment whose `commander_id` no longer
     names a squad still present in `squads` (i.e. the Commander squad was
     just pruned) has every member squad's `commander_id` cleared and any
     `{type: "regiment_move"}` order reset to idle (`{}`), then the
     `RegimentInstance` itself is removed from `regiments`. `tests/test_combat.gd`
     extended (new section). Cargo-boarded regiment members are now handled
     too: a boarded member was already excluded from lock-step mirroring
     (its `boarded_on_squad_id` check predates this) and already tracked its
     carrier's position via `_mirror_boarded_squads`, but `CargoSystem.unload()`
     left it idle (order `{}`) rather than `regiment_move` on release, and
     `resolve_regiment_tick()`'s rejoin check only matched an ad hoc
     `{type:"move"}` split, not a bare idle squad — so an unloaded member
     never rejoined lock-step. The rejoin check is broadened to "any
     non-boarded member whose order isn't already `regiment_move` and whose
     path is empty," covering both cases with one rule. `tests/test_movement.gd`
     extended (new section). **Deferred**: none — the two remaining
     regiment-adjacent items (Commander buff auras' regiment-membership
     filter, `assign_to_commander`/`leave_regiment` themselves) are already
     tracked above under the command/order-issuing-layer gap.
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
   - [x] Cargo: `CargoSystem.board()`/`.unload()` (`sim/units/cargo_system.gd`)
     — `can_board()` checks same-owner, neither squad already boarded/full-of-
     nothing, the carrier's free capacity (`cargoCapacity` summed across its
     own living members, since capacity counts squads not troop headcount —
     `> cargo_squad_ids.length`), and the boarding squad's Domain/tags against
     `cargoAllowedTags` (same match mechanism as `canTarget`). `can_unload()`
     gates mid-battle deploys on the carrier's `canLaunchCargoMidCombat` via a
     caller-supplied `in_combat` flag (no broader combat-state/order-issuing
     layer exists yet to derive it, the same gap already deferred for
     `assign_to_commander` — defaults to false so idle-unload callers don't
     need to pass it) and `unload()` only allows the carrier's own hex or an
     immediate neighbor, checked against `grid.edge_cost()` for the unloaded
     squad's own Domain/terrainOverrides. `MovementResolver.resolve_tick()`
     gained `_mirror_boarded_squads()`, closing the previously-deferred
     "cargo position-driving" gap — a boarded squad's `current_hex` now
     tracks its carrier's every tick instead of just being skipped.
     `CombatResolver._prune_dead()` now deletes every boarded `SquadInstance`
     (and its `TroopInstance` members) when its carrier squad is pruned for
     having no living members — cargo does not survive its carrier's
     destruction, no "spills out" recovery. `tests/test_cargo.gd`, 28 checks
     passing.
   - [x] HQ capture-flip, building ruin state, and out-of-combat HP regen:
     `CombatResolver._prune_dead()` (`sim/units/combat_resolver.gd`) no longer
     unconditionally deletes a base's buildings at 0 HP. An HQ instead
     captures per `02-bases-and-buildings.md`: `base.owner_id` flips to
     whoever dealt the killing blow (tracked via the new
     `BuildingInstance.last_damaged_by`, set in `_damage_target()`) and the HQ
     respawns at full HP in place — since every base-attached building
     already derives ownership from `base.owner_id`
     (`building_instance.gd`'s existing convention), flipping just that one
     field is enough to flip the whole base, with no per-building ownership
     to update. Garrisoned squads are untouched (they carry their own
     `owner_id`) — elimination-on-last-base-lost stays a separate, not-yet-
     built system. A non-HQ building at 0 HP instead becomes a **ruin**
     (`BuildingInstance.is_ruin`): it stays in `base.buildings`, still
     occupying its hex and counting for the hex-adjacency placement rule
     (`BuildingPlacement`'s `occupied_hexes()`-based checks needed no changes
     — they already don't filter on HP), but no longer functions.
     `VisionSystem`/`DetectionSystem` (`sim/vision/`) gained an explicit
     `current_hp <= 0.0` skip for base buildings to match — previously
     implicit since dead buildings were removed before either system ran;
     `AuraSystem` already had this check on both the source and
     `friendly_buildings`/`enemy_buildings` target side. Walls/standalone
     buildings (which delete outright per `06-building-stats-and-defenses.md`)
     need no exception yet since neither is targetable by `CombatResolver`
     today (Walls unimplemented; standalone buildings out of
     `_build_targets()`'s scope). New `BuildingRegenSystem`
     (`sim/units/building_regen_system.gd`), called at the end of
     `CombatResolver.resolve_tick()`: any damaged-but-surviving,
     non-ruined building regenerates 5% of current max HP per banked 5-second
     tick once `BuildingInstance.time_since_damage` (reset on every hit
     alongside `last_damaged_by`) clears a placeholder out-of-combat delay —
     same accumulator-over-dt shape as `attack_progress`/`edge_progress`,
     not an assumed fixed external cadence. `tests/test_combat.gd` extended
     (ruin, HQ capture-flip, and regen sections). **Deferred**: the actual
     rebuild-on-ruin action/cost and the voluntary `demolish_building` action
     that shares this same ruin data model (both still need the
     command/order-issuing layer noted as missing throughout this doc), and
     Walls/standalone-building delete-outright once either becomes
     targetable.
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
     `tests/test_placement.gd`, 33 checks passing. Walls now land:
     `BuildingPlacement.can_place_wall()`/`.place_wall()` validate/place an
     edge-keyed Wall (both hexes on-grid and mutually adjacent, the edge not
     already walled, ≥1 of the two hexes already in `base.occupied_hexes()` —
     the 1-adjacent-building exception, a placeholder interpretation of "one
     existing adjacent building" for an edge that has no hex of its own to
     count neighbors around, same spirit as `hq_build_radius`). A Wall is
     just a `BuildingInstance` with `hex` left null and new `hex_a`/`hex_b`
     fields set instead — deliberately reusing `base.buildings` wholesale
     rather than a parallel registry, so `BuildingStats.max_hp`,
     `BuildingRegenSystem`, and `CombatResolver`'s existing base-building
     loops all pick up Walls for free with zero changes. What *did* need
     changes: `CombatTarget.for_building()` sets `hex`/`hex_b` from
     `hex_a`/`hex_b` instead of `building.hex` and skips the terrain-bonus/
     stealth lookups (a Wall stands on no single tile); a new
     `CombatTarget.distance_from()` (used by `CombatTargeting.candidates()`/
     `_best_in_tier()` in place of raw `HexCoord.distance`) returns the
     nearer of a Wall's two endpoints, since it's in range of an attacker
     adjacent to either hex it borders; `candidates()` also drops any Wall
     target for an Air-domain attacker (Walls "never attack" and are
     ignored entirely by Air, per `01-map-and-terrain.md`); `_prune_dead()`
     deletes a destroyed Wall outright (never ruins) and clears
     `grid.set_wall()` so the edge reopens for movement; and
     `AuraSystem`/`Population` each needed a one-line guard/reads-populationCost-0
     path for a building with a null `hex`. `tests/test_placement.gd` (new
     Wall-placement section) and `tests/test_combat.gd` (new Wall-combat
     section) extended. **Deferred**: the actual line-of-sight blocking half
     of Walls ("an attack whose line from attacker-hex to target-hex crosses
     a walled edge is blocked" — `01-map-and-terrain.md`) — movement across a
     walled edge is already blocked (`HexGrid.edge_cost`/`is_walled_edge`,
     from the very first hex-grid slice), but line-of-sight requires an
     actual hex-line/raycast algorithm between attacker and target hexes,
     which is a distinct, larger unit of work from "Walls exist as a
     targetable, edge-keyed building" and is left as its own future slice;
     and demolish/ruin state (ruin state itself now exists, from the
     HQ-capture/ruin item above — only the player-issued demolish action is
     still missing, gated on the same command/order-issuing layer as
     everything else in that bucket). The Bridge-foothold adjacency
     exception is also now wired: `BuildingPlacement._has_bridge_foothold_exemption()`
     walks each of a candidate hex's 6 neighbor directions looking for one
     that's a Bridge (`grid.get_infrastructure() == BRIDGE` — no
     `standalone_buildings` param needed, since Bridge infrastructure is
     already tracked on the grid itself regardless of which array its
     `BuildingInstance` lives in); if found, it checks that Bridge's hex
     *continuing in the same direction* (not the reverse — that would just
     walk back to the candidate hex itself) against `occupied` — that's the
     near-bank foothold the Bridge stands in for. `can_place()`'s
     `NOT_ENOUGH_ADJACENT_BUILDINGS` check now falls through to this
     exemption instead of failing outright. `tests/test_placement.gd`
     extended (new section, covering both the exempted and
     no-foothold-yet-so-still-rejected cases).
   - [x] Top-level tick orchestrator, command/order-issuing layer, and Wall
     line-of-sight raycasting — the last three headless gaps, closed together
     since building the order-issuing layer meant actually wiring in most of
     the "blocked on this layer" deferrals scattered through this file.
     `SimOrchestrator.resolve_tick()` (`sim/sim_orchestrator.gd`) is the
     tick everything else was only ever driven from a test in isolation
     before now: per `07-data-architecture.md`'s two tick rates, its fine
     tick (whatever `dt` the caller passes, nominally 100ms) runs
     Detection → Vision → attack-move → Movement → regiment lock-step →
     Combat → production advance/pump every call, while its economy tick
     (Aura → upkeep/production → `ResourceTick` → deficit-deaths) only fires
     once 5 seconds have banked, via a `MatchState.economy_accumulator`
     (state lives on the instance, same as every other accumulator in this
     codebase — the resolver itself stays stateless). `MatchState`
     (`sim/match_state.gd`) is the new shared registry bundle (squads, bases,
     troops_by_id, regiments, standalone_buildings, production_queues,
     resource_pools, defs, id generation) both it and the command layer
     thread through — introduced now because this is the first code that
     actually needs to hold all of it together across ticks, not a
     speculative abstraction.
     `CommandProcessor` (`sim/command/command_processor.gd`) is the
     order-issuing layer itself: resolves an id-based player action into a
     call against the existing systems that already did the work, closing
     the specific gaps their own doc comments flagged as blocked on it —
     `move_squad`/`attack_target` (including regiment-vs-plain-squad
     dispatch for a Commander move), `board_cargo`/`unload_cargo` (in_combat
     now derived on demand via new `CombatStateSystem.is_squad_in_combat()`,
     rather than always defaulting false), `assign_to_commander`/
     `leave_regiment` (creates/mutates `RegimentInstance` directly, the
     `07-data-architecture.md` 4b flow), `place_building`/
     `place_standalone_building` (now enforcing Engineer-only
     `canBuildInfrastructure`, per `troop.schema.json`)/`place_wall`, and two
     brand-new actions: `demolish_building` (flat 50% of
     `BuildingInstance.total_resources_spent` refunded, blocked for
     `isFixed`) and `rebuild_building` (pays the def's `rebuildCost`% of
     `BuildingStats.base_cost()` to restore a ruin to level 1). Wiring
     demolish/rebuild needed `total_resources_spent` tracking
     (`BuildingInstance.init_cost()`, called alongside `init_hp()` at every
     placement site — this also caught `place_building()` never having
     called `init_hp()` at all, unlike `place_standalone_building()`/
     `place_wall()`, so a player-placed base building had no combat HP until
     now) and `BuildingStats.base_cost()`/`.rebuild_cost_percent()`
     (mirroring `max_hp()`'s per-shape dispatch, plus a `commanderProgression`
     branch for Command Centre). Wall line-of-sight
     (`01-map-and-terrain.md`: "an attack whose line from attacker-hex to
     target-hex crosses a walled edge is blocked") is `HexCoord.line()` (cube
     lerp + round, the standard hex-line algorithm) and
     `HexGrid.is_line_blocked()`, consumed by `CombatTargeting.candidates()`
     via a new optional `grid` param (default null = no LOS check, so every
     existing call site kept compiling) — never applied to a Wall's own edge
     (attacking a Wall is never blocked by itself) and skipped entirely for
     Air attackers, same as every other terrain rule. Landing the order layer
     also closed several other deferrals its own doc comments named: Commander
     regiment-membership buff auras (Vanguard's `speed_boost`, Nightfall's
     `grant_stealth`, Warden's `heal_out_of_combat`) — `AuraSystem.resolve_tick()`
     gained a `regiments` param and resolves `own_regiment`/
     `own_regiment_and_self` by membership instead of proximity now that
     regiments are addressable; `grant_stealth` reached
     `DetectionSystem.is_squad_hidden()`/`.squad_reveal_range()` via a new
     `auras` param; `heal_out_of_combat` finally gates on a new
     `SquadInstance.time_since_damage` (mirroring `BuildingInstance`'s own
     regen-delay field) instead of being folded unconditionally into
     `heal_over_time`, per that code's own long-standing note. Mule's
     `upkeep_reduction` also finally reaches `UpkeepSystem.compute_upkeep()`
     (new `auras` param). Separately (not order-layer-gated, just never
     built): `ProductionOutputSystem.compute_production()`
     (`sim/economy/production_output_system.gd`) sources every Resource
     building's `foodOutput`/`stoneOutput`/etc. (`BuildingStats.resource_output()`)
     through `ResourceModifier` into the dict `ResourceTick.apply()` always
     expected but nothing had ever computed — production was authored data
     with zero consumers until now. Building the orchestrator also surfaced a
     real, previously-invisible bug: `ProductionManager.pump()` created each
     deployed troop's `TroopInstance` but never registered it in any
     `troops_by_id` registry, so a squad it produced looked dead to
     `CombatResolver._prune_dead()` the very next tick and was silently
     wiped — invisible before because no test exercised `pump()` and
     `CombatResolver` together in the same tick loop; `pump()` now takes a
     `troops_by_id` param and registers every troop it creates.
     `tests/test_line_of_sight.gd`, `tests/test_sim_orchestrator.gd`,
     `tests/test_command_processor.gd`, and `tests/test_commander_auras.gd`
     (new files), plus `tests/test_units.gd` extended for the `pump()` fix.
     **Deferred at the time** (found during this pass, out of scope for it,
     since resolved in a later pass — see below): resource-cost
     enforcement/deduction on fresh builds or troop training —
     `place_building`/`place_standalone_building`/`enqueue_production` still
     don't check or spend resources at all (demolish/rebuild do, since paying/
     refunding is their entire point, but this is a separate, larger gate to
     add later); and clearing a `ProductionQueue` when its building is ruined
     or its base captured, per `07-data-architecture.md` 3b (today an
     orphaned queue is simply skipped by the orchestrator's production step
     rather than actively erased).

     **Both of those deferred items are now resolved.** Resource-cost
     enforcement lives in `CommandProcessor` (`sim/command/command_processor.gd`),
     the same check-then-spend shape `rebuild_building` already used:
     `place_building`/`place_standalone_building`/`place_wall` each validate
     placement first (`BuildingPlacement.can_place*`, read-only), price it via
     `BuildingStats.base_cost()` + `ResourceType.dict_from_named()`, reject
     with a new `BuildingPlacement.Result.INSUFFICIENT_RESOURCES` if the
     owner's `ResourcePool` can't cover it, and only deduct once the
     underlying placement call actually succeeds; `enqueue_production` does
     the same against `troop_defs[type]["cost"]`, returning
     `CommandProcessor.Result.INSUFFICIENT_RESOURCES`. `BuildingPlacement`
     itself stays resource-agnostic (still no pool param) — the gate is
     command-layer only, so direct `BuildingPlacement.place_*` callers (tests,
     and any future non-command caller) are unaffected. Separately,
     `CombatResolver.resolve_tick()`/`_prune_dead()` gained a
     `production_queues` param (threaded from `SimOrchestrator` as
     `state.production_queues`): a building freshly ruined this tick has its
     own `production_queues` entry erased, and a base captured this tick (its
     HQ hit 0 HP) has every one of its buildings' entries erased, per
     `07-data-architecture.md` 3b's "resources already spent on those entries
     are not refunded" rule.
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
