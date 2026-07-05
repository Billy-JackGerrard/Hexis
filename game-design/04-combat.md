# Combat

## Core Model
- Units **auto-attack** any enemy in range — there is no manual "attack" command.
- The player's only direct control is **movement**; combat resolves itself once units
  are within range of each other.
- Units **hold position and fight** rather than breaking formation to chase fleeing
  enemies — this keeps squad positioning predictable and readable.
- **Target priority**: nearest enemy in range.
- **Vision range and engagement (attack) range are separate** — a unit can see an
  enemy approaching before it's close enough to fight, giving the player a genuine
  reaction window (retreat, reposition, garrison a base, etc.).

## Squads
- Troops are selected and moved as **squads/groups**, not individually — necessary
  given the scale of multiple bases and fronts.
- A squad can only contain **mixed unit types** if it's led by a **Commander**
  (a Capital-Base-only unit). Troops are assigned to a Commander to form a
  combined-arms squad.
- Without a Commander, a squad must be a single unit type.
- Squad movement speed is presumably capped by its slowest member (to be confirmed
  once vehicle/infantry speed stats are finalized).

## Base Defenses
- Bases have **static defenses** (Turret, Missile Launcher — universal; plus
  base-specific specialty defenses like Grenade Tower or Flamethrower) that also
  auto-attack anything in range, independent of garrisoned troops.
- **Defender bonuses stack**: e.g. a base on a hill with walls benefits from both the
  hill's defensive terrain bonus and the walls' defense bonus simultaneously — this
  rewards capturing/holding naturally strong positions.

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
- Exact squad speed rule when mixing unit types under a Commander.
- Whether the Aircraft Carrier can launch its stored aircraft mid-battle or is purely
  a mobile storage/defense platform.
