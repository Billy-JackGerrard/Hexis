# Building Stats & Defenses

## The Gist
Buildings use a schema that overlaps heavily with the troop schema (`05-troop-stat
-schema.md`) — HP, damage modifiers, and for defensive buildings, the same
damage/range/splash/can_target/detector fields a troop would have. The key differences
from troops: buildings don't move, aren't "produced" the way troops are (built
instantly per `02-bases-and-buildings.md`), and have a distinct destruction/ruin state
instead of simply dying.

## Destruction & Ruins
- **HQ** is the sole exception: indestructible, can only be captured (ownership of the
  whole base flips — see `02-bases-and-buildings.md`).
- **All other buildings** (production buildings, defensive buildings, resource
  buildings) have their own HP and **can be destroyed individually** during a siege —
  e.g. an attacker can kill a Turret specifically to open a path, without needing to
  capture the whole base.
- When a non-HQ building is destroyed, it becomes a **ruin**:
  - The hex tile is **not** freed up — it stays occupied by the ruin, so nobody
    (attacker or defender) can build a *different* building on that hex afterward.
  - The ruin still counts as "a building" for the hex-adjacency placement rule (new
    buildings elsewhere in the base can still be placed adjacent to it, same as before
    it was destroyed).
  - The original owner can **rebuild the same building type** on that hex for a
    fraction of its normal cost.
- This prevents "grief" destruction from permanently reshaping a base's buildable
  layout, while still making individual buildings valid, meaningful combat targets.

## Structural Stats (all non-HQ buildings)
| Field | Type | Notes |
|---|---|---|
| HP | number | building's health pool |
| Damage received modifiers | dict `{tag: multiplier}` | same pattern as troops/walls, e.g. Wood Wall `{Fire: 2.0}` |
| Rebuild cost | number/dict | fraction of original build cost, paid to restore a ruin to the same building type |

## Defensive Building Stats (Turret, Missile Launcher, Grenade Tower, Flamethrower, and Walls where relevant)
These use the same combat-facing fields as troops:

| Field | Type | Notes |
|---|---|---|
| Damage | number | base damage per attack |
| Attack speed | number | attacks per time unit |
| Range | number | engagement range |
| Splash radius | number | 0 = single-target (e.g. Turret); >0 for Grenade Tower, etc. |
| can_target | list of tags | e.g. Missile Launcher may include `Air`; Turret may not |
| Damage dealt modifiers | dict `{tag: multiplier}` | e.g. Flamethrower vs Wood-tagged targets |
| detector | bool | optional — a defensive building could double as stealth detection |
| Vision range | number | separate from attack range, same as troops |

## Known Defensive Buildings (stats TBD, structure only for now)

| Building | Available at | Known character (from earlier design) |
|---|---|---|
| Turret | All bases | Generic default defense |
| Missile Launcher | All bases | Generic default defense — likely the anti-air generalist given Grenade Tower/Flamethrower are already ground-specialized |
| Grenade Tower | Fort Irongrad only | Cheap, short range, low damage, splash |
| Flamethrower | Firebase only | Fire-tagged damage, likely bonus vs Wood-tagged targets/walls |
| Walls (Wood/Stone/Steel) | All (Wood requires Treehouse captured) | Not a "defense" that attacks, but has HP + damage-received modifiers (Wood: weak vs Fire) |

- **Some buildings will act as stealth detectors** — i.e. carry the `detector: true`
  flag from the troop/building schema, letting them reveal stealthed enemy troops at
  full vision range regardless of `reveal_range`. Which specific building(s) serve
  this role is still to be decided (could be a dedicated new building, or a flag added
  onto an existing defensive building like Turret or Missile Launcher).

## Upgrades
- **Buildings can be upgraded** (unlike troops, which cannot — see
  `05-troop-stat-schema.md`), and upgrades are instant (per `02-bases-and-buildings.md`).
- **HQ level as a global ceiling**: no building in a base can be upgraded past the
  HQ's current level, regardless of building type.
- **Troop-production buildings** (Barracks, Factory, Port, Tank Plant, Fire Helipad,
  Air Factory, Hangar, Quad Hangar, Shipyard) have a **derived max level**: there's no
  separate stored cap — the max level is simply `length(troop_list)` for that
  building. Each level unlocks the next troop in the list, in order. This means the
  cap is never a value that can drift out of sync with the roster — add a 4th troop to
  a building's list, and its cap becomes 4 automatically.
- **Every other building type has no inherent level cap** — it can keep being
  upgraded indefinitely, bottlenecked only by the HQ ceiling. Each level grants a
  **stat boost** rather than unlocking new content:
  - **Resource buildings** (Farm, Quarry, Mine, Oil Rig): each level grants a
    percentage boost to production output, plus a boost to the building's own HP.
  - **Walls**: each level grants a boost to HP/armor (damage-received modifiers
    improve, e.g. reducing the Wood-vs-Fire penalty over levels, or just raising flat HP).
  - **Defensive buildings** (Turret, Missile Launcher, Grenade Tower, Flamethrower):
    each level grants a boost to HP, Damage, and possibly Range.
- **Effective reachable level** for a production building = `min(HQ level,
  length(troop_list))`. For all other buildings, effective reachable level = HQ level
  directly (no second cap to compare against).

## Upgrade Data Model
Two different storage patterns are used, matching the two building categories above:

**Production buildings (finite, explicit per-level table)**
Since production buildings have a small, finite number of levels (`length(troop_list)`),
each level is hand-authored as its own row — precise control since each level is tied
to a specific unlock, not a formula:
```
levels: [
  { level: 1, hp: 100, unlocks: "InfantryA", cost: { steel: 50, stone: 30 } },
  { level: 2, hp: 150, unlocks: "InfantryB", cost: { steel: 100, stone: 60 } },
  { level: 3, hp: 220, unlocks: "InfantryC", cost: { steel: 180, stone: 100 } }
]
```
- `hp` (and any other stat) is stored as the **absolute value at that level**, not a
  delta — avoids compounding rounding errors and makes editing a single level trivial.
- `cost` is the price to go from the previous level to this one, hand-tuned per row.

**Non-production buildings (uncapped, formula-based)**
Since these can be upgraded indefinitely (bounded only by the HQ ceiling), storing an
explicit row per level doesn't scale. Instead: a base stat block plus a growth rule
per stat:
```
base_stats: { hp: 200, damage: 15, range: 4 }
stat_growth: { hp: "+10%_per_level", damage: "+8%_per_level", range: "+0_per_level" }
base_cost: { steel: 40, stone: 20 }
cost_growth: "+25%_per_level"
```
- Level N's value for a stat = `base_stats.X * (1 + stat_growth.X)^(N-1)` (additive
  growth is an alternative to compounding, if flatter late-game scaling is preferred —
  compounding gets swingy at high levels).
- Level N's upgrade cost = `base_cost.X * (1 + cost_growth)^(N-1)`.
- **Cost growth is intentionally faster than stat growth** (e.g. cost +25%/level vs.
  HP +10%/level) — this is the "diminishing returns" lever that naturally slows
  late-game snowballing on buildings that otherwise have no hard level cap.
- Not every stat needs to grow — e.g. Range might stay flat (`+0%_per_level`) even
  while HP/Damage scale, since ever-increasing range could break terrain-based
  positioning balance. This is decided per building, not applied as one universal rule.

## Upgrade Cost — Resources
Upgrade cost draws **only from Steel, Stone, or Wood** (Wood specifically for Wood-tier
walls) — never Food or Fuel. This matches general construction cost rules and means
a Food/Fuel-starved player can still upgrade defensively (e.g. mid-siege) as long as
they have Steel/Stone/Wood on hand.

## Tower (Standalone Structure)
Like Dock/Road/Bridge, the Tower is **not tied to a base** — built anywhere by an
**Engineer** (confirmed). Its purpose is twofold: a long-range vision structure
(clears fog of war around it at high range) and a defensive structure, with two
distinct material variants offering genuinely different playstyles rather than just a
cost/power tradeoff:

| Variant | Damage | Attack Speed | Fire Vulnerability | Cost | Special |
|---|---|---|---|---|---|
| **Stone Tower** | High | Low | Normal | Higher | Simple stat scaling per level (standard non-production growth model) |
| **Wood Tower** | Low | High | **Vulnerable** (like Wood walls/bridges) | Lower | Each upgrade level **adds an additional turret** to the structure |

- **Vision**: both variants clear fog of war at a high vision range, independent of
  attack range (consistent with vision ≠ engagement range elsewhere in the design).
- **Wood Tower's role is confirmed as swarm-clearing**: its multiple turrets
  **independently target** (each turret slot picks its own nearest enemy, per the
  standard combat targeting rule), so a max-level Wood Tower can engage several
  separate weak/fast units at once rather than focus-firing one target. This is its
  defined purpose — countering swarms/scouts/fast harassment units (like Quad-bikes) —
  while the Stone Tower remains the pick for stopping a single strong threat (e.g. a
  Heavy Tank).

## Wood Material Option — Docks & Bridges
Docks and Bridges (in addition to Walls) can now be built in **either Stone or Wood**:
- Wood is significantly cheaper.
- Wood is weaker (lower HP) and **vulnerable to Fire-tagged attackers**, consistent
  with the existing Wood wall vulnerability rule.
- This extends Wood's identity — "cheap, fast, fire-vulnerable" — consistently across
  every structure type it touches, rather than introducing a use for it with a
  different profile.

## Open / Unresolved Items
- Exact HP/damage/range/splash numbers for every defensive building.
- Whether Missile Launcher is the anti-air generalist (implied, not yet confirmed).
- Whether walls themselves ever "attack" (e.g. spikes/damage on contact) or are purely
  passive HP barriers.
- Which specific building(s) carry the `detector: true` stealth-detection flag.
- Rebuild cost fraction (e.g. 25%? 50%?) — not yet specified.
- What a defensive building's own per-level unlocks look like (e.g. does Turret level
  2/3 just scale stats, or unlock new can_target entries like gaining anti-air?).
