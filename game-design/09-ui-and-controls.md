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

## Open / Unresolved Items
- Exact squad-selection UX (drag-box, control groups, double-click-to-select-all-of-type).
- How a Commander's regiment (up to 4 squads) is visually distinguished/grouped for
  selection versus an independent single-type squad.
- Whether there's a dedicated "alerts" panel for under-attack bases / resource deficits
  (likely necessary given multi-base management under a 40-minute clock).
- Build menu layout for Unique bases with restricted building sets vs. Capital's fixed set.
