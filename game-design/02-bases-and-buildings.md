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
- Walls and standalone buildings (Road/Bridge/Dock/Tower/Landmine) can also be demolished under
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
| Stone Works | Stone (mechanically a Quarry equivalent, steeper growth curve) | Foundry Reach only |
| Oil Rig | Fuel | All (Capital's Oil Rig has -50% production penalty; same cost everywhere, no inherent level cap on either — see `06-building-stats-and-defenses.md`) |
| House | Population capacity (does not itself consume a population slot) | All — see Population section below |
| Turret | Defense (generic) | All |
| Missile Launcher | Defense (generic) | All except Camp Cozy (deliberately lighter on fixed defense — see Camp Cozy below) |
| Barracks | Infantry | Capital, Treehouse, Firebase, Windy Peaks, Rivergate, Signal Ridge, Camp Cozy |
| Factory | Light land vehicles | Capital, Foundry Reach |
| Port | Navy (basic roster) | Any base with a water-adjacent tile |
| Tank Plant | Heavy tanks (full roster, builds 3-5 at a time) | Fort Irongrad only |
| Grenade Tower | Defense — splash damage, cheap, short range/low damage | Fort Irongrad only |
| Fire Helipad | Flamecopter, Plasmacopter | Firebase only |
| Flame Turret (renamed from Flamethrower) | Defense (fire) | Firebase only |
| Wind Sanctuary | Glider, Hot Air Balloon | Windy Peaks only (hill tiles) |
| Wind Spire | Defense — low damage, strong knockback, bonus damage vs. Air | Windy Peaks only (hill tiles) |
| Lumber Mill | Wood | Any base with a Forest-adjacent tile; Treehouse can additionally place it directly on Forest tiles (its specialty) |
| Forest Yard | Quad-bike | Treehouse only (forest tiles) |
| Hangar | Wingfighter, Thunder | Sky Fortress only |
| Command Centre | Commander | Capital only |
| Hospital | Support — heals nearby friendly troops slowly (passive aura, no production) | Capital, Foundry Reach, Sky Fortress, Camp Cozy (discounted here — see Camp Cozy below) |
| Supply Depot | Engineer, Ambulance, Transport Truck, Repair Truck, Mule, Volt Truck (support vehicles, all non-combat) | Camp Cozy only |
| Shipyard (renamed from Harbour) | Full navy incl. Aircraft Carrier; base carries a +50% Harbour production bonus | Kraken Point only |
| Dock | Ship landing point (no production) | Anywhere adjacent to Ocean or River (sits on the adjoining Plains hex, not on the water tile itself — same siteTerrain/adjacency shape as Port), Engineer-built, not tied to a base. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Road | Unblocks Forest tiles for land vehicles | Anywhere in Forest, Engineer-built |
| Bridge | Unblocks River tiles for infantry & land vehicles | Anywhere on River, Engineer-built. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Tower | Standalone defense + long-range fog-of-war clearing + short-range stealth detection (`detector: true`, `detectionRange: 3`) | Anywhere, Engineer-built, not tied to a base. Buildable in Stone or Wood — see `06-building-stats-and-defenses.md` for the two variants |
| Walls | Defense — sits on hex border. Tiers: Wood (cheapest/weakest, vulnerable to flame troops) / Stone (mid) / Steel (priciest/strongest) | All (Wood tier requires access to Wood, produced by any base's Lumber Mill) |
| Ice Spire | Aura — slows nearby enemy troops | Winter Forge only — **fixed/pre-seeded, cannot be freshly built** (see below) |
| Cold Turret | Defense — ice bombs, medium-low range, low damage, freezes target briefly on hit | Winter Forge only |
| Frostworks | Heavy tanks (partial roster — a subset of Tank Plant's) | Winter Forge only |
| Radar Array | Support — extends this player's vision range map-wide; reveals stealthed units at its own full (long) vision range | Signal Ridge only — **fixed/pre-seeded, cannot be freshly built** (same as Ice Spire, so its global vision bonus can't be stacked) |
| Covert Works | Ghost Tank, Disruptor | Signal Ridge only |
| EMP Turret | Defense — low damage, immobilizes Land vehicles, destroys Air troops outright (except Hot Air Balloon/Glider) | Signal Ridge only |
| Ford Yard | Amphibious Raider, Submarine | Rivergate only |
| River Battery | Defense — bonus damage vs. Naval targets | Rivergate only |

- Every base type can build **Turret**; every base except Camp Cozy can also build
  **Missile Launcher** (Camp Cozy deliberately omits it — see Camp Cozy below). Each
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
- **Not yet implemented**: `data/buildings/command_centre.json` fully implements this
  progression model, but no troop file in `data/troops/` carries a `commanderTier`
  field or a `Commander` tag yet — the Commander roster itself doesn't exist in data.
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
  vehicles. Winter Forge's Frostworks (below) also builds a subset of this roster, so
  Fort Irongrad is the most complete source of heavy armor but no longer the *only*
  source — heavy-tank access will keep spreading across more Unique bases over time as
  the roster grows.
- **Grenade Tower** (defense): cheap, short range, low damage, splash.

### Firebase
- Incendiary air power specialist.
- **Fire Helipad**: builds Flamecopter (short range, high splash, fire damage) and
  Plasmacopter (bigger, slower, longer range, explosive impact damage).
- **Flame Turret** (defense) — renamed from Flamethrower to avoid colliding with the
  Barracks infantry unit of the same name (see `08-troop-roster.md`).

### Windy Peaks
- Ground-support and reconnaissance aircraft specialist. Found on hills; its buildings
  can be placed on hill tiles.
- **Wind Sanctuary** (merged Air Factory + Hangar into a single building): builds, in
  order, Glider (fast scouting air unit, cannot attack at all, cheap, uses no Fuel at
  all — being unpowered, it draws Food upkeep instead, like infantry) and Hot Air
  Balloon (cheap, high splash, low range, ground/naval targets only, slow-moving,
  modest Fuel upkeep).
- **Wind Spire** (defense): a Turret variant (see `data/buildings/schema.json`'s
  `extends`) trading raw damage for control — low base damage, but every hit applies a
  strong `knockback` (shoves the target back several hexes, see
  `05-troop-stat-schema.md`'s Status Effects section for how `knockback` differs from
  `freeze`/`stun`), plus a large damage bonus against Air targets. Sits on Hill tiles
  like Wind Sanctuary.

### Treehouse
- Forest/infantry/economy specialist. Found in a large forest biome; its buildings can
  be placed on forest tiles.
- **Barracks** (standard infantry — shared building type, see Building Reference above
  for the full list of bases that build it).
- **Lumber Mill**: produces Wood. Treehouse can place its Lumber Mill directly on
  Forest tiles (its specialty); any other base can also build a Lumber Mill if it has
  a Forest-adjacent tile (see Building Reference above) — Wood is no longer exclusive
  to holding a Treehouse.
- **Forest Yard**: builds Quad-bike (fast, forest-capable — ignores the forest
  vehicle-block rule — low armor/damage).
- Only **one Treehouse** exists on a given map (see `01-map-and-terrain.md`) — like
  every Unique base type, it's a genuinely unique, non-repeating base.

### Kraken Point (renamed from Atlantis)
- Naval capstone. Found along the map's ocean edge.
- **Shipyard** (renamed from Harbour — an unrelated, later-introduced building has
  since reused that name for a Farm-equivalent, see Harbour above): builds everything
  Port can, plus larger/advanced ships, topping out at the **Aircraft Carrier**.
- **+50% Harbour production**: a building-scoped bonus authored directly on
  Kraken Point's own `BaseDef` (a `scope: "building", buildingType: "harbour"`
  `resourceModifiers` entry — same shape as Foundry Reach's/Treehouse's building-scoped
  bonuses, see `07-data-architecture.md`), not a Shipyard aura — making Kraken Point a
  strong Food-economy base as well as a military one, provided it has a Harbour built.
- Aircraft Carriers can *hold* most air troops (they don't consume fuel while docked
  there) but do not produce them. **Resolved**: they can launch stored aircraft
  mid-battle, not just while idle — see `05-troop-stat-schema.md`'s
  `can_launch_cargo_mid_combat` field.

### Sky Fortress
- Elite air-superiority specialist — the pure air-combat counterpart to Windy Peaks'
  scouting/ground-support focus.
- **Hangar**: builds **Wingfighter** (fast, rapid-fire machine guns, low damage
  against buildings/walls — an anti-troop dogfighter, not a siege unit) and
  **Thunder** (slower, heavier armored, missile-armed — the harder-hitting,
  slower-to-lose alternative).
- **Moat**: generated with a ring of water terrain surrounding the base, making it
  harder to approach with Land-domain troops (Infantry/Land vehicles) — Naval units
  can't reach it either, being landlocked, but Air units ignore it entirely, same as
  every other terrain restriction. Reinforces the base's air-superiority identity by
  making ground sieges specifically harder, not just defended by stronger units.

### Winter Forge
- Cold/ice specialist — a second, partial route into heavy armor, plus area
  control via slow and freeze effects.
- **Ice Spire**: not a production or defensive building — a pure aura structure.
  Carries a single aura that slows nearby *enemy* troops (a debuff aura, unlike the
  friendly-only auras seen so far — see `05-troop-stat-schema.md`). **Fixed/pre-seeded,
  cannot be freshly built** — see below. Winter Forge's Oil Rig boost is instead a
  base-wide bonus authored on its own `BaseDef`, not an Ice Spire aura (see
  `03-resources.md`).
- **Cold Turret** (defense): ice bombs, medium-low range, low damage, but **freezes**
  its target for a couple seconds on hit (target can't move or attack while frozen) —
  a crowd-control defense rather than a raw-damage one.
- **Frostworks**: builds a **subset** of the Heavy Tank roster (not the full list Fort
  Irongrad's Tank Plant offers) — the first case of a troop type being split across
  more than one building/base; see `08-troop-roster.md`.

### Foundry Reach
- Economic specialist — the first Unique base built entirely around resource output
  rather than a troop roster. No terrain exception; it's sited on Plains like Fort
  Irongrad, Firebase, Sky Fortress, and Winter Forge.
- **+100% Steel production**: a building-scoped bonus on Mine authored directly on
  Foundry Reach's own `BaseDef` (a `scope: "building", buildingType: "mine"` entry in
  `resourceModifiers` — see `03-resources.md` and `07-data-architecture.md`), not a
  base-wide multiplier.
- **Stone Works**: Foundry Reach's one exclusive building — a Resource-category
  building mechanically equivalent to Quarry (Stone output, steep compounding growth
  curve), gated by base eligibility rather than terrain (see Harbour above for the
  identical pattern applied to Food). Stacks with the +100% Steel bonus to make
  Foundry Reach a strong dual resource-economy base. Its sole offensive/defensive
  option beyond the generic Turret/Missile Launcher and Stone Works is a **Factory**
  (Capital, Foundry Reach), the same light-vehicle roster a Capital gets.
- Because it can never out-produce a dedicated combat base on troops, Foundry Reach's
  value is largely in **capturing** it — taking it is what gets you (or denies a
  rival) the doubled Steel output plus Stone Works' output, a bigger incentive than
  sabotaging a single building would be. This echoes the Food/Fuel deficit pillar in
  `00-overview.md`.

### Signal Ridge
- Stealth-detection and electronic-warfare specialist. No terrain exception; sited on
  Plains.
- **Radar Array**: extends this player's vision range map-wide and reveals stealthed
  units within its own range (its full, long `visionRange` — no short `detectionRange`
  restriction, unlike Tower) — the first building whose effect isn't local to its own
  base. `isFixed: true`, same pattern as HQ/Ice Spire: pre-seeded only, never freshly
  built, so there's exactly one and its global vision bonus can't be stacked.
- **Covert Works**: builds **Ghost Tank** (stealth armor — visible to non-detectors
  only at very short range, visible to `detector` units like Sniper at their normal
  vision range, and it breaks its own stealth the instant it fires — see
  `05-troop-stat-schema.md`'s `reveals_on_attack` flag) and **Disruptor** (an EW
  troop, not a building — while alive it projects an `enemy_buildings`-targeted aura
  that suppresses enemy defensive buildings' targeting within its radius; killing the
  Disruptor immediately restores them). See `08-troop-roster.md` for full stats.
- **EMP Turret** (defense): a Turret variant (see `data/buildings/schema.json`'s
  `extends`) — low damage, but every hit applies an `emp` status effect
  (`05-troop-stat-schema.md`'s Status Effects section): immobilizes Land-domain
  vehicles (movement disabled, can still attack) for a few seconds, and **destroys
  Air-domain troops outright** — except Hot Air Balloon and Glider, both flagged
  `empImmune` as unpowered/non-electronic exceptions. No effect on Infantry or Naval
  beyond normal damage.

### Rivergate
- River-crossing specialist — the first Unique base whose identity comes from
  adjacency to River terrain rather than Forest or Hills. It's still seeded on Plains
  like every other base (see Base Seeding above); no buildings are ever placed on the
  river itself.
- **Ford Yard**: builds, in order, **Amphibious Raider** — a light *vehicle* (not
  infantry) that ignores the River-blocked movement rule, fording rivers directly
  without needing a Bridge — and **Submarine** (also built at Kraken Point's Shipyard).
  See `08-troop-roster.md`.
- **+25% Harbour production**: a building-scoped bonus authored directly on
  Rivergate's own `BaseDef` (same `resourceModifiers` shape as Kraken Point's +50%
  Harbour bonus above), given the base's water/river adjacency.
- **River Battery** (defense): a Turret variant — trades Air targeting for bonus
  damage against **Naval** targets. Rivers are naval-passable all the way inland
  from the sea (see `01-map-and-terrain.md`), so without this, an enemy fleet could
  otherwise sail straight past a river base uncontested — River Battery is what
  makes holding Rivergate matter for denying that route, not just for the
  Amphibious Raider. Must be placed adjacent to a Water tile (Ocean or River),
  same adjacency rule as Port/Shipyard, so it can't be built somewhere that
  doesn't actually cover the crossing.

### Camp Cozy
- Logistics/support specialist — the first Unique base built around sustaining an
  army rather than fighting or producing resources. Sited on Plains, no terrain
  exception.
- **Supply Depot**: builds, in order, **Engineer**, **Ambulance**, **Transport
  Truck**, **Repair Truck** (Ambulance's vehicle-repair counterpart — heals Land
  vehicles instead of Infantry), **Mule** (upkeep-reduction aura, easing Food/Fuel
  deficit pressure), and **Volt Truck** (speed + attack-speed boost aura for
  Land/Air/Naval) — a support-vehicle-only roster, distinct from Factory's combat
  vehicles. All six are non-combat (`canTarget: []`), so Camp Cozy produces no
  defenders of its own from this building.
- **Barracks** included specifically so the base isn't a total pushover
  garrison-wise, given Supply Depot's roster can't defend it — but deliberately
  **no Missile Launcher**, only Turret plus Walls, keeping its fixed defenses
  lighter than other Unique bases too.
- **Hospital** is buildable here (unlike most bases, which don't get it at all) at
  a **25% cost discount** (`costModifiers`, a new `BaseDef` field mirroring
  `resourceModifiers` but discounting build/upgrade cost instead of production
  output — see `07-data-architecture.md`), plus a **50% Wall cost discount** —
  cheap to wall in and keep supplied is the whole point.
- No specialty defense building and no base-wide `resourceModifiers` bonus — its
  identity is entirely the cost discounts plus Supply Depot's roster, not raw
  output or damage.

## Building Categories
Every building falls into one of five categories, which determines whether it needs
player input to function or just runs on its own once built:

| Category | Examples | Requires player action? |
|---|---|---|
| **Production** | Barracks, Factory, Port, Tank Plant, Frostworks, Fire Helipad, Wind Sanctuary, Forest Yard, Shipyard, Hangar, Command Centre, Covert Works, Ford Yard, Supply Depot | **Yes** — the player must pick a troop from the building's roster to queue; nothing is produced until a choice is made |
| **Resource** | Farm, Quarry, Mine, Oil Rig, Lumber Mill, Harbour, Stone Works | No — ticks automatically every resource tick (see `07-data-architecture.md`) |
| **Defensive** | Turret, Missile Launcher, Grenade Tower, Flame Turret, Cold Turret, River Battery, Wind Spire, EMP Turret, Walls, Tower | No — auto-fires on any enemy troop that enters range, same as troops (see `04-combat.md`) |
| **Support** | Hospital, Ice Spire, House, Radar Array | No — passively applies its effect (healing / aura / population capacity / vision) with no queue or target selection involved |
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
