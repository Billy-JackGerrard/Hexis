# Map & Terrain

## Shape
- Map is a large **hexagon** made of hex tiles.
- Outer edge is a fixed **coastline**; a bit of open ocean extends beyond it for scale/
  visual purposes (not strategically significant).
- Generation: **organic/hand-crafted feel**, produced via procedural generation with
  balance constraints (e.g. every Capital Base guarantees at least 2 viable expansion
  paths). Not symmetric/mirrored.

## Base Density (scalable)
- Ratio: roughly **2 Unique (neutral city-state) bases per player**, plus 1 Capital Base
  per player.
  - 2 players → 2 Capitals + 4 Unique = 6 bases
  - 4 players → 4 Capitals + 8 Unique = 12 bases
  - 6 players → 6 Capitals + 12 Unique = 18 bases
- Capitals are placed defensively (spread out) to avoid trivial early rushes.
- **Unique base types typically repeat on a map** rather than appearing once each —
  e.g. a 4-player map might have 2 Treehouses, so Wood access (and other unique-base
  perks) isn't monopolized by whichever single player gets there first. Exact
  distribution of base types is part of the map-generation balance constraints.

## Terrain Types
Terrain forms **biome clusters/patches** (varying sizes — small/medium/large), not
scattered single tiles, e.g. a proper forest region rather than one random forest tile.

| Terrain | Infantry | Land Vehicles | Naval | Air | Vision | Buildable? |
|---|---|---|---|---|---|---|
| **Plains** | Normal | Normal | N/A | Normal | **Extended vision + extends fog-of-war clearing** | Yes (only buildable terrain, and majority of tiles) |
| **Forest** | Normal | **Blocked** unless a Road is built through it | N/A | Normal | Normal | No (except Treehouse's buildings — forest tiles) |
| **Hills** | Slowed | Normal | N/A | Normal | Normal | No (except Air Temple's buildings — hill tiles) |
| **River** | **Blocked** unless a Bridge is built | **Blocked** unless a Bridge is built | Fully passable | Normal | Normal | No |

- **Air units** ignore all terrain restrictions entirely.
- **Vision range vs. engagement range are separate** — you can see an enemy approaching
  before they're in attack range, giving a reaction window.

## Naval / Coastline Rules
- Naval troops can travel the **outer coastline ring** all the way around the map, and
  can sail up any **river** — rivers are automatically navigable from the sea at their
  mouth (no port/dock required just to sail).
- Naval troops can **only disembark onto land at a Dock or a Port/Shipyard** —
  they cannot land anywhere else along a coast or riverbank.
- **Fuel**: ships use very little Fuel (negligible compared to aircraft).

## Public Infrastructure (Roads, Bridges, Docks)
- Built only by the **Engineer** troop.
- Buildable **anywhere**, including behind enemy lines (high risk/high reward play —
  an unescorted Engineer is easy to kill).
- Once built, these are **public** — any player's troops can use a Road, Bridge, or Dock,
  not just the builder's. This creates natural contested chokepoints.
- **Destroying** a Road/Bridge/Dock: any troop can do it, but only after all
  defenders on/near it have been cleared first.
- **Dock**: standalone structure, allows ship landing only. Can be placed anywhere on
  coast/riverbank, not tied to a base.

## Fog of War
- **Full fog** until scouted.
- Standard "explored but not currently visible" fade — persistent reveal of terrain
  shape, but current troop positions/base composition require live vision.
- Plains tiles extend both sight radius and how far fog clears — plains are
  economically good but harder to move through unseen; forests/hills are where
  sneaky plays happen.

## Rendering Notes (2.5D Cartoon Style)
- Isometric or top-down camera over a hex heightmap/tile mesh.
- Forests/hills/props as billboarded or low-poly 3D assets on top of terrain.
- Fog of war as a shader overlay (darkened/desaturated unexplored, grayed "explored but
  not visible").
- Target implementation: Three.js (web) or an engine like Unity/Godot exporting to WebGL.
