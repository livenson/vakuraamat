# The town feed: game events (sales, rents, bids, months) and, when a town is online, real regional
# headlines and official notices pushed by the news feeder. Newest first; real items are read-only.
class_name NewsPanel
extends PanelContainer

signal show_parcel(tunnus: String)

const GOLD := Color(0.93, 0.78, 0.35)
const REAL := ["news", "official", "macro"]

var _page: VBoxContainer


func setup() -> void:
	custom_minimum_size = Vector2(900, 600)
	visible = false
	var v := VBoxContainer.new()
	v.name = "Body"
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var t := Label.new()
	t.name = "Title"
	t.add_theme_font_size_override("font_size", 26)
	t.add_theme_color_override("font_color", GOLD)
	v.add_child(t)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	_page = VBoxContainer.new()
	_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page.add_theme_constant_override("separation", 4)
	sc.add_child(_page)
	Ledger.event_added.connect(func(_e): _refill_if_visible())


func fill() -> void:
	get_node("Body/Title").text = "%s   ·   %s" % [tr("UI_NEWS"), Ledger.date_string()]
	for c in _page.get_children():
		c.queue_free()
	var events := Ledger.events(120)
	if events.is_empty():
		_page.add_child(_lbl(tr("UI_NEWS_EMPTY"), 15))
	for e in events:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		_page.add_child(line)
		var real: bool = str(e.kind) in REAL
		var when: String = str(e.published).left(10) if real and str(e.published) != "" else "M%d" % int(e.month)
		line.add_child(_lbl(when, 13, GOLD if real else Color(0.8, 0.8, 0.8)))
		var title := _lbl(str(e.title), 14, Color.WHITE)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(title)
		if real:
			line.add_child(_lbl(str(e.source), 13, GOLD))
			if str(e.link) != "":
				var b := Button.new()
				b.text = tr("BTN_LINK")
				b.tooltip_text = str(e.link)
				var link: String = str(e.link)
				b.pressed.connect(func():
					DisplayServer.clipboard_set(link)
					OS.shell_open(link))
				line.add_child(b)
		elif str(e.tunnus) != "":
			var b := Button.new()
			b.text = tr("BTN_SHOW")
			var tunnus: String = str(e.tunnus)
			b.pressed.connect(func(): show_parcel.emit(tunnus))
			line.add_child(b)


func _lbl(text: String, size: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _refill_if_visible() -> void:
	if visible:
		fill()
