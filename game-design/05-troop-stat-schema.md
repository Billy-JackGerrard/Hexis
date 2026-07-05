# Troop Stat Schema

## The Gist
Every troop is defined by a common **data schema** rather than hand-coded logic per
unit. A unit is built from:
1. A set of **tags** describing what it *is* (domain, category, traits).
2. A set of **base stats** (HP, damage, speed, etc).
3. A set of **modifier dictionaries** describing how it performs *against* other tags
   (bonus/penalty damage dealt, bonus/penalty damage received).
4. A set of **flags** for special behavior (can't attack, ignores a terrain rule, is
   stealthed, provides an aura, etc).

Because bonuses/weaknesses are expressed as "multiplier vs. tag" rather than a fixed
matchup table, adding a new unit later never requires editing existing units — you
just give the new unit its own tags and modifier entries, and every existing unit's
"vs tag" rules automatically apply to it if it shares a tag. This keeps the roster open
for future additions (Shield Tank, Stealth unit, etc.) without a redesign.

## Field-by-Field Explanation

### Identity
- **Domain** (`Land` / `Air` / `Naval`) — which terrain/movement ruleset applies by
  default (see `01-map-and-terrain.md`). Determines base eligibility to cross
  forest/river/etc. before any per-unit overrides.
- **Category/Trait tags** (list, e.g. `[Vehicle, Tank, Heavy]`) — descriptive labels
  used purely so other units' modifier dictionaries can reference them. A unit can
  carry as many tags as make sense (e.g. Flame Helicopter might be `[Aircraft,
  Helicopter, Fire]`).

### Core Combat Stats
- **HP** — how much damage a unit can take before dying.
- **Damage** — base damage per attack, before any modifiers are applied.
- **Attack speed** — how often it attacks (attacks per time unit).
- **Range** — max distance at which it can engage a target. Deliberately separate
  from Vision range.
- **Splash radius** — 0 for single-target units; >0 applies damage to a radius around
  the impact point (e.g. Grenade Tower, Hot Air Balloon, Plasma Helicopter).
- **Vision range** — how far the unit can see, kept separate from Range so a unit can
  spot an enemy before being able to fight it (or vice versa), giving reaction time.

### Movement
- **Speed** — base movement rate.
- **Terrain overrides** — per-unit exception flags layered on top of the Domain's
  default terrain behavior. Example: Quad-bike is `Domain: Land`, which normally means
  "blocked by Forest," but carries `ignores_forest_block: true` to override just that
  one rule. This avoids rewriting terrain logic per unit — defaults come from Domain,
  exceptions come from flags.

### Targeting
- **can_target** (list of Domains/tags, e.g. `[Land, Naval]`) — a hard restriction on
  what a unit is even allowed to engage, independent of range. An empty list means the
  unit cannot attack at all (e.g. **Engineer**). This is how "Hot Air Balloon can't hit
  aircraft" and "some infantry can't hit aircraft" are both expressed with the same
  mechanism, rather than special-cased per unit.

### Damage Modifiers (the "strong/weak against" system)
- **Damage dealt modifiers** (`{tag: multiplier}`) — e.g. an anti-air unit might carry
  `{Air: 1.5}`, meaning it deals 1.5x its base damage to anything tagged `Air`. If a
  target's tags don't match any entry, the multiplier defaults to 1.0 (no bonus/penalty).
- **Damage received modifiers** (`{tag: multiplier}`) — the same idea from the
  receiving end. E.g. a Wood Wall might carry `{Fire: 2.0}`, taking double damage from
  any attacker tagged `Fire`. A Turret might carry `{Air: -0.5}` (meaning it takes only
  half damage from air attackers) if that's a bonus you want towers to have vs. air raids.
- Both dictionaries stack multiplicatively with each other and with terrain/aura
  bonuses (consistent with the "bonuses stack" rule already established for base
  defenses).

### Detection & Stealth
- **stealth** (bool) — if true, the unit is invisible to enemies beyond its
  `reveal_range`.
- **reveal_range** — the distance at which a stealthed unit becomes visible to a normal
  (non-detector) enemy unit — i.e. "really close" per your description.
- **detector** (bool) — if true, this unit/building can see stealthed units at its full
  normal vision range, ignoring `reveal_range` entirely. Lets you design specific
  counter-play (build/bring a detector to neutralize enemy stealth) rather than making
  stealth uncounterable or trivially countered by everything.

### Support Units
- **aura** (optional object: `{radius, effect, magnitude}`) — support units project a
  passive effect onto nearby friendly units rather than (or in addition to) fighting
  directly. Example: Shield Tank → `{radius: 3, effect: damage_reduction,
  magnitude: 20%}`, boosting armor/damage reduction for anything friendly standing
  within 3 tiles. Aura effects stack with terrain and wall bonuses like everything else.

### Upgrades
- **Troops cannot be upgraded** once trained. A unit's stats are fixed for its
  lifetime — getting access to stronger units comes from capturing/unlocking new
  production buildings or better unit types within an existing building's roster, not
  from upgrading individual troops. This is the opposite of buildings, which *can* be
  upgraded (see `06-building-stats-and-defenses.md`).

### Economy
- **Cost** (dict per resource — Food/Steel/Stone/Fuel as relevant) — one-time cost to
  produce the unit.
- **Food upkeep** — ongoing Food consumption while the unit exists.
- **Fuel upkeep** — ongoing Fuel consumption; rules differ by Domain (land
  vehicles: only while moving; aircraft: constant unless docked adjacent to a base;
  ships: minimal regardless of state — see `03-resources.md`).
- **Production time** — troop training is **not instant** (unlike building
  construction). This is why a base can build multiple copies of the same production
  building (e.g. two Barracks = double infantry output) — each building has its own
  independent queue and its own production-time countdown per unit.

## Full Schema Reference (implementation-ready shape)

| Field | Type | Notes |
|---|---|---|
| Domain | enum | Land / Air / Naval |
| Category/Trait tags | list | e.g. `[Vehicle, Tank, Heavy]` |
| HP | number | |
| Damage | number | base, before modifiers |
| Attack speed | number | attacks per time unit |
| Range | number | separate from vision |
| Splash radius | number | 0 = single-target |
| Vision range | number | separate from engagement range |
| Speed | number | |
| Terrain overrides | flags | e.g. `ignores_forest_block` |
| can_target | list of tags | empty list = non-combat (e.g. Engineer) |
| Damage dealt modifiers | dict `{tag: multiplier}` | "strong against" |
| Damage received modifiers | dict `{tag: multiplier}` | "weak against" |
| stealth | bool | |
| reveal_range | number | distance at which stealth breaks vs. non-detectors |
| detector | bool | sees stealth at full vision range |
| aura | object `{radius, effect, magnitude}` | for support units |
| Cost | dict per resource | Food/Steel/Stone/Fuel |
| Food upkeep | number | ongoing |
| Fuel upkeep | number | rules vary by Domain |
| Production time | number | per-unit training duration, per production building's own queue |

## Example Units Under This Schema (illustrative, not final stats)

**Engineer**
- Domain: Land · Tags: `[Infantry, Support]`
- can_target: `[]` (cannot attack)
- Special: only unit that can build Roads/Bridges/Docks

**Hot Air Balloon**
- Domain: Air · Tags: `[Aircraft, Balloon]`
- can_target: `[Land, Naval]` (cannot target Air)
- Splash radius: high · Range: low · Speed: slow

**Quad-bike**
- Domain: Land · Tags: `[Vehicle, Light]`
- Terrain override: `ignores_forest_block: true`
- HP/Damage: low (fragile, fast scout/harassment unit)

**Shield Tank** (future/planned)
- Domain: Land · Tags: `[Vehicle, Tank, Support]`
- aura: `{radius: 3, effect: damage_reduction, magnitude: 20%}`

**Stealth Unit** (future/planned)
- stealth: true · reveal_range: short
- Countered specifically by units/buildings with `detector: true`
