# Building Stats & Defenses

## The Gist
Buildings use a schema that overlaps heavily with the troop schema (`05-troop-stat
-schema.md`) — HP, damage modifiers, and for defensive buildings, the same
damage/range/splash/can_target/detector fields a troop would have. The key differences
from troops: buildings don't move, aren't "produced" the way troops are (built
instantly per `02-bases-and-buildings.md`), and have a distinct destruction/ruin state
instead of simply dying.

## Destruction & Ruins
- **HQ** is the sole exception to normal destruction: it has HP like everything else,
  but hitting 0 HP doesn't ruin it — it triggers a **capture** (ownership of the whole
  base flips to the attacker) and the HQ **respawns at full HP** immediately under its
  new owner. It's never ruined, rebuilt, or removed from the map — see
  `02-bases-and-buildings.md`.
- **All other buildings** (production buildings, defensive buildings, resource
  buildings) have their own HP and **can be destroyed individually** during a siege —
  e.g. an attacker can kill a Turret specifically to open a path, without needing to
  capture the whole base.
- When a non-HQ, non-Wall building is destroyed, it becomes a **ruin**:
  - The hex tile is **not** freed up — it stays occupied by the ruin, so nobody
    (attacker or defender) can build a *different* building on that hex afterward.
  - The ruin still counts as "a building" for the hex-adjacency placement rule (new
    buildings elsewhere in the base can still be placed adjacent to it, same as before
    it was destroyed).
  - The original owner can **rebuild the same building type** on that hex for a
    fraction of its normal cost.
- **Walls are the exception**: a destroyed Wall doesn't become a ruin — it simply
  **disappears** entirely, freeing its hex-border edge. Rebuilding it there is a full
  fresh build (any material, at normal cost), not a discounted ruin-rebuild.
- **Standalone buildings (Road, Bridge, Dock, Tower, Landmine) follow the same rule as Walls**:
  not tied to a base, they carry their own `ownerId` directly rather than deriving
  ownership from a base, and a destroyed standalone building **deletes outright**
  rather than ruining — freeing the hex/edge for a full fresh build at normal cost
  (see `07-data-architecture.md`).
- **Regeneration**: all buildings and walls **slowly regenerate HP over time** once
  they haven't taken damage recently — a siege that's beaten off doesn't leave
  permanent scarring the way an outright kill (ruin) does. **Resolved: this is a
  single global rule, not a per-building/per-level stat** — every building and Wall
  regenerates **5% of its current max HP per 5-second tick** (the same cadence as the
  resource tick, see `07-data-architecture.md`) while it hasn't taken damage recently.
  There is no `hpRegenRate` field on individual building definitions.
- This prevents "grief" destruction from permanently reshaping a base's buildable
  layout, while still making individual buildings valid, meaningful combat targets.

## Structural Stats (all non-HQ buildings)
| Field | Type | Notes |
|---|---|---|
| HP | number | building's health pool |
| Damage received modifiers | dict `{tag: multiplier}` | same pattern as troops/walls, e.g. Wood Wall `{Fire: 2.0}` |
| Rebuild cost | number | Flat **50% of original build cost**, same material. Not applicable to Walls or standalone buildings (Road/Bridge/Dock/Tower/Landmine), which delete outright on destruction (full rebuild cost, any material) rather than ruining. |

HP regen is **not** a per-building stat — see the global 5%-per-5s-tick rule above.

## Defensive Building Stats (Turret, Missile Launcher, Grenade Tower, Flame Turret, and Walls where relevant)
These use the same combat-facing fields as troops:

| Field | Type | Notes |
|---|---|---|
| Damage | number | base damage per attack |
| Attack speed | number | attacks per time unit |
| Range | number | engagement range |
| Splash radius | number | 0 = single-target (e.g. Turret); >0 for Grenade Tower, etc. |
| can_target | list of tags | e.g. Missile Launcher may include `Air`; Turret may not. Reserved value `Structure` isn't relevant here — defensive buildings target troops, not other structures |
| damage_types | list | e.g. Flame Turret carries `[Fire]` (see `05-troop-stat-schema.md`) |
| Damage dealt modifiers | dict `{tag: multiplier}` | e.g. Flame Turret vs Wood-tagged targets |
| detector | bool | optional — a defensive building could double as stealth detection |
| Vision range | number | separate from attack range, same as troops |

## Known Defensive Buildings (fully implemented — see data/buildings/*.json)

| Building | Available at | Known character |
|---|---|---|
| Turret | All bases | Generic default defense |
| Missile Launcher | All bases | Generic default defense — confirmed anti-air generalist (`damageDealtModifiers: {Air: 1.5}`), since Grenade Tower/Flame Turret are already ground-specialized |
| Grenade Tower | Fort Irongrad only | Cheap, short range, low damage, splash |
| Flame Turret (renamed from Flamethrower) | Firebase only | Fire-tagged damage, bonus vs Wood-tagged targets/walls |
| Cold Turret | Winter Forge only | Ice bombs, medium-low range, low damage, applies `status_effect_on_hit: {type: freeze}` for a couple seconds — crowd control over raw damage |
| River Battery | Rivergate only | Turret variant, trades Air targeting for a bonus vs. Naval targets; must be placed adjacent to Water |
| Wind Spire | Windy Peaks only (hill tiles) | Turret variant, low damage, applies `status_effect_on_hit: {type: knockback}` on every hit, large damage bonus vs. Air |
| EMP Turret | Signal Ridge only | Turret variant, low damage, applies `status_effect_on_hit: {type: emp}` on every hit — immobilizes Land vehicles, destroys Air troops outright (except empImmune troops: Hot Air Balloon, Glider), no effect on Infantry/Naval beyond direct damage |
| Walls (Wood/Stone/Steel) | All (Wood requires access to Wood, from any base's Lumber Mill) | Not a "defense" that attacks, but has HP + damage-received modifiers (Wood: weak vs Fire). Disappears on destruction rather than ruining (see Destruction & Ruins above) |

- **Stealth detection is resolved**: Radar Array (Signal Ridge, Support-category)
  carries the top-level `detector: true` flag; no Defensive building currently doubles
  as a detector.

## Support Buildings (Hospital, Ice Spire, House)
Support buildings reuse the troop schema's **auras** field (`05-troop-stat-schema.md`)
rather than a combat-facing stat block — most don't attack, don't produce, they just
project a passive effect:

| Field | Type | Notes |
|---|---|---|
| auras | list of `{radius, target, filter, effect, magnitude}` | e.g. Hospital → `{radius: 3, target: friendly_troops, effect: heal_over_time, magnitude: X hp/tick}` |

- **Hospital**: heals nearby friendly troops slowly over time (passive, no targeting/
  queue involved). Buildable at **any** base. Its main use is defensive — garrisoning
  troops near a Hospital lets them recover between skirmishes instead of sitting at
  reduced HP, which matters most when positioning a standing defense force at a base
  rather than actively pushing.
- **Ice Spire** (Winter Forge only): carries *two* auras simultaneously — a
  `target: enemy_troops` slow debuff, and a `target: friendly_buildings, filter:
  "Oil Rig"` production buff for this base's own Oil Rigs. **Fixed/pre-seeded** — see
  `02-bases-and-buildings.md`'s Fixed / Unique Structures section; if destroyed it
  ruins and can be rebuilt at the usual discount, but can never be freshly built where
  one didn't already exist.
- **House**: doesn't carry an aura at all — its effect is structural, not a radius
  effect. Each House (and each of its upgrade levels) contributes population capacity
  to its base; unlike every other building, a House itself doesn't consume a
  population slot. See `02-bases-and-buildings.md`'s Population section and
  `03-resources.md`.
- Like other non-production buildings, Hospital/Ice Spire/House have no inherent level
  cap — upgrades scale magnitude/radius/population-capacity, bottlenecked only by the
  HQ ceiling, using the same formula-based growth model as other uncapped buildings.
- Aura effects stack with terrain/wall/other-aura bonuses, consistent with the general
  "bonuses stack" rule (see `04-combat.md`).

## Upgrades
- **Buildings can be upgraded** (unlike troops, which cannot — see
  `05-troop-stat-schema.md`), and upgrades are instant (per `02-bases-and-buildings.md`).
- **HQ level as a global ceiling**: no building in a base can be upgraded past the
  HQ's current level, regardless of building type.
- **Troop-production buildings** (Barracks, Factory, Port, Tank Plant, Frostworks,
  Blazeworks, Wind Sanctuary, Iron Aviary, Forest Yard, Shipyard, Covert Works, Ford
  Yard) have a **derived max level**: there's no
  separate stored cap — the max level is simply `length(troop_list)` for that
  building. Each level unlocks the next troop in the list, in order. This means the
  cap is never a value that can drift out of sync with the roster — add a 4th troop to
  a building's list, and its cap becomes 4 automatically. **Command Centre is the one
  exception** to this model — see Command Centre's Own Upgrade Model below.
- **Every other building type has no inherent level cap** — it can keep being
  upgraded indefinitely, bottlenecked only by the HQ ceiling. Each level grants a
  **stat boost** rather than unlocking new content:
  - **Resource buildings** (Farm, Quarry, Mine, Oil Rig, Harbour): each level grants a
    percentage boost to production output, plus a boost to the building's own HP.
    **Harbour is a deliberate exception to a mild/steady growth curve**: its base
    (level 1, "1 boat") output is noticeably lower than a Farm's, but its
    `stat_growth.foodOutput` is tuned much steeper (boat count roughly doubling per
    level) so that a maxed-out Harbour ends up out-producing a maxed-out Farm despite
    the lower starting point — see `02-bases-and-buildings.md`.
  - **Walls**: each level grants a flat HP boost only — `damageReceivedModifiers`
    (e.g. Wood's Fire weakness) and flat `armor` (Steel's 5, mirroring Steel
    Tower) are fixed per material tier and don't currently improve with level
    in `data/buildings/wall.json`.
  - **Defensive buildings** (Turret, Missile Launcher, Grenade Tower, Flame Turret):
    each level grants a boost to HP, Damage, and possibly Range.
- **Effective reachable level** for a production building = `min(HQ level,
  length(troop_list))`. For all other buildings, effective reachable level = HQ level
  directly (no second cap to compare against). **Command Centre** behaves like the
  latter group despite being Production-category — since `postTierGrowth` is uncapped
  (levels 4+ just keep growing HP/slots), its effective reachable level is HQ level
  directly, same as a non-production building.

### HQ's Own Upgrade Model
**Resolved**: the HQ itself uses the **non-production, formula-based** upgrade model
(it has no `troop_list` to derive a cap from — it's the thing that gates every other
building's cap, not something gated by one), with two deliberate choices to keep HQ
upgrades a real pacing lever rather than a rubber-stamp: 
- A **steep cost-growth curve** (steeper than the general "cost grows faster than
  stats" default used elsewhere) — since every other building's max level rides on
  HQ level, letting HQ upgrades stay cheap would trivialize the whole ceiling.
  **Resolved numbers**: base cost **300 Stone + 200 Steel**, cost growth **+35%/level**
  (steeper than the generic +25%/level default used elsewhere — see `data/buildings/hq.json`).
- **A minimum population requirement per level** (`minPopulationPerLevel` on the
  `nonProductionUpgradeModel` — see `data/buildings/schema.json`), on top of the
  normal resource cost — a base has to actually be built out (Houses included) before
  its HQ can advance, tying HQ progression to base development rather than pure
  resource stockpiling. **Resolved: this gate scales with level** —
  `requiredPopulationUsed = 3 * (targetLevel - 1)` (level 2 needs `populationUsed >= 3`,
  level 3 needs `>= 6`, etc.), rather than a single flat number for every level.
- **HP**: base **300 at level 1**, growing **+10%/level** (compounding), the standard
  non-production growth model.
- **Category**: HQ is its own **`Core`** category (not Support/Defensive/etc. — see
  `data/buildings/schema.json`) since it doesn't attack, produce, or apply an aura; its
  only mechanical effects are capture-on-zero-HP and gating every other building's max
  level at that base.
- **Population**: **Resolved — HQ does not consume a population slot itself
  (`populationCost: 0`), and in fact *grants* population capacity, the same way House
  does**: **+2 capacity per level** (level 1 grants 2, level 2 grants 4, level 3 grants
  6, and so on — see `02-bases-and-buildings.md`'s Population section). This stacks
  with whatever Houses contribute at that base. Note the resulting loop: upgrading HQ
  grants more population capacity, but *advancing* HQ further requires that capacity to
  already be filled with real buildings (the `minPopulationPerLevel` gate above) — HQ
  opens room to grow, but the base has to actually use that room before HQ can climb
  again.

### Command Centre's Own Upgrade Model
**Resolved**: the Command Centre is a **second exception** to the standard
production-building model (alongside HQ being the exception to the non-production
model) — it has a `troopList`-shaped roster of Commanders, but doesn't unlock them
one-per-level. Instead it uses a dedicated `commanderProgression` shape
(`data/buildings/schema.json`) with two parts. It's also **`isFixed`** (`true` in
`data/buildings/command_centre.json`), same pattern as HQ: pre-seeded on every
Capital at match start (`data/bases/capital.json`'s `initialBuildings`), never
freshly built even after capture, and not demolishable — only rebuildable from a
ruin. Its own level (not building count) is what grows the Commander cap, so:
- **`tierLevels`** (explicit per-level table, levels 1-3): each level unlocks a whole
  Commander **tier** at once (`common` at 1, `rare` at 2, `epic` at 3 — see
  `05-troop-stat-schema.md`'s `commander_tier` field), plus an absolute `hp` value and
  a `commanderSlots` contribution toward the player's Commander cap (1 per level here).
- **`postTierGrowth`** (formula-based, levels 4+): once every tier is unlocked, further
  levels grant no new troops — just HP growth (percentage-based, like other non-
  production stat growth) and **+1 `commanderSlots` per level**.
- See `02-bases-and-buildings.md`'s Command Centre & the Commander Cap section and
  `04-combat.md`'s Commander Tiers & the Commander Cap section for the gameplay
  rationale; `07-data-architecture.md` for how the player-wide Commander cap is derived
  and enforced.

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
- **Stealth detection**: both variants also carry `detector: true` with a short
  `detectionRange` — much shorter than their `visionRange` (which varies per
  material; see `data/buildings/tower.json` for current values), since normal
  fog-of-war clearing and spotting a cloaked Ghost Tank/Submarine are treated as
  different senses. This is deliberately a *short-range, place-and-defend* counter
  rather than a mobile escort: Tower is cheap and buildable anywhere by an Engineer, so
  countering stealth this way means walling/towering specific water approaches or
  chokepoints, not tagging along with a fleet. Unlike Radar Array (Signal Ridge's
  single, fixed, long-range detector — see below), stealth stays viable everywhere
  except the specific spots a player has invested Tower coverage in. This also gives
  Tower a second reason to be defended, beyond being a generic chokepoint piece.
- **Detection reveals, it doesn't require Tower to land the kill itself**: revealing a
  stealthed unit exposes it to ANY of the owning player's troops/buildings within that
  same local radius, not just to Tower's own attack (same as Radar Array below, which
  has no attack at all — its detector flag would be pointless otherwise). A lone Tower
  can still lose a straight fight to a full squad (e.g. four Light Tanks' combined dps
  kills a 300 HP Stone Tower in a few seconds), but that's fine: its job is to strip
  the stealth so a garrison, Wall, or other nearby defense can finish it, not to
  out-tank an entire squad alone. Against a single stealthed unit its own stats hold up
  fine — Stone Tower's 300 HP/28 dmg/range 6 beats a Light Tank's 180 HP/15 dmg/range 4
  in a straight 1v1.
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

## Resolved (previously Open) Items
- Exact HP/damage/range/splash numbers for every defensive building are authored in
  `data/buildings/*.json`.
- Missile Launcher is confirmed the anti-air generalist (`damageDealtModifiers:
  {Air: 1.5}`).
- Radar Array carries the `detector: true` stealth-detection flag (no `detectionRange`
  override, so it detects at its full, long `visionRange`) and is `isFixed: true` —
  pre-seeded only, same as HQ/Ice Spire, so its map-wide `globalVisionRangeBonus`
  can't be stacked by building more than one. Tower is the Defensive building that
  doubles as a (short-range) detector — see the Tower section above.
- Defensive buildings use pure stat scaling per level (hp/damage/range via
  `nonProductionUpgrade`) — no new `can_target` entries unlock at higher levels.

## Known Data Inconsistencies (need a decision, not yet fixed)
- `data/buildings/emp_turret.json`'s `defensiveStats` omits `canTarget` entirely; per
  the `extends` rule in `data/buildings/schema.json` (a variant's `defensiveStats`
  overrides the base wholesale, not merged key-by-key), this Turret variant may not be
  able to target anything as authored.

## Resolved Decisions
- **Walls never attack** — purely passive HP barriers, no contact/spike damage. This is
  final, not just a default.
- **Rebuild cost**: flat 50% of original cost, same material (see Structural Stats
  table above).
- **Demolish (voluntary removal) is a separate mechanic from ruin-rebuild**: refunds
  50% of total resources spent (not a cost like rebuild-from-ruin is), frees the hex/
  population slot immediately with no ruin, and isn't available for `isFixed`
  buildings (HQ, Ice Spire). See `02-bases-and-buildings.md`'s Demolishing Buildings
  section and `07-data-architecture.md`'s `BuildingInstance.totalResourcesSpent`.
