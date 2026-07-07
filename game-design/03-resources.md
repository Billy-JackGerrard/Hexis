# Resources

## Resource List

| Resource | Source(s) | Used for |
|---|---|---|
| Food | Farms, Harbour (Farm-equivalent, requires a Water-adjacent tile — see `02-bases-and-buildings.md`) | Troop creation + troop/base maintenance |
| Steel | Mines | Vehicle creation, vehicle maintenance, **Quarry** construction/upgrade, and (alongside Stone) general building construction |
| Fuel | Oil Rigs (all bases; Capital has -50% production penalty) | Vehicle & aircraft maintenance (ships use very little) |
| Stone | Quarry | Building construction, walls, bridges, roads, **Mine** construction/upgrade, and (alongside Steel) general building construction |
| Wood | Lumber Mill (any base with a Forest-adjacent tile, or a Treehouse directly on Forest) | Cheapest wall/Dock/Bridge/Tower tier — see `02-bases-and-buildings.md` and `06-building-stats-and-defenses.md` |

- **Steel/Stone wording, clarified**: "general building construction" draws on
  **both** Steel and Stone — most buildings cost some mix of the two (not one or the
  other exclusively), the same way many buildings also carry a Wood-tier option. The
  exact per-building split is an implementation-time balancing decision (see
  `06-building-stats-and-defenses.md`'s upgrade-cost model), not a design rule to
  resolve here — this table previously read as if Steel funded some buildings and
  Stone funded others exclusively, which wasn't the intent.

- **Mine and Quarry deliberately cost each other's output** (Mine costs Stone, Quarry
  costs Steel) rather than each costing its own resource — this breaks a chicken-and-
  egg problem where a base's first Mine could never be paid for out of zero starting
  Steel: a base is seeded with a working Quarry from the start (see
  `02-bases-and-buildings.md`), so Stone is available turn one to fund the base's
  first Mine.
- **Wood** is no longer capture-gated behind Treehouse: any base with a Forest-adjacent
  tile can build its own Lumber Mill, the same way Port only needs a water-adjacent
  tile. Treehouse's specialty is placing its Lumber Mill directly *on* Forest tiles
  (no adjacency needed), not exclusive access to Wood itself. Wood walls (and other
  Wood-tier structures) are specifically vulnerable to flame-based troops.

## Starting Resources
Every player begins a match with: **Food 100, Stone 100, Steel 50, Wood 0, Fuel 0**.
Wood and Fuel start at zero deliberately — a bare starting Capital has no
Forest-adjacent Lumber Mill or built Oil Rig yet, so there's nothing to have banked.
Stored on the per-match `Player.resources` record (see `07-data-architecture.md`) —
not on any account-level/meta-progression record (that's a separate, later system —
see `ideas.txt`'s account-perks idea).

## Consumption Rules
- **Food**: consumption scales with base size (bigger base = more food required) and
  with troop count/creation.
- **Fuel**: land vehicles only consume Fuel while **moving** — stationary land
  vehicles are free to maintain. Aircraft consume Fuel heavily while active, but are
  Fuel-free whenever not under a move order while occupying or adjacent to a hex that
  is part of **one of that player's own bases** (not an enemy's or a neutral/unowned
  one, and not gated behind any specific building like a Hangar/Blazeworks — any
  owned base's footprint qualifies) — meaning aircraft have a practical "leash range"
  tied to friendly base coverage, not a landing mechanic. **Resolved: this was
  deliberately chosen over an alternative "aircraft must land inside a Hangar/
  Blazeworks to refuel" design** — simpler to implement (no land/idle-in-building state,
  no per-building capacity) at the cost of Hangar/Blazeworks having no fuel-related
  role beyond production; only the Aircraft Carrier keeps an explicit docking
  mechanic (see `05-troop-stat-schema.md`). Ships consume very little Fuel regardless
  of state.
  - **Exception — Glider** (Windy Peaks' Wind Sanctuary): unpowered, so it uses **no
    Fuel at all** — it draws Food upkeep instead, like ground infantry, despite being
    an Aircraft-domain unit.
- **Steel**: shared between vehicle production/maintenance and general building
  construction — a genuinely contested resource across military and infrastructure
  spending.

## Deficit Consequences
- If Food or Fuel goes into **deficit**, it's resolved **per squad, per resource
  tick** (every 5 seconds — see `07-data-architecture.md`): each squad that has at
  least one member consuming the deficient resource loses **one troop** from that
  squad per tick the deficit persists (the squad's weakest/lowest-HP member dies
  first). This is not a soft cap; economic sabotage (raiding farms, cutting off Oil
  Rigs, destroying a Harbour) is a legitimate way to cripple an enemy army without
  ever fighting it directly.
- Killing off troops naturally reduces upkeep, which can pull the deficit back to
  zero — that's intended, not a bug to patch around: a deficit is meant to be
  self-limiting pressure (bleed troops until affordable again), not a death spiral,
  though the player still feels the cost via losing units either way.

## Oil Rig Notes
- Buildable at **all** bases (Capital and Unique).
- Same build cost everywhere, and — like other non-production buildings — no inherent
  level cap, only the HQ-level ceiling (see `06-building-stats-and-defenses.md`).
- Capital Base's Oil Rig specifically has a **-50% resource production penalty**
  compared to a Unique base's Oil Rig — the only differentiator, kept simple for ease
  of implementation/balancing. Capital carries no offsetting base-wide bonus, so this
  is a straight `baseOutput * 0.5` — a `scope: "building", buildingType: "oil_rig"`
  multiplier (`0.5`) in its `resourceModifiers` (`data/bases/schema.json`), and nothing
  else. See `07-data-architecture.md`'s Base & Ownership section for the field shape.
- **Winter Forge** gets a boost to its Oil Rig production, but this is authored as a
  building-scoped bonus on Winter Forge's own `BaseDef` (a `scope: "building",
  buildingType: "oil_rig"` `resourceModifiers` entry, multiplier 1.5), not an Ice
  Spire aura.

## Population
- Introduced as a **per-base** gating value, separate from the four tradeable
  resources above: **every building placed at a base consumes 1 population slot**,
  except **House**, which grants population capacity instead of consuming it.
- A base at its population cap cannot place any further building — other than a House
  — until capacity is raised (build/upgrade a House) or a building is lost. See
  `02-bases-and-buildings.md`'s Population section and
  `07-data-architecture.md` for how it's stored per base.
- Walls don't count against population (edge-placed, not hex-placed).

## Port / Shipyard / Harbour Notes
- **Port**: buildable at any base (Capital or Unique) with a tile adjacent to water.
- **Harbour**: a Resource-category building, mechanically a Farm gated behind the
  same water-adjacency requirement as Port — not a separate unit/production chain.
  "Fishing boats" are purely the building's visual (boat count scales with level);
  see `02-bases-and-buildings.md`.
- **Shipyard** (Kraken Point only): builds everything Port can, plus larger/advanced
  ships (up to Aircraft Carrier). Kraken Point's own `BaseDef` separately carries a
  +50% Harbour production bonus (a base-wide, building-scoped `resourceModifiers`
  entry, not a Shipyard aura — see `07-data-architecture.md`) — making Kraken Point a strong Food-economy
  base as well as a military one, provided it has a Harbour built.
