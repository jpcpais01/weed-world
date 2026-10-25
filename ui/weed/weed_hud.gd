class_name WeedHud
extends CanvasLayer
## The weed HUD for the local Keling: the pouch (tap it, or press Q, to pick
## which strain to roll), a prompt for the weed action with a progress bar
## while rolling, a round leaf button for touch, toasts for picked buds and
## new strains, a big title when a bench power kicks in with a timer pill
## while it lasts, and the dreamy glow at the edges of the screen. Holding
## the puff charges Dragon Breath: the bar (or the leaf button's ring) fills
## blue until it catches. Each puff charges the strain's smoke gift: a gift
## chip (or a round touch button over the leaf) shows it with its charges,
## and the time left once it's breathed out.

const BTN_RADIUS := 46.0
const DRAGON_BLUE := Color(0.45, 0.88, 1.0)
const GIFT_RADIUS := 40.0

var weed: KelingWeed
var _root: Control
var _overlay: ColorRect
var _overlay_mat: ShaderMaterial
var _draw: Control
var _pouch_btn: Button
var _touch_btn: Button
var _toasts: Array[Dictionary] = []   # {text, color, t, life}
var _banner := {}                      # {title, text, color, t}
var _t := 0.0
var _pouch_pop := 0.0
var _joint_pop := 0.0
var _btn_press := 0.0
var _title_font: Font
var _body_font: Font
var _dragon_told := false
var _gift_btn: Button
var _gift_pop := 0.0
var _gift_told := {}


func setup(p_weed: KelingWeed) -> void:
	weed = p_weed
	weed.pouch_changed.connect(func(): _pouch_pop = 1.0)
	weed.joint_changed.connect(func(): _joint_pop = 1.0)
	weed.bud_collected.connect(_on_bud)
	weed.joint_rolled.connect(_on_joint_rolled)
	weed.note.connect(func(text: String): _toast(text, HudTheme.CREAM))
	weed.high.started.connect(_on_power)
	weed.high.ended.connect(func(): _toast("The high drifts away", Color(HudTheme.CREAM, 0.85)))
	weed.dragon_breathed.connect(_on_dragon)
	if weed.gifts:
		weed.gifts.charged.connect(_on_gift_charged)
		weed.gifts.cast_gift.connect(_on_gift_cast)


func _ready() -> void:
	layer = 9
	_title_font = HudTheme.title_font(600)
	_body_font = HudTheme.body_font(750)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = preload("res://ui/weed/dream_overlay.gdshader")
	_overlay.material = _overlay_mat
	_overlay.visible = false
	_root.add_child(_overlay)

	_draw = Control.new()
	_draw.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw.draw.connect(_on_draw)
	_root.add_child(_draw)

	_pouch_btn = _invisible_button()
	_pouch_btn.pressed.connect(func(): if weed: weed.cycle_strain())
	_root.add_child(_pouch_btn)
	_touch_btn = _invisible_button()
	_touch_btn.button_down.connect(func():
		_btn_press = 1.0
		if weed:
			weed.dragon_held = true
			weed.use())
	_touch_btn.button_up.connect(func(): if weed: weed.dragon_held = false)
	_root.add_child(_touch_btn)
	_gift_btn = _invisible_button()
	_gift_btn.pressed.connect(func(): if weed and weed.gifts: weed.gifts.cast())
	_root.add_child(_gift_btn)


func _invisible_button() -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.add_to_group("touch_blockers")
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _on_bud(strain: StringName, first: bool) -> void:
	var info := WeedStrains.info(strain)
	if first:
		var r := WeedStrains.rarity(strain)
		var found: int = weed.discovered.size() if weed else 1
		var kicker: String = "%s  %s strain  ·  %d of %d found" % ["★".repeat(r.stars), r.name, found, WeedStrains.ORDER.size()]
		var life: float = 4.2 + 0.6 * (r.stars - 1)
		_banner = {"title": "New strain: %s" % info.name, "text": info.blurb, "color": info.glow, "t": 0.0, "life": life,
			"kicker": kicker, "kicker_color": r.color}
	_toast("+1 %s bud" % info.name, info.glow.lerp(Color.WHITE, 0.35))


func _on_joint_rolled(strain: StringName) -> void:
	var info := WeedStrains.info(strain)
	var how := "tap the leaf" if _touch() else ("RT" if Bench.input_method() == 1 else "R")
	_toast("%s joint ready! %s to smoke" % [info.name, how], info.glow.lerp(Color.WHITE, 0.3))


func _on_power(element: StringName) -> void:
	var p := WeedStrains.power(element)
	var where := "" if element == &"none" else "  ·  %s" % _bench_view_name()
	_banner = {"title": p.name, "text": p.text + where, "color": p.color, "t": 0.0, "life": 4.0}


func _on_dragon() -> void:
	if _dragon_told:
		_toast("Dragon Breath!", DRAGON_BLUE.lerp(Color.WHITE, 0.3))
		return
	_dragon_told = true
	_banner = {"title": "Dragon Breath", "text": "A water dragon swims out of your breath and rains on all it passes", "color": DRAGON_BLUE, "t": 0.0, "life": 4.2}


func _on_gift_charged(gift: StringName, charges: int) -> void:
	if charges <= 0:
		return
	_gift_pop = 1.0
	var g := SmokeGifts.info(gift)
	var key := _gift_key()
	if not _gift_told.has(gift):
		_gift_told[gift] = true
		_banner = {"title": "Smoke gift: %s" % g.name, "text": "%s to breathe it out  ·  %s" % [key, g.text], "color": g.color, "t": 0.0, "life": 4.6}
	else:
		_toast("%s ×%d  ·  %s" % [g.name, charges, key], (g.color as Color).lerp(Color.WHITE, 0.3))


func _on_gift_cast(gift: StringName, boosted: bool) -> void:
	_gift_pop = 1.0
	var g := SmokeGifts.info(gift)
	var sub: String = g.text
	if boosted:
		sub = "The view makes it stronger!  ·  " + sub
	_banner = {"title": g.name, "text": sub, "color": g.color, "t": 0.0, "life": 3.6}


func _gift_key() -> String:
	match Bench.input_method():
		1:
			return "RB"
		2:
			return "Tap the gift"
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.has_method("key_label"):
		return "Press " + String(settings.key_label("gift"))
	return "Press V"


func _bench_view_name() -> String:
	var b := weed.keling.current_bench()
	return b.view_name() if b else ""


func _toast(text: String, color: Color) -> void:
	for t in _toasts:
		if t.text == text:
			t.t = minf(t.t, 0.3)
			return
	_toasts.append({"text": text, "color": color, "t": 0.0, "life": 2.6})
	if _toasts.size() > 3:
		_toasts.pop_front()


func _touch() -> bool:
	return Bench.input_method() == 2


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"weed HUD", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if weed == null:
		return
	delta = SmokeGifts.real(delta)
	_t += delta
	_gift_pop = move_toward(_gift_pop, 0.0, delta * 3.0)
	_pouch_pop = move_toward(_pouch_pop, 0.0, delta * 3.0)
	_joint_pop = move_toward(_joint_pop, 0.0, delta * 3.0)
	_btn_press = move_toward(_btn_press, 0.0, delta * 5.0)
	for t in _toasts:
		t.t += delta
	_toasts = _toasts.filter(func(t): return t.t < t.life)
	if not _banner.is_empty():
		_banner.t += delta
		if _banner.t > _banner.life:
			_banner = {}
	var locked := _ui_locked()
	_draw.visible = not locked
	# The dream at the edges of the screen.
	var high := weed.high
	var k := high.shown if high else 0.0
	_overlay.visible = k > 0.01
	if _overlay.visible:
		_overlay_mat.set_shader_parameter("intensity", k)
		_overlay_mat.set_shader_parameter("tint", high.power_info().color)
		_overlay_mat.set_shader_parameter("rainbow", 1.0 if high.element == &"none" else 0.0)
		_overlay_mat.set_shader_parameter("aspect", _root.size.x / maxf(_root.size.y, 1.0))
	_layout_buttons(locked)
	_draw.queue_redraw()


func _ui_locked() -> bool:
	var tree := get_tree()
	var input := tree.root.get_node_or_null("GameInput") if tree else null
	return input != null and bool(input.get("ui_locked"))


func _inset() -> Vector4:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var k := _root.size.x / float(win.x)
	return Vector4(safe.position.x * k, safe.position.y * k, (win.x - safe.end.x) * k, (win.y - safe.end.y) * k)


func _pouch_rect() -> Rect2:
	var ins := _inset()
	var y := 104.0 + ins.y
	# Make way for the frame-time readout under the FPS counter when it's open.
	var perf := get_tree().get_first_node_in_group("hud_perf") as Control
	if perf and perf.is_visible_in_tree():
		y = maxf(y, perf.position.y + perf.size.y + 10.0)
	return Rect2(Vector2(22.0 + ins.x, y), Vector2(_pouch_width(), 50.0))


func _pouch_width() -> float:
	return 150.0 if weed.has_joint() or weed.joint_strain != &"" else 112.0


func _button_center() -> Vector2:
	var s := _root.size
	var ins := _inset()
	return Vector2(s.x - 410.0 - ins.z, s.y - 205.0 - ins.w)


func _show_pouch() -> bool:
	return weed.bud_count() > 0 or weed.has_joint() or weed.busy()


func _show_touch_button() -> bool:
	return _touch() and (weed.next_action() != &"" or weed.busy())


func _layout_buttons(locked: bool) -> void:
	var pr := _pouch_rect()
	_pouch_btn.position = pr.position
	_pouch_btn.size = pr.size
	_pouch_btn.visible = not locked and _show_pouch()
	var c := _button_center()
	_touch_btn.position = c - Vector2.ONE * BTN_RADIUS * 1.15
	_touch_btn.size = Vector2.ONE * BTN_RADIUS * 2.3
	_touch_btn.visible = not locked and _show_touch_button()
	var gc := _gift_center()
	_gift_btn.position = gc - Vector2.ONE * GIFT_RADIUS * 1.2
	_gift_btn.size = Vector2.ONE * GIFT_RADIUS * 2.4
	_gift_btn.visible = not locked and _touch() and _show_gift()


# ---------------------------------------------------------------------------
# Drawing

func _on_draw() -> void:
	if weed == null:
		return
	if _show_pouch():
		_draw_pouch()
	if _show_touch_button():
		_draw_touch_button()
	elif not _touch():
		_draw_prompt()
	elif weed.busy():
		_draw_progress_caption(Vector2(_root.size.x * 0.5, _root.size.y - 150.0))
	_draw_power_pill()
	if _show_gift():
		if _touch():
			_draw_gift_button()
		else:
			_draw_gift_chip()
	_draw_toasts()
	_draw_banner()


func _draw_pouch() -> void:
	var r := _pouch_rect()
	var pop := _pouch_pop
	var sb := HudTheme.pill(Color(HudTheme.GLASS, 0.55))
	_draw.draw_style_box(sb, r.grow(pop * 3.0))
	var strain := weed.selected if weed.selected != &"" else (WeedStrains.ORDER[0] if weed.bud_count() == 0 else weed.selected)
	var info := WeedStrains.info(strain)
	var c := r.position + Vector2(28.0, r.size.y * 0.5)
	_bud_icon(c, 15.0 * (1.0 + pop * 0.25), info.bud_tint if weed.bud_count(strain) > 0 else Color(0.6, 0.6, 0.6, 0.6), info.glow)
	var n := weed.bud_count(strain)
	_text(Vector2(c.x + 22.0, c.y + 8.0), "×%d" % n, 22, HudTheme.CREAM, _title_font)
	var others := weed.bud_count() - n
	if others > 0:
		_text(Vector2(c.x + 22.0, c.y + 22.0), "+%d" % others, 12, Color(HudTheme.CREAM, 0.6), _body_font)
	if weed.has_joint():
		var jc := r.position + Vector2(r.size.x - 34.0, r.size.y * 0.5)
		_joint_icon(jc, 26.0 * (1.0 + _joint_pop * 0.2), WeedStrains.info(weed.joint_strain).glow, weed.lit)
		for i in KelingWeed.HITS:
			var dp := jc + Vector2(-9.0 + i * 9.0, 14.0)
			var on := i < weed.joint_puffs
			_draw.draw_circle(dp, 3.2, HudTheme.GOLD if on else Color(HudTheme.CREAM, 0.25))


func _draw_prompt() -> void:
	var s := _root.size
	var centre := Vector2(s.x * 0.5, s.y - 70.0 - _inset().w)
	if weed.busy():
		_draw_progress_caption(centre)
		return
	var action := weed.next_action()
	if action == &"" or weed.keling.mode not in [KelingController.Mode.GROUND, KelingController.Mode.SIT, KelingController.Mode.EMOTE]:
		return
	if weed.keling.mode == KelingController.Mode.SIT and not weed.keling.is_sitting():
		return
	var key := "RT" if Bench.input_method() == 1 else "R"
	var label := ""
	if action == &"roll":
		label = "Roll a %s joint" % WeedStrains.display_name(weed.selected if weed.selected != &"" else WeedStrains.ORDER[0])
		if weed.bud_count() > weed.bud_count(weed.selected):
			label += "   ·   Q other strain" if key == "R" else ""
	else:
		var b := weed.keling.current_bench()
		var power := WeedStrains.power(StringName(b.site.element) if b else &"none")
		label = ("Light up" if not weed.lit else "Take a puff") + "   ·   " + power.name
		if weed.lit:
			label = "Take a puff   ·   hold for Dragon Breath" + ("" if b == null else "   ·   " + power.name)
	var w := _body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + 74.0
	var rect := Rect2(centre - Vector2(w * 0.5, 22.0), Vector2(w, 44.0))
	_draw.draw_style_box(HudTheme.pill(Color(HudTheme.GLASS, 0.6)), rect)
	var cap := Rect2(rect.position + Vector2(8.0, 7.0), Vector2(maxf(30.0, key.length() * 14.0 + 12.0), 30.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = HudTheme.CREAM
	sb.set_corner_radius_all(8)
	_draw.draw_style_box(sb, cap)
	_text(cap.position + Vector2(cap.size.x * 0.5 - key.length() * 6.0, 22.0), key, 17, HudTheme.INK, _title_font)
	_text(Vector2(cap.end.x + 12.0, rect.position.y + 28.0), label, 17, HudTheme.CREAM, _body_font)


func _draw_progress_caption(centre: Vector2) -> void:
	var label := ""
	match weed.act:
		KelingWeed.Act.ROLL:
			label = weed.roll_stage()
		KelingWeed.Act.LIGHT:
			label = "Lighting up"
		KelingWeed.Act.HIT:
			label = "Puff %d of %d" % [KelingWeed.HITS - weed.joint_puffs + (0 if weed.act_t > 2.4 else 1), KelingWeed.HITS]
			if weed.dragon_charge() > 0.0:
				label = "Hold it in for Dragon Breath..."
		KelingWeed.Act.DRAGON:
			label = "Dragon Breath!" if weed.act_t > KelingWeed.DRAGON_RELEASE else "Drawing in the dragon..."
	var w := 300.0
	var rect := Rect2(centre - Vector2(w * 0.5, 26.0), Vector2(w, 52.0))
	_draw.draw_style_box(HudTheme.pill(Color(HudTheme.GLASS, 0.6)), rect)
	var tw := _body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	_text(Vector2(centre.x - tw * 0.5, rect.position.y + 22.0), label, 16, HudTheme.CREAM, _body_font)
	var bar := Rect2(rect.position + Vector2(22.0, 31.0), Vector2(w - 44.0, 8.0))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(HudTheme.CREAM, 0.18)
	sb.set_corner_radius_all(4)
	_draw.draw_style_box(sb, bar)
	var p := clampf(weed.progress(), 0.0, 1.0)
	var charging := weed.dragon_charge()
	if charging > 0.0 and weed.act == KelingWeed.Act.HIT:
		p = charging
	if p > 0.01:
		var fill := sb.duplicate() as StyleBoxFlat
		var strain := weed._roll_strain if weed.act == KelingWeed.Act.ROLL else weed.joint_strain
		fill.bg_color = WeedStrains.info(strain).glow.lerp(HudTheme.LEAF, 0.3)
		if charging > 0.0:
			fill.bg_color = DRAGON_BLUE.lerp(Color.WHITE, 0.25 * (0.5 + 0.5 * sin(_t * 12.0)))
		_draw.draw_style_box(fill, Rect2(bar.position, Vector2(bar.size.x * p, bar.size.y)))
		if weed.act == KelingWeed.Act.ROLL:
			var secs := ceili(KelingWeed.ROLL_TIME - weed.act_t)
			_text(Vector2(rect.end.x - 34.0, rect.position.y + 22.0), "%ds" % secs, 13, Color(HudTheme.CREAM, 0.65), _body_font)


func _draw_touch_button() -> void:
	var c := _button_center()
	var r := BTN_RADIUS * (1.0 - 0.08 * _btn_press)
	_draw.draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.25))
	var busy := weed.busy()
	var action := weed.next_action()
	var strain := weed.joint_strain if action == &"smoke" or weed.act != KelingWeed.Act.ROLL else weed._roll_strain
	if action == &"roll":
		strain = weed.selected if weed.selected != &"" else WeedStrains.ORDER[0]
	var glow: Color = WeedStrains.info(strain).glow
	_draw.draw_circle(c, r, Color(HudTheme.GLASS, 0.66))
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	_draw.draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(glow, 0.35 + 0.3 * pulse * (0.0 if busy else 1.0)), 2.6, true)
	if busy:
		var p := clampf(weed.progress(), 0.0, 1.0)
		_draw.draw_arc(c, r + 5.0, -PI * 0.5, -PI * 0.5 + TAU * p, 64, glow.lerp(Color.WHITE, 0.2), 5.0, true)
		var charging := weed.dragon_charge()
		if charging > 0.0:
			# Holding: a blue ring winds round until Dragon Breath catches.
			_draw.draw_arc(c, r + 12.0, -PI * 0.5, -PI * 0.5 + TAU * charging, 64, Color(DRAGON_BLUE, 0.9), 4.0, true)
	if action == &"smoke" or (busy and weed.act != KelingWeed.Act.ROLL):
		_joint_icon(c, r * 1.05, glow, weed.lit)
	else:
		_bud_icon(c, r * 0.42, WeedStrains.info(strain).bud_tint, glow)
	var label := "Roll" if action == &"roll" else ("Smoke" if action == &"smoke" else "")
	if action == &"smoke" and weed.lit:
		label = "Smoke · hold: dragon"
	if busy:
		label = "%ds" % ceili(KelingWeed.ROLL_TIME - weed.act_t) if weed.act == KelingWeed.Act.ROLL else ""
	if label != "":
		var tw := _body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_text(c + Vector2(-tw * 0.5, r + 22.0), label, 14, HudTheme.CREAM, _body_font)


func _draw_power_pill() -> void:
	var high := weed.high
	if high == null or not high.active() or high.shown < 0.03:
		return
	var p := high.power_info()
	var s := _root.size
	var label: String = p.name
	var w := _title_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 70.0
	var rect := Rect2(Vector2(s.x * 0.5 - w * 0.5, 16.0 + _inset().y), Vector2(w, 40.0))
	var a := clampf(high.shown * 3.0, 0.0, 1.0)
	_draw.draw_style_box(HudTheme.pill(Color(HudTheme.GLASS, 0.55 * a)), rect)
	var c := rect.position + Vector2(22.0, 20.0)
	var col: Color = p.color
	_draw.draw_arc(c, 12.0, 0.0, TAU, 32, Color(col, 0.25 * a), 4.0, true)
	_draw.draw_arc(c, 12.0, -PI * 0.5, -PI * 0.5 + TAU * high.remaining_fraction(), 32, Color(col, a), 4.0, true)
	_draw.draw_circle(c, 4.0 + 1.5 * sin(_t * 3.0), Color(col, a))
	_text(Vector2(c.x + 22.0, rect.position.y + 27.0), label, 18, Color(HudTheme.CREAM, a), _title_font)


# ---------------------------------------------------------------------------
# Smoke gifts

func _show_gift() -> bool:
	var g := weed.gifts
	return g != null and (g.charges > 0 or g.current() != null)


func _gift_center() -> Vector2:
	return _button_center() + Vector2(0.0, -128.0)


## The gift shown: the one charged, else the one running.
func _gift_shown() -> StringName:
	var g := weed.gifts
	if g.charges > 0:
		return g.ready_gift
	var cur := g.current()
	return cur.gift if cur else &""


func _draw_gift_button() -> void:
	var g := weed.gifts
	var id := _gift_shown()
	if id == &"":
		return
	var info := SmokeGifts.info(id)
	var col: Color = info.color
	var c := _gift_center()
	var ready := g.charges > 0
	var r := GIFT_RADIUS * (1.0 + 0.12 * _gift_pop)
	_draw.draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.25))
	_draw.draw_circle(c, r, Color(HudTheme.GLASS, 0.66))
	var pulse := 0.5 + 0.5 * sin(_t * 3.4)
	if ready:
		_draw.draw_circle(c, r * (1.15 + 0.08 * pulse), Color(col, 0.12 + 0.1 * pulse))
		_draw.draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(col, 0.55 + 0.35 * pulse), 3.0, true)
	var cur := g.current()
	if cur:
		_draw.draw_arc(c, r + 6.0, -PI * 0.5, -PI * 0.5 + TAU * cur.remaining_fraction(), 64, Color(col, 0.9), 4.0, true)
	_gift_icon(c, r * 0.55, id, col if ready or cur else Color(col, 0.5))
	_charge_dots(c + Vector2(0, r * 0.62), g.charges, col)
	var label: String = info.name
	var tw := _body_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_text(c + Vector2(-tw * 0.5, r + 20.0), label, 13, HudTheme.CREAM, _body_font)


func _draw_gift_chip() -> void:
	var g := weed.gifts
	var id := _gift_shown()
	if id == &"":
		return
	var info := SmokeGifts.info(id)
	var col: Color = info.color
	var s := _root.size
	var ready := g.charges > 0
	var cur := g.current()
	var key := "RB" if Bench.input_method() == 1 else _key_name()
	var label: String = info.name
	var w := _title_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x + (110.0 if ready else 70.0)
	var y := 64.0 + _inset().y
	var high := weed.high
	if high == null or not high.active() or high.shown < 0.03:
		y = 16.0 + _inset().y
	var rect := Rect2(Vector2(s.x * 0.5 - w * 0.5, y), Vector2(w, 38.0)).grow(_gift_pop * 3.0)
	_draw.draw_style_box(HudTheme.pill(Color(HudTheme.GLASS, 0.58)), rect)
	var c := rect.position + Vector2(22.0, rect.size.y * 0.5)
	if cur:
		_draw.draw_arc(c, 14.0, -PI * 0.5, -PI * 0.5 + TAU * cur.remaining_fraction(), 32, Color(col, 0.9), 3.0, true)
	elif ready:
		_draw.draw_circle(c, 15.0 + 1.5 * sin(_t * 3.4), Color(col, 0.18))
	_gift_icon(c, 10.0, id, col)
	_text(Vector2(c.x + 22.0, rect.position.y + 26.0), label, 17, HudTheme.CREAM, _title_font)
	if ready:
		_charge_dots(Vector2(rect.end.x - 62.0, rect.position.y + rect.size.y * 0.5), g.charges, col)
		var cap := Rect2(Vector2(rect.end.x - 38.0, rect.position.y + 6.0), Vector2(maxf(26.0, key.length() * 12.0 + 10.0), 26.0))
		cap.position.x = rect.end.x - cap.size.x - 8.0
		var sb := StyleBoxFlat.new()
		sb.bg_color = HudTheme.CREAM
		sb.set_corner_radius_all(7)
		_draw.draw_style_box(sb, cap)
		_text(cap.position + Vector2(cap.size.x * 0.5 - key.length() * 5.2, 19.0), key, 15, HudTheme.INK, _title_font)


func _key_name() -> String:
	var settings := get_node_or_null("/root/Settings")
	if settings and settings.has_method("key_label"):
		return String(settings.key_label("gift"))
	return "V"


func _charge_dots(c: Vector2, n: int, col: Color) -> void:
	var total := SmokeGifts.MAX_CHARGES
	for i in total:
		var p := c + Vector2((i - (total - 1) * 0.5) * 9.0, 0.0)
		_draw.draw_circle(p, 3.0, col.lerp(Color.WHITE, 0.3) if i < n else Color(HudTheme.CREAM, 0.22))


## Little drawn icons for the gifts.
func _gift_icon(c: Vector2, r: float, id: StringName, col: Color) -> void:
	var light := col.lerp(Color.WHITE, 0.45)
	match id:
		&"fireflies":
			for i in 3:
				var a := _t * 1.4 + i * 2.1
				var p := c + Vector2(cos(a), sin(a * 1.3)) * r * 0.55
				var glow := 0.5 + 0.5 * sin(_t * 4.0 + i * 1.7)
				_draw.draw_circle(p, r * 0.42, Color(col, 0.18 * glow))
				_draw.draw_circle(p, r * 0.16, Color(light, 0.6 + 0.4 * glow))
		&"cloud":
			for b in [[Vector2(-0.45, 0.15), 0.42], [Vector2(0.05, -0.12), 0.55], [Vector2(0.5, 0.18), 0.38], [Vector2(0.0, 0.28), 0.4]]:
				_draw.draw_circle(c + (b[0] as Vector2) * r, float(b[1]) * r, light)
		&"bloom":
			for i in 6:
				var a := TAU * i / 6.0 + _t * 0.4
				_draw.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.5, r * 0.36, Color(col, 0.9))
			_draw.draw_circle(c, r * 0.3, Color(1.0, 0.9, 0.5))
		&"slowtime":
			var top := PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.85), c + Vector2(r * 0.6, -r * 0.85), c, ])
			var bot := PackedVector2Array([c, c + Vector2(r * 0.6, r * 0.85), c + Vector2(-r * 0.6, r * 0.85)])
			_draw.draw_colored_polygon(top, Color(light, 0.9))
			_draw.draw_colored_polygon(bot, Color(light, 0.45))
			_draw.draw_line(c + Vector2(-r * 0.7, -r * 0.88), c + Vector2(r * 0.7, -r * 0.88), light, 2.0, true)
			_draw.draw_line(c + Vector2(-r * 0.7, r * 0.88), c + Vector2(r * 0.7, r * 0.88), light, 2.0, true)
		&"moonjump":
			_draw.draw_circle(c, r * 0.8, light)
			_draw.draw_circle(c + Vector2(r * 0.38, -r * 0.18), r * 0.68, Color(HudTheme.GLASS, 0.95))
			_star(c + Vector2(r * 0.75, r * 0.55), r * 0.25, light)
		&"owl":
			# Spread wings, a round head with two big eyes.
			var flap := sin(_t * 3.0) * 0.12
			for sgn: float in [-1.0, 1.0]:
				var wing := PackedVector2Array([c + Vector2(sgn * r * 0.2, -r * 0.05), c + Vector2(sgn * r * 1.0, -r * (0.45 + flap)),
						c + Vector2(sgn * r * 0.85, r * 0.05), c + Vector2(sgn * r * 0.25, r * 0.35)])
				_draw.draw_colored_polygon(wing, Color(light, 0.75))
			_draw.draw_circle(c + Vector2(0, r * 0.1), r * 0.36, light)
			_draw.draw_circle(c + Vector2(0, -r * 0.32), r * 0.3, light)
			for sgn: float in [-1.0, 1.0]:
				_draw.draw_circle(c + Vector2(sgn * r * 0.13, -r * 0.34), r * 0.11, Color(HudTheme.GLASS, 0.95))
		_:
			_draw.draw_circle(c, r * 0.6, light)


func _draw_toasts() -> void:
	var s := _root.size
	var y := s.y - (210.0 if _touch() else 130.0) - _inset().w
	for i in range(_toasts.size() - 1, -1, -1):
		var t: Dictionary = _toasts[i]
		var a := clampf(t.t / 0.2, 0.0, 1.0) * clampf((t.life - t.t) / 0.5, 0.0, 1.0)
		var rise := (1.0 - clampf(t.t / 0.3, 0.0, 1.0)) * 12.0
		var w := _body_font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 36.0
		var rect := Rect2(Vector2(s.x * 0.5 - w * 0.5, y + rise - 18.0), Vector2(w, 36.0))
		_draw.draw_style_box(HudTheme.pill(Color(HudTheme.GLASS, 0.55 * a)), rect)
		_text(rect.position + Vector2(18.0, 24.0), t.text, 16, Color(t.color, a), _body_font)
		y -= 44.0


func _draw_banner() -> void:
	if _banner.is_empty():
		return
	var s := _root.size
	var t: float = _banner.t
	var a := clampf(t / 0.35, 0.0, 1.0) * clampf((_banner.life - t) / 0.8, 0.0, 1.0)
	var scale := 1.0 + 0.25 * pow(1.0 - clampf(t / 0.45, 0.0, 1.0), 3.0)
	var title: String = _banner.title
	var size := int(46.0 * scale)
	var tw := _title_font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var y := s.y * 0.3
	var col: Color = _banner.color
	# Soft glow behind the title.
	for k in 3:
		_draw.draw_string(_title_font, Vector2(s.x * 0.5 - tw * 0.5, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col, 0.18 * a), 0)
		_draw.draw_string_outline(_title_font, Vector2(s.x * 0.5 - tw * 0.5, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 10 + k * 8, Color(col, 0.08 * a))
	_draw.draw_string_outline(_title_font, Vector2(s.x * 0.5 - tw * 0.5, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(HudTheme.INK, 0.55 * a))
	_draw.draw_string(_title_font, Vector2(s.x * 0.5 - tw * 0.5, y), title, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(col.lerp(Color.WHITE, 0.55), a))
	if _banner.has("kicker"):
		var kick: String = _banner.kicker
		var kc: Color = _banner.kicker_color
		var kw := _body_font.get_string_size(kick, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		var kp := Vector2(s.x * 0.5 - kw * 0.5, y - size * 0.95)
		_draw.draw_string_outline(_body_font, kp, kick, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, 6, Color(HudTheme.INK, 0.55 * a))
		_draw.draw_string(_body_font, kp, kick, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(kc.lerp(Color.WHITE, 0.25), a))
	var sub: String = _banner.text
	var sw := _body_font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_draw.draw_string_outline(_body_font, Vector2(s.x * 0.5 - sw * 0.5, y + 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 6, Color(HudTheme.INK, 0.5 * a))
	_draw.draw_string(_body_font, Vector2(s.x * 0.5 - sw * 0.5, y + 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(HudTheme.CREAM, a))
	# A few sparkles round the title.
	for i in 7:
		var ang := float(i) / 7.0 * TAU + t * 0.8
		var p := Vector2(s.x * 0.5 + cos(ang) * (tw * 0.55 + 20.0), y - 14.0 + sin(ang * 1.7) * 30.0)
		var tw2 := 0.5 + 0.5 * sin(t * 6.0 + i * 1.3)
		_star(p, 3.0 + 4.0 * tw2, Color(col.lerp(Color.WHITE, 0.4), a * tw2))


func _text(pos: Vector2, text: String, size: int, col: Color, font: Font) -> void:
	_draw.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.45 * col.a))
	_draw.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _star(c: Vector2, r: float, col: Color) -> void:
	_draw.draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 1.6, true)
	_draw.draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 1.6, true)
	_draw.draw_circle(c, r * 0.3, col)


## A plump bud: a teardrop with a few sugar-leaf points and a glint.
func _bud_icon(c: Vector2, r: float, tint: Color, glow: Color) -> void:
	_draw.draw_circle(c, r * 1.25, Color(glow, 0.18 + 0.08 * sin(_t * 2.5)))
	var pts := PackedVector2Array()
	for i in 24:
		var a := float(i) / 24.0 * TAU
		var rr := r * (1.0 + 0.12 * sin(a * 5.0))
		var p := Vector2(sin(a) * rr * 0.72, -cos(a) * rr)
		if p.y < 0.0:
			p.x *= 1.0 + p.y / r * 0.35  # taper to a point at the top
		pts.append(c + p)
	_draw.draw_colored_polygon(pts, tint.darkened(0.15))
	_draw.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(HudTheme.INK, 0.7), 1.6, true)
	for k in 3:
		var a := -0.8 + k * 0.8
		var tip := c + Vector2(sin(a), -cos(a) * 0.4) * r * 1.05
		_draw.draw_line(c + Vector2(0, r * 0.2), tip, Color(tint.lightened(0.35), 0.8), 1.4, true)
	_draw.draw_circle(c + Vector2(-r * 0.25, -r * 0.35), r * 0.16, Color(1, 1, 1, 0.7))
	_draw.draw_line(c + Vector2(0, r * 0.95), c + Vector2(0, r * 1.3), Color(HudTheme.MOSS, 0.9), 2.2, true)


## A little joint, tilted, with its ember glowing when lit.
func _joint_icon(c: Vector2, length: float, glow: Color, is_lit: bool) -> void:
	var dir := Vector2(1.0, -0.42).normalized()
	var n := Vector2(-dir.y, dir.x)
	var a := c - dir * length * 0.5
	var b := c + dir * length * 0.5
	var poly := PackedVector2Array([a + n * 2.6, b + n * 4.0, b - n * 4.0, a - n * 2.6])
	_draw.draw_colored_polygon(poly, Color(0.98, 0.95, 0.88))
	_draw.draw_polyline(poly + PackedVector2Array([poly[0]]), Color(HudTheme.INK, 0.7), 1.4, true)
	_draw.draw_line(a, a + dir * length * 0.16, Color(0.86, 0.72, 0.5), 5.0, true)
	if is_lit:
		var f := 0.7 + 0.3 * sin(_t * 9.0)
		_draw.draw_circle(b, 7.0, Color(1.0, 0.45, 0.12, 0.3 * f))
		_draw.draw_circle(b, 3.6, Color(1.0, 0.55, 0.2, f))
		for i in 3:
			var up := Vector2(sin(_t * 1.5 + i) * 3.0, -8.0 - i * 6.0 - fmod(_t * 10.0, 6.0))
			_draw.draw_circle(b + up, 2.0 + i, Color(glow.lerp(Color.WHITE, 0.6), 0.25 - i * 0.07))
	else:
		_draw.draw_line(b, b + dir * 5.0, Color(0.98, 0.95, 0.88), 3.0, true)
