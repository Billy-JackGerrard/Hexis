# Bases & Buildings

## Base Types
- **Capital Base** (renamed from "Home Base"): one per player at match start. Capital
  status is **permanent and cumulative** — once a base is a Capital, it's always a
  Capital no matter who owns it. Capturing a rival's Capital gives you an *additional*
  Capital (its own Command Centre, its own bonus) rather than replacing/relocating
  yours — see `00-overview.md`'s Base Ownership Rules for the win-condition
  implications of this.
  - Unique unit access: only Capital Bases can train **Commander** troops, via the
    **Command Centre** building (see `04-combat.md` for how Commanders work).
- **Unique Base**: neutral city-states scattered across the map, each **genuinely
  unique** — at most one instance of each Unique base type exists on a given map (see
  `01-map-and-terrain.md`). Each has 1-2 unique buildings not available elsewhere, and
  its own troop roster. Before capture, a Unique base is already garrisoned — see
  Initial Garrison below. Capturing one means inheriting everything already built and
  standing there.

## Base Seeding
Every base (new or captured) starts with three pre-placed, mutually-adjacent buildings,
always sited on **Plains** (see `01-map-and-terrain.md`) regardless of base type:
- **HQ** — the core. Has its own HP like any other building, but destroying it doesn't
  remove it — it triggers a **capture**: when an HQ's HP hits 0, ownership of the whole
  base flips to whoever dealt the killing blow, and the HQ **respawns immediately at
  full HP** under its new owner. The HQ is never ruined or removed from the map —
  "destroying" it *is* how a base is captured. Every other building in the base
  (non-HQ, non-Wall) is immediately ruined by the capture itself, regardless of its
  own HP at the time — the new owner inherits the base's hexes/adjacency slots, not
  a working economy, and has to rebuild from there.
- **Farm** — Food.
- **Quarry** — Stone.

Every **Capital** additionally seeds a fourth pre-placed building on top of this
universal trio: a **Command Centre**, `isFixed` just like HQ (see Command Centre &
the Commander Cap below) — so a fresh Capital, and any Capital gained by capturing a
rival's, always already has one. It's never freshly built from a menu and can't be
demolished, only rebuilt from a ruin if destroyed.

## Initial Garrison (Unique Bases)
Unlike a player's Capital (which starts bare and is built up from scratch over the
match), a neutral **Unique base already has a working base built** when the match
starts:
- Its generic defenses (Turret, Missile Launcher) and its specialty defensive building
  (e.g. Grenade Turret, Flame Turret, Cold Turret) are already built.
- Its troop-production building(s) (e.g. Tank Plant, Wind Sanctuary) are already built.
- Its walls are already built.
- It holds a **standing garrison of troops** — only unit types that base's own
  production building(s) can actually make (e.g. Fort Irongrad starts garrisoned with
  Heavy Tanks, not infantry).
This makes Unique bases real early-game objectives worth fighting for, not a free
first building slot.

**Resolved: garrison troops are not part of the base and don't change hands on
capture.** Troops are never "inside" a base the way buildings are — a garrison is just
squads standing nearby, each with its own ownership independent of the base record
(see `07-data-architecture.md`). So when an HQ hits 0 HP and the base flips, any
surviving defending squads **remain under their original owner's control** and keep
fighting — capture only flips the base's buildings/walls, not troops caught defending
it. The one exception: if that base was the defender's **last** base, they're
eliminated on the spot and all their remaining troops/squads disappear from the map
(see `07-data-architecture.md`'s elimination rule) — there's no ownerless leftover army.

## Expansion Rule (Hex Adjacency)
- One building per hex tile.
- Buildings can only be placed on **Plains** tiles, with named exceptions:
  - **Treehouse**'s buildings can be placed on **Forest** tiles.
  - **Windy Peaks**' buildings can be placed on **Hill** tiles.
  - **Docks, Roads, Bridges** are placed on/adjacent to their relevant terrain
    (coast/river/forest) regardless of the plains rule, and aren't tied to a base at all.
  - **Water/Forest-adjacency requirements are a first-class schema field, not just
    prose**: Port/Shipyard require an adjacent Water tile and a Lumber Mill (outside
    Treehouse) requires an adjacent Forest tile via `placementRequirement` on the
    building definition (`data/buildings/schema.json`) — `siteTerrain` covers what the
    building's own hex must be (Plains, or Forest/Hill for Treehouse/Windy Peaks), and
    `adjacentTerrainRequired` covers a separate nearby-terrain requirement. These two
    checks combine with the two-adjacent-buildings and HQ-radius rules below; in
    practice a base with any water/forest-adjacent Plains hex at all can always satisfy
    every constraint at once since Houses are cheap and plentiful — a true placement
    dead-end isn't expected to occur, but the validator checks all constraints
    independently regardless.
- A new building must be placed on a hex adjacent to **two existing buildings**
  (or just **one** existing building if the new placement is a **Wall**). The seeded
  HQ/Farm/Quarry cluster satisfies the two-building rule for a base's first
  player-built building.
  - **Bridge exception**: without this, a base could never expand across a River —
    the far bank starts with zero adjacent buildings, so the two-adjacent-buildings
    rule could never be satisfied there. A new building placed adjacent to a **Bridge**
    is exempt from the two-adjacent-buildings requirement, **provided** there's already
    a building on the *other* side of that same Bridge (i.e. the base has a foothold on
    the near bank) — the Bridge itself functions as the connective link that stands in
    for the missing adjacent buildings on the far bank. Without an existing building on
    the near-bank end, the far bank still can't be reached this way (the Bridge alone
    doesn't seed a foothold from nothing).
- **Walls** are also the exception to "one building per hex" — they sit on the
  **border between two hexes**, not on a hex itself. A Wall **blocks movement and
  line-of-sight/projectiles** across the specific edge it occupies (pathfinding treats
  it as impassable; a ranged attack whose line crosses the edge is blocked) — Air units
  ignore Walls entirely, same as every other terrain rule (see
  `01-map-and-terrain.md`'s Movement & Positioning section).
- **Maximum build distance from HQ**: a base can only place buildings within a
  certain radius of its HQ. This radius is **not fixed — it scales with the HQ's
  upgrade level**, so upgrading the HQ is what unlocks room for the base to keep
  physically expanding outward. In practice this cap rarely matters on its own — the
  two-adjacent-buildings placement rule already forces a base to grow outward from its
  centre organically, hex by hex, so runaway/uncontrolled expansion isn't really
  possible regardless of how high the HQ level goes.
- **HQ level also gates the maximum level of every other building in the base**:
  a building cannot be upgraded past the HQ's current level (e.g. a Barracks can't
  reach level 3 while the HQ is still level 1). **Troop-production buildings** also
  have a separate cap, but it isn't a stored value — it's simply the **length of that
  building's own troop list** (level 1 unlocks the first troop, and so on). **Non-
  production buildings** (Farm, Quarry, Mine, Oil Rig, Walls, defensive buildings)
  have **no such cap at all** — they scale indefinitely via stat boosts per level,
  limited only by the HQ ceiling. See `06-building-stats-and-defenses.md` for the full
  breakdown, including the **HQ's own upgrade model** (non-production/formula-based,
  a deliberately steep cost curve, gated by a minimum population requirement per level
  on top of resource cost).
- **Building Unlock Levels**: separately from the upgrade-level ceiling above, HQ
  level also gates which building *types* are available to build at all — a base's
  `buildableBuildings` list (data/bases/schema.json) is still the sole source of truth
  for *which* building types a given base can ever build, but each building type now
  additionally carries its own `unlockHqLevel` (data/buildings/schema.json, default 1),
  and the base's HQ must be at least that level before that type appears as buildable.
  This is a property of the building type itself, not of the base — a Barracks needs
  HQ level 1 at every base that can build one at all. Checked by
  `BuildingPlacement.can_place`/`can_place_wall` (fresh construction) and
  `CommandProcessor.rebuild_building` (`Result.NOT_UNLOCKED` either way) — **a building
  that already exists (e.g. inherited by capturing a base) but is ruined while the
  HQ is below its unlock level cannot be rebuilt until the HQ reaches that level**, the
  same as if it had never been built. `isFixed`/`isStandalone` buildings (HQ, Command
  Centre, Ice Spire, Radar Array, Road, Bridge, Dock, Tower, Landmine) never carry this
  field — they're either pre-seeded-only or placed outside the base-menu flow entirely,
  so an HQ-level gate doesn't apply to them.

  | HQ level | Unlocks |
  |---|---|
  | 1 | Barracks, Farm, House, Lumber Mill, Mine, Quarry |
  | 2 | Harbour, Turret, Wood Turret, Flame Turret, Grenade Turret, Water Turret, Oil Rig, Stone Works, Wall, Port |
  | 3 | Missile Launcher, Cold Turret, EMP Turret, Wind Spire, Factory, Ford Yard, Forest Yard, Wind Sanctuary, Hangar, Hospital, Supply Depot, Sniper Turret |
  | 4 | Frostworks, Blazeworks, Covert Works, Covert Airfield, Demolition Plant, Iron Aviary, Salvage Works, Shipyard, Tank Plant |
- **Building construction is instant** (no build timers). **Buildings can be
  upgraded** (see `06-building-stats-and-defenses.md`) — **troops cannot be
  upgraded** once trained (see `05-troop-stat-schema.md`).

## Demolishing Buildings
**Resolved**: a player can voluntarily **demolish** a building they own (a new
`demolish_building` action — see `07-data-architecture.md`), distinct from a building
being destroyed in combat:
- **Refund**: demolishing refunds **50% of the total resources spent** on that
  building — its original build cost plus every upgrade cost paid to reach its current
  level (tracked live per instance as `totalResourcesSpent`, see
  `07-data-architecture.md`). This is a flat 50%, unlike the combat-destruction
  ruin-rebuild cost model in `06-building-stats-and-defenses.md`, which is a *cost to
  rebuild*, not a refund.
- **Immediate and clean**: unlike combat destruction (which leaves a ruin occupying
  the hex), demolishing frees the hex and the population slot immediately — the
  player can place something new there right away. This is the intended fix for a
  misplaced/regretted building, which combat-ruin rules alone don't provide.
- **`isFixed` buildings cannot be demolished** — HQ, Command Centre, Ice Spire, and
  Radar Array (and any future pre-seeded-only building) can never be freshly built
  from a menu, so voluntarily removing one would create a hole nothing can refill.
  The demolish action is simply not offered for them.
- Walls and standalone buildings (Road/Bridge/Dock/Tower/Landmine) can also be demolished under
  the same 50%-of-spend refund rule — consistent with them already deleting outright
  (no ruin) on combat destruction.

## Building Reference

The "Buildable at" column below is a *rule* (all bases, a terrain/adjacency
requirement, or one specific Unique base) where the rule is short and stable. For
buildings available at a hand-picked subset of bases with no single unifying rule
(Barracks, Hangar, Hospital), don't trust a hard-coded list here — it drifts as new
bases gain access (e.g. Hangar has since spread to more bases than originally
authored). Check that base's `buildableBuildings` array in `data/bases/*.json`,
which is the sole source of truth for building-vs-base eligibility (see
`data/bases/schema.json`).

| Building | Function | Buildable at |
|---|---|---|
| HQ | Base core (pre-seeded, capturable by destruction — see Base Seeding above) | All |
| Farm | Food | All |
| Harbour | Food (fishing boats) | Any base with a Water-adjacent tile |
| Quarry | Stone | All (costs **Steel** to build/upgrade — see `03-resources.md`) |
| Mine | Steel | All (costs **Stone** to build/upgrade — see `03-resources.md`) |
| Stone Works | Stone (mechanically a Quarry equivalent, steeper growth curve) | Foundry Reach only |
| Oil Rig | Fuel | All (Capital's Oil Rig has -50% production penalty; same cost everywhere, no inherent level cap on either — see `06-building-stats-and-defenses.md`) |
| House | Population capacity (does not itself consume a population slot) | All — see Population section below |
| Turret | Defense (generic) | All |
| Missile Launcher | Defense (generic) | All except Camp Cosy (deliberately lighter on fixed defense — see Camp Cosy below) |
| Barracks | Infantry | See `data/bases/*.json` — a hand-picked subset of bases, no unifying rule |
| Factory | Light land vehicles | Capital, Foundry Reach |
| Port | Navy (basic roster) | Any base with a water-adjacent tile |
| Tank Plant | Heavy tanks (full roster, builds 3-5 at a time) | Fort Irongrad only |
| Salvage Works | Juggernaut, Repair Truck, Granite Crumbler (heavy-armor sustainment subset) | Scrapyard only |
| Demolition Plant | Tank Obliterator, Earthshaker (rail gun/siege-artillery pair) | Camp Kaboom only |
| Grenade Turret | Defense — splash damage, cheap, short range/low damage | Fort Irongrad, Camp Kaboom |
| Blazeworks | Flamecopter, Plasmacopter | Tinder Box only |
| Flame Turret (renamed from Flamethrower) | Defense (fire) | Tinder Box only |
| Wind Sanctuary | Glider, Hot Air Balloon | Windy Peaks only (hill tiles) |
| Wind Spire | Defense — low damage, strong knockback, bonus damage vs. Air | Windy Peaks only (hill tiles) |
| Lumber Mill | Wood | Any base with a Forest-adjacent tile; Treehouse can additionally place it directly on Forest tiles (its specialty) |
| Forest Yard | Quad-bike | Treehouse only (forest tiles) |
| Iron Aviary | Wingfighter, Thunder | Sky Fortress only |
| Covert Airfield | Repair Drone, Cargocopter, Kleptocopter (support aircraft, all non-combat), Shadowcopter (stealth long-range harasser) | Cloudreach only |
| Hangar | Support — fuel-free aircraft landing/storage, hides docked squads from enemy vision/detection; also the required landing-hex for Cargocopter to board/unload Infantry cargo (see `04-combat.md`'s Cargo section and `05-troop-stat-schema.md`) | See `data/bases/*.json` — a hand-picked, growing subset of bases, no unifying rule |
| Command Centre | Commander | Capital only |
| Hospital | Support — heals nearby friendly troops slowly (passive aura, no production) | See `data/bases/*.json` — a hand-picked subset of bases, discounted at Camp Cosy (see Camp Cosy below) |
| Supply Depot | Engineer, Ambulance, Transport Truck, Repair Truck, Mule, Volt Truck (support vehicles, all non-combat) | Camp Cosy only |
| Shipyard (renamed from Harbour) | Full navy incl. Aircraft Carrier; base carries a +50% Harbour production bonus | Kraken Point only |
| Dock | Ship landing point (no production) | Anywhere adjacent to Ocean or River (sits on the adjoining Plains hex, not on the water tile itself — same siteTerrain/adjacency shape as Port), Engineer-built, not tied to a base. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Road | Unblocks Forest tiles for land vehicles | Anywhere in Forest, Engineer-built |
| Bridge | Unblocks River tiles for infantry & land vehicles | Anywhere on River, Engineer-built. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Tower | Standalone defense + long-range fog-of-war clearing + short-range stealth detection (`detector: true`, `detectionRange: 3`) | Anywhere, Engineer-built, not tied to a base. Buildable in Stone or Wood — see `06-building-stats-and-defenses.md` for the two variants |
| Walls | Defense — sits on hex border. Tiers: Wood (cheapest/weakest, vulnerable to flame troops) / Stone (mid) / Steel (priciest/strongest, flat armor 5) | All (Wood tier requires access to Wood, produced by any base's Lumber Mill) |
| Ice Spire | Aura — slows nearby enemy troops | Winter Forge only — **fixed/pre-seeded, cannot be freshly built** (see below) |
| Cold Turret | Defense — ice bombs, medium-low range, low damage, freezes target briefly on hit | Winter Forge only |
| Frostworks | Heavy tanks (partial roster — a subset of Tank Plant's) | Winter Forge only |
| Radar Array | Support — extends this player's vision range map-wide; reveals stealthed units at its own full (long) vision range | Signal Ridge only — **fixed/pre-seeded, cannot be freshly built** (same as Ice Spire, so its global vision bonus can't be stacked) |
| Covert Works | Ghost Tank, Disruptor | Signal Ridge only |
| EMP Turret | Defense — low damage, immobilizes Land vehicles, destroys Air troops outright (except Hot Air Balloon/Glider) | Signal Ridge, Camp Kaboom |
| Ford Yard | Amphibious Raider, Submarine | Rivergate only |
| River Battery | Defense — bonus damage vs. Naval targets | Rivergate only |

- Every base type can build **Turret**; every base except Camp Cosy can also build
  **Missile Launcher** (Camp Cosy deliberately omits it — see Camp Cosy below). Each
  Unique base's specialty defense building is in addition to these.
- Wood is no longer capture-gated: any base with a Forest-adjacent tile can build its
  own Lumber Mill and produce Wood independently, the same way Port works off water
  adjacency. Capturing a Treehouse is no longer required to unlock Wood — see
  `03-resources.md`.
- **Harbour**: a Food **Resource**-category building — mechanically a Farm, just
  gated behind the same water-adjacency requirement as Port (`placementRequirement:
  {siteTerrain: Plains, adjacentTerrainRequired: Water}` — see
  `data/buildings/schema.json`), not a separate production chain. "Fishing boats" are
  purely a visual — the building's level determines how many boat sprites are shown
  at that hex, the same way a level shows up as a bigger farm plot or a taller mine;
  there's no separate fishing-boat unit/entity to produce, upkeep, or lose in combat.
  Destroying the Harbour building itself is the sabotage target, same as a Farm. (This
  reuses the name "Harbour," which Kraken Point's building was called before it was
  renamed to Shipyard — the two are unrelated buildings; see Kraken Point below.)
  - **Deliberately steep growth curve**: a single boat produces noticeably less Food
    than a Farm at the same level — but the boat count itself scales hard per level
    (level 1 = 1 boat, level 2 = 2 boats, and so on, roughly doubling), so a
    fully-upgraded Harbour ends up out-producing a fully-upgraded Farm despite the
    weaker per-boat baseline. This means Harbour's `stat_growth.foodOutput` (see
    `06-building-stats-and-defenses.md`'s Upgrade Data Model) should be tuned as a
    much steeper compounding curve than Farm's — a deliberate design intent to record
    now, not just a default to copy from Farm's numbers at balancing time.
- **Stone Works**: the same Harbour pattern applied to Stone instead of Food — a
  Resource-category building mechanically equivalent to Quarry (same steep,
  compounding growth curve as Harbour vs. Farm), but gated by **base eligibility**
  (Foundry Reach only) rather than a terrain/adjacency requirement. It stacks with
  Foundry Reach's own +100% Steel bonus (see Foundry Reach below) to make that base
  a strong dual resource-economy target, not just a Steel one.
- **Standalone buildings (Road, Bridge, Dock, Tower, Landmine) own themselves, and don't ruin.**
  Since they aren't tied to a base, they carry an `ownerId` directly instead of
  deriving ownership from a `BaseInstance` (see `07-data-architecture.md`) — this is
  who a Tower fires for, and who gets rebuild rights. Roads/Bridges/Docks stay
  **public to use** regardless of who owns them. And like a Wall, a standalone
  building at 0 HP is **deleted outright**, not turned into a ruin — rebuilding it is
  a fresh build at full cost, never a discounted ruin-rebuild.

## Command Centre & the Commander Cap
**Resolved: Command Centre is `isFixed`**, same pattern as HQ — every Capital is
pre-seeded with exactly one at level 1 (see Base Seeding above), it's never freshly
built from a menu even after capture, and it cannot be voluntarily demolished (only
rebuilt from a ruin if destroyed in combat). This is deliberate: unlike a generic
Production building (no cap on how many you can build — see Building Reference
above), Command Centre's level directly grows a player-wide cap (below), so letting
a player freely build extra ones in a single base would let commander-cap growth be
farmed by population/hex-tile spend alone rather than by capturing more Capitals.

**Resolved**: the Command Centre does **not** use the standard production-building
model (one troop unlocked per level, max level = `length(troopList)`). Commanders are
a small named roster split into three **tiers** — `common` / `rare` / `epic` (a field on
the Commander's own troop definition, see `05-troop-stat-schema.md`) — and the Command
Centre's level unlocks a whole tier at once, not one Commander at a time:

- **Level 1**: unlocks every `common`-tier Commander (plural, all at once) and
  contributes **1** slot toward the player's Commander cap (below).
- **Level 2**: unlocks every `rare`-tier Commander, in addition to `common`.
- **Level 3**: unlocks every `epic`-tier Commander, in addition to `common`/`rare` — the
  full roster is now trainable at this Command Centre.
- Implemented: the Commander roster (`commander_vanguard` (`common`), `commander_nightfall`
  (`rare`), `commander_warden` (`epic`)) carries `commanderTier`/`Commander` tag per
  `05-troop-stat-schema.md`, and `CommandProcessor.enqueue_production` rejects
  (`Result.NOT_UNLOCKED`) queuing a Commander whose tier isn't yet unlocked at the
  Command Centre's current level (`CommanderProgression.tier_unlocked`) — same
  check gates a standard Production building's `productionUpgradeLevels.unlocks`.
- **Level 4 and beyond**: no further unlocks (all tiers are already available) — each
  additional level is pure stat growth (HP, following the standard non-production
  growth-curve model) **plus +1 Commander-cap slot per level**.
- See `06-building-stats-and-defenses.md`'s Command Centre section for the exact data
  shape (`commanderProgression`), and `data/buildings/schema.json`.

**Commander cap (a player-wide value, separate from the global squad cap)**:
- A player's maximum simultaneous Commanders = the **sum of every owned Command
  Centre's current commander-slot contribution** (1 per Command Centre at levels 1-3,
  then +1 per level from level 4 onward — see above). A fresh player with one level-1
  Capital can field **1** Commander at a time; capturing a second player's Capital
  (with its own Command Centre) adds that Command Centre's slots on top — e.g. two
  level-1 Command Centres together allow **2** simultaneous Commanders.
- Since each Commander is also its own squad (`max_squad_size: 1`), producing one
  consumes both a Commander-cap slot **and** a global squad-cap slot simultaneously —
  a Command Centre's queue is blocked from starting a new Commander if *either* cap is
  currently full (see `07-data-architecture.md`'s production-queue-pause rule).
- **Losing a Command Centre** (its Capital is captured or falls) immediately lowers the
  Commander cap. If the player is now *over* the new cap, existing Commanders are
  **not** killed or forcibly removed — they keep fighting normally. The player simply
  can't train another Commander at any Command Centre until their live Commander count
  drops back under the (now-lower) cap.

## Unique Bases (defined so far)

Each entry below is the *identity* and non-obvious design rationale for that base —
the exact buildable list, initial buildings/garrison, and any `resourceModifiers`/
`costModifiers` numbers all live in that base's own `data/bases/<id>.json`, which is
self-contained on purpose (see its schema's description) and is the source of truth;
don't re-derive those specifics from this section, and don't add them here when
authoring a new base — extend the JSON and add only the "why" here if there is one.

### Fort Irongrad
Heavy armor specialist. Tank Plant is the most complete source of heavy tanks, but not
the only one — Winter Forge's Frostworks and Scrapyard's Salvage Works (below) also
build subsets of the same roster, and heavy-tank access is expected to keep spreading
to more bases over time.

### Tinder Box
Incendiary air power specialist. Its defense building is called **Flame Turret**,
renamed from Flamethrower specifically to avoid colliding with the Barracks infantry
unit of the same name (see `08-troop-roster.md`).

### Windy Peaks
Ground-support/recon aircraft specialist. Found on hills; its buildings can be placed
on hill tiles. **Wind Sanctuary** merges what would otherwise be a separate Air
Factory and Iron Aviary into one building. **Wind Spire** is a Turret variant that
trades raw damage for control (knockback) plus a large bonus vs. Air.

### Treehouse
Forest/infantry/economy specialist; its buildings can be placed on forest tiles. Wood
is no longer capture-gated — any base with a Forest-adjacent tile can build its own
Lumber Mill, so Treehouse is no longer the sole route to Wood, just the base that can
site its Lumber Mill directly on Forest. Only one Treehouse exists on a given map (see
`01-map-and-terrain.md`), same as every Unique base type.

### Kraken Point (renamed from Atlantis)
Naval capstone, found along the map's ocean edge. Its production building is
**Shipyard** — renamed from Harbour after an unrelated, later-introduced building
reused that name for a Farm-equivalent (see the Harbour building above; the two are
unrelated). Aircraft Carriers can *hold* most air troops fuel-free without producing
them, and can launch stored aircraft mid-battle, not just while idle (see
`05-troop-stat-schema.md`'s `can_launch_cargo_mid_combat` field).

### Sky Fortress
Elite air-superiority specialist — the pure air-combat counterpart to Windy Peaks'
scouting/ground-support focus. Generated with a **Moat**: a ring of water terrain
around the base that blocks Land and Naval approach (Air ignores it, like every other
terrain restriction) — this is a world-gen/terrain feature, not a `BaseDef` field.

### Winter Forge
Cold/ice specialist — a second, partial route into heavy armor, plus area control via
slow/freeze effects. Its **Ice Spire** is a pure-aura structure (not production or
defensive) and is fixed/pre-seeded — see Fixed/Unique Structures below. **Frostworks**
building a subset of the Heavy Tank roster was the first case of a troop type split
across more than one building/base (see `08-troop-roster.md`).

### Foundry Reach
Economic specialist — the first Unique base built entirely around resource output
rather than a troop roster. Because it can never out-produce a dedicated combat base
on troops, its value is largely in *capturing* it — denying/gaining its doubled Steel
output plus Stone Works is a bigger incentive than sabotaging a single building would
be (echoes the Food/Fuel deficit pillar in `00-overview.md`).

### Signal Ridge
Stealth-detection and electronic-warfare specialist. Its **Radar Array** is the first
building whose effect isn't local to its own base (map-wide vision), and is
fixed/pre-seeded — same reasoning as Ice Spire, so its global bonus can't be stacked.
Its **EMP Turret** destroys Air-domain troops outright rather than just damaging them,
except troops flagged `empImmune` (Hot Air Balloon, Glider — unpowered/non-electronic).

### Rivergate
River-crossing specialist — the first Unique base whose identity comes from River
adjacency rather than Forest or Hills (still seeded on Plains, like every base). Its
**River Battery** exists because rivers are naval-passable all the way inland (see
`01-map-and-terrain.md`) — without it, an enemy fleet could sail straight past a river
base uncontested.

### Camp Cosy
Logistics/support specialist — the first Unique base built around sustaining an army
rather than fighting or producing resources. Supply Depot's entire roster is
non-combat, so Barracks is included specifically so the base isn't a total pushover
garrison-wise; deliberately no Missile Launcher, keeping its fixed defenses lighter
than other Unique bases. No specialty defense building and no output bonus — its
identity is entirely the Hospital/Wall cost discounts plus Supply Depot's roster.

### Cloudreach
Air-logistics/covert-resupply specialist — the aerial mirror of Camp Cosy. Covert
Airfield's roster is mostly non-combat (Shadowcopter is the one combat-capable
unlock, but low HP and a squad cap of 2 make it a harasser, not a defender), so
Barracks is included for the same reason as Camp Cosy — but Cloudreach keeps the
standard Turret + Missile Launcher pairing rather than going lighter. Hangar is
pre-seeded alongside Covert Airfield rather than left as an optional build, since
Cargocopter can't board/unload Infantry without one nearby.

### Scrapyard
Heavy-armor sustainment specialist — the field-repair counterpart to Fort Irongrad's
raw production. Its **Salvage Works** builds Juggernaut and Granite Crumbler alongside
Repair Truck, keeping its own heavy squads running without relying on Camp Cosy;
Granite Crumbler was previously Fort Irongrad-exclusive and Repair Truck previously
Camp Cosy-exclusive, so this is the first base to pull a troop out of two different
prior single-source buildings into one roster. No specialty defense building — relies
on generic Turret/Missile Launcher plus Walls, same as Kraken Point/Windy Peaks/Sky
Fortress.

### Camp Kaboom
Heavy-artillery specialist — the most extreme "skips a tier" base yet: no Barracks
and no Factory at all, so it fields **no infantry and no light vehicles** whatsoever
(Camp Cosy and Cloudreach at least kept a Barracks for baseline self-defense; Camp
Kaboom doesn't). Its **Demolition Plant** unlocks **Tank Obliterator** at level 1
and **Earthshaker** at level 2 — two heavy tanks found nowhere else in the roster
(see `08-troop-roster.md`). Fixed defenses double down on the explosives theme
instead of the standard Turret/Missile Launcher-only baseline: **Grenade Turret**
(previously Fort Irongrad-exclusive) and **EMP Turret** (previously Signal
Ridge-exclusive) are both buildable here too, alongside the usual Turret/Missile
Launcher/Walls. Starts with a heavy garrison from turn one (2 Earthshaker + 2 Tank
Obliterator squads) rather than the lighter infantry garrisons other Unique bases
open with, since it has no infantry to garrison with in the first place.

## Building Categories
Every building falls into one of five categories, which determines whether it needs
player input to function or just runs on its own once built:

| Category | Examples | Requires player action? |
|---|---|---|
| **Production** | Barracks, Factory, Port, Tank Plant, Frostworks, Blazeworks, Wind Sanctuary, Forest Yard, Shipyard, Iron Aviary, Command Centre, Covert Works, Ford Yard, Supply Depot | **Yes** — the player must pick a troop from the building's roster to queue; nothing is produced until a choice is made |
| **Resource** | Farm, Quarry, Mine, Oil Rig, Lumber Mill, Harbour, Stone Works | No — ticks automatically every resource tick (see `07-data-architecture.md`) |
| **Defensive** | Turret, Missile Launcher, Grenade Turret, Flame Turret, Cold Turret, River Battery, Wind Spire, EMP Turret, Walls, Tower | No — auto-fires on any enemy troop that enters range, same as troops (see `04-combat.md`) |
| **Support** | Hospital, Ice Spire, House, Radar Array, Hangar | No — passively applies its effect (healing / aura / population capacity / vision) with no queue or target selection involved |
| **Infrastructure** | Road, Bridge, Dock | No — passive, but must be placed by an Engineer rather than built from a base's menu |

- This is why Production buildings are the only ones with a visible **queue** in the
  build UI (see `09-ui-and-controls.md`) — every other category is "place it and it
  works," with no further per-building decisions after construction/upgrades.

## Population
- **Every building placed at a base consumes 1 population slot**, except **House**,
  which instead *grants* population capacity (and doesn't consume a slot itself), and
  **HQ**, which also doesn't consume a slot and — **resolved** — *also* grants
  population capacity, the same way House does: **+2 capacity per HQ level** (level 1
  grants 2, level 2 grants 4, etc. — see `06-building-stats-and-defenses.md`'s HQ
  Upgrade Model and `data/buildings/hq.json`). A base's total `populationCap` is
  therefore House contributions **plus** HQ's own level-based contribution, not House
  alone.
- If a base's population is at capacity, no further buildings can be placed there —
  **other than House**. Building a House (or upgrading an existing one, which
  increases its capacity contribution further), or upgrading HQ, are the ways to keep
  expanding once capped.
- Population is tracked **per base** (it's what gates that base's own building count),
  not as a shared player-wide pool — see `03-resources.md` and
  `07-data-architecture.md` for how it's stored and ticked.
- Walls don't consume population (they sit on hex borders, not on a building hex).

## Fixed / Unique Structures
A small category of buildings are **pre-seeded only** — they exist because a specific
base was generated with them already built, and a player can never construct a fresh
one from the build menu, even after capturing that base:
- **HQ** — never built by a player at all; always pre-seeded (see Base Seeding above).
- **Ice Spire** (Winter Forge) — if destroyed, it becomes a ruin like any other
  building and can be **rebuilt** at the usual ruin discount (see
  `06-building-stats-and-defenses.md`), but a Winter Forge that somehow lost its Ice
  Spire entirely (or any other base) can never have a first one freshly constructed.
- **Radar Array** (Signal Ridge) — same rule as Ice Spire: ruins and can be rebuilt at
  the usual discount, but never freshly built beyond the one pre-seeded copy. This one
  matters for balance, not just flavor: its `globalVisionRangeBonus` is a map-wide,
  scaling effect (unlike Tower's local-only stealth detection — see
  `06-building-stats-and-defenses.md`), so capping it at exactly one prevents a player
  from stacking several inside Signal Ridge's own footprint.
This is distinct from ordinary specialty *production* buildings (Tank Plant, Wind
Sanctuary, Frostworks, etc.), which remain normal player-buildable buildings — including
multiple copies at the same base, same as Barracks — once that base is owned. Which
other buildings (if any) should join this fixed/unique category is a per-building
design call to make as more Unique bases are authored.

## Open / Unresolved Items
- **Resolved: not every Unique base gets a specialty defensive building.** Sky Fortress
  (and any future Unique base without one authored) simply relies on the two generic
  defenses every base gets (Turret, Missile Launcher) — a specialty defense building is
  a bonus some Unique bases have, not a requirement all of them need. This was never a
  gap to fill, just an assumption to drop. Windy Peaks has since gained its own
  specialty defense, Wind Spire (see Windy Peaks above).
