# Bases & Buildings

## Base Types
- **Capital Base** (renamed from "Home Base"): one per player at match start. Capital
  status is **permanent and cumulative** — once a base is a Capital, it's always a
  Capital no matter who owns it. Capturing a rival's Capital gives you an *additional*
  Capital (its own Command Centre, its own bonus) rather than replacing/relocating
  yours — see `00-overview.md`'s Base Ownership Rules for the win-condition
  implications of this.
  - Bonus: **+50% resource production**.
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
  "destroying" it *is* how a base is captured.
- **Farm** — Food.
- **Quarry** — Stone.

## Initial Garrison (Unique Bases)
Unlike a player's Capital (which starts bare and is built up from scratch over the
match), a neutral **Unique base already has a working base built** when the match
starts:
- Its generic defenses (Turret, Missile Launcher) and its specialty defensive building
  (e.g. Grenade Tower, Flame Turret, Cold Turret) are already built.
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
- **`isFixed` buildings cannot be demolished** — HQ and Ice Spire (and any future
  pre-seeded-only building) can never be freshly built from a menu, so voluntarily
  removing one would create a hole nothing can refill. The demolish action is simply
  not offered for them.
- Walls and standalone buildings (Road/Bridge/Dock/Tower) can also be demolished under
  the same 50%-of-spend refund rule — consistent with them already deleting outright
  (no ruin) on combat destruction.

## Building Reference

| Building | Function | Buildable at |
|---|---|---|
| HQ | Base core (pre-seeded, capturable by destruction — see Base Seeding above) | All |
| Farm | Food | All |
| Harbour | Food (fishing boats) | Any base with a Water-adjacent tile |
| Quarry | Stone | All (costs **Steel** to build/upgrade — see `03-resources.md`) |
| Mine | Steel | All (costs **Stone** to build/upgrade — see `03-resources.md`) |
| Oil Rig | Fuel | All (Capital's Oil Rig has -50% production penalty; same cost everywhere, no inherent level cap on either — see `06-building-stats-and-defenses.md`) |
| House | Population capacity (does not itself consume a population slot) | All — see Population section below |
| Turret | Defense (generic) | All |
| Missile Launcher | Defense (generic) | All |
| Barracks | Infantry | Capital, Treehouse |
| Factory | Light land vehicles | Capital, Foundry Reach |
| Port | Navy (basic roster) | Any base with a water-adjacent tile |
| Tank Plant | Heavy tanks (full roster, builds 3-5 at a time) | Fort Irongrad only — **fixed/pre-seeded, cannot be freshly built** (see below) |
| Grenade Tower | Defense — splash damage, cheap, short range/low damage | Fort Irongrad only |
| Fire Helipad | Flame Helicopter, Plasma Helicopter | Firebase only |
| Flame Turret (renamed from Flamethrower) | Defense (fire) | Firebase only |
| Wind Sanctuary | Hot Air Balloon, Glider | Windy Peaks only (hill tiles) |
| Lumber Mill | Wood | Any base with a Forest-adjacent tile; Treehouse can additionally place it directly on Forest tiles (its specialty) |
| Quad Hangar | Quad-bike | Treehouse only (forest tiles) |
| Hangar | Wingfighter, Falcon | Sky Fortress only |
| Command Centre | Commander | Capital only |
| Hospital | Support — heals nearby friendly troops slowly (passive aura, no production) | All |
| Shipyard (renamed from Harbour) | Full navy incl. Aircraft Carrier; aura boosts this base's own Harbour building | Kraken Point only |
| Dock | Ship landing point (no production) | Anywhere adjacent to Ocean or River (sits on the adjoining Plains/Forest/Hill hex, not on the water tile itself), Engineer-built, not tied to a base. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Road | Unblocks Forest tiles for land vehicles | Anywhere in Forest, Engineer-built |
| Bridge | Unblocks River tiles for infantry & land vehicles | Anywhere on River, Engineer-built. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Tower | Standalone defense + long-range fog-of-war clearing | Anywhere, Engineer-built, not tied to a base. Buildable in Stone or Wood — see `06-building-stats-and-defenses.md` for the two variants |
| Walls | Defense — sits on hex border. Tiers: Wood (cheapest/weakest, vulnerable to flame troops) / Stone (mid) / Steel (priciest/strongest) | All (Wood tier requires access to Wood, produced by any base's Lumber Mill) |
| Ice Spire | Aura — slows nearby enemy troops; buffs this base's own Oil Rigs | Winter Forge only — **fixed/pre-seeded, cannot be freshly built** (see below) |
| Cold Turret | Defense — ice bombs, medium-low range, low damage, freezes target briefly on hit | Winter Forge only |
| Hot Forge | Heavy tanks (partial roster — a subset of Tank Plant's) | Winter Forge only |
| Smeltery | Resource — doubles this base's Steel output | Foundry Reach only |
| Radar Array | Support — extends this player's vision range map-wide; reveals stealthed units within its own range | Signal Ridge only |
| Covert Works | Ghost Tank, Disruptor | Signal Ridge only |
| Ford Yard | Amphibious Raider | Rivergate only |
| River Battery | Defense — bonus damage vs. Naval targets | Rivergate only |

- Every base type (Capital and all Unique) can build the two generic defenses
  (**Turret**, **Missile Launcher**); each Unique base's specialty defense building is
  in addition to these.
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
- **Standalone buildings (Road, Bridge, Dock, Tower) own themselves, and don't ruin.**
  Since they aren't tied to a base, they carry an `ownerId` directly instead of
  deriving ownership from a `BaseInstance` (see `07-data-architecture.md`) — this is
  who a Tower fires for, and who gets rebuild rights. Roads/Bridges/Docks stay
  **public to use** regardless of who owns them. And like a Wall, a standalone
  building at 0 HP is **deleted outright**, not turned into a ruin — rebuilding it is
  a fresh build at full cost, never a discounted ruin-rebuild.

## Command Centre & the Commander Cap
**Resolved**: the Command Centre does **not** use the standard production-building
model (one troop unlocked per level, max level = `length(troopList)`). Commanders are
a small named roster split into three **tiers** — `basic` / `rare` / `best` (a field on
the Commander's own troop definition, see `05-troop-stat-schema.md`) — and the Command
Centre's level unlocks a whole tier at once, not one Commander at a time:

- **Level 1**: unlocks every `basic`-tier Commander (plural, all at once) and
  contributes **1** slot toward the player's Commander cap (below).
- **Level 2**: unlocks every `rare`-tier Commander, in addition to `basic`.
- **Level 3**: unlocks every `best`-tier Commander, in addition to `basic`/`rare` — the
  full roster is now trainable at this Command Centre.
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

### Fort Irongrad
- Heavy armor specialist.
- **Tank Plant**: builds the full Heavy Tank roster; Capital's Factory only makes light
  vehicles. Winter Forge's Hot Forge (below) also builds a subset of this roster, so
  Fort Irongrad is the most complete source of heavy armor but no longer the *only*
  source — heavy-tank access will keep spreading across more Unique bases over time as
  the roster grows.
- **Grenade Tower** (defense): cheap, short range, low damage, splash.

### Firebase
- Incendiary air power specialist.
- **Fire Helipad**: builds Flame Helicopter (short range, high splash, fire damage) and
  Plasma Helicopter (bigger, slower, longer range, explosive impact damage).
- **Flame Turret** (defense) — renamed from Flamethrower to avoid colliding with the
  Barracks infantry unit of the same name (see `08-troop-roster.md`).

### Windy Peaks
- Ground-support and reconnaissance aircraft specialist. Found on hills; its buildings
  can be placed on hill tiles.
- **Wind Sanctuary** (merged Air Factory + Hangar into a single building): builds
  Hot Air Balloon (cheap, high splash, low range, ground/naval targets only,
  slow-moving, modest Fuel upkeep) and Glider (fast scouting air unit, cannot attack at all, cheap, uses no Fuel at all — being unpowered, it draws Food upkeep instead,
  like infantry).

### Treehouse
- Forest/infantry/economy specialist. Found in a large forest biome; its buildings can
  be placed on forest tiles.
- **Barracks** (standard infantry — shared building type with Capital).
- **Lumber Mill**: produces Wood. Treehouse can place its Lumber Mill directly on
  Forest tiles (its specialty); any other base can also build a Lumber Mill if it has
  a Forest-adjacent tile (see Building Reference above) — Wood is no longer exclusive
  to holding a Treehouse.
- **Quad Hangar**: builds Quad-bike (fast, forest-capable — ignores the forest
  vehicle-block rule — low armor/damage).
- Only **one Treehouse** exists on a given map (see `01-map-and-terrain.md`) — like
  every Unique base type, it's a genuinely unique, non-repeating base.

### Kraken Point (renamed from Atlantis)
- Naval capstone. Found along the map's ocean edge.
- **Shipyard** (renamed from Harbour — an unrelated, later-introduced building has
  since reused that name for a Farm-equivalent, see Harbour above): builds everything
  Port can, plus larger/advanced ships, topping out at the **Aircraft Carrier**. Also
  carries an aura boosting this base's own **Harbour** building's Food output, the
  same aura pattern as Winter Forge's Ice Spire buffing its base's Oil Rigs (see
  `05-troop-stat-schema.md`'s auras field) — making Kraken Point a strong Food-economy
  base as well as a military one, provided it has a Harbour built.
- Aircraft Carriers can *hold* most air troops (they don't consume fuel while docked
  there) but do not produce them. **Resolved**: they can launch stored aircraft
  mid-battle, not just while idle — see `05-troop-stat-schema.md`'s
  `can_launch_cargo_mid_combat` field.

### Sky Fortress
- Elite air-superiority specialist — the pure air-combat counterpart to Windy Peaks'
  scouting/ground-support focus.
- **Hangar**: builds **Wingfighter** (fast, rapid-fire machine guns, low damage
  against buildings/walls — an anti-troop dogfighter, not a siege unit) and
  **Falcon** (slower, heavier armored, missile-armed — the harder-hitting,
  slower-to-lose alternative).

### Winter Forge
- Cold/ice specialist — a second, partial route into heavy armor, plus area
  control via slow and freeze effects.
- **Ice Spire**: not a production or defensive building — a pure aura structure.
  Carries two simultaneous auras: slows nearby *enemy* troops (a debuff aura, unlike
  the friendly-only auras seen so far — see `05-troop-stat-schema.md`), and buffs the
  output of all Oil Rigs at this base (an aura that targets a friendly *building* type
  rather than friendly troops). **Fixed/pre-seeded, cannot be freshly built** — see
  below.
- **Cold Turret** (defense): ice bombs, medium-low range, low damage, but **freezes**
  its target for a couple seconds on hit (target can't move or attack while frozen) —
  a crowd-control defense rather than a raw-damage one.
- **Hot Forge**: builds a **subset** of the Heavy Tank roster (not the full list Fort
  Irongrad's Tank Plant offers) — the first case of a troop type being split across
  more than one building/base; see `08-troop-roster.md`.

### Foundry Reach
- Economic specialist — the first Unique base built entirely around resource output
  rather than a troop roster. No terrain exception; it's sited on Plains like Fort
  Irongrad, Firebase, Sky Fortress, and Winter Forge.
- **Smeltery**: doubles this base's Steel output. That's its only unique building —
  Foundry Reach has no specialty production building at all. Its sole offensive/
  defensive option beyond the generic Turret/Missile Launcher is a **Factory**
  (Capital, Foundry Reach), the same light-vehicle roster a Capital gets.
- Because it can never out-produce a dedicated combat base, Foundry Reach's value is
  in what happens to your economy if you lose it — crippling a rival's Steel supply
  here is as valid a target as their army, echoing the Food/Fuel deficit pillar in
  `00-overview.md`.

### Signal Ridge
- Stealth-detection and electronic-warfare specialist. No terrain exception; sited on
  Plains.
- **Radar Array**: extends this player's vision range map-wide and reveals stealthed
  units within its own range — the first building whose effect isn't local to its own
  base.
- **Covert Works**: builds **Ghost Tank** (stealth armor — visible to non-detectors
  only at very short range, visible to `detector` units like Sniper at their normal
  vision range, and it breaks its own stealth the instant it fires — see
  `05-troop-stat-schema.md`'s `reveals_on_attack` flag) and **Disruptor** (an EW
  troop, not a building — while alive it projects an `enemy_buildings`-targeted aura
  that suppresses enemy defensive buildings' targeting within its radius; killing the
  Disruptor immediately restores them). See `08-troop-roster.md` for full stats.
- No specialty defensive building — Signal Ridge relies on the generic Turret/Missile
  Launcher plus its production roster.

### Rivergate
- River-crossing specialist — the first Unique base whose identity comes from
  adjacency to River terrain rather than Forest or Hills. It's still seeded on Plains
  like every other base (see Base Seeding above); no buildings are ever placed on the
  river itself.
- **Ford Yard**: builds **Amphibious Raider** — a light *vehicle* (not infantry) that
  ignores the River-blocked movement rule, fording rivers directly without needing a
  Bridge. See `08-troop-roster.md`.
- **River Battery** (defense): a Turret variant with bonus damage against **Naval**
  targets. Rivers are naval-passable all the way inland from the sea (see
  `01-map-and-terrain.md`), so without this, an enemy fleet could otherwise sail
  straight past a river base uncontested — River Battery is what makes holding
  Rivergate matter for denying that route, not just for the Amphibious Raider.

## Building Categories
Every building falls into one of five categories, which determines whether it needs
player input to function or just runs on its own once built:

| Category | Examples | Requires player action? |
|---|---|---|
| **Production** | Barracks, Factory, Port, Tank Plant, Hot Forge, Fire Helipad, Wind Sanctuary, Quad Hangar, Shipyard, Hangar, Command Centre, Covert Works, Ford Yard | **Yes** — the player must pick a troop from the building's roster to queue; nothing is produced until a choice is made |
| **Resource** | Farm, Quarry, Mine, Oil Rig, Lumber Mill, Smeltery | No — ticks automatically every resource tick (see `07-data-architecture.md`) |
| **Defensive** | Turret, Missile Launcher, Grenade Tower, Flame Turret, Cold Turret, River Battery, Walls, Tower | No — auto-fires on any enemy troop that enters range, same as troops (see `04-combat.md`) |
| **Support** | Hospital, Ice Spire, House, Radar Array | No — passively applies its effect (healing / aura / population capacity / vision) with no queue or target selection involved |
| **Infrastructure** | Road, Bridge, Dock | No — passive, but must be placed by an Engineer rather than built from a base's menu |

- This is why Production buildings are the only ones with a visible **queue** in the
  build UI (see `09-ui-and-controls.md`) — every other category is "place it and it
  works," with no further per-building decisions after construction/upgrades.

## Population
- **Every building placed at a base consumes 1 population slot**, except **House**,
  which instead *grants* population capacity (and doesn't consume a slot itself).
- If a base's population is at capacity, no further buildings can be placed there —
  **other than House**. Building a House (or upgrading an existing one, which
  increases its capacity contribution further) is the only way to keep expanding once
  capped.
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
This is distinct from ordinary specialty *production* buildings (Tank Plant, Wind
Sanctuary, Hot Forge, etc.), which remain normal player-buildable buildings — including
multiple copies at the same base, same as Barracks — once that base is owned. Which
other buildings (if any) should join this fixed/unique category is a per-building
design call to make as more Unique bases are authored.

## Open / Unresolved Items
- **Resolved: not every Unique base gets a specialty defensive building.** Windy Peaks
  and Sky Fortress (and any future Unique base without one authored) simply rely on the
  two generic defenses every base gets (Turret, Missile Launcher) — a specialty
  defense building is a bonus some Unique bases have, not a requirement all of them
  need. This was never a gap to fill, just an assumption to drop.
