# Data Architecture

This document lays out how the game's core concepts map to actual stored data —
definitions (static, authored once) vs. instances (live, per-match state).

## 1. Materials (Wood/Stone/Steel) for Multi-Material Buildings
Buildings that come in multiple materials (Tower, Wall, Dock, Bridge) are **one
building type each**, not separate types per material. Stat/growth/cost tables are
keyed by material:
```
BuildingDef["Tower"]["stone"] = { base_stats, stat_growth, base_cost, cost_growth }
BuildingDef["Tower"]["wood"]  = { base_stats, stat_growth, base_cost, cost_growth,
                                   adds_turret_per_level: true }
BuildingDef["Wall"]["wood"]   = { base_stats, stat_growth, base_cost, cost_growth,
                                   damage_received_modifiers: { Fire: 2.0 } }
BuildingDef["Wall"]["stone"]  = { ... }
BuildingDef["Wall"]["steel"]  = { ... }
```
A built instance stores which type + which material it was built as; material is
fixed at construction time. (Whether a destroyed-and-rebuilt ruin can switch material
is an open decision — see Open Items.)

## 2. Walls
Walls sit on hex **borders**, not on a hex itself, so they're keyed by an edge, not a
tile. Unlike other buildings, a Wall at 0 HP is simply **deleted** rather than flipped
into a ruin state (see `06-building-stats-and-defenses.md`):
```
Wall {
  id,
  edgeKey: "hexA|hexB"   // canonical sorted pair of adjacent hex coordinates
  ownerId,
  material,              // wood / stone / steel
  level,
  currentHP,
  lastDamagedAt          // used to gate HP regen — no recent damage means it's regenerating
}
```
Stored in its own table, separate from tile-based `BuildingInstance` records. When
`currentHP` hits 0, the row is removed and the edge is freed — there is no
`ruinState` for Walls.

- **Walls block movement and line-of-sight/projectiles across the edge they occupy**:
  pathfinding treats a walled edge as impassable (see `01-map-and-terrain.md`'s
  Movement & Positioning section), and a ranged attack whose line from attacker-hex
  to target-hex crosses a walled edge is blocked, forcing an attacker to path around
  or destroy the wall first. **Air-domain** units/attacks ignore Walls entirely, same
  as they ignore every other terrain restriction.

## 3. Building Instances (including Health)
Every non-HQ building tracks its own live health independently of its static
definition. **HQ is a special case**: it's still a `BuildingInstance` structurally,
but instead of a `ruinState` it has capture-on-zero-HP behavior (see below):
```
BuildingInstance {
  id,
  baseId,               // which base this belongs to (null for standalone Dock/Road/Bridge/Tower)
  buildingType,
  material,             // only relevant for Tower/Wall/Dock/Bridge
  hex,
  level,
  currentHP,            // depletes under attack; building def determines maxHP at current level
  lastDamagedAt,        // used to gate HP regen (see 06-building-stats-and-defenses.md)
  totalResourcesSpent,  // dict per resource; cumulative — original build cost + every upgrade cost paid, used to compute the demolish refund (see below)
  ruinState: null | { destroyedAt, rebuildCost }   // set when currentHP hits 0, except for HQ and Wall
}
```
- **currentHP is always tracked per instance**, separate from the definition's
  `maxHP-at-this-level` — this is what actually depletes during a siege, and what
  regenerates back up via `lastDamagedAt` once combat stops.
- **`totalResourcesSpent`** accumulates every resource cost the owner has actually paid
  for this specific instance (its original build cost, plus each upgrade's cost as it's
  paid) — it never resets or decreases. This is the base the **demolish** action refunds
  against (see below); it's tracked independently of `ruinState`/rebuild cost, which is
  a *cost to pay*, not a value to refund from.
- When a non-HQ building's `currentHP` reaches 0, the instance flips into `ruinState`
  (per `06-building-stats-and-defenses.md`'s ruin rules) rather than being deleted —
  the hex stays occupied, and the owner can pay `rebuildCost` (a fraction of original
  cost) to restore it to the same building type/material at level 1. **Fixed/unique
  buildings** (e.g. Ice Spire) follow this same ruin/rebuild flow but can never be
  freshly constructed where one wasn't already pre-seeded — enforced at build-menu
  level (the building type simply isn't offered), not by this table's shape.
- **HQ**: when `currentHP` reaches 0, no `ruinState` is set. Instead, `Base.ownerId`
  (see below) flips to the attacker and `currentHP` is immediately reset to max — the
  HQ's `BuildingInstance` row is otherwise untouched.
- **Wall**: when `currentHP` reaches 0, the row is deleted outright (see `Wall` above)
  rather than gaining a `ruinState`.

### Standalone Buildings (Road, Bridge, Dock, Tower, Landmine) — ownerId, no ruin
Unlike a base-attached building, a standalone `BuildingInstance` has `baseId: null`,
so ownership can't be derived from a Base. Standalone instances instead carry their
own `ownerId` directly:
```
BuildingInstance {
  ...
  baseId: null,
  ownerId,              // only set (and only meaningful) when baseId is null
  ...
}
```
- Roads/Bridges/Docks remain **public** regardless of `ownerId` (any player's troops
  can use them) — `ownerId` here is about who built/owns it for rebuild-rights and
  attribution, not who's allowed to use it.
- A **Tower**, being a defensive structure, uses `ownerId` to decide who it auto-fires
  *for* (attacks anyone not matching `ownerId`).
- Standalone buildings **do not ruin** — like Walls, a standalone building at 0 HP is
  **deleted outright**, freeing the hex/edge. Rebuilding it there is a fresh build at
  full cost, not a discounted ruin-rebuild. `ruinState` is therefore never set on a
  standalone instance, same as Wall.

### 3a. Demolishing a Building (Voluntary Removal)
**Resolved**: a `demolish_building` player action lets an owner voluntarily remove one
of their own buildings — a separate mechanic from combat destruction/ruin, primarily
meant to recover from a misplaced/regretted building (which ruin-rebuild alone doesn't
solve, since a ruin still occupies the hex):
- Refunds **50% of `BuildingInstance.totalResourcesSpent`** to the owner's resource
  pool.
- The `BuildingInstance` (and any `ruinState`) is deleted outright and its `hex` is
  freed immediately — no ruin is left behind, unlike combat destruction.
- Frees the building's `populationCost` back to the base's available population
  immediately (see `populationUsed` in Base & Ownership below).
- **Blocked for any building whose def has `isFixed: true`** (HQ, Ice Spire) — since
  these can never be freshly built from a menu, demolishing one would create a
  permanent hole. The action simply isn't offered for them.
- Applies equally to Walls and standalone buildings (Road/Bridge/Dock/Tower/Landmine), which
  already delete-outright on combat destruction — demolish just triggers that same
  deletion voluntarily, with the 50%-of-spend refund.
- See `02-bases-and-buildings.md`'s Demolishing Buildings section for the player-
  facing rationale.

### 3b. Production Queue (Production-category Buildings)
Each Production-category `BuildingInstance` (Barracks, Factory, Command Centre, etc.)
owns its own independent queue — never a shared base-wide queue (see
`09-ui-and-controls.md`):
```
ProductionQueue {
  buildingId,           // the producing BuildingInstance; baseId derives from it
  entries: [
    { troopId, startedAt, productionTime }   // FIFO — entries[0] is currently training
  ],
  paused,               // true if completing entries[0] would breach a cap (see below)
  pauseReason: null | "squad_cap" | "commander_cap"
}
```
- **Resolved: destroyed building or captured base clears the queue outright.** If the
  producing `BuildingInstance` is destroyed (ruined) or its `BaseInstance.ownerId`
  changes hands (capture), its `ProductionQueue` — every entry, including the
  in-progress one — is deleted with it. Resources already spent on those entries are
  not refunded, consistent with troops/production never carrying over on capture (see
  Garrisoned Troops and the Base & Ownership section below).
- **Resolved: production pauses (doesn't silently drop the troop) at the squad/
  Commander cap.** When `entries[0]` finishes, before spawning the troop the
  simulation checks whether it would need a **brand-new squad** (no existing same-type
  squad in range has room) — if an existing squad has room, the troop joins it and
  production continues regardless of cap. If a new squad *would* be needed and the
  owner is already at their global squad cap (`4c` below), or — for a Command Centre
  specifically — at their Commander cap (`4d` below), the queue **pauses**:
  `entries[0]` holds in a completed-but-undeployed state, the queue doesn't advance to
  the next entry, and the build UI shows an alert indicator on that building
  (see `09-ui-and-controls.md`). The queue automatically resumes and the held troop
  spawns the moment the relevant cap has room again (a squad frees a slot, an HQ
  upgrade raises the cap, a Commander dies freeing a Commander-cap slot, etc.) — no
  player action is required to un-pause it beyond freeing capacity.

## 4. Troop Runtime State
**Resolved: the game is fully hex-based, including movement — there is no continuous
open-field position.** See `01-map-and-terrain.md`'s Movement & Positioning section
for the pathfinding/edge-crossing model this schema implements.

Static troop definitions (from `05-troop-stat-schema.md`) are separate from live
per-unit instances. A `TroopInstance` is always a **member of a `SquadInstance`**
(even a lone unit is a squad of 1) — movement, pathing, and targeting orders live on
the squad, not the individual troop:
```
TroopInstance {
  id,
  unitType,
  ownerId,
  squadId,              // never null — every troop belongs to a squad, even if solo
  currentHP,
  activeBuffs: [
    { source, effect, magnitude, expiresAt }   // auras, deficit-drain, etc.
  ],
  fuelStatus            // only relevant for aircraft/vehicles
}
```
Buffs/debuffs (Shield Tank auras, Food/Fuel deficit drain, terrain bonuses) are
computed each tick from what's currently in range/in effect, not baked permanently
into the unit's stats.

### 4a. Squad Instance (the atomic move/select/order unit)
```
SquadInstance {
  id,
  ownerId,
  troopType,             // always a single unit type — squads never mix types directly
  memberIds: [...],      // TroopInstance ids; length <= troopType's maxSquadSize
  currentHex,            // the hex this squad occupies/is departing from
  path: [hex, ...],       // queued hexes left to traverse, computed by pathfinding
  edgeProgress,          // 0-1, how far advanced from currentHex toward path[0]
  commanderId,           // nullable — set if assigned to a Commander's regiment
  boardedOnSquadId,      // nullable — set if this squad is currently cargo aboard a carrier squad; while set, this squad doesn't path/act independently (see 04-combat.md's Cargo section)
  cargoSquadIds: [...],  // only meaningful if troopType's cargoCapacity > 0 — squad ids currently boarded aboard this carrier squad
  order: { type: "move" | "attack_target" | "board" | "unload", targetId }
                         // targetId resolves to a Squad, BuildingInstance, or Wall for
                         // "attack_target"; a carrier SquadInstance for "board"; a
                         // boarded SquadInstance for "unload" (see 04-combat.md's
                         // directed-target/siege targeting and Cargo section)
}
```
- **Cargo/boarding**: a squad with `boardedOnSquadId` set is "inside" that carrier
  squad — it has no independent `currentHex`/`path` of its own while boarded (it
  moves with the carrier) and **still counts against the owner's global squad cap**.
  Boarding requires the carrier squad to have free capacity
  (`sum(cargoCapacity across carrier's member troops) > cargoSquadIds.length`) and the
  boarding squad's `troopType` to match the carrier's `cargoAllowedTags`. **Resolved:
  `cargoCapacity` counts squads, not individual troop headcount** — a boarded squad
  occupies exactly one slot regardless of its own member count. **If a carrier
  `SquadInstance` is destroyed (its `memberIds`
  reaches empty) while `cargoSquadIds` is non-empty, every boarded `SquadInstance` and
  all of its `TroopInstance` members are deleted along with it** — cargo does not
  survive the loss of its carrier.
- **A `SquadInstance` is always single-type** — "combined arms" doesn't happen by
  mixing troop types inside one squad. It happens one level up, at the
  `RegimentInstance` (4b below): a Commander leads a **regiment of up to 4 squads**,
  each squad still single-type, moving/fighting together under the Commander. This is
  simpler to implement than literal mixed-type squads (a squad's stats/targeting never
  need to reason about heterogeneous members) while still delivering the
  "mix infantry + vehicles under one command" experience at the regiment level.
- A freshly produced troop spawns in the nearest unoccupied hex to its production
  building; if a same-type squad within that hex's neighborhood has room (below
  `maxSquadSize`), the new troop auto-joins it, otherwise it forms a new squad of 1.
- Movement advances `edgeProgress` each simulation tick by
  `(speed / terrainCostMultiplier) * tickDuration` — `speed` in hexes/second, dividing
  by (not multiplying by) `terrainCostMultiplier` so that harder terrain (cost > 1)
  slows movement rather than speeding it up (see `01-map-and-terrain.md`'s Movement &
  Positioning section for the full writeup of this fix). On reaching 1.0, `currentHex`
  becomes `path[0]`, `path` shifts, and `edgeProgress` resets to 0. `edgeProgress`
  exists purely to smooth rendering/animation between hexes — range, vision, and
  engagement checks all use `currentHex` (integer hex distance), never a sub-hex
  position.
- **No per-hex unit cap** — any number of squads/troops can stack on one hex (combat
  scale here is about squads and fronts, not unit-level collision, matching the
  "positioning over micromanagement" pillar).
- Unlimited stacking means a squad's `order.type: "attack_target"` is how a player
  commits fire to a *specific* Structure (building/wall) rather than whichever is
  nearest — see `04-combat.md`'s targeting rules for the full default-vs-directed
  priority order.

### 4b. Regiment Instance (Commander-led combined-arms groups of squads)
```
RegimentInstance {
  id,
  commanderId,           // the Commander TroopInstance leading it
  squadIds: [...]        // up to that Commander's maxSquadsLed (baseline 4)
}
```
- Assigning a squad to a Commander sets that squad's `commanderId` and adds it to the
  Commander's `RegimentInstance.squadIds`; this is what lets a Commander's regiment mix
  troop types under one follow-the-Commander order, per `04-combat.md`.
- If the Commander dies, the `RegimentInstance` is deleted and every member squad's
  `commanderId` is cleared — they revert to unled, single-type-only squads (see
  `04-combat.md`'s Commander-death rule).

### 4c. Global Squad Cap
A player's maximum simultaneous squad count is **not a flat number** — it's derived:
`maxSquads = sum(hqLevel across every base the player owns) * 2 + 2` — every base
(Capital *and* Unique) has its own HQ and its own `hqLevel` (see Base Seeding in
`02-bases-and-buildings.md`), so this scales with both how many bases and how
developed each one is. A fresh player with one level-1 Capital starts at `maxSquads =
3` (`1 * 2 + 2`). Producing a troop that would need a new squad (no existing
same-type squad has room) is blocked/paused once the player is at their squad cap (see
`3b`'s production-queue-pause rule) — upgrading any owned base's HQ, or capturing an
additional base, raises the cap again.
- **If `maxSquads` drops below the player's current live squad count** (losing a
  base lowers `sum(hqLevel)`), nothing is forcibly disbanded — every existing squad
  keeps operating normally. The player is simply blocked from forming any *new* squad
  until their count drops back under the (now-lower) cap on its own (through losses).

## 4d. Commander Cap
A **separate** player-wide cap, independent of `maxSquads` above, though a Commander
(being a size-1 squad) consumes a slot against both simultaneously:
`maxCommanders = sum(commanderSlots across every Command Centre the player owns, at
each Command Centre's current level)`. Per `data/buildings/schema.json`'s
`commanderProgression`, each owned Command Centre contributes:
- **1** slot at levels 1-3 (these levels are about unlocking Commander *tiers* —
  common/rare/epic — not growing the cap; see `02-bases-and-buildings.md`'s Command
  Centre & the Commander Cap section).
- **+1 additional slot per level from level 4 onward** (levels 4+ have no further
  tier unlocks, so their only effect is HP growth plus this Commander-cap growth).

A player with two Command Centres (e.g. after capturing a rival's Capital) sums both —
two level-1 Command Centres together allow 2 simultaneous Commanders. As with
`maxSquads`, **losing a Command Centre can drop `maxCommanders` below the player's
current live Commander count without killing any existing Commander** — they keep
fighting; only *new* Commander production is blocked (paused, per `3b`) until the
count is back under the lower cap.

## 5. Base & Ownership
**Resolved: `BaseDef` (static, per base type — `data/bases/schema.json`) and
`BaseInstance` (live, per-match) are now separate**, matching the pattern already used
for troops and buildings. `BaseDef` holds `baseType`, `isCapital`, `terrainException`,
`buildableBuildings`, `initialBuildings` (pre-built buildings for Unique bases — see
below), `initialGarrison` (the authored garrison-troop template), `resourceModifiers`
(structured production multipliers — see below; replaces an earlier free-text
`resourceBonus` string), and `costModifiers` (structured build/upgrade-cost
multipliers, same shape as `resourceModifiers` but discounting/inflating what a
building costs rather than what it produces — e.g. Camp Cozy discounts Hospital and
Wall cost, see `02-bases-and-buildings.md`'s Camp Cozy section and
`data/bases/schema.json`).
- **`buildableBuildings`** is the explicit, complete list of every building id a base
  type can build — generic buildings (Farm, Turret, House, ...) included, not just its
  specialty ones. There's deliberately no "buildable at All bases" sentinel anywhere:
  `data/buildings/schema.json`'s building definitions carry no base-eligibility field
  of their own, so this list on `BaseDef` is the single source of truth for
  building-vs-base eligibility (no second copy to drift out of sync), and a Unique base
  that's a deliberate exception to an otherwise-generic building simply omits it from
  its own list — no special-case flag needed. See `data/bases/schema.json`.
`BaseInstance` holds everything that changes during a match:
```
BaseInstance {
  id,
  baseDefId,            // references BaseDef.id, e.g. "fort_irongrad"
  ownerId,              // nullable if neutral/unclaimed
  hqLevel,
  hexCoord,             // the base's map location
  populationCap,        // derived from Houses built at this base
  populationUsed,       // count of non-House buildings placed at this base (Walls excluded)
  buildings: [BuildingInstance...],
  walls: [Wall...]
}

Player {
  id,
  ownedBaseIds: [...],
  resources: { food, steel, fuel, stone, wood },
  maxSquads               // derived, see 4c — not stored, computed from owned bases' hqLevels
}
```
- When a base is captured, only `BaseInstance.ownerId` changes — every
  `BuildingInstance` underneath it (including its current HP/ruin state) carries over
  unchanged. This matches the earlier rule that capturing a base means inheriting
  everything already built there.
- Buildings don't carry their own `ownerId` — ownership is derived from the
  `BaseInstance` they belong to (`baseId`). This does **not** extend to standalone
  buildings (Road/Bridge/Dock/Tower/Landmine — see section 3) or to troops/squads (see below),
  which carry `ownerId` directly.
- **`resourceModifiers`** (on `BaseDef`) is a structured list, e.g. Capital's entry:
  ```
  resourceModifiers: [
    { scope: "building", buildingType: "oil_rig", multiplier: 0.5 }   // Capital's Oil Rig -50% penalty
  ]
  ```
  Applied multiplicatively, building-scoped entries first, then base-scoped (bases
  that carry both stack the same way) — see `03-resources.md`'s Oil Rig Notes for the
  worked example. Note: every current base's `resourceModifiers`/`costModifiers` entry
  is actually `scope: "building"` (e.g. Foundry Reach's +100% Steel is a
  `buildingType: "mine"` entry, not base-wide) — `scope: "base"` is supported by the
  schema but not yet used by any base. This replaces
  an earlier free-text `resourceBonus: "+50%..."` string, which couldn't represent a
  per-building-type exception without prose.
- **`isCapital`** (on `BaseDef`) is set once, at world-gen, and never changes — Capital
  status doesn't transfer or get "designated," it's a permanent property of that
  specific base type (see `00-overview.md`/`02-bases-and-buildings.md`). A player's
  `ownedBaseIds` can include any number of Capital bases simultaneously; the win check
  is simply "does one player's `ownedBaseIds` cover every `BaseInstance` whose
  `BaseDef.isCapital` is true."
- **Population** is tracked per-`BaseInstance`, not per-Player: `populationUsed`
  increments by 1 each time a non-House, non-HQ building is placed and decrements when
  one is destroyed/ruined; `populationCap` is derived from the level/count of House
  buildings at that base **plus HQ's own level-based contribution** (+2 capacity per
  HQ level — see `02-bases-and-buildings.md`'s Population section and
  `06-building-stats-and-defenses.md`'s HQ Upgrade Model). A new building placement is
  only valid if `populationUsed < populationCap` (or the building being placed is a
  House or HQ, neither of which consumes a slot).

### Garrisoned Troops Are Not Part Of The Base
**Resolved: troops are never "in" a `BaseInstance` — a garrison is just squads
standing near the base, each carrying its own `ownerId` on `TroopInstance`/
`SquadInstance` independent of `BaseInstance.ownerId`.** This means capturing a base
(via its HQ hitting 0 HP) does **not** flip ownership of any troops that were
defending it — surviving garrison/defending squads simply remain under their original
owner's control, still on the map, still able to keep fighting for the base back.
The only thing that changes on capture is `BaseInstance.ownerId` and everything
structurally attached to it (buildings, walls).
- **Elimination**: when a player's `ownedBaseIds` becomes empty (their last base's HQ
  falls), that player is eliminated and **every remaining `TroopInstance`/
  `SquadInstance` they own is removed from the game** — there's no ownerless army
  wandering the map after a full elimination.

### Starting Resources
Every player's `Player.resources` initializes to: **Food 100, Stone 100, Steel 50,
Wood 0, Fuel 0** — enough to fund a base's first Farm/Quarry-adjacent builds without
needing Wood (no Forest-adjacent Lumber Mill yet) or Fuel (no Oil Rig built yet) on
turn one. This lives on the per-match `Player` record shown above, **not** on any
account-level/meta-progression record — `ideas.txt`'s account-perks idea is an
explicitly later, separate system layered on top of match outcomes, not part of a
match's starting economy.

## 6. Map & Terrain Storage
```
Tile {
  hexCoord,
  terrainType,          // Plains / Forest / Hill / River / Ocean (Coast is not a distinct type — see 01-map-and-terrain.md)
  biomePatchId           // which forest/hill cluster this tile belongs to, if any
}
```
- **Rivers**: generated as a connected path of River-tagged tiles running from an
  interior source point to a coastline tile — e.g. via a constrained random walk or
  flow-simulation toward the nearest coast edge, marking tiles as River along the way.
  Generation is validated against the balance constraints already established (a river
  can't fully wall off a Capital's expansion paths).
- **Forest/Hill biomes**: generated via seed points + blob/flood-fill growth to a
  randomized patch size (small/medium/large), then stamped onto the tile grid —
  standard procedural terrain-clustering approach.

## 7. Resources — Storage & Tick
- Resources are a **shared pool per player**, not per-base — each base's production
  buildings feed into one pool on the `Player` record (see Base & Ownership above).
- **Tick interval: every 5 seconds.** At each tick:
  1. Sum production from all owned bases' resource buildings (Farm/Harbour/Quarry/
     Mine/Oil Rig/Lumber Mill, at their current level).
  2. Subtract upkeep (Food for all troops/bases; Fuel for moving vehicles and
     un-docked aircraft, per the fuel rules in `03-resources.md`).
  3. Apply the net delta to the player's resource pool.
  4. If a resource is in deficit, apply that resource's per-squad drain (one troop
     death per affected squad, per resource tick — see `03-resources.md`).
- This is fully automatic — no player action triggers a tick. Any real-time "counting
  up" shown in the UI between ticks is a visual interpolation only; the tick is the
  actual source of truth.
- A 5-second tick over a 40-minute match is 480 ticks total — frequent enough to feel
  responsive, coarse enough to keep the simulation/sync simple.

## 8. Simulation vs. Rendering (Multiplayer-Ready, Built Single-Player First)
- The game ships **single-player/local only** for now. Multiplayer is a real future
  goal, but networking code is **not** being built yet — instead, the architecture is
  kept clean enough that adding it later is an integration, not a rewrite.
- **Simulation and rendering are separate modules.** The simulation owns all game
  state (Player, BaseInstance, BuildingInstance, TroopInstance, SquadInstance,
  RegimentInstance, Wall, Tile, resource ticks, combat resolution, movement) and
  advances it by consuming a stream of **player actions** (move squad, place building,
  queue troop, focus-fire/attack-target order, board/unload cargo, demolish building,
  etc.) — it has no knowledge of the
  renderer, camera, or input devices. The rendering layer reads simulation state to
  draw it, and translates player input into that same action stream; it never mutates
  simulation state directly.
- **Local play today is a client and a "local server" running in the same process,
  talking through the same action-stream interface a real network connection would
  use later.** Swapping in real multiplayer means routing that action stream over a
  network (e.g. WebSocket) to a server running the same simulation module — the
  simulation logic itself shouldn't need to change.
- **Players are modeled as a list from the start** (`Player[]`), never a hardcoded
  singleton "the player" — trivial to enforce now, expensive to retrofit once game
  logic has singleton assumptions baked into it.
- This is an ongoing architectural discipline, not a scheduled milestone — there's no
  separate "multiplayer build" being deferred, just a boundary (simulation vs.
  rendering/input) that's cheap to maintain now and costly to introduce after the fact.

### Simulation Tick Rates
Two independent tick rates drive the simulation:
- **Resource/economy tick: every 5 seconds** (unchanged — see section 7). Coarse
  enough to keep the economy simple to reason about and sync.
- **Movement/combat tick: every 100ms (10 ticks/second).** This is the step rate for
  squad movement (`edgeProgress` advancement), auto-attack resolution, aura
  application, HP regen, and status-effect duration countdowns (freeze, deficit-drain,
  etc.) — fine enough to feel responsive for real-time positioning and combat, coarse
  enough to stay cheap to compute and (later) to network. Any smoother motion the
  player sees between ticks is rendering-layer interpolation only, same principle as
  the resource tick's "counting up" being visual-only (see section 7).

### Networking Model: Authoritative Server, Not Lockstep
**Recommendation: build toward an authoritative-server model, not deterministic
lockstep.** Reasoning:
- Lockstep requires every client to compute **bit-identical** state from the same
  inputs — any float drift, iteration-order difference, or timing edge case causes a
  silent desync that's notoriously hard to debug, and the whole simulation has to stay
  perfectly deterministic forever to keep working.
- Going hex-based for movement (section 4 above) removes the worst source of that
  drift (no continuous float positions to diverge), but full bit-exact determinism
  across independent clients is still a much stronger constraint than this game
  actually needs.
- An authoritative server is simply "the same local server this game already runs
  in-process" (see above), given a real network boundary: it owns the one true state,
  clients send actions and receive periodic state snapshots, and a client that falls
  behind or glitches can just resync from a snapshot instead of desyncing permanently.
- Hexis's scale (12-18 bases, squad-based unit counts, not the thousands-of-units
  scale where lockstep's bandwidth savings actually start to matter) means snapshot
  bandwidth is a non-issue — the case for lockstep is weakest exactly where this game
  sits.
- This changes nothing about the action-stream design above; it just means the future
  "server" is authoritative over state rather than merely relaying inputs.

## Open / Unresolved Items
- Whether a squad's `path`/`edgeProgress` needs a separate "facing" stored for
  visual/animation purposes, or if that's purely a rendering concern outside this
  schema.
- Exact list of what counts toward `activeBuffs` vs. what's computed live from terrain
  each frame without being stored as a discrete buff entry (e.g. is "standing on a
  hill" a stored buff, or just checked live off `currentHex`?).
