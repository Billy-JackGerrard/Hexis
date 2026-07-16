# Resources

## Resource List

| Resource | Source(s) | Used for |
|---|---|---|
| Food | Farms, Harbour (Farm-equivalent, requires a Water-adjacent tile — see `02-bases-and-buildings.md`) | Troop creation + troop/building maintenance |
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
not on any account-level/meta-progression record (an account-perks system is a
separate, later idea, not designed yet).

## Consumption Rules
- **Food**: consumption scales with base size (bigger base = more food required) and
  with troop count/creation.
- **Building upkeep (Food only)**: every building draws a flat per-tick Food upkeep
  EXCEPT HQ, Farm, and Harbour (the two Food producers — see Deficit Consequences
  below for why they're exempt) and the standalone Infrastructure buildings (Road/
  Bridge/Dock/Tower) plus Landmine, which carry their own ownerId directly rather
  than living on a base and aren't walked by the upkeep system at all
  (`data/buildings/schema.json`'s `foodUpkeep`, sourced by `BuildingUpkeepSystem`).
  Same idea as troop upkeep, but the consequence differs by category — see Deficit
  Consequences below. A Production building's queue pauses and a Resource
  building's output stops; a Defensive/Support building (Turret, Wall, Hospital,
  Hangar, House, ...) has nothing to pause or stop, so its upkeep is pure pressure
  on the pool with no direct consequence of its own. Buildings never draw Fuel
  upkeep.
- **Fuel**: land vehicles only consume Fuel while **moving** — stationary land
  vehicles are free to maintain. Aircraft consume Fuel heavily while active, and
  **always do so while airborne** — there is no proximity-to-base fuel-free rule.
  **Resolved: this reverses an earlier decision.** The original design had aircraft
  go fuel-free simply for occupying/being adjacent to any of that player's own bases
  (a "leash range" tied to base coverage, not a landing mechanic), chosen for being
  simpler to implement than a landing mechanic. That tradeoff was later revisited:
  always-drains-in-flight is more interesting than a passive near-base freebie, and it
  gives a landing mechanic real teeth — see **Hangar**, below.
  - **Hangar** (a dedicated storage building, distinct from Iron Aviary/Blazeworks,
    which remain pure production with no fuel-related role) is where an aircraft
    actually stops consuming Fuel: landing/docking inside one, the same mechanic the
    Aircraft Carrier already uses to hold 2 Air squads fuel-free (see
    `05-troop-stat-schema.md`). A docked aircraft is also hidden from enemy vision/
    detection/targeting while inside — not spotted by scouts, not hit by long-range
    AA — so landing trades mobility for safety rather than being a free lunch.
    Deliberately not split into separate runway/helipad buildings — Air-domain covers
    both fixed-wing and rotary troops, so one Hangar stores either. Also doubles as
    Cargocopter's required landing hex for boarding/unloading Infantry cargo (see
    `04-combat.md`'s Cargo section and `05-troop-stat-schema.md`'s
    `cargoRequiresBuildingDock`). Buildable at a growing, hand-picked subset of bases
    (Capital included) — see `02-bases-and-buildings.md`'s Building Reference; check
    `data/bases/*.json` for the current list rather than trusting a hardcoded one here.
  - Ships consume very little Fuel regardless of state.
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
- **Buildings never die from a Food deficit** — deliberately a softer consequence
  than the troop-death-drain above. A building with `foodUpkeep > 0` just stops
  functioning for as long as the deficit lasts: a Resource building contributes
  zero output that tick (`ProductionOutputSystem.compute_production`), a Production
  building's queue holds paused (`pause_reason` `food_deficit`,
  `ProductionManager.pump`) rather than deploying finished troops. Farm/Harbour are
  never authored with `foodUpkeep` specifically so this can't deadlock: the two
  buildings that could recover a Food deficit are immune to being stopped by one.

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
