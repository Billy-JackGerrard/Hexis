# Combat

## Core Model
- Units **auto-attack** any enemy in range — there is no manual "attack" command.
- The player's only direct control is **movement**; combat resolves itself once units
  are within range of each other.
- Units **hold position and fight** rather than breaking formation to chase fleeing
  enemies — this keeps squad positioning predictable and readable.
- **Target priority**: nearest enemy in range, by default.
- **Resolved: a damage-dealt-modifier bonus re-orders that default.** If a troop has
  a `damageDealtModifiers` entry above 1.0 matching something in range, it prefers
  that target over an equally-or-nearer plain target — e.g. Grenadier prefers a
  `Land`-domain vehicle over an equally-near Rifleman. This only changes *which*
  already-allowed target gets picked first; it never expands `canTarget` or overrides
  an explicit directed order (see `05-troop-stat-schema.md`'s Damage Modifiers
  section).
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
  - **Resolved: this is also how a siege is directed at a building or the HQ itself.**
    Default (undirected) auto-targeting only ever picks the **nearest enemy troop**
    in range — defensive buildings/walls in the way don't get auto-attacked just for
    standing between a squad and the enemy. To actually clear a path and reach a
    structure, the player clicks it directly (same mechanic as clicking an enemy
    troop above), and the squad will fight through whatever's defending it to reach
    and attack that specific target.
  - **Siege troops** (schema flag `prioritizeStructures` — see
    `05-troop-stat-schema.md`) invert the *default*: with no explicit order and
    nothing directly attacking them, they auto-target the nearest building/wall
    (Structure OR Defensive) over enemy troops, letting a dedicated siege unit
    beeline for defenses/HQ without a per-target click. Regular troops never do this
    on their own — they always need the explicit directed order above to attack a
    structure. **Basekiller** combines this with a `Defensive` damage bonus, so among
    in-range structures it further prefers Defensive buildings specifically (see the
    damage-modifier target-priority rule above).
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
  4 squads), which then **follows the Commander** as its rally point/anchor — this is
  how a player mixes troop types (e.g. an infantry squad + a vehicle squad) under one
  combined command instead of moving single-type squads independently.
- **Resolved: if a Commander dies mid-battle, its regiment disbands** — every member
  squad reverts to operating independently (no more shared rally point, no more buff
  aura). Re-forming the regiment requires assigning those squads to a (living)
  Commander again.
- **Resolved: a regiment's movement speed is capped by its slowest member squad.**

#### Commander Tiers & the Commander Cap
**Resolved**: the Command Centre doesn't unlock Commanders one-per-level like a normal
production building. Commanders are split into three tiers (`basic` / `rare` / `best`,
a field on each Commander's troop definition):
- **Command Centre level 1** unlocks **every** `basic`-tier Commander at once (not just
  one), and contributes 1 slot to the player's **Commander cap**.
- **Level 2** additionally unlocks every `rare`-tier Commander.
- **Level 3** additionally unlocks every `best`-tier Commander — full roster available.
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
- **Boarding**: a squad boards a carrier squad (Transport Carrier, Aircraft Carrier)
  via a `board` order targeting the carrier squad, provided the carrier has open
  cargo capacity and the boarding squad's Domain/tags are in the carrier's
  `cargoAllowedTags` (see `05-troop-stat-schema.md`). A boarded squad's position
  becomes the carrier's — it stops pathing/acting independently until unloaded.
- **A boarded squad still counts against the owner's global squad cap** — boarding
  doesn't grant a "free" squad; it just changes how that squad moves for as long as
  it's aboard.
- **Launching/unloading**: an `unload` order deploys a specific boarded squad at the
  carrier's current hex (or an adjacent hex), resuming its independent movement/combat.
  Confirmed **mid-battle capable** for both Aircraft Carrier and Transport Carrier
  (`can_launch_cargo_mid_combat`) — not restricted to idle/docked moments.
- **Resolved: if a carrier squad is destroyed while troops are boarded, everything
  aboard dies with it** — boarded squads (and their member troops) are removed from
  the game entirely, the same way a losing player's remaining squads are cleared on
  elimination. There's no "cargo spills out" recovery; escorting a loaded carrier
  matters for exactly this reason.

## Base Defenses
- Bases have **static defenses** (Turret, Missile Launcher — universal; plus
  base-specific specialty defenses like Grenade Tower, Flame Turret, or Winter Forge's
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
  new schema field (`status_effect_on_hit`), not a special case — see
  `05-troop-stat-schema.md`.
- **All buildings and walls regenerate HP slowly over time** once out of combat —
  damage from a fight isn't permanent unless the structure is actually destroyed
  during the fight.

## Terrain Interaction in Combat
- See `01-map-and-terrain.md` for the full terrain/movement table. Key combat-relevant
  points:
  - Forests grant an ambush bonus (attacker hidden until engaging).
  - Hills give a defender bonus to troops stationed there.
  - Plains offer no combat bonus but extended vision.

## Infrastructure Combat
- Roads, Bridges, and Docks can be destroyed by any troop, but only after any
  defenders garrisoned on/near the structure have been cleared first — this creates a
  natural "escort the Engineer" and "garrison the chokepoint" dynamic.

## Open / Unresolved Items
- Full unit stat design (health, damage, speed, splash radius, rock-paper-scissors
  matchups) — see `08-troop-roster.md`.
- Named Commander roster and each one's specific buff/ability — still TBD.

## Resolved Decisions
- **Commander dies mid-battle → squad disbands** (see Commanders section above).
- **Mixed-squad speed = slowest member's speed.**
- **Aircraft Carrier and Transport Carrier can both launch/deploy their cargo
  mid-battle** — not purely storage/transport-while-idle. See `05-troop-stat-schema.md`'s
  Transport/Cargo fields (`can_launch_cargo_mid_combat`).
- **Boarding is an explicit order, cargo counts against squad cap, and cargo dies with
  its carrier** — see Cargo section above.
- **Global squad cap formula**: `(sum of hqLevel across owned bases) * 2 + 2` (starts
  at 3) — see Squads section above.
- **Commander cap is tiered and Command-Centre-count-based**, separate from the squad
  cap — see Commander Tiers & the Commander Cap above.
