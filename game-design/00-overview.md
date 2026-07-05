# Game Design Overview

## Concept
A cartoon-style, 2.5D top-down/isometric strategy game. Each match lasts roughly
**40 minutes**. Players expand by capturing bases across a hex-tile map — there is
no "found a new base" option; growth comes purely through conquest.

## Core Pillars
- **Territory conquest**: grow your holdings by capturing bases, not building new ones.
- **Positioning over micromanagement**: combat auto-resolves (units auto-attack nearest
  enemy in range); the player's only direct lever is movement.
- **Asymmetric bases**: each Unique base has its own building set and troop roster,
  making *which* bases you hold shape your strategy, not just how many.
- **Logistics matter**: Food/Fuel deficits actively damage your forces, so supply lines
  and economy targets are as strategically important as military targets.
- **No hard "enemy territory"**: control is emergent — defined only by where your bases
  and troops physically are, not by zones or borders.

## Players & Win Condition
- Designed for **4 players** initially, with a scalable base:player ratio for other
  counts (see `01-map-and-terrain.md`).
- **Win**: capture all rival Capital Bases.
- **Elimination**: a player is only eliminated when they lose **all** bases (Capital or
  Unique) — losing your Capital just costs you its bonuses, it's not fatal.
- **Timer fallback**: if no player has won by 40 minutes, most Capitals/territory held wins.

## Base Ownership Rules
- Every player starts with one **Capital Base**.
- Capturing a rival's (or a now-neutral) Capital lets you **designate it as your new
  Capital** — Capital status is transferable, not tied to a fixed location.
- A player who loses their Capital keeps playing ("homeless") as long as they hold at
  least one other base; they can reclaim a Capital by retaking one by force.
- Unique bases (neutral city-states) start unclaimed and are the main early-game
  expansion targets.

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
  runtime state, ownership, map/terrain, resource ticking
- `08-troop-roster.md` — units defined so far, filled in against the schema (in progress)
- `09-ui-and-controls.md` — control scheme direction
