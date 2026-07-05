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
- **Base building**: per-base build menu, respecting the hex-adjacency placement rule
  (building must go on a Plains hex — or Forest/Hill for Treehouse/Air Temple —
  adjacent to two existing buildings).
- **Minimap**: needed given multi-base, multi-front play across a large hex map.
- **Per-building production queues**: each troop-producing building has its own
  independent queue (not a shared base-wide queue).
- **Resource HUD**: Food / Steel / Fuel / Stone (+ Wood once Treehouse is captured),
  likely with production/consumption deltas visible given the active-deficit-drain
  mechanic.
- **Fog of war overlay**: distinguishing "unexplored," "explored but not currently
  visible," and "currently visible" states.

## Open / Unresolved Items
- Exact squad-selection UX (drag-box, control groups, double-click-to-select-all-of-type).
- How Commander-led mixed squads are visually distinguished from single-type squads.
- Whether there's a dedicated "alerts" panel for under-attack bases / resource deficits
  (likely necessary given multi-base management under a 40-minute clock).
- Build menu layout for Unique bases with restricted building sets vs. Capital's fixed set.
