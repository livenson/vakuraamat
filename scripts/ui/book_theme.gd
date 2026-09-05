# The book: one Theme for every menu and panel. An archive ledger under reading-room light: aged
# rag paper, iron-gall ink, the cadastre's blue for anything you can act on, a rubric red only as the
# page's margin rule and for money owed. EB Garamond speaks for the register (titles, heads, prose);
# IBM Plex Sans carries buttons, tables and every figure with tabular numerals so columns align.
class_name BookTheme
extends RefCounted

const PAGE := Color("dcd5c1")
const PAGE_DARK := Color("cfc7b1")
const PAGE_LIGHT := Color("ebe5d4")
const INK := Color("221e19")
const FADED := Color("6b6255")
const BLUE := Color("2d5f8b")
const RUBRIC := Color("8e3a2f")
const GREEN := Color("4f6b3f")
const FONT_DIR := "res://assets/fonts/"

static var _theme: Theme
static var _fonts: Dictionary = {}
static var _grain: Texture2D


## Named faces: garamond, garamond_semibold, garamond_italic, plex, plex_medium (all figures tabular).
static func font(which: String) -> Font:
	if _fonts.has(which):
		return _fonts[which]
	var fv := FontVariation.new()
	var wght := TextServerManager.get_primary_interface().name_to_tag("wght")
	match which:
		"garamond", "garamond_semibold":
			fv.base_font = load(FONT_DIR + "EBGaramond[wght].ttf")
			fv.variation_opentype = {wght: 600 if which == "garamond_semibold" else 450}
		"garamond_italic":
			fv.base_font = load(FONT_DIR + "EBGaramond-Italic[wght].ttf")
			fv.variation_opentype = {wght: 450}
		_:
			fv.base_font = load(FONT_DIR + "IBMPlexSans[wdth,wght].ttf")
			fv.variation_opentype = {wght: 500 if which == "plex_medium" else 400, TextServerManager.get_primary_interface().name_to_tag("wdth"): 100}
			fv.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("tnum"): 1}
	_fonts[which] = fv
	return fv


static func theme() -> Theme:
	if _theme:
		return _theme
	var th := Theme.new()
	th.default_font = font("plex")
	th.default_font_size = 15
	th.set_color("font_color", "Label", INK)
	th.set_color("font_color", "RichTextLabel", INK)
	th.set_color("default_color", "RichTextLabel", INK)
	# panels are pages
	th.set_stylebox("panel", "PanelContainer", page_box())
	th.set_stylebox("panel", "Panel", page_box())
	th.set_stylebox("panel", "ScrollContainer", _flat(Color.TRANSPARENT))
	th.set_stylebox("panel", "TooltipPanel", page_box(true, 8))
	th.set_color("font_color", "TooltipLabel", INK)
	# buttons: outlined ink, blue when pressed; PrimaryButton filled blue; RowButton a ruled ledger line
	th.set_font("font", "Button", font("plex_medium"))
	th.set_font_size("font_size", "Button", 15)
	th.set_stylebox("normal", "Button", _flat(Color.TRANSPARENT, INK, 1, 2, 14, 7))
	th.set_stylebox("hover", "Button", _flat(PAGE_DARK, INK, 1, 2, 14, 7))
	th.set_stylebox("pressed", "Button", _flat(BLUE, BLUE, 1, 2, 14, 7))
	th.set_stylebox("disabled", "Button", _flat(Color.TRANSPARENT, FADED, 1, 2, 14, 7))
	th.set_stylebox("focus", "Button", _flat(Color.TRANSPARENT, BLUE, 2, 2, 14, 7))
	th.set_color("font_color", "Button", INK)
	th.set_color("font_hover_color", "Button", INK)
	th.set_color("font_focus_color", "Button", INK)
	th.set_color("font_pressed_color", "Button", PAGE_LIGHT)
	th.set_color("font_hover_pressed_color", "Button", PAGE_LIGHT)
	th.set_color("font_disabled_color", "Button", FADED)
	th.set_type_variation("PrimaryButton", "Button")
	th.set_stylebox("normal", "PrimaryButton", _flat(BLUE, BLUE, 1, 2, 16, 7))
	th.set_stylebox("hover", "PrimaryButton", _flat(BLUE.darkened(0.15), BLUE, 1, 2, 16, 7))
	th.set_stylebox("pressed", "PrimaryButton", _flat(INK, INK, 1, 2, 16, 7))
	th.set_color("font_color", "PrimaryButton", PAGE_LIGHT)
	th.set_color("font_hover_color", "PrimaryButton", PAGE_LIGHT)
	th.set_color("font_focus_color", "PrimaryButton", PAGE_LIGHT)
	th.set_type_variation("TextButton", "Button")
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		th.set_stylebox(st, "TextButton", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 2, 2))
	th.set_color("font_color", "TextButton", BLUE)
	th.set_color("font_hover_color", "TextButton", INK)
	th.set_color("font_pressed_color", "TextButton", INK)
	th.set_type_variation("RowButton", "Button")
	var row := _flat(Color.TRANSPARENT, FADED, 0, 0, 12, 12)
	row.border_width_bottom = 1
	th.set_stylebox("normal", "RowButton", row)
	var row_h := _flat(PAGE_DARK, FADED, 0, 0, 12, 12)
	row_h.border_width_bottom = 1
	th.set_stylebox("hover", "RowButton", row_h)
	th.set_stylebox("pressed", "RowButton", row_h)
	th.set_stylebox("focus", "RowButton", row_h)
	th.set_stylebox("disabled", "RowButton", row)
	th.set_font("font", "RowButton", font("plex_medium"))
	th.set_font_size("font_size", "RowButton", 17)
	th.set_color("font_pressed_color", "RowButton", INK)
	th.set_color("font_hover_pressed_color", "RowButton", INK)
	th.set_constant("align_to_largest_stylebox", "RowButton", 0)
	# option buttons and their menus
	th.set_stylebox("panel", "PopupMenu", page_box(true, 6))
	th.set_stylebox("hover", "PopupMenu", _flat(PAGE_DARK))
	th.set_color("font_color", "PopupMenu", INK)
	th.set_color("font_hover_color", "PopupMenu", INK)
	# tabs: an ink underline
	th.set_stylebox("panel", "TabContainer", _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0, 10))
	th.set_stylebox("tabbar_background", "TabContainer", _flat(Color.TRANSPARENT))
	var tab_sel := _flat(Color.TRANSPARENT, BLUE, 0, 0, 12, 6)
	tab_sel.border_width_bottom = 2
	var tab_un := _flat(Color.TRANSPARENT, FADED, 0, 0, 12, 6)
	tab_un.border_width_bottom = 1
	var tab_hov := _flat(PAGE_DARK, FADED, 0, 0, 12, 6)
	tab_hov.border_width_bottom = 1
	th.set_stylebox("tab_selected", "TabContainer", tab_sel)
	th.set_stylebox("tab_unselected", "TabContainer", tab_un)
	th.set_stylebox("tab_hovered", "TabContainer", tab_hov)
	th.set_stylebox("tab_focus", "TabContainer", _flat(Color.TRANSPARENT))
	th.set_font("font", "TabContainer", font("plex_medium"))
	th.set_font_size("font_size", "TabContainer", 15)
	th.set_color("font_selected_color", "TabContainer", INK)
	th.set_color("font_unselected_color", "TabContainer", FADED)
	th.set_color("font_hovered_color", "TabContainer", INK)
	# text fields
	th.set_stylebox("normal", "LineEdit", _flat(PAGE_LIGHT, FADED, 1, 2, 8, 5))
	th.set_stylebox("focus", "LineEdit", _flat(PAGE_LIGHT, BLUE, 1, 2, 8, 5))
	th.set_stylebox("read_only", "LineEdit", _flat(PAGE, FADED, 1, 2, 8, 5))
	th.set_color("font_color", "LineEdit", INK)
	th.set_color("font_placeholder_color", "LineEdit", FADED)
	th.set_color("caret_color", "LineEdit", INK)
	th.set_color("selection_color", "LineEdit", Color(BLUE, 0.3))
	th.set_stylebox("normal", "TextEdit", _flat(PAGE_LIGHT, FADED, 1, 2, 8, 6))
	th.set_stylebox("focus", "TextEdit", _flat(PAGE_LIGHT, BLUE, 1, 2, 8, 6))
	th.set_color("font_color", "TextEdit", INK)
	th.set_color("caret_color", "TextEdit", INK)
	th.set_color("font_color", "CheckButton", INK)
	th.set_color("font_hover_color", "CheckButton", INK)
	th.set_color("font_pressed_color", "CheckButton", INK)
	th.set_color("font_hover_pressed_color", "CheckButton", INK)
	th.set_stylebox("separator", "HSeparator", _line(FADED))
	th.set_constant("h_separation", "GridContainer", 18)
	th.set_constant("v_separation", "GridContainer", 4)
	# label variations
	th.set_type_variation("TitleLabel", "Label")
	th.set_font("font", "TitleLabel", font("garamond"))
	th.set_font_size("font_size", "TitleLabel", 56)
	th.set_type_variation("HeadLabel", "Label")
	th.set_font("font", "HeadLabel", font("garamond_semibold"))
	th.set_font_size("font_size", "HeadLabel", 26)
	th.set_type_variation("SubheadLabel", "Label")
	th.set_font("font", "SubheadLabel", font("garamond_semibold"))
	th.set_font_size("font_size", "SubheadLabel", 20)
	th.set_type_variation("ProseLabel", "Label")
	th.set_font("font", "ProseLabel", font("garamond"))
	th.set_font_size("font_size", "ProseLabel", 18)
	th.set_type_variation("DetailLabel", "Label")
	th.set_font_size("font_size", "DetailLabel", 13)
	th.set_color("font_color", "DetailLabel", FADED)
	th.set_type_variation("ColumnLabel", "Label")
	th.set_font("font", "ColumnLabel", font("plex_medium"))
	th.set_font_size("font_size", "ColumnLabel", 13)
	th.set_color("font_color", "ColumnLabel", FADED)
	_theme = th
	return th


## A page: the paper fill, a hairline of ink, square corners.
static func page_box(border: bool = true, margin: int = 24) -> StyleBoxFlat:
	return _flat(PAGE, INK if border else Color.TRANSPARENT, 1 if border else 0, 2, margin, margin)


## Paper grain to lay over a page at a few percent alpha (generated, tiled).
static func grain() -> Texture2D:
	if _grain:
		return _grain
	var nt := NoiseTexture2D.new()
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	nt.noise = noise
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	_grain = nt
	return _grain


## A whole-euro amount with thousands grouped: "250 000 €".
static func money(amount: int) -> String:
	var neg := amount < 0
	var digits := str(absi(amount))
	var out := ""
	var n := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = "\u202f" + out   # narrow no-break space between groups
	return ("-" if neg else "") + out + "\u00a0€"


static func label(text: String, variation: String = "", parent: Node = null) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if parent:
		parent.add_child(l)
	return l


static func rule(parent: Node) -> HSeparator:
	var h := HSeparator.new()
	parent.add_child(h)
	return h


static func _flat(fill: Color, border: Color = Color.TRANSPARENT, width: int = 0, radius: int = 0, mx: int = 0, my: int = 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(width)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = mx
	sb.content_margin_right = mx
	sb.content_margin_top = my
	sb.content_margin_bottom = my
	return sb


static func _line(color: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = color
	sb.thickness = 1
	return sb
