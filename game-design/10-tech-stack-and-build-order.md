# Tech Stack & Build Order

## Engine
**Godot** (GDScript). Chosen over Phaser: this project's UI surface is heavy
(per-base build menus, per-building production queues, resource HUD, minimap,
fog-of-war overlay — see `09-ui-and-controls.md`), and Godot's built-in `Control`
node UI toolkit covers that directly instead of hand-rolling an HTML/CSS overlay.
Godot also ships a high-level multiplayer API (ENet), which matters since
`07-data-architecture.md` already targets a simulation/rendering split for
multiplayer-readiness. No Tilemap plugin — hex grid is custom axial/cube-coordinate
math, not a built-in tile layer.

## Build Order
Backend/simulation before frontend/UI implementation — not before UI *design*.
Wireframing and mockups don't depend on the engine and can happen anytime;
writing real UI code does, and it also needs actual game state to bind to.

1. **Headless simulation core** — resource ticking, combat resolution,
   hex-adjacency placement rules (see `02-bases-and-buildings.md`,
   `03-resources.md`, `04-combat.md`) as plain GDScript classes with no scene or
   rendering dependency. Validate mechanics via tests/console output before any
   rendering exists.
2. **Godot project scaffold** — hex-grid coordinate utility, a minimal scene
   rendering one base, click-to-move wired to the sim core.
3. **UI layer** — `Control`-node HUD (resources, build menu, minimap) bound to
   sim state via signals.

## Art
Placeholder art until the core loop (movement, combat resolution, base capture)
is validated as fun — final art is expensive to redo if mechanics change, so
don't invest in it early.

- **Hex tiles/terrain**: flat-color or simple-gradient hexes per terrain type
  (Plains/Forest/Hill/etc.) — `Polygon2D` is enough to playtest fog-of-war and
  adjacency rules, no textures needed.
- **Troops/buildings**: colored geometric shapes or free CC0 asset packs
  (itch.io has many "top-down strategy" packs), one stand-in per troop/building
  type, tinted by owner.
- **UI**: Godot's default theme; no custom skin yet.
- **Asset naming/folders**: structure placeholder sprites so real art is a
  drop-in swap later — one file per troop/building `id` (matching the `data/`
  JSON keys), e.g. `assets/sprites/troops/<id>.png`,
  `assets/sprites/buildings/<id>.png`, referenced by id rather than hardcoded
  paths in scenes, so swapping the file later requires no code changes.

Commission vs. asset-pack vs. draw-it-yourself for the final "cartoon-style
2.5D" look (see `00-overview.md`) is a bigger scope/cost decision to make once
the loop is validated, not now.
