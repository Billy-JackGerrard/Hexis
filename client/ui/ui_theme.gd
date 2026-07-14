## The single source of truth for the HUD's look — palette, font sizes, a
## Godot Theme (panels + buttons in every state), and node factories every
## client/hud/ panel builds from. Introduced with the UI restyle so panels
## stop hard-coding one-off Color/FONT_SIZE constants and native unstyled
## Buttons; see game-design/11-ui-style-guide.md for the usage guide and how
## to reskin (swap the palette constants below — nothing else references raw
## colors). World/map views (client/board.gd, base_view.gd, ...) keep their
## own _draw() palettes and are deliberately NOT themed — they're placeholder
## art, not HUD chrome.
##
## Default look: "Slate + emerald" — charcoal panels, emerald accent for
## primary/affordable actions, red for blocked, amber for warnings, muted grey
## for ineligible-but-clickable options.
class_name UITheme
extends RefCounted

# --- Palette ----------------------------------------------------------------
# Swap these to reskin the whole HUD. Every other client/ui + client/hud file
# reads colors through here, never as raw literals.
const BG := Color(0.078, 0.086, 0.110)              ## full-screen overlay bg (start screen)
const PANEL_BG := Color(0.106, 0.118, 0.145, 0.97)  ## HUD panel fill
const PANEL_BORDER := Color(0.235, 0.267, 0.318)    ## HUD panel/border hairline

const SLATE := Color(0.152, 0.169, 0.204)           ## neutral button
const SLATE_HOVER := Color(0.200, 0.224, 0.267)
const SLATE_PRESSED := Color(0.117, 0.129, 0.157)

const ACCENT := Color(0.243, 0.651, 0.447)          ## emerald — primary/affordable
const ACCENT_HOVER := Color(0.302, 0.745, 0.522)
const ACCENT_PRESSED := Color(0.196, 0.545, 0.373)
const ACCENT_TEXT := Color(0.055, 0.086, 0.067)     ## dark text on emerald fill

const DANGER := Color(0.851, 0.345, 0.290)          ## blocked / deficit / red reason
const WARNING := Color(0.878, 0.651, 0.235)         ## paused / caution

const TEXT := Color(0.878, 0.898, 0.918)
const TEXT_MUTED := Color(0.478, 0.510, 0.549)

const MUTED_BG := Color(0.113, 0.125, 0.149)        ## ineligible-but-clickable button fill
const MUTED_BORDER := Color(0.200, 0.220, 0.259)

# --- Font sizes -------------------------------------------------------------
const FONT_TITLE := 28
const FONT_SUBTITLE := 18
const FONT_HEADER := 19
const FONT_BODY := 21
const FONT_SMALL := 16
const FONT_BAR := 24

# --- Per-resource palette ---------------------------------------------------
## ResourceType.Type -> display color, keyed the same as resource_bar.gd's
## DISPLAY_ORDER / building_info_panel.gd's RESOURCE_NAMES.
const RESOURCE_COLOR := {
	ResourceType.Type.FOOD: Color(0.482, 0.745, 0.408),
	ResourceType.Type.STEEL: Color(0.588, 0.647, 0.706),
	ResourceType.Type.FUEL: Color(0.878, 0.573, 0.235),
	ResourceType.Type.STONE: Color(0.706, 0.647, 0.545),
	ResourceType.Type.WOOD: Color(0.647, 0.478, 0.353),
}
const RESOURCE_LABEL := {
	ResourceType.Type.FOOD: "Food",
	ResourceType.Type.STEEL: "Steel",
	ResourceType.Type.FUEL: "Fuel",
	ResourceType.Type.STONE: "Stone",
	ResourceType.Type.WOOD: "Wood",
}

# Button variation names (theme_type_variation values). "Button" is the plain
# neutral default; these override it.
const PRIMARY := "PrimaryButton" ## emerald fill — main call to action
const MUTED := "MutedButton"     ## greyed, still clickable (ineligible options)

# --- Theme construction -----------------------------------------------------

## One shared Theme for the whole HUD. Assign it to each top-level panel Control
## (a Control's theme cascades to its descendants; a CanvasLayer's does not, so
## hud_layer.gd sets it per panel rather than once at the layer).
static func create_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_BODY
	t.set_color("font_color", "Label", TEXT)

	var panel := _flat(PANEL_BG, PANEL_BORDER, 8, 1)
	panel.set_content_margin_all(16.0)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	_apply_button(t, "Button", SLATE, SLATE_HOVER, SLATE_PRESSED, TEXT, PANEL_BORDER)
	t.set_type_variation(PRIMARY, "Button")
	_apply_button(t, PRIMARY, ACCENT, ACCENT_HOVER, ACCENT_PRESSED, ACCENT_TEXT, ACCENT)
	t.set_type_variation(MUTED, "Button")
	# Hover/pressed match normal so a muted button reads as inert even though it
	# still fires pressed (so we can surface a red reason on click).
	_apply_button(t, MUTED, MUTED_BG, MUTED_BG, MUTED_BG, TEXT_MUTED, MUTED_BORDER)

	var line_edit := _flat(SLATE, PANEL_BORDER, 6, 1)
	line_edit.set_content_margin_all(8.0)
	t.set_stylebox("normal", "LineEdit", line_edit)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)

	return t

static func _apply_button(t: Theme, type: String, bg: Color, hover: Color, pressed: Color, font_color: Color, border: Color) -> void:
	var normal := _flat(bg, border, 6, 1)
	normal.set_content_margin_all(12.0)
	normal.content_margin_left = 16.0
	normal.content_margin_right = 16.0
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, _button_state(normal, hover))
	t.set_stylebox("pressed", type, _button_state(normal, pressed))
	t.set_stylebox("disabled", type, _button_state(normal, MUTED_BG))
	t.set_stylebox("focus", type, _flat(Color(0, 0, 0, 0), ACCENT, 6, 1))
	t.set_color("font_color", type, font_color)
	t.set_color("font_hover_color", type, font_color)
	t.set_color("font_pressed_color", type, font_color)
	t.set_color("font_disabled_color", type, TEXT_MUTED)
	t.set_font_size("font_size", type, FONT_BODY)

static func _button_state(base: StyleBoxFlat, bg: Color) -> StyleBoxFlat:
	var box: StyleBoxFlat = base.duplicate()
	box.bg_color = bg
	return box

static func _flat(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.set_border_width_all(border_width)
	box.border_color = border
	return box

# --- Node factories ---------------------------------------------------------

static func panel() -> PanelContainer:
	return PanelContainer.new()

static func title_label(text: String) -> Label:
	return _label(text, FONT_TITLE, TEXT)

static func subtitle_label(text: String) -> Label:
	return _label(text, FONT_SUBTITLE, TEXT_MUTED)

## Small emerald section header ("Build", "Train", ...).
static func header_label(text: String) -> Label:
	return _label(text, FONT_HEADER, ACCENT)

static func body_label(text: String) -> Label:
	return _label(text, FONT_BODY, TEXT)

static func muted_label(text: String) -> Label:
	return _label(text, FONT_BODY, TEXT_MUTED)

## Red reason text (shown when an ineligible option is clicked).
static func danger_label(text: String) -> Label:
	var label := _label(text, FONT_SUBTITLE, DANGER)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

## Amber caution text (e.g. a paused production queue).
static func warning_label(text: String) -> Label:
	return _label(text, FONT_SUBTITLE, WARNING)

static func action_button(text: String, variation: String = "") -> Button:
	var button := Button.new()
	button.text = text
	button.theme_type_variation = variation
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return button

## A row of small colored pills, one per resource in `named` (a data/*.json
## cost dict, e.g. {"stone": 80, "steel": 20}) — the styled replacement for the
## old "(Stone 80, Steel 20)" bracketed button text. Iterates ResourceType.ALL
## for a stable left-to-right order regardless of the dict's key order.
static func cost_chips(named: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	if named.is_empty():
		row.add_child(_label("Free", FONT_SMALL, TEXT_MUTED))
		return row
	for type in ResourceType.ALL:
		var key := String(RESOURCE_LABEL[type]).to_lower()
		if not named.has(key):
			continue
		row.add_child(chip("%s %d" % [RESOURCE_LABEL[type], int(named[key])], RESOURCE_COLOR[type]))
	return row

## One pill: a color-tinted rounded background with the text in that color.
static func chip(text: String, color: Color) -> PanelContainer:
	var box := _flat(Color(color.r, color.g, color.b, 0.16), Color(color.r, color.g, color.b, 0.55), 8, 1)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", box)
	pill.add_child(_label(text, FONT_SMALL, color.lightened(0.15)))
	return pill

# --- World-space text (Node2D views) ----------------------------------------
## Dark halo drawn behind world labels so base/player/hover names stay legible
## over any terrain color.
const WORLD_LABEL_OUTLINE := Color(0.0, 0.0, 0.0, 0.85)
const WORLD_LABEL_OUTLINE_SIZE := 5

## Draws `text` on a world-space CanvasItem (base_view/squad_view — Node2D, so
## they can't use the Control/Theme path) with a dark outline for contrast, then
## the fill in `color`. The one shared entry point so every map label reads the
## same and stays legible; keep the HUD palette (TEXT/TEXT_MUTED/ACCENT/owner
## colors) as the fill so map chrome matches the panels.
static func draw_world_label(ci: CanvasItem, font: Font, pos: Vector2, text: String, font_size: int, color: Color, width: float = -1.0, alignment: int = HORIZONTAL_ALIGNMENT_CENTER) -> void:
	ci.draw_string_outline(font, pos, text, alignment, width, font_size, WORLD_LABEL_OUTLINE_SIZE, WORLD_LABEL_OUTLINE)
	ci.draw_string(font, pos, text, alignment, width, font_size, color)

static func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
