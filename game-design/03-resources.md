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
  vehicles are free to maintain. Aircraft consume Fuel heavily while active, but
  refuel/idle for free when stationed adjacent to a base — meaning aircraft have a
  practical "leash range" tied to friendly base coverage. Ships consume very little
  Fuel regardless of state.
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
  of implementation/balancing.
- **Resolved: how this stacks with the Capital's own +50% base-wide bonus.** Both are
  now structured `resourceModifiers` entries on `BaseDef` (`data/bases/schema.json`)
  rather than free-text — a `scope: "base"` multiplier (`1.5`, the Capital's general
  +50%) and a `scope: "building", buildingType: "oil_rig"` multiplier (`0.5`, the
  penalty). They stack **multiplicatively**, building-scoped first: `baseOutput * 0.5
  (Oil Rig penalty) * 1.5 (Capital-wide bonus)` = **0.75x** a Unique base's equivalent-
  level Oil Rig — a net penalty, but softer than the raw -50% reading in isolation.
  See `07-data-architecture.md`'s Base & Ownership section for the field shape.
- **Winter Forge's Ice Spire** buffs the production of every Oil Rig at that specific
  base (an aura targeting a friendly building type, not friendly troops — see
  `05-troop-stat-schema.md`), making Winter Forge a notably strong Fuel-economy base
  on top of its heavy-armor/crowd-control identity.

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
  ships (up to Aircraft Carrier), and carries an aura boosting this base's own
  Harbour's Food output (same pattern as Ice Spire buffing Oil Rigs) — making Kraken
  Point a strong Food-economy base as well as a military one, provided it has a
  Harbour built.
