class_name HudTheme
extends RefCounted
## The HUD's shared look: a cozy forest palette, the two typefaces (rounded
## Fredoka for titles and labels, Nunito for body text) and the frosted-glass
## panels every widget sits on.

const INK := Color(0.07, 0.11, 0.08)
const GLASS := Color(0.06, 0.11, 0.08, 0.62)
const GLASS_EDGE := Color(1.0, 0.97, 0.86, 0.22)
const CREAM := Color(1.0, 0.965, 0.875)
const LEAF := Color(0.72, 0.9, 0.52)
const MOSS := Color(0.36, 0.55, 0.32)
const GOLD := Color(1.0, 0.82, 0.45)
const BLOSSOM := Color(0.97, 0.66, 0.79)
const LILAC := Color(0.78, 0.65, 1.0)
const WATER := Color(0.48, 0.8, 0.88)
const SHADOW := Color(0.0, 0.03, 0.01, 0.45)

## Marker colours for the up to four Kelings in a session.
const PLAYER_COLORS: Array[Color] = [
	Color(1.0, 0.84, 0.36), Color(1.0, 0.55, 0.48), Color(0.49, 0.79, 1.0), Color(0.79, 0.64, 1.0),
]

const _FREDOKA := preload("res://ui/fonts/Fredoka.ttf")
const _NUNITO := preload("res://ui/fonts/Nunito.ttf")

static var _fonts := {}
static var _theme: Theme


## Rounded display face. Weight 300..700.
static func title_font(weight := 600) -> Font:
	return _variant(_FREDOKA, weight)


## Friendly body face. Weight 200..1000.
static func body_font(weight := 650) -> Font:
	return _variant(_NUNITO, weight)


static func _variant(base: FontFile, weight: int) -> Font:
	var key := "%s:%d" % [base.resource_path, weight]
	if not _fonts.has(key):
		var fv := FontVariation.new()
		fv.base_font = base
		var ts := TextServerManager.get_primary_interface()
		fv.variation_opentype = {ts.name_to_tag("wght"): weight}
		_fonts[key] = fv
	return _fonts[key]


## Frosted panel: soft glass, a hairline cream edge and a gentle drop shadow.
static func glass(radius := 18, alpha := 0.62, pad := 12.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(GLASS, alpha)
	sb.set_corner_radius_all(radius)
	sb.border_color = GLASS_EDGE
	sb.set_border_width_all(2)
	sb.shadow_color = Color(0, 0, 0, 0.22)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing = true
	return sb


static func pill(fill: Color, edge := GLASS_EDGE, radius := 22) -> StyleBoxFlat:
	var sb := glass(radius, fill.a, 0.0)
	sb.bg_color = fill
	sb.border_color = edge
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


static func style_label(l: Label, size: int, color := CREAM, font: Font = null, shadow := true) -> void:
	l.add_theme_font_override("font", font if font else body_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.add_theme_constant_override("shadow_outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Theme for the whole HUD tree, so stray Labels and Buttons look right too.
static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 18
	t.set_color("font_color", "Label", CREAM)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_font("font", "Button", title_font(560))
	t.set_font_size("font_size", "Button", 18)
	t.set_color("font_color", "Button", CREAM)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", LEAF)
	t.set_stylebox("normal", "Button", pill(Color(GLASS, 0.55)))
	t.set_stylebox("hover", "Button", pill(Color(0.14, 0.24, 0.13, 0.7), Color(CREAM, 0.45)))
	t.set_stylebox("pressed", "Button", pill(Color(0.24, 0.38, 0.18, 0.78), Color(LEAF, 0.7)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("panel", "PanelContainer", glass())
	t.set_font("normal_font", "RichTextLabel", body_font(600))
	t.set_font("bold_font", "RichTextLabel", title_font(600))
	t.set_color("default_color", "RichTextLabel", Color(CREAM, 0.92))
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(CREAM, 0.35)
	grab.set_corner_radius_all(4)
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.15)
	track.set_corner_radius_all(4)
	track.content_margin_left = 3
	track.content_margin_right = 3
	for k in ["grabber", "grabber_highlight", "grabber_pressed"]:
		t.set_stylebox(k, "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", track)
	_theme = t
	return t
