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

This is a compact status log, not a growing checklist — every phase below is
**complete** except art. It records *why* something is shaped the way it is and
what's deliberately deferred; see git history for the literal order things
landed in.

### 1. Headless simulation core (`sim/`) — complete
No scene/rendering dependency; validated via `tests/test_*.gd` before any
rendering existed.

- Hex-grid axial/cube math, terrain costs, A*, wall-edge LOS blocking (`sim/hex/`).
- Resource ticking — per-player pools, production/upkeep netting, deficit
  deaths (`sim/economy/`).
- Troop/Squad/Regiment runtime state, squad/commander caps, production queues
  (`sim/troops/`).
- Combat — targeting, damage math, splash, line-attack beams, ballistic
  projectile travel time (a shot aims at a hex, not a tracked target — a
  repositioned target dodges), buildings as combatants, status effects,
  proximity auras (`sim/combat/`).
- Movement — pathing, regiment lock-step, attack-move chase, cargo board/
  unload (`sim/movement/`).
- Vision/fog-of-war, terrain combat bonuses, stealth/detection
  (`sim/vision/`).
- Base/building runtime state, placement rules (adjacency, Walls, Bridge
  foothold exception), HQ capture-flip, ruin/regen, population
  (`sim/bases/`).
- Procedural map/terrain generation — biome clusters, rivers, Capital/Unique
  base siting with spacing/terrain/uniqueness constraints, whole-pipeline
  retry with a fresh derived seed on a dead-end terrain roll
  (`sim/worldgen/`, `sim/map_generator.gd`).
- Barbarian outposts — best-effort scattered camps (standalone tower +
  garrison, neutral-owned), tier scaled by distance from the nearest Capital,
  one-shot loot payout once both tower and garrison are cleared
  (`sim/outposts/`).
- Command/order-issuing layer resolving a player action into calls against
  the systems above, with ownership/eligibility/resource-cost checks
  (`sim/command/command_processor.gd`), plus the `schedule()`/`drain_due()`
  seam that lets a networked command land deterministically on a future tick
  (`sim/command/command_queue.gd`).
- Top-level tick orchestrator (`sim/sim_orchestrator.gd`, `sim/match_state.gd`).
- Match events — structured combat/economy/capture notifications
  (`sim/events/match_event.gd`), independent of the alerts/toast HUD panel.

### 2. Multiplayer networking (`client/net/`) — complete
Everything that touches `multiplayer`/RPC lives here; `sim/` stays
engine/network-free (`07-data-architecture.md` section 8).

- `net_manager.gd` — ENet listen-server transport (host is also a player),
  lobby roster (host hands out contiguous `"p0".."pN"` owner_ids, compacted
  right before match start so an earlier lobby disconnect can't leave a gap or
  a duplicate id), match-start broadcast, per-tick input-frame relay,
  per-section state-checksum desync detection + cross-peer dump collection.
- `lockstep_driver.gd` — fixed input delay (issue on tick T, apply at
  T+delay) so every peer has time to receive a command before it must resolve
  that tick; a tick only advances once every peer's input frame for it has
  arrived.
- `command_submitter.gd` — the one seam `client/` code issues orders through,
  so the same call site works unchanged in singleplayer (applies immediately)
  or multiplayer (buffers via `LockstepDriver`, applies after the input
  delay).
- `lan_discovery.gd` — separate raw-UDP broadcast lobby browser, independent
  of the ENet game port.

### 3. Godot rendering scaffold (`client/`) — complete except art
Sibling to `sim/`, never the reverse.

- `main.gd`/`main.tscn` — builds a `MatchState` via `MapGenerator.generate()`
  and drives `SimOrchestrator.resolve_tick()` every frame (or
  `LockstepDriver.advance()` in multiplayer).
- `hex_view.gd` — axial↔pixel projection (flat-top); the one new-math piece
  this slice needed.
- `board.gd` / `base_view.gd` / `squad_view.gd` / `projectile_view.gd` —
  terrain, bases, squads, projectiles as flat-color placeholder shapes,
  owner-tinted, read from sim state every frame.
- `input_controller.gd` — click-to-move/attack-target, drag-select, control
  groups, click-precedence (enemy troop/structure vs. open ground).
- `fog_of_war.gd`, `camera_controller.gd` (pan/zoom).
- **Deferred: real art.** Placeholder shapes/colors until the core loop
  (movement, combat, base capture) is validated as fun — see the Art section
  below.

### 4. UI layer (`client/hud/`, `client/ui/`) — complete
`Control`-node HUD bound to sim state via polling (no sim-side signals exist
to bind to). Style system lives in `client/ui/ui_theme.gd`, see
`11-ui-style-guide.md`.

- `hud_layer.gd` — screen-space `CanvasLayer` scaffold.
- `resource_bar.gd` — resource totals + expandable production/usage
  breakdown, deficit rows in red.
- `building_panel.gd` — the one consolidated per-building panel (build menu,
  troop queue, upgrade/rebuild, per-tick output), eligibility-greyed rather
  than disabled so a blocked action can still show its reason.
- `toast_panel.gd` — under-attack / production-paused / resource-deficit
  alerts, one row per base per type, click to recenter camera.
- `minimap.gd` — terrain/base/squad overview + viewport rectangle.
- `pause_menu.gd` — Escape-triggered darken-and-card overlay: match time,
  local resources + production/upkeep, base/squad counts, Resume/Exit.
  Deliberately mode-agnostic (never checks `lockstep_driver`) — `main.gd`'s
  own `_process` gate is what decides whether opening it actually halts the
  sim (singleplayer only; multiplayer keeps advancing underneath it).

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
