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
## Default look: "Candy" — bright cream panels with thick dark cartoon
## outlines and drop shadows, glossy lime accent for primary/affordable
## actions, cherry red for blocked, sunny orange for warnings, warm grey for
## ineligible-but-clickable options. Every Label/Button gets a dark text
## outline for a "sticker" pop.
class_name UITheme
extends RefCounted

# --- Palette ----------------------------------------------------------------
# Swap these to reskin the whole HUD. Every other client/ui + client/hud file
# reads colors through here, never as raw literals.
const BG := Color(0.204, 0.706, 0.816)              ## full-screen overlay bg (start screen)
const PANEL_BG := Color(0.988, 0.957, 0.898, 1.0)   ## HUD panel fill — warm cream
const PANEL_BORDER := Color(0.157, 0.114, 0.086)    ## thick dark cartoon outline

const SLATE := Color(0.529, 0.816, 0.922)           ## neutral button — sky blue
const SLATE_HOVER := Color(0.639, 0.878, 0.965)
const SLATE_PRESSED := Color(0.412, 0.678, 0.784)

const ACCENT := Color(0.596, 0.827, 0.239)          ## candy lime — primary/affordable
const ACCENT_HOVER := Color(0.686, 0.902, 0.318)
const ACCENT_PRESSED := Color(0.494, 0.706, 0.180)
const ACCENT_TEXT := Color(0.157, 0.114, 0.086)     ## dark text on lime fill

const DANGER := Color(0.937, 0.294, 0.294)          ## cherry red — blocked / deficit
const WARNING := Color(0.988, 0.686, 0.153)         ## sunny orange — paused / caution

const TEXT := Color(0.157, 0.114, 0.086)            ## near-black on cream panels
const TEXT_MUTED := Color(0.478, 0.427, 0.388)

const MUTED_BG := Color(0.851, 0.816, 0.749)        ## ineligible-but-clickable button fill
const MUTED_BORDER := Color(0.157, 0.114, 0.086)

# --- Font -------------------------------------------------------------------
const FONT_PATH := "res://assets/fonts/Fredoka.ttf"

# --- Font sizes -------------------------------------------------------------
const FONT_TITLE := 34
const FONT_SUBTITLE := 20
const FONT_HEADER := 21
const FONT_BODY := 22
const FONT_SMALL := 17
const FONT_BAR := 26

# --- Cartoon text outline ----------------------------------------------------
const TEXT_OUTLINE_SIZE := 4

# --- Per-resource palette ---------------------------------------------------
## ResourceType.Type -> display color, keyed the same as resource_bar.gd's
## DISPLAY_ORDER / building_info_panel.gd's RESOURCE_NAMES.
const RESOURCE_COLOR := {
	ResourceType.Type.FOOD: Color(0.596, 0.827, 0.239),
	ResourceType.Type.STEEL: Color(0.545, 0.616, 0.678),
	ResourceType.Type.FUEL: Color(0.988, 0.573, 0.153),
	ResourceType.Type.STONE: Color(0.816, 0.729, 0.549),
	ResourceType.Type.WOOD: Color(0.729, 0.475, 0.259),
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
	var font: Font = load(FONT_PATH)
	t.default_font = font
	t.default_font_size = FONT_BODY
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", PANEL_BORDER)
	t.set_constant("outline_size", "Label", TEXT_OUTLINE_SIZE)

	var panel := _flat(PANEL_BG, PANEL_BORDER, 16, 4)
	panel.set_content_margin_all(16.0)
	_add_shadow(panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	_apply_button(t, "Button", SLATE, SLATE_HOVER, SLATE_PRESSED, TEXT, PANEL_BORDER)
	t.set_type_variation(PRIMARY, "Button")
	_apply_button(t, PRIMARY, ACCENT, ACCENT_HOVER, ACCENT_PRESSED, ACCENT_TEXT, ACCENT)
	t.set_type_variation(MUTED, "Button")
	# Hover/pressed match normal so a muted button reads as inert even though it
	# still fires pressed (so we can surface a red reason on click).
	_apply_button(t, MUTED, MUTED_BG, MUTED_BG, MUTED_BG, TEXT_MUTED, MUTED_BORDER)

	var line_edit := _flat(SLATE, PANEL_BORDER, 12, 3)
	line_edit.set_content_margin_all(8.0)
	t.set_stylebox("normal", "LineEdit", line_edit)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_MUTED)
	t.set_color("font_outline_color", "LineEdit", PANEL_BORDER)
	t.set_constant("outline_size", "LineEdit", TEXT_OUTLINE_SIZE)

	return t

static func _apply_button(t: Theme, type: String, bg: Color, hover: Color, pressed: Color, font_color: Color, border: Color) -> void:
	var normal := _flat(bg, border, 16, 4)
	normal.set_content_margin_all(12.0)
	normal.content_margin_left = 18.0
	normal.content_margin_right = 18.0
	_add_shadow(normal)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, _button_state(normal, hover))
	t.set_stylebox("pressed", type, _button_state(normal, pressed, Vector2(0, 1), 1.0))
	t.set_stylebox("disabled", type, _button_state(normal, MUTED_BG))
	t.set_stylebox("focus", type, _flat(Color(0, 0, 0, 0), ACCENT, 16, 4))
	t.set_color("font_color", type, font_color)
	t.set_color("font_hover_color", type, font_color)
	t.set_color("font_pressed_color", type, font_color)
	t.set_color("font_disabled_color", type, TEXT_MUTED)
	t.set_color("font_outline_color", type, PANEL_BORDER)
	t.set_constant("outline_size", type, TEXT_OUTLINE_SIZE)
	t.set_font_size("font_size", type, FONT_BODY)

## `shadow_scale` shrinks the drop shadow (e.g. on press, to read as "pushed down").
static func _button_state(base: StyleBoxFlat, bg: Color, shadow_offset: Vector2 = Vector2(0, 4), shadow_scale: float = 1.0) -> StyleBoxFlat:
	var box: StyleBoxFlat = base.duplicate()
	box.bg_color = bg
	box.shadow_size = int(4 * shadow_scale)
	box.shadow_offset = shadow_offset
	return box

## Cartoon-style flat panel/button background: thick dark outline, big rounded
## corners. `_add_shadow` layers a soft drop shadow on top for the glossy/lifted
## candy look.
static func _flat(bg: Color, border: Color, radius: int, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.set_border_width_all(border_width)
	box.border_color = border
	return box

static func _add_shadow(box: StyleBoxFlat) -> void:
	box.shadow_color = Color(0.157, 0.114, 0.086, 0.35)
	box.shadow_size = 4
	box.shadow_offset = Vector2(0, 4)

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
	# PASS (not the Button default STOP): these buttons live inside a
	# ScrollContainer wall-to-wall (BuildingPanel/SquadPanel) — STOP would eat
	# every mouse-wheel event that lands on a button before it reaches the
	# ScrollContainer above, making the list unscrollable everywhere except the
	# thin gaps between rows. PASS still clicks normally; it just lets unhandled
	# wheel input bubble up too.
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	# These buttons stretch full-width inside a clipping ScrollContainer
	# (BuildingPanel/SquadPanel) — horizontal hover growth would bleed past
	# the clip edge and get cut off, so only grow vertically.
	UIJuice.hover_grow(button, false)
	return button

## A fill bar (0..1 `value`) for showing training/production progress, with
## room for a centered label (add it as a child, e.g. a body_label) drawn on
## top of the fill since Control children paint after their parent.
static func progress_bar() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 34)
	bar.add_theme_stylebox_override("background", _flat(SLATE, PANEL_BORDER, 14, 3))
	bar.add_theme_stylebox_override("fill", _flat(ACCENT, PANEL_BORDER, 14, 3))
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	return bar

## A small procedurally-drawn glyph for `type` (wheat/stone/gear/log/drop),
## tinted via RESOURCE_COLOR — see client/ui/resource_icon.gd.
static func resource_icon(type: ResourceType.Type, icon_size: float = 20.0) -> ResourceIcon:
	return ResourceIcon.new(type, icon_size)

## A row of small colored pills, one per resource in `named` (a data/*.json
## cost dict, e.g. {"stone": 80, "steel": 20}) — the styled replacement for the
## old "(Stone 80, Steel 20)" bracketed button text. Iterates ResourceType.ALL
## for a stable left-to-right order regardless of the dict's key order.
static func cost_chips(named: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	if named.is_empty():
		row.add_child(_label("Free", FONT_SMALL, TEXT_MUTED))
		return row
	for type in ResourceType.ALL:
		var key := String(RESOURCE_LABEL[type]).to_lower()
		if not named.has(key):
			continue
		row.add_child(chip("%d" % int(named[key]), RESOURCE_COLOR[type], resource_icon(type, 16.0)))
	return row

## One pill: a glossy color-tinted rounded background with the text in that
## color — a small candy button that doesn't press. Pass `icon` (e.g. from
## resource_icon()) to show a small glyph before the text.
static func chip(text: String, color: Color, icon: Control = null) -> PanelContainer:
	var box := _flat(Color(color.r, color.g, color.b, 0.35), PANEL_BORDER, 12, 3)
	box.content_margin_left = 10.0
	box.content_margin_right = 10.0
	box.content_margin_top = 4.0
	box.content_margin_bottom = 4.0
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", box)
	pill.mouse_filter = Control.MOUSE_FILTER_PASS
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	if icon != null:
		content.add_child(icon)
	content.add_child(_label(text, FONT_SMALL, color.darkened(0.35)))
	pill.add_child(content)
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
