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
- **Domain** (`Infantry` / `Land` / `Air` / `Naval`) — which terrain/movement ruleset
  applies by default (see `01-map-and-terrain.md`). Determines base eligibility to
  cross forest/river/etc. before any per-unit overrides. **Infantry is its own Domain,
  not a tag under `Land`** — the terrain table in `01-map-and-terrain.md` already gives
  Infantry and Land Vehicles genuinely different default rules (Forest blocks Land
  Vehicles but not Infantry; Hills slow Infantry but not vehicles), so `Land` now means
  land *vehicles* specifically. This also means Domain doubles as a matchable key for
  the damage modifier dictionaries below, the same way tags do — see Damage Modifiers.
- **Category/Trait tags** (list, e.g. `[Vehicle, Tank, Heavy]`) — descriptive labels
  used purely so other units' modifier dictionaries can reference them. A unit can
  carry as many tags as make sense (e.g. Flame Helicopter might be `[Aircraft,
  Helicopter, Fire]`).

### Core Combat Stats
- **HP** — how much damage a unit can take before dying.
- **Armor** (number, default 0) — flat damage reduction applied to each incoming hit,
  after `damage_received_modifiers`/`Piercing` are resolved, floored so a hit always
  deals at least 1 damage. Distinct from `damage_received_modifiers`, which is a
  multiplier rather than a flat subtraction — the two stack (multiplier first, then
  flat reduction). Introduced for **Shielder** (see `08-troop-roster.md`), a pure
  tank/meatshield with no attack of its own.
- **Damage** — base damage per attack, before any modifiers are applied.
- **Attack speed** — how often it attacks (attacks per time unit).
- **Range** — max distance at which it can engage a target. Deliberately separate
  from Vision range.
- **Splash radius** — 0 for single-target units; >0 applies damage to a radius around
  the impact point (e.g. Grenade Tower, Hot Air Balloon, Plasma Helicopter).
- **Vision range** — how far the unit can see, kept separate from Range so a unit can
  spot an enemy before being able to fight it (or vice versa), giving reaction time.

### Movement
- **Speed** — base movement rate, in **hexes per second** (not per tick — see
  `01-map-and-terrain.md`'s Movement & Positioning section for the exact per-tick
  formula, `(speed / terrainCostMultiplier) * tickDuration`; harder terrain divides
  effective speed down, it does not multiply it up).
- **Terrain overrides** — per-unit exception flags layered on top of the Domain's
  default terrain behavior. Example: Quad-bike is `Domain: Land`, which normally means
  "blocked by Forest," but carries `ignores_forest_block: true` to override just that
  one rule. This avoids rewriting terrain logic per unit — defaults come from Domain,
  exceptions come from flags.
- **Domain terrain defaults** (see `01-map-and-terrain.md`): `Infantry` — blocked by
  River (needs a Bridge), slowed by Hills, normal on Forest/Plains; `Land` (vehicles) —
  blocked by Forest (needs a Road) and River (needs a Bridge), normal on Hills/Plains;
  `Air` — ignores all terrain restrictions; `Naval` — Ocean/River only, disembarks only
  at a Dock/Port/Shipyard.

### Targeting
- **can_target** (list of Domains/tags, e.g. `[Land, Naval]`) — a hard restriction on
  what a unit is even allowed to engage, independent of range. An empty list means the
  unit cannot attack at all (e.g. **Engineer**). This is how "Hot Air Balloon can't hit
  aircraft" and "some infantry can't hit aircraft" are both expressed with the same
  mechanism, rather than special-cased per unit.
- **Resolved: `Structure` is a reserved value** usable in `can_target` (and in the
  damage modifier dictionaries below), covering **buildings and walls uniformly,
  except Defensive-category buildings** — there's no separate "Building" vs. "Wall"
  target kind, since the ability to attack one implies the ability to attack the
  other. Most combat troops include `Structure` in `can_target` by default, since
  sieging buildings/HQs is core to the conquest win condition — **Sniper** is a
  deliberate exception that omits it (see `08-troop-roster.md`). Default (undirected)
  auto-targeting still only ever picks the nearest enemy **troop** in range, though —
  attacking a Structure normally requires an explicit directed order (see
  `04-combat.md`), the one exception being siege troops (below).
- **Resolved: `Defensive` is a second reserved value**, split out from `Structure`,
  covering Defensive-category buildings specifically (Turret, Missile Launcher,
  Grenade Tower, Flame/Cold Turret, River Battery, Tower — matches
  `data/buildings/schema.json`'s `category: "Defensive"`). A troop must list
  `Defensive` separately from `Structure` to be able to target base defenses at all —
  e.g. **Basekiller** carries `can_target` including `Defensive` but not `Infantry`,
  and `damage_dealt_modifiers: { Defensive: 2.5 }` for a large bonus specifically vs.
  base defenses (see `08-troop-roster.md`).

### Squads & Siege Behavior
- **max_squad_size** (number, default a common baseline) — how many of this troop
  type can share one squad (see `07-data-architecture.md`'s `SquadInstance`). A
  freshly produced troop auto-joins the nearest same-type squad below this cap, or
  starts a new squad of 1. Set to **1** for troops that never merge (Engineer,
  Commander, Disruptor).
- **max_squads_led** (number, Commander-tagged troops only) — how many squads this
  Commander can lead as a **regiment** (baseline **4** — see `04-combat.md`).
- **commander_tier** (enum `basic` / `rare` / `best`, Commander-tagged troops only) —
  which Command Centre level unlocks this Commander: `basic` at level 1, `rare` at
  level 2, `best` at level 3 (all lower tiers stay unlocked at higher levels — see
  `02-bases-and-buildings.md`'s Command Centre & the Commander Cap section and
  `06-building-stats-and-defenses.md`). Not the same thing as `max_squads_led` — tier
  gates *which Commanders are trainable*, not how large their regiment is.
- **prioritize_structures** (bool, default false) — a siege-behavior flag: when true,
  and nothing is directly attacking it, this unit's default auto-targeting picks the
  nearest **Structure** (building/wall) over enemy troops, letting a dedicated siege
  unit beeline for defenses/the HQ without needing a per-target click. Regular troops
  (flag false) always default to nearest-enemy-**troop**, and need an explicit
  directed order (see `04-combat.md`) to attack a Structure at all.

### Damage Modifiers (the "strong/weak against" system)
- Modifier dictionary keys can be **a Domain value, a descriptive tag, or a
  damage type** (see `damage_types` below) — all three are matched against the target
  the same way, so there's no separate mechanism needed for "vs a movement class" vs.
  "vs a descriptive trait" vs. "vs a kind of attack."
- **Damage dealt modifiers** (`{tag_or_domain: multiplier}`) — e.g. an anti-air unit
  might carry `{Air: 1.5}`, meaning it deals 1.5x its base damage to anything with
  Domain `Air`. **Grenadier** carries `{Land: 1.5}` — a bonus against `Land`-domain
  targets (i.e. land vehicles) specifically, which does *not* apply to Air/Naval units
  even if they also happen to carry a `Vehicle` tag, and does not apply to Infantry
  (Infantry is a separate Domain, not part of `Land`). If a target's tags/domain don't
  match any entry, the multiplier defaults to 1.0 (no bonus/penalty). **Basekiller**
  carries `{Defensive: 2.5}` — a large bonus specifically vs. Defensive-category
  buildings, using the `Defensive` reserved key split out from `Structure` above.
- **Resolved: a multiplier entry doubles as a target-priority hint.** If a troop has
  any `damage_dealt_modifiers` entry above 1.0 for a tag/Domain/reserved value, and a
  target matching that entry is in range, the troop's default auto-targeting prefers
  it over the plain nearest-enemy rule — e.g. Grenadier prefers a `Land`-domain target
  over an equally-near Rifleman, and **Basekiller** (with `prioritizeStructures: true`
  and a `Defensive` bonus) prefers the nearest Defensive building over any other
  Structure in range. This only re-orders *which* in-range/allowed target is picked
  first; it doesn't expand `can_target` or override an explicit directed order (see
  `04-combat.md`).
- **Damage received modifiers** (`{tag_or_domain: multiplier}`) — the same idea from
  the receiving end. E.g. a Wood Wall might carry `{Fire: 2.0}`, taking double damage
  from any attacker whose `damage_types` includes `Fire`. A Turret might carry
  `{Air: -0.5}` (meaning it takes only half damage from air attackers) if that's a
  bonus you want towers to have vs. air raids.
- Both dictionaries stack multiplicatively with each other and with terrain/aura
  bonuses (consistent with the "bonuses stack" rule already established for base
  defenses).

### Damage Types (the "what kind of hit is this" label)
- **damage_types** (list, e.g. `[Fire]`, `[Piercing]`) — labels describing the nature
  of an attack, kept **separate from Category/Trait tags** so combat-relevant labels
  (which feed the modifier-matching system above) don't get mixed with purely
  descriptive/matchmaking tags (`Vehicle`, `Tank`, `Heavy`, etc.). A value here is
  matched against a target's `damage_received_modifiers` exactly like a Domain or tag
  — e.g. Flamethrower/Flame Turret carry `[Fire]`, which is what triggers a Wood
  Wall's `{Fire: 2.0}` entry.
- **Reserved value `Piercing`**: rather than being matched against
  `damage_received_modifiers`, it **bypasses them entirely** — the attack ignores
  whatever armor-type modifiers the target has. This is how **Sniper**'s "damage
  bypasses target armor/damage-received modifiers" is expressed as data rather than a
  special case. Piercing only cancels the *target's* received-side modifiers; the
  attacker's own `damage_dealt_modifiers` (its Domain/tag-based bonuses) still apply
  normally on top.
- **Splash is not a damage type.** It's a delivery mechanism, not a resistance label,
  and it's already fully expressed by the `splash_radius` field above — a splash
  attack can independently carry `damage_types: [Fire]` (or nothing at all) on top of
  its radius; the two are orthogonal.

### Detection & Stealth
- **stealth** (bool) — if true, the unit is invisible to enemies beyond its
  `reveal_range`.
- **reveal_range** — the distance at which a stealthed unit becomes visible to a normal
  (non-detector) enemy unit — i.e. "really close" per your description.
- **detector** (bool) — if true, this unit/building can see stealthed units at its full
  normal vision range, ignoring `reveal_range` entirely. Lets you design specific
  counter-play (build/bring a detector to neutralize enemy stealth) rather than making
  stealth uncounterable or trivially countered by everything.
- **reveals_on_attack** (bool) — if true, the unit's own stealth breaks the instant it
  attacks: it becomes visible to everyone (not just detectors or units within
  `reveal_range`), and stays visible until a few seconds pass without it attacking
  again, at which point it re-cloaks. Example: Ghost Tank (Signal Ridge) — see
  `02-bases-and-buildings.md`.

### Support Units
- **auras** (optional **list** of objects: `{radius, target, filter, effect,
  magnitude}`) — support units/buildings project a passive effect onto nearby units
  (or buildings) rather than (or in addition to) fighting directly. A unit/building
  can carry more than one aura at once. **target** says who the aura affects:
  - `friendly_troops` (default/most common) — e.g. Shield Tank →
    `{radius: 3, target: friendly_troops, effect: damage_reduction, magnitude: 20%}`.
  - `enemy_troops` — a debuff aura. E.g. Winter Forge's Ice Spire →
    `{radius: X, target: enemy_troops, effect: slow, magnitude: Y%}`.
  - `friendly_buildings` (optionally narrowed with **filter**, e.g. a specific
    building type) — a buff aimed at buildings rather than troops. E.g. Ice Spire's
    second aura → `{radius: base-wide, target: friendly_buildings, filter: "Oil Rig",
    effect: production_boost, magnitude: Z%}`.
  - `enemy_buildings` (optionally narrowed with **filter**) — a debuff aimed at an
    enemy building's *function* rather than damaging it. E.g. Signal Ridge's
    Disruptor → `{radius: X, target: enemy_buildings, filter: "Defensive",
    effect: suppress_targeting}` — enemy Turrets/Missile Launchers/specialty defenses
    within radius stop firing while the Disruptor is alive; killing the Disruptor
    immediately restores them. This is why the Disruptor has to be escorted into range
    rather than sitting at its own base — unlike other auras, it only matters deep in
    enemy territory.
  Aura effects stack with terrain, wall, and other aura bonuses like everything else.

### Construction
- **can_build_infrastructure** (bool, default false) — if true, this unit can construct
  standalone Road/Bridge/Dock/Tower (see `01-map-and-terrain.md` and
  `02-bases-and-buildings.md`). Only **Engineer** has this today; the buildable set
  itself is fixed rather than per-unit, so a single boolean is sufficient rather than
  a list like `can_target`/`cargo_allowed_tags`.

### Transport / Cargo
- **cargo_capacity** (number, 0 = cannot transport) — how many **squads** this troop
  can carry aboard it, not individual troop headcount — a boarding squad occupies
  exactly one slot regardless of its own size (see `07-data-architecture.md`'s
  `SquadInstance.cargoSquadIds`, which capacity is checked against directly).
  Confirmed carriers so far: **Aircraft Carrier** (Kraken Point) and
  **Transport Carrier** (Capital Factory).
- **cargo_allowed_tags** (list of Domains/tags) — what it's allowed to load, same
  mechanism as `can_target`. Aircraft Carrier carries `Air`-tagged troops; Transport
  Carrier carries `Infantry`-tagged land troops.
- **can_launch_cargo_mid_combat** (bool) — confirmed **true** for both Aircraft Carrier
  and Transport Carrier: cargo isn't just passive storage, it can be deployed mid-battle
  rather than only when idle/docked.
- Fuel/upkeep for cargo while stored: aircraft aboard an Aircraft Carrier don't consume
  Fuel while docked (consistent with the "docked adjacent to a base" Fuel-free rule —
  a Carrier counts as a mobile dock for this purpose).
- **Resolved: boarding/unloading are explicit orders** (`board` targeting a carrier
  squad; `unload` naming which boarded squad to deploy) — see `04-combat.md`'s Cargo
  section. A boarded squad keeps counting against its owner's global squad cap while
  aboard, and **if the carrier squad is destroyed while loaded, every boarded squad
  and its troops are destroyed along with it** — no survivors spill out.

### Status Effects (on-hit)
- **status_effect_on_hit** (optional object: `{type, duration, magnitude?}`) — some
  attacks apply a temporary condition to the target on a successful hit, separate from
  (or in addition to) direct damage. Example: Cold Turret (Winter Forge) →
  `{type: freeze, duration: "2-3s"}` — the target can't move or attack for the
  duration. This is the same "flags describe special behavior" pattern used
  elsewhere in the schema (stealth, terrain overrides) rather than a one-off case.

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
| Domain | enum | Infantry / Land / Air / Naval — Land means land *vehicles*; also usable as a modifier-dictionary key, same as tags |
| Category/Trait tags | list | e.g. `[Vehicle, Tank, Heavy]` |
| HP | number | |
| Armor | number | default 0; flat damage reduction per hit, applied after damage_received_modifiers/Piercing, floored at 1 damage; stacks with (doesn't replace) the multiplier-based modifiers |
| Damage | number | base, before modifiers |
| Attack speed | number | attacks per time unit |
| Range | number | separate from vision |
| Splash radius | number | 0 = single-target |
| Vision range | number | separate from engagement range |
| Speed | number | |
| Terrain overrides | flags | e.g. `ignores_forest_block` |
| can_target | list of tags | empty list = non-combat (e.g. Engineer); reserved value `Structure` covers buildings+walls EXCEPT Defensive-category buildings; reserved value `Defensive` covers those separately and must be listed to be attackable |
| max_squad_size | number | default common baseline; 1 for troops that never merge (Engineer, Commander, Disruptor) |
| max_squads_led | number | Commander-tagged troops only; baseline 4 |
| commander_tier | enum: basic/rare/best | Commander-tagged troops only; which Command Centre level unlocks this Commander (see `02-bases-and-buildings.md`) |
| prioritize_structures | bool | default false; true = default-targets nearest Structure over troops (siege behavior) |
| Damage dealt modifiers | dict `{tag_or_domain: multiplier}` | "strong against"; key may be a Domain value (e.g. `Land`), a tag, a damage type, or `Structure`/`Defensive`; any entry above 1.0 also acts as a target-priority hint (see Damage Modifiers section) |
| Damage received modifiers | dict `{tag_or_domain: multiplier}` | "weak against"; key may be a Domain value, a tag, or a damage type |
| damage_types | list | e.g. `[Fire]`, `[Piercing]`; matched against damage received modifiers, except `Piercing` which bypasses them entirely; splash is NOT a damage type (see splash_radius) |
| stealth | bool | |
| reveal_range | number | distance at which stealth breaks vs. non-detectors |
| detector | bool | sees stealth at full vision range |
| cargo_capacity | number | counts SQUADS, not troop headcount; 0 = cannot transport; e.g. Aircraft Carrier, Transport Carrier |
| cargo_allowed_tags | list of tags | what it's allowed to load, same mechanism as `can_target` |
| can_launch_cargo_mid_combat | bool | true for Aircraft Carrier and Transport Carrier — cargo can deploy mid-battle, not just while idle |
| can_build_infrastructure | bool | default false; true = can construct standalone Road/Bridge/Dock/Tower. Only Engineer has this |
| auras | list of `{radius, target, filter, effect, magnitude}` | for support units/buildings; `target` = friendly_troops / enemy_troops / friendly_buildings |
| status_effect_on_hit | object `{type, duration, magnitude?}` | e.g. `{type: freeze, duration: 2s}` — applied to target on hit, alongside damage |
| Cost | dict per resource | Food/Steel/Stone/Fuel |
| Food upkeep | number | ongoing |
| Fuel upkeep | number | rules vary by Domain |
| Production time | number | per-unit training duration, per production building's own queue |

## Example Units Under This Schema (illustrative, not final stats)

**Engineer**
- Domain: Infantry · Tags: `[Support]`
- can_target: `[]` (cannot attack)
- Special: only unit that can build Roads/Bridges/Docks

**Hot Air Balloon**
- Domain: Air · Tags: `[Aircraft, Balloon]`
- can_target: `[Land, Naval]` (cannot target Air)
- Splash radius: high · Range: low · Speed: slow
- Fuel upkeep: modest (lighter than most aircraft)

**Glider** (Windy Peaks' Wind Sanctuary)
- Domain: Air · Tags: `[Aircraft, Scout]`
- can_target: `[]` (cannot attack — pure scout, like Engineer)
- Vision range: high · Speed: fast · Cost: cheap
- Fuel upkeep override: unpowered, so it uses **Food** upkeep instead of the Air
  domain's usual heavy Fuel upkeep — another example of a per-unit flag overriding a
  Domain default, same pattern as Quad-bike's terrain override below.

**Quad-bike**
- Domain: Land · Tags: `[Vehicle, Light]`
- Terrain override: `ignores_forest_block: true`
- HP/Damage: low (fragile, fast scout/harassment unit)

**Transport Carrier** (Capital Factory)
- Domain: Land · Tags: `[Vehicle, Support]`
- can_target: `[]` or minimal (little/no attack — see `08-troop-roster.md`)
- cargo_capacity: > 0 · cargo_allowed_tags: `[Infantry]` · can_launch_cargo_mid_combat: true

**Aircraft Carrier** (Kraken Point Shipyard)
- Domain: Naval · Tags: `[Ship, Carrier]`
- cargo_capacity: > 0 · cargo_allowed_tags: `[Air]` · can_launch_cargo_mid_combat: true
- Docked aircraft use no Fuel while stored, same as being docked adjacent to a base

**Shield Tank** (future/planned)
- Domain: Land · Tags: `[Vehicle, Tank, Support]`
- aura: `{radius: 3, effect: damage_reduction, magnitude: 20%}`

**Stealth Unit** (future/planned)
- stealth: true · reveal_range: short
- Countered specifically by units/buildings with `detector: true`
