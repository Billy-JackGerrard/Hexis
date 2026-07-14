# 11 — UI Style System

The reusable look-and-feel layer for the HUD. Everything screen-space (panels,
buttons, the resource bar, the start screen) is styled through one place —
[`client/ui/ui_theme.gd`](../client/ui/ui_theme.gd) (`class_name UITheme`) — so
new UI is consistent and a reskin is a one-file change. World/map views
(`board.gd`, `base_view.gd`, `squad_view.gd`, …) are placeholder art and are
**not** themed, with one exception: their text overlays (base/player/hover
names) go through `UITheme.draw_world_label` for legibility.

Default look: **Slate + emerald** — charcoal panels, emerald accent for
primary/affordable actions, red for blocked, amber for caution, muted grey for
ineligible-but-clickable options.

## Where things live

| File | Role |
|---|---|
| `client/ui/ui_theme.gd` | Palette, font sizes, the Godot `Theme`, node factories, `draw_world_label`. The only file with raw color literals. |
| `client/ui/eligibility.gd` | `UIEligibility` — non-mutating "can the player do this, and if not why" (returns a short reason string, `""` = eligible). Composes the sim's pure predicates; no colors/nodes. |
| `client/hud/*.gd` | The panels, each built from `UITheme` factories + real Control nodes (no `_draw()`). |

## Reskinning

Change the palette constants at the top of `ui_theme.gd` (`BG`, `PANEL_BG`,
`ACCENT`, `DANGER`, `WARNING`, `TEXT`, `TEXT_MUTED`, `SLATE*`, `MUTED*`,
`RESOURCE_COLOR`). Nothing else references raw colors, so that's the whole job.
Font sizes are the `FONT_*` constants in the same block.

## The Theme

`UITheme.create_theme() -> Theme` builds one shared `Theme` (StyleBoxFlats for
`PanelContainer`/`Panel`, `Button` in every state, `LineEdit`, `Label` color).
A `CanvasLayer` is not a `Control`, so its theme does **not** cascade — assign
the theme to each top-level panel instead (see `hud_layer.gd`, which makes one
theme and sets `.theme` on every panel; `start_screen.gd` sets it on its root
Control, where it *does* cascade).

### Button variations

Set `button.theme_type_variation` to pick a look (via `UITheme.action_button`):

- `""` (plain `Button`) — neutral slate. Default list actions (build/troop rows).
- `UITheme.PRIMARY` — filled emerald. The main call to action (Upgrade, Rebuild,
  Single Player).
- `UITheme.MUTED` — greyed, **still clickable**. Ineligible options: hover/pressed
  match normal so it reads inert, but `pressed` still fires so the panel can show
  the red reason instead of acting.

## Node factories (all static on `UITheme`)

- `panel()` → themed `PanelContainer`.
- `title_label(t)`, `subtitle_label(t)`, `header_label(t)` (emerald section head),
  `body_label(t)`, `muted_label(t)`, `warning_label(t)` (amber), `danger_label(t)`
  (red, word-wrapping).
- `action_button(text, variation="")` → full-width, clip-safe `Button`.
- `cost_chips(named)` → row of small colored pills, one per resource, from a
  `data/*.json` cost dict (`{"stone": 80, "steel": 20}`). The styled replacement
  for the old `"(Stone 80, Steel 20)"` bracketed button text. `{}` renders `Free`.
- `chip(text, color)` → one pill (used for cost chips and the troop build-time chip).
- `draw_world_label(canvas_item, font, pos, text, size, color, width, align)` —
  world-space text with a dark outline halo, for Node2D views.

## Eligibility → greying (the pattern)

Ineligible build/upgrade/troop options are shown **muted but clickable**, not
disabled (a disabled Button swallows its click, so we couldn't surface a reason).
The pattern, in `building_panel.gd`:

1. Each option registers a `reason_fn: Callable` returning `UIEligibility`'s
   reason (`""` if eligible).
2. On a throttle, `_refresh_eligibility()` flips each button between its normal
   variation and `MUTED`, and sets `tooltip_text` to the reason.
3. On press, `_handle_press` re-checks `reason_fn`: non-empty → write it to the
   red reason `Label`; empty → clear it and run the action.

`UIEligibility` maps the sim's granular `CommandProcessor.Result` values
(`MAX_LEVEL`, `HQ_LEVEL_TOO_LOW`, `NEED_MORE_POPULATION`, `INSUFFICIENT_RESOURCES`,
`NOT_UNLOCKED`, …) and `BuildingPlacement`/`Population`/`SquadCap` to human text.
The rules themselves stay in `sim/` — the UI never re-implements them. The
expensive "any valid placement hex exists" scan (`UIEligibility.any_valid_hex`)
runs once per panel rebuild and is cached; the cheap affordability/population
checks re-run on the throttle.

## The consolidated building panel

`client/hud/building_panel.gd` (`BuildingPanel`) is the one right-side panel for
a selected building — title, base name + population, a Level row with an Upgrade
button (or RUINED + Rebuild), then a category body: build menu (HQ), troop menu +
queue (Production), or per-tick output (Resource). It replaced the old
`base_panel` / `build_menu` / `building_info_panel` / `production_panel` quartet.
The node tree rebuilds only on selection change; eligibility styling re-checks on
a throttle; live values (queue timers, next-tick countdown) update every frame.

## Adding a new panel — checklist

- `extends Control`; build the tree from `UITheme` factories, no `_draw()`.
- Assign the shared theme (`hud_layer.gd` does this) or parent under a themed Control.
- Anchor to a screen edge; if it can coexist with the minimap/resource bar, respect
  their `HEIGHT`/`SIZE`/`MARGIN` constants (the informal layout contract).
- For any action that can be blocked, add a `UIEligibility` reason and use the
  muted-button + red-reason pattern above rather than inventing a new one.
