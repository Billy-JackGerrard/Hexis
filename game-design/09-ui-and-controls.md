# UI & Controls

## Direction
Referenced style: **Civilization / Alpha Wars** — a hex-grid strategy game control
scheme, adapted for real-time (not turn-based) play.

## Implied Requirements
- **Camera**: top-down/isometric, pannable/zoomable across a large hex map spanning
  multiple bases and fronts.
- **Selection**: click/drag to select squads of troops (group selection is core to the
  design — see `04-combat.md`).
- **Movement**: click-to-move for selected squads; this is the primary and near-only
  direct player action during combat.
- **Focus-fire / structure-targeting**: with a squad selected, clicking directly on an
  enemy **troop, squad, building, or wall** issues a directed-target order instead of
  a move order (see `04-combat.md`) — this is also how a siege on a building or the
  HQ itself is directed, since default auto-targeting only ever picks the nearest
  enemy troop. Needs a distinct cursor/highlight state per hoverable case (valid enemy
  troop, valid enemy structure, open ground) so the player can tell which click
  they're about to make.
- **Base building**: per-base build menu, respecting the hex-adjacency placement rule
  (building must go on a Plains hex — or Forest/Hill for Treehouse/Windy Peaks —
  adjacent to two existing buildings).
- **Minimap**: needed given multi-base, multi-front play across a large hex map.
- **Per-building production queues**: each troop-producing building has its own
  independent queue (not a shared base-wide queue).
- **Resource HUD**: Food / Steel / Fuel / Stone / Wood (once any base has a Lumber
  Mill running), likely with production/consumption deltas visible given the
  active-deficit-drain mechanic.
- **Population indicator**: per-base, not global — likely shown on the base's own
  panel (used/cap, e.g. "7/10") rather than the top-level resource HUD, since it gates
  that specific base's building placement, not a player-wide pool.
- **Fog of war overlay**: distinguishing "unexplored," "explored but not currently
  visible," and "currently visible" states.

## Squad Selection
- **Drag-box**: standard RTS marquee select — selects every one of the player's own
  squads whose `currentHex` falls inside the dragged screen rectangle.
- **Single click on a hex**:
  - If exactly one of the player's squads occupies that hex, it's selected directly.
  - **Resolved: if multiple squads are stacked on the same hex** (stacking is
    unlimited — see `07-data-architecture.md`), a click selects one squad at a time,
    and **repeated clicks on that same hex cycle through the stack** (one squad per
    click, wrapping back to the first). This lets the player reach a buried squad
    without needing a drag-box, at the cost of extra clicks on a heavily stacked hex.
- **Control groups**: standard numbered control groups (assign selection to a number
  key, press the number to reselect), stored as a saved list of squad ids — a group
  member that's since died or merged away is simply dropped from the group silently.
- **Resolved: double-click-to-select-all-of-type is on-screen only**, not global — a
  double-click on a squad selects every squad of that same troop type currently
  visible in the viewport, matching classic RTS convention. Given 12-18 bases and
  multiple simultaneous fronts, a global version risked silently stripping a
  defended base the player isn't currently looking at.

## Commander Regiments
- **Selecting a Commander selects its whole regiment as one group** (the Commander
  plus up to 4 member squads) for movement purposes — a move order given while the
  Commander is selected moves the regiment together, with the Commander as the
  rally point/anchor (see `04-combat.md`).
- **Visual grouping**: a Commander and its regiment's squads share a common
  highlight/outline treatment (e.g. a shared banner color tied to that Commander)
  distinct from the plain selection outline used for an independent, unassigned
  squad — so the player can tell at a glance which squads on screen currently belong
  to a regiment versus operating solo.
- **Resolved: regiment membership doesn't lock a squad out of independent orders.**
  Clicking directly on one squad within a regiment (rather than the Commander)
  still selects just that squad and allows an ad hoc move/attack order for it alone,
  temporarily splitting it from the regiment's shared movement. It automatically
  resumes following the Commander's rally point once it goes idle again (no order
  pending) — membership itself is unaffected; only which squads currently share the
  Commander's move order changes moment to moment.

## Alerts Panel
- **Resolved: yes, a dedicated alerts panel exists**, given multi-base management under
  a real-time clock makes it impractical to notice every threat by scanning the map.
  A persistent list (corner of the HUD) surfaces, per base:
  - **Under attack** — an enemy troop/squad is currently in range of or engaging that
    base (its defenses, garrison, or buildings).
  - **Resource deficit** — that base is contributing to (or the player's pool is in) a
    Food/Fuel deficit, tying into the per-squad drain in `03-resources.md`.
  - **Production paused** — a building's queue is paused at the squad or Commander cap
    (see `07-data-architecture.md`'s `pauseReason`), since that's otherwise silent.
- **One entry per base per alert type**, not per event — an ongoing attack shows a
  single persistent "under attack" entry for that base for as long as it continues,
  rather than spamming one row per hit; it clears automatically once no enemy remains
  in range.
- **Clicking an alert recenters the camera on that base** — the fastest way to jump
  across a large, multi-front map without hunting for the minimap location.

## Pause Menu
- **Escape opens a darken-and-card overlay** (`client/pause_menu.gd`) showing match
  time, the local player's resources with live production/upkeep rates, base counts
  by owner, and squad counts by troop type, plus Resume/Exit Game buttons.
- **Singleplayer-only pause; multiplayer stays a local overlay.** Escape actually
  halts the sim only when there's no `LockstepDriver` (`main.gd`'s `_process` gates
  `sim_clock.advance` on `not pause_menu.is_open`). In multiplayer the menu still
  opens, but every other peer keeps playing underneath it — the pause card itself
  is deliberately agnostic to which mode it's in.

## Build Menu (Unique Bases)
- **Resolved: a Unique base's build menu only lists the buildings that base type can
  actually build** — it does not show every game building grayed out with a "not
  available here" state. Capital's menu is the fixed superset (every non-Unique
  production/resource/support building); each Unique base instead has its own fixed,
  shorter list (see `02-bases-and-buildings.md`'s per-base building tables). Reasoning:
  Unique-base restrictions are **permanent identity, not a temporary lock a player
  might unlock later** (unlike, say, a production building's level-gated troop
  roster) — showing greyed-out entries for buildings that base will *never* be able to
  build would just be clutter/false affordance, not useful information.
