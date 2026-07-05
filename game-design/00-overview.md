# Game Design Overview

## Concept
A cartoon-style, 2.5D top-down/isometric strategy game. Each match lasts roughly
**40-60 minutes**. Players expand by capturing bases across a hex-tile map — there is no "found a new base" option; growth comes purely through conquest.

## Core Pillars
- **Territory conquest**: grow your holdings by capturing bases, not building new ones.
- **Positioning over micromanagement**: combat auto-resolves (units auto-attack nearest enemy in range); the player's only direct lever is movement, though the player can click on a squad, and click on an enemy troop or building; and the squad will attack that.
- **Asymmetric bases**: each Unique base has its own building set and troop roster,
  making *which* bases you hold shape your strategy, not just how many.
- **Logistics matter**: Food/Fuel deficits actively damage your forces, so an
  opponent's economy (Farms, Oil Rigs, Harbours) is as valid a target as their
  army — crippling their resource pool weakens everything they have, even without a
  direct fight. (Resources are a single shared pool per player, not per-base — this is
  aggregate economic warfare, not a "cut off the supply line to this army" mechanic.)
- **No hard "enemy territory"**: control is emergent — defined only by where your bases
  and troops physically are, not by zones or borders.

## Players & Win Condition
- Designed for **4 players** initially, with a scalable base:player ratio for other
  counts (see `01-map-and-terrain.md`).
- **Win**: capture every Capital Base in the game. The number of Capital Bases is fixed
  at match start (one per starting player) and never changes during the match, so this
  is always a concrete, checkable target regardless of how Capitals change hands.
- **Elimination**: a player is only eliminated when they lose **all** bases (Capital or
  Unique) — losing every Capital you hold costs you Command Centre access and each
  base's +50% bonus, but it's not fatal on its own.
- **Timer fallback**: if no player has won by 60 minutes, the player holding the most
  Capitals wins. Ties break down a fixed chain: **most Capitals** → if tied, **most
  bases overall** → if still tied, **most total buildings** across all owned bases →
  if still tied, **most total troops** → if that's *still* tied, it's a **draw**.

## Base Ownership Rules
- Every player starts with one **Capital Base**.
- **Capital status is permanent and cumulative, not transferable**: once a base is
  founded as a Capital, it is always a Capital, no matter who owns it. Capturing a
  rival's Capital gives you an *additional* Capital — its own Command Centre, its own
  +50% bonus — on top of any Capitals you already hold. There is no "designation"
  step and no cap of one Capital per player; a player can end up owning several
  Capitals at once.
- A player who loses every Capital they hold keeps playing ("homeless") as long as
  they hold at least one Unique base — but this is a real handicap, not a cosmetic
  one: without a Command Centre they cannot train new Commanders, and Commanders are
  the only way to field a combined-arms regiment (see `04-combat.md`). They recover by
  capturing any Capital Base — their original or a rival's — by force.
- Unique bases (neutral city-states) start unclaimed, but **not undefended**: they're
  pre-seeded with defensive buildings, walls, their troop-production building(s), and a
  standing garrison of whatever troops they can produce (see `02-bases-and-buildings.md`).
  They're still the main early-game expansion targets, just not a free first move.

## Document Index
- `01-map-and-terrain.md` — map shape, terrain types, naval rules, fog of war
- `02-bases-and-buildings.md` — base seeding, hex-adjacency building rule, full building
  reference table, Capital vs Unique base differences
- `03-resources.md` — resource list, production, consumption, deficit consequences
- `04-combat.md` — combat resolution, squads, commanders, defenses
- `05-troop-stat-schema.md` — the data schema every troop is built from, with a
  field-by-field explanation
- `06-building-stats-and-defenses.md` — building health/defense schema, defensive
  building stats
- `07-data-architecture.md` — how it's all actually stored: buildings, walls, troop
  runtime state, ownership, map/terrain, resource ticking; also the simulation/
  rendering split that keeps the single-player build multiplayer-ready
- `08-troop-roster.md` — units defined so far, filled in against the schema (in progress)
- `09-ui-and-controls.md` — control scheme direction
