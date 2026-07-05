# Bases & Buildings

## Base Types
- **Capital Base** (renamed from "Home Base"): one per player at match start. Can be
  lost and later reclaimed (either by retaking the original, or by capturing any
  rival/neutral Capital and designating it as your new one).
  - Bonus: **+50% resource production**.
  - Unique unit access: only Capital Bases can train **Commander** troops.
- **Unique Base**: neutral city-states scattered across the map. Each has 1-2 unique
  buildings not available elsewhere, and its own troop roster. Capturing one means
  inheriting everything already built there.

## Base Seeding
Every base (new or captured) starts with three pre-placed, mutually-adjacent buildings:
- **HQ** — the core. Indestructible; can only be *captured*, never destroyed. If taken,
  the base simply changes owner.
- **Farm** — Food.
- **Quarry** — Stone.

## Expansion Rule (Hex Adjacency)
- One building per hex tile.
- Buildings can only be placed on **Plains** tiles, with named exceptions:
  - **Treehouse**'s buildings can be placed on **Forest** tiles.
  - **Air Temple**'s buildings can be placed on **Hill** tiles.
  - **Docks, Roads, Bridges** are placed on/adjacent to their relevant terrain
    (coast/river/forest) regardless of the plains rule, and aren't tied to a base at all.
- A new building must be placed on a hex adjacent to **two existing buildings**
  (or just **one** existing building if the new placement is a **Wall**). The seeded
  HQ/Farm/Quarry cluster satisfies the two-building rule for a base's first
  player-built building.
- **Walls** are also the exception to "one building per hex" — they sit on the
  **border between two hexes**, not on a hex itself.
- **Maximum build distance from HQ**: a base can only place buildings within a
  certain radius of its HQ. This radius is **not fixed — it scales with the HQ's
  upgrade level**, so upgrading the HQ is what unlocks room for the base to keep
  physically expanding outward.
- **HQ level also gates the maximum level of every other building in the base**:
  a building cannot be upgraded past the HQ's current level (e.g. a Barracks can't
  reach level 3 while the HQ is still level 1). **Troop-production buildings** also
  have a separate cap, but it isn't a stored value — it's simply the **length of that
  building's own troop list** (level 1 unlocks the first troop, and so on). **Non-
  production buildings** (Farm, Quarry, Mine, Oil Rig, Walls, defensive buildings)
  have **no such cap at all** — they scale indefinitely via stat boosts per level,
  limited only by the HQ ceiling. See `06-building-stats-and-defenses.md` for the full
  breakdown.
- **Building construction is instant** (no build timers). **Buildings can be
  upgraded** (see `06-building-stats-and-defenses.md`) — **troops cannot be
  upgraded** once trained (see `05-troop-stat-schema.md`).

## Building Reference

| Building | Function | Buildable at |
|---|---|---|
| HQ | Base core (pre-seeded, indestructible, capturable) | All |
| Farm | Food | All |
| Quarry | Stone | All |
| Mine | Steel | All |
| Oil Rig | Fuel | All (Capital's Oil Rig has -50% production penalty; same cost everywhere, no inherent level cap on either — see `06-building-stats-and-defenses.md`) |
| Turret | Defense (generic) | All |
| Missile Launcher | Defense (generic) | All |
| Barracks | Infantry | Capital, Treehouse |
| Factory | Light land vehicles | Capital only |
| Port | Navy (basic roster) | Any base with a water-adjacent tile |
| Tank Plant | Heavy tanks (builds 3-5 at a time) | Fort Irongrad only |
| Grenade Tower | Defense — splash damage, cheap, short range/low damage | Fort Irongrad only |
| Fire Helipad | Flame Helicopter, Plasma Helicopter | Firebase only |
| Flamethrower | Defense (fire) | Firebase only |
| Air Factory | Hot Air Balloon | Air Temple only (hill tiles) |
| Hangar | Planes (2 units) | Air Temple only (hill tiles) |
| Lumber Mill | Wood | Treehouse only |
| Quad Hangar | Quad-bike | Treehouse only (forest tiles) |
| Shipyard (renamed from Harbour) | Full navy incl. Aircraft Carrier; bonus to fishing boat output | Kraken Point only |
| Dock | Ship landing point (no production) | Anywhere on coast/river, Engineer-built, not tied to a base. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Road | Unblocks Forest tiles for land vehicles | Anywhere in Forest, Engineer-built |
| Bridge | Unblocks River tiles for infantry & land vehicles | Anywhere on River, Engineer-built. Buildable in Stone or Wood (Wood cheaper, weaker, fire-vulnerable) |
| Tower | Standalone defense + long-range fog-of-war clearing | Anywhere, Engineer-built, not tied to a base. Buildable in Stone or Wood — see `06-building-stats-and-defenses.md` for the two variants |
| Walls | Defense — sits on hex border. Tiers: Wood (cheapest/weakest, vulnerable to flame troops) / Stone (mid) / Steel (priciest/strongest) | All (Wood tier requires Treehouse captured first, to unlock Wood resource) |

- Every base type (Capital and all Unique) can build the two generic defenses
  (**Turret**, **Missile Launcher**); each Unique base's specialty defense building is
  in addition to these.

## Unique Bases (defined so far)

### Fort Irongrad
- Heavy armor specialist.
- **Tank Plant**: builds Heavy Tanks (3-5 per batch) — the only source of heavy tanks;
  Capital's Factory only makes light vehicles.
- **Grenade Tower** (defense): cheap, short range, low damage, splash.

### Firebase
- Incendiary air power specialist.
- **Fire Helipad**: builds Flame Helicopter (short range, high splash, fire damage) and
  Plasma Helicopter (bigger, slower, longer range, explosive impact damage).
- **Flamethrower** (defense).

### Air Temple
- Ground-support aircraft specialist. Found on hills; its buildings can be placed on
  hill tiles.
- **Air Factory**: builds Hot Air Balloon (cheap, high splash, low range, ground/naval
  targets only, slow-moving).
- **Hangar**: builds planes (2 units; specific roster TBD).

### Treehouse
- Forest/infantry/economy specialist. Found in a large forest biome; its buildings can
  be placed on forest tiles.
- **Barracks** (standard infantry — shared building type with Capital).
- **Lumber Mill**: produces Wood, which unlocks the cheap Wood wall tier for *all*
  bases once captured.
- **Quad Hangar**: builds Quad-bike (fast, forest-capable — ignores the forest
  vehicle-block rule — low armor/damage).
- **A map will typically contain multiple Treehouse bases** (not just one) — same for
  other Unique base types in general — so Wood access (and other unique-base perks)
  isn't a single-player monopoly. Exact count per base type scales with the map's
  overall base:player ratio (see `01-map-and-terrain.md`).

### Kraken Point (renamed from Atlantis)
- Naval capstone. Found on the coastline.
- **Shipyard** (renamed from Harbour): builds everything Port can, plus larger/advanced
  ships, topping out at the **Aircraft Carrier**. Also gives a bonus to fishing boat
  output.
- Aircraft Carriers can *hold* most air troops (they don't consume fuel while docked
  there) but do not produce them.

## Open / Unresolved Items
- Air Temple has no specialty defense building specified (relies on aircraft?).
- Hangar's two plane units and Air Temple's aircraft still need names/stats.
- Whether the Aircraft Carrier can itself act as a mobile launch platform (vs. just
  storage) is still undecided.
