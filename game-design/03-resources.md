# Resources

## Resource List

| Resource | Source(s) | Used for |
|---|---|---|
| Food | Fishing boats, Farms | Troop creation + troop/base maintenance |
| Steel | Mines | Vehicle creation, vehicle maintenance, building construction |
| Fuel | Oil Rigs (all bases; Capital has -50% production penalty) | Vehicle & aircraft maintenance (ships use very little) |
| Stone | Quarry | Building construction, walls, bridges, roads |

- **Wood** was considered but removed from the base game — reintroduced later as a
  Treehouse-specific resource (see below), not a general-purpose global resource.
- **Wood** (Treehouse's Lumber Mill): once unlocked by capturing a Treehouse, **all**
  bases can build the Wood wall tier (cheapest, weakest wall type). Wood walls are
  specifically vulnerable to flame-based troops.

## Consumption Rules
- **Food**: consumption scales with base size (bigger base = more food required) and
  with troop count/creation.
- **Fuel**: land vehicles only consume Fuel while **moving** — stationary land
  vehicles are free to maintain. Aircraft consume Fuel heavily while active, but
  refuel/idle for free when stationed adjacent to a base — meaning aircraft have a
  practical "leash range" tied to friendly base coverage. Ships consume very little
  Fuel regardless of state.
- **Steel**: shared between vehicle production/maintenance and general building
  construction — a genuinely contested resource across military and infrastructure
  spending.

## Deficit Consequences
- If Food or Fuel goes into **deficit**, affected troops/vehicles suffer an
  **active drain** — they weaken over time and can eventually die if the deficit isn't
  resolved. This is not a soft cap; economic sabotage (raiding farms, cutting off Oil
  Rigs, sinking fishing boats) is a legitimate way to cripple an enemy army without
  ever fighting it directly.

## Oil Rig Notes
- Buildable at **all** bases (Capital and Unique).
- Same build cost everywhere, and — like other non-production buildings — no inherent
  level cap, only the HQ-level ceiling (see `06-building-stats-and-defenses.md`).
- Capital Base's Oil Rig specifically has a **-50% resource production penalty**
  compared to a Unique base's Oil Rig — the only differentiator, kept simple for ease
  of implementation/balancing.

## Port / Shipyard Notes
- **Port**: buildable at any base (Capital or Unique) with a tile adjacent to water.
- **Shipyard** (Kraken Point only): builds everything Port can, plus larger/advanced
  ships (up to Aircraft Carrier), and gives a bonus to fishing boat output — making
  Kraken Point a strong Food-economy base as well as a military one.
