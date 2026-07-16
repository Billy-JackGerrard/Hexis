# Combat

## Core Model
- Units **auto-attack** any enemy in range — there is no manual "attack" command.
- The player's only direct control is **movement**; combat resolves itself once units
  are within range of each other.
- Units **hold position and fight** rather than breaking formation to chase fleeing
  enemies — this keeps squad positioning predictable and readable.
- **Target priority**: nearest enemy in range, by default.
- **Resolved: `damageDealtModifiers` re-orders that default, in proportion to how
  much damage it actually changes.** A troop's priority value for an in-range
  target is its `damageDealtModifiers` product for that target (every matching
  entry multiplies together, exactly like the real damage calculation in
  `05-troop-stat-schema.md` — no matching entry defaults to 1.0). Highest value
  wins:
  - A value **above 1.0** (a bonus) is preferred over the neutral 1.0 default —
    e.g. Grenadier (`{"Land": 1.5}`) prefers a `Land`-domain vehicle over an
    equally-near Rifleman it has no modifier against.
  - A value **below 1.0** (a dampener, e.g. `0.5`) is *not* tied with the neutral
    default — it's deprioritized *below* it, since it deals strictly less damage
    than a target the troop has no modifier against. A troop only engages a
    dampened target once nothing better (bonus or neutral) is in range.
  - Distance is only the tie-breaker among targets with **exactly equal** values
    (including two neutral targets, or two targets sharing the same bonus/dampener
    value) — e.g. a troop with `{"Defensive": 2.5, "Land": 1.5}` picks a Defensive
    building over an equally- or even nearer Land vehicle, since 2.5 > 1.5.
  - This only changes *which* already-allowed target gets picked first; it never
    expands `canTarget` or overrides an explicit directed order (see
    `05-troop-stat-schema.md`'s Damage Modifiers section).
- **Focus-fire / structure-targeting override**: with a squad selected, clicking
  directly on a specific enemy **troop, squad, building, or wall** issues a
  **directed-target order** (`order: { type: "attack_target", targetId }` — see
  `07-data-architecture.md`'s `SquadInstance`) — the squad paths toward it if
  necessary and every member (in range) fires on that specific target instead of
  defaulting to nearest-enemy, until the target dies, leaves range/vision, or the
  player issues a new move/target order. This is the one exception to pure
  auto-resolve combat, and stays consistent with "movement is the only direct lever"
  by treating it as a targeted variant of a click-command rather than a manual attack
  action (see `09-ui-and-controls.md`).
  - **Resolved: `Defensive`-category buildings (Turret, Missile Launcher, Grenade
    Tower, Flame/Cold Turret, River Battery, Tower) are auto-targeted by default, the
    same as an enemy troop — no explicit order needed.** This applies to any troop
    that lists `Defensive` in its `canTarget` (see `05-troop-stat-schema.md`). The
    reasoning: Defensive buildings actively shoot at troops in range, so troops
    fighting back against them is the same "auto-resolve combat" default as fighting
    back against an enemy squad. If both an enemy troop and a Defensive building are
    in range, normal nearest-target/damage-modifier-priority rules above decide which
    is engaged first — a unit with a `Defensive` damage bonus (e.g. Basekiller)
    prefers the Defensive building even if a troop is equally near.
  - **Resolved: plain `Structure` targets (HQ, Farm, Barracks, walls, etc.) are also
    auto-targeted by default whenever no enemy troop or Defensive building is in
    range.** Any troop that lists `Structure` in its `canTarget` will, once nothing
    else is fighting it, automatically path to and attack the nearest such building or
    wall — no directed click required. This is a lower-priority tier than troops/
    Defensive buildings: as long as an enemy troop or Defensive building the unit can
    engage is in range, that's attacked first; the squad only turns on plain
    Structures once the immediate area is clear of those. A directed click still works
    exactly as described above, e.g. to make a squad path toward and commit to a
    *specific* distant Structure rather than whichever is nearest by default.
    **Basekiller** is a good example: `Defensive` and `Structure` in `canTarget` mean
    it auto-fights base defenses first, then auto-beelines for HQ/Farm/etc. once no
    Defensive building or troop is in range — combined with its `Defensive` damage
    bonus, it prefers Defensive buildings over any other target when several are in
    range (see the damage-modifier target-priority rule above).
- **Vision range and engagement (attack) range are separate** — a unit can see an
  enemy approaching before it's close enough to fight, giving the player a genuine
  reaction window (retreat, reposition, garrison a base, etc.).

## Squads
- Troops are selected and moved as **squads**, not individually — necessary given the
  scale of multiple bases and fronts. A squad is always **single unit type**; even a
  lone unit is just a squad of 1 (see `07-data-architecture.md`'s `SquadInstance`).
- A freshly produced troop spawns at the nearest unoccupied hex to its production
  building and auto-joins the nearest same-type squad with room (below that troop
  type's `maxSquadSize`), or forms a new squad of 1 if none is nearby/available. Some
  troop types (Engineer, Commander, Disruptor) have `maxSquadSize: 1` and never merge.
- **Global squad cap**: a player's max simultaneous squads =
  `(sum of hqLevel across every base they own) * 2 + 2` — every base (Capital and
  Unique alike) has its own HQ, per `02-bases-and-buildings.md`'s Base Seeding, so this
  scales with both base count and HQ development. A fresh player with a single
  level-1 Capital starts at cap **3** (`1 * 2 + 2`). If a player's total HQ levels
  drops (losing a base) and they're now *over* their new, lower cap, nothing is
  forcibly disbanded — existing squads keep fighting; the player simply can't form a
  new squad (via production) until they're back under the cap. See
  `07-data-architecture.md`'s production-queue-pause rule for what happens to a
  production order that would breach the cap.
- **Mixed unit types are never combined into one squad.** Instead, a **Commander**
  leads a **regiment** — a group of up to **4 squads** (each still single-type)
  that move and fight together under that Commander, achieving "combined arms" at the
  regiment level rather than by heterogeneous squad membership (see
  `07-data-architecture.md`'s `RegimentInstance`). Without being assigned to a
  Commander's regiment, a squad just operates on its own.

### Commanders
- Trained at the **Command Centre**, a Capital-only production building. Commanders
  are fairly expensive relative to regular troops.
- Each Commander is itself a troop with its own combat stats (HP/damage/speed/etc.,
  per the standard schema in `05-troop-stat-schema.md`) — it isn't purely a support
  unit sitting behind the squad.
- Each Commander additionally carries a **unique buff aura** (distinct per Commander —
  a small roster of named Commanders, not one generic unit) that applies to every
  squad in its regiment, on top of its own combat presence.
- Assigning a squad to a Commander adds it to that Commander's **regiment** (up to
  4 squads, **not counting the Commander's own squad** — a full regiment is the
  Commander plus 4 escorted squads), which then **follows the Commander** as its
  rally point/anchor — this is how a player mixes troop types (e.g. an infantry squad
  + a vehicle squad) under one combined command instead of moving single-type squads
  independently.
- **Resolved: joining/leaving a regiment are explicit player orders**
  (`assign_to_commander` targeting the Commander; `leave_regiment` with no target),
  not passive/automatic — see `07-data-architecture.md`'s `RegimentInstance` section
  for the full data-level rules, including rejection when the regiment is already at
  its 4-squad cap.
- **Resolved: if a Commander dies mid-battle, its regiment disbands** — every member
  squad reverts to operating independently (no more shared rally point, no more buff
  aura). Re-forming the regiment requires assigning those squads to a (living)
  Commander again.
- **Resolved: a regiment's movement speed is capped by its slowest member squad.**
- **Resolved: a regiment moves as a single lock-step block, not independently
  pathing squads chasing an anchor.** A move order issued to a Commander (or with
  its regiment selected) computes **one shared path** from the Commander's current
  position; every squad in the regiment — the Commander included — advances along
  that identical path in sync, hex-by-hex, at the regiment's capped (slowest-member)
  speed. Because stacking is unlimited (see `07-data-architecture.md`), this means
  the whole regiment literally occupies the same hex together at every step rather
  than spreading out or straggling around obstacles individually — the visual/
  gameplay expression of "squads under a Commander stick together." An individual
  squad that's been given a temporary ad hoc order (per the independent-selection
  rule in `09-ui-and-controls.md`) simply drops out of lock-step until it goes idle
  and rejoins the shared path.

#### Commander Tiers & the Commander Cap
**Resolved**: the Command Centre doesn't unlock Commanders one-per-level like a normal
production building. Commanders are split into three tiers (`common` / `rare` / `epic`,
a field on each Commander's troop definition), implemented by
`data/buildings/command_centre.json`'s progression. Full named roster: **Vanguard**
(`common`), **Nightfall** (`rare`), **Warden** (`epic`) — see `08-troop-roster.md` for
each one's unique aura.
- **Command Centre level 1** unlocks **every** `common`-tier Commander at once (not just
  one), and contributes 1 slot to the player's **Commander cap**.
- **Level 2** additionally unlocks every `rare`-tier Commander.
- **Level 3** additionally unlocks every `epic`-tier Commander — full roster available.
- **Level 4+**: no further unlocks — just HP growth, plus **+1 Commander-cap slot per
  level**.

A player's Commander cap is the **sum of every owned Command Centre's current slot
contribution** — capturing a rival's Capital adds its Command Centre's slots on top of
your own. Since a Commander is also a size-1 squad, training one consumes a slot
against **both** the Commander cap and the global squad cap above; a Command Centre's
queue pauses if either is full (see `07-data-architecture.md`). Losing a Command
Centre lowers the cap immediately; if that leaves the player over cap, existing
Commanders keep fighting — only *new* Commander production is blocked until the count
drops back under the (lower) cap. Full details and the data shape: see
`02-bases-and-buildings.md`'s Command Centre & the Commander Cap section and
`06-building-stats-and-defenses.md`.

### Cargo: Boarding, Launching, and Carrier Loss
- **Boarding**: a squad boards a carrier squad (Transport Truck, HMS Cuddles, Tank
  Carrier, Aircraft Carrier) via a `board` order targeting the carrier squad, provided
  the carrier has open
  cargo capacity and the boarding squad's Domain/tags are in the carrier's
  `cargoAllowedTags` (see `05-troop-stat-schema.md`). A boarded squad's position
  becomes the carrier's — it stops pathing/acting independently until unloaded.
- **A boarded squad still counts against the owner's global squad cap** — boarding
  doesn't grant a "free" squad; it just changes how that squad moves for as long as
  it's aboard.
- **Launching/unloading**: an `unload` order deploys a specific boarded squad at the
  carrier's current hex (or an adjacent hex), resuming its independent movement/combat.
  Confirmed **mid-battle capable** for both Aircraft Carrier and Transport Truck
  (`can_launch_cargo_mid_combat`) — not restricted to idle/docked moments.
- **Resolved: if a carrier squad is destroyed while troops are boarded, everything
  aboard dies with it** — boarded squads (and their member troops) are removed from
  the game entirely, the same way a losing player's remaining squads are cleared on
  elimination. There's no "cargo spills out" recovery; escorting a loaded carrier
  matters for exactly this reason.
- **A boarded squad can't be targeted, can't fire, and can't be given orders** while
  aboard — it has no independent position to fire from or be shot at, and stops
  reacting to player input entirely until unloaded.
- **Docking (Hangar)**: the building equivalent of boarding — a squad lands inside a
  building via a `dock` order (targeting the building instead of a carrier squad),
  gated by the same open-capacity/`cargoAllowedTags` check. Everything above applies
  identically: still counts against the squad cap, can't be targeted/fired
  at/ordered while docked, `undock` mirrors `unload` (including the mid-battle
  `can_launch_cargo_mid_combat` gate), and a building destroyed while occupied kills
  every docked squad with it — same "no spills out" rule as a destroyed carrier.
  **Hangar** is the first (and, as of this design pass, only) building with docking —
  see `03-resources.md`'s Fuel rules and `05-troop-stat-schema.md`'s Transport/Cargo
  section.
- **Building-gated cargo transfer (Cargocopter)**: separate from docking above, a
  carrier can also be flagged `cargoRequiresBuildingDock` (currently only
  **Cargocopter**), meaning it can only `board`/`unload` its own Infantry cargo while
  sitting on a hex that carries a building capable of docking *it* (i.e. a Hangar,
  matched the same way `dock` matches a squad against a building's `cargoAllowedTags`
  — see `05-troop-stat-schema.md`). This is distinct from the Naval coastline rule
  above (Tank Carrier/HMS Cuddles are gated by physics — Land/Infantry cargo simply
  can't stand on water, so a Dock/Port/Shipyard/Harbour is implicitly required): Air
  has no terrain that blocks a helicopter from meeting cargo anywhere, so Cargocopter
  needs this explicit flag instead. Critically, the Cargocopter itself never actually
  *docks* in the Hangar to transfer cargo — it just needs to be positioned on the
  Hangar's hex — so this never consumes one of the Hangar's own limited docking slots,
  which stay reserved for aircraft resting/refueling there.

## Base Defenses
- Bases have **static defenses** (Turret, Missile Launcher — universal; plus
  base-specific specialty defenses like Grenade Turret, Flame Turret, or Winter Forge's
  Cold Turret) that also auto-attack anything in range, independent of garrisoned
  troops.
- **Defender bonuses stack**: e.g. a base on a hill with walls benefits from both the
  hill's defensive terrain bonus and the walls' defense bonus simultaneously — this
  rewards capturing/holding naturally strong positions.
- **Capturing a base**: the HQ has its own HP and is fought down like any other
  building — there's no separate "capture" action or timer. Once an HQ's HP hits 0,
  the base immediately flips to the attacker's ownership and the HQ respawns at full
  HP under its new owner (see `02-bases-and-buildings.md`). Every other building at a
  captured base carries over exactly as it was (including any ruin/damage state).
  **Troops don't carry over** — garrisoned/defending squads keep their original
  owner regardless of the base flipping (see `02-bases-and-buildings.md`'s Initial
  Garrison section and `07-data-architecture.md`), unless this was the defender's
  last base, which eliminates them and clears their remaining squads instead.
- **Status effects beyond damage**: some attacks apply a temporary effect on hit
  rather than (or in addition to) damage — e.g. Winter Forge's Cold Turret **freezes**
  its target for a couple of seconds (can't move or attack while frozen). This is a
  schema field (`status_effect_on_hit`), not a special case — see
  `05-troop-stat-schema.md`. **`stun`** is a related but distinct effect type: the same
  full-lockout shape as freeze, but it always ends with a global, fixed follow-on
  debuff (-30% move/attack speed, lasting the same `duration` as the lockout itself)
  once the lockout expires — the -30%/-30% magnitude is a fixed rule of the `stun`
  type itself, not a number authored per building/troop, the same way HP regen is a
  global rule rather than a per-building stat; only the tail's *length* is derived
  from whatever `duration` was already set for the lockout.
- **All buildings and walls regenerate HP slowly over time** once out of combat —
  damage from a fight isn't permanent unless the structure is actually destroyed
  during the fight.

## Terrain Interaction in Combat
- See `01-map-and-terrain.md` for the full terrain/movement table. Key combat-relevant
  points:
  - Forests grant an ambush bonus (attacker hidden until engaging), but obstruct
    vision (own-tile halved, sightlines through it reduced further).
  - Hills give a defender bonus to troops stationed there, but obstruct vision
    identically to Forest (own-tile halved, sightlines through it reduced further).
  - Plains offer no combat bonus and no vision bonus — purely economic/buildable
    terrain.

## Infrastructure Combat
- Roads, Bridges, and Docks can be destroyed by any troop, but only after any
  defenders garrisoned on/near the structure have been cleared first — this creates a
  natural "escort the Engineer" and "garrison the chokepoint" dynamic.

## Status
Every mechanic above is implemented — full unit stats (`08-troop-roster.md`), the
named Commander roster (Vanguard/Nightfall/Warden), line attacks/`minRange`, and
ballistic `projectileSpeed` travel time. Two mechanics not detailed inline above:
ballistic shots aim at a fixed hex at the moment of firing, not a tracked target — a
repositioned target dodges the shot entirely, splash included, unless it only steps
just outside blast radius. A `lineAttack` with no `projectileSpeed` (Tank Obliterator)
resolves instantly, having no obvious travel time to model; one that also carries
`projectileSpeed` (Wind Spire) sweeps its beam hex-by-hex over time instead. See
`05-troop-stat-schema.md` for both fields.
