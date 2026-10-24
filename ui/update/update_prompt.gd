extends CanvasLayer
## The update card, owned by the Updater autoload so it works in any scene.
## A frosted toast slides down once you are in the forest ("A new Weed World
## is ready"). It opens a card with every patch note you have missed, then
## follows the update through: the vine progress bar while downloading,
## a check of the file, Android's one-time "allow installs" switch with a
## step-by-step guide, the installer, or a restart on Windows. "Keep playing"
## tucks a download away into a small chip so you can carry on exploring.
## Also says hello on the first launch after an update.

const UpdaterScript := preload("res://autoload/updater.gd")
const S := UpdaterScript.State
const TOAST_HOLD := 12.0

var _u   ## the Updater autoload
var _root: Control
var _toast: PanelContainer
var _toast_icon: UpdateSprout
var _toast_title: Label
var _toast_sub: Label
var _toast_action: Button
var _toast_action_cb := Callable()
var _toast_shown := 0.0      ## 0..1 slide
var _toast_want := false
var _toast_timer := 0.0
var _chip: Button
var _chip_icon: UpdateSprout
var _backdrop: ColorRect
var _panel: PanelContainer
var _icon: UpdateSprout
var _title: Label
var _sub: Label
var _close: RoundIconButton
var _notes_frame: PanelContainer
var _notes: RichTextLabel
var _guide: VBoxContainer
var _progress_box: VBoxContainer
var _vine_holder: Control
var _vine: VineProgress
var _status: Label
var _percent: Label
var _message: Label
var _link: Button
var _secondary: Button
var _primary: Button
var _panel_pop := 0.0
var _offered_tag := ""
var _parked := false          ## the player chose "Later" / "Keep playing"
var _game_clock := 0.0
var _pending_welcome := ""
var _prev_lock := false
var _locked := false
var _watching_manual := false
var _queued: Array = []       ## a toast waiting for the player to be in the forest


func _init(updater) -> void:
	_u = updater


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = HudTheme.theme()
	add_child(_root)
	_build_toast()
	_build_chip()
	_build_panel()
	_root.resized.connect(_layout)
	_u.state_changed.connect(_on_state)
	_u.updated.connect(func(from: String, to: String): _pending_welcome = "%s|%s" % [from, to])
	_u.card_requested.connect(_on_card_requested)
	_layout()


# ---------------------------------------------------------------------------
# Building

func _build_toast() -> void:
	_toast = PanelContainer.new()
	_toast.add_theme_stylebox_override("panel", HudTheme.glass(30, 0.86, 12.0))
	_toast.visible = false
	_toast.mouse_filter = Control.MOUSE_FILTER_STOP
	_toast.add_to_group("touch_blockers")
	_toast.gui_input.connect(func(e):
		if _is_tap(e) and _toast_action_cb.is_valid():
			_toast_action_cb.call())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.add_child(row)
	_toast_icon = UpdateSprout.new(50.0)
	row.add_child(_toast_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	_toast_title = Label.new()
	HudTheme.style_label(_toast_title, 21, HudTheme.CREAM, HudTheme.title_font(600))
	col.add_child(_toast_title)
	_toast_sub = Label.new()
	HudTheme.style_label(_toast_sub, 15, Color(HudTheme.CREAM, 0.72), HudTheme.body_font(700), false)
	col.add_child(_toast_sub)
	_toast_action = _make_button("", true)
	_toast_action.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toast_action.pressed.connect(func():
		if _toast_action_cb.is_valid():
			_toast_action_cb.call())
	row.add_child(_toast_action)
	var close := RoundIconButton.new("close", 40.0)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func():
		_hide_toast()
		_parked = true)
	row.add_child(close)
	_root.add_child(_toast)


func _build_chip() -> void:
	_chip = Button.new()
	_chip.focus_mode = Control.FOCUS_NONE
	_chip.visible = false
	_chip.add_theme_font_override("font", HudTheme.title_font(600))
	_chip.add_theme_font_size_override("font_size", 16)
	var st := HudTheme.pill(Color(HudTheme.GLASS, 0.7), Color(HudTheme.GOLD, 0.55))
	st.content_margin_left = 48
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	_chip.add_theme_stylebox_override("normal", st)
	var hov := st.duplicate() as StyleBoxFlat
	hov.bg_color = Color(0.14, 0.24, 0.13, 0.82)
	_chip.add_theme_stylebox_override("hover", hov)
	_chip.add_theme_stylebox_override("pressed", hov)
	_chip.add_to_group("touch_blockers")
	_chip.pressed.connect(_open_panel)
	_chip_icon = UpdateSprout.new(34.0)
	_chip_icon.position = Vector2(8, 3)
	_chip.add_child(_chip_icon)
	_root.add_child(_chip)


func _build_panel() -> void:
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.02, 0.05, 0.03, 0.55)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.visible = false
	_backdrop.add_to_group("touch_blockers")
	_backdrop.gui_input.connect(func(e):
		if _is_tap(e) and _closable():
			_close_panel())
	_root.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", HudTheme.glass(28, 0.93, 26.0))
	_panel.visible = false
	_panel.add_to_group("touch_blockers")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	_icon = UpdateSprout.new(76.0)
	head.add_child(_icon)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	_title = Label.new()
	HudTheme.style_label(_title, 30, HudTheme.CREAM, HudTheme.title_font(600))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_title)
	_sub = Label.new()
	HudTheme.style_label(_sub, 16, Color(HudTheme.CREAM, 0.72), HudTheme.body_font(700), false)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_sub)
	_close = RoundIconButton.new("close", 46.0, true)
	_close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close.pressed.connect(_close_panel)
	head.add_child(_close)

	_notes_frame = PanelContainer.new()
	var inset := StyleBoxFlat.new()
	inset.bg_color = Color(0, 0.02, 0.0, 0.28)
	inset.set_corner_radius_all(18)
	inset.set_content_margin_all(16)
	_notes_frame.add_theme_stylebox_override("panel", inset)
	_notes_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_notes_frame)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.scroll_active = true
	_notes.add_theme_font_size_override("normal_font_size", 16)
	_notes.add_theme_font_size_override("bold_font_size", 18)
	_notes.add_theme_constant_override("line_separation", 4)
	_notes_frame.add_child(_notes)

	_guide = VBoxContainer.new()
	_guide.add_theme_constant_override("separation", 10)
	box.add_child(_guide)
	var steps := [
		["1", "Tap [b]Open settings[/b] below."],
		["2", "Switch on [b]Allow from this source[/b] for Weed World."],
		["3", "Come back here. The install carries on by itself."],
	]
	for st in steps:
		var row := _guide_row(st[0], st[1])
		if st[0] == "2":
			row.add_child(_switch_glyph())
		_guide.add_child(row)

	_progress_box = VBoxContainer.new()
	_progress_box.add_theme_constant_override("separation", 6)
	box.add_child(_progress_box)
	_vine_holder = Control.new()
	_vine_holder.custom_minimum_size = Vector2(0, 46)
	_vine_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_box.add_child(_vine_holder)
	var srow := HBoxContainer.new()
	_progress_box.add_child(srow)
	_status = Label.new()
	HudTheme.style_label(_status, 16, Color(HudTheme.CREAM, 0.85), HudTheme.body_font(700))
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	srow.add_child(_status)
	_percent = Label.new()
	HudTheme.style_label(_percent, 24, HudTheme.GOLD, HudTheme.title_font(600))
	srow.add_child(_percent)

	_message = Label.new()
	HudTheme.style_label(_message, 17, Color(HudTheme.CREAM, 0.9), HudTheme.body_font(650))
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_message)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_link = Button.new()
	_link.flat = true
	_link.text = "Download page"
	_link.focus_mode = Control.FOCUS_ALL
	_link.add_theme_font_override("font", HudTheme.body_font(750))
	_link.add_theme_font_size_override("font_size", 15)
	_link.add_theme_color_override("font_color", Color(HudTheme.WATER, 0.9))
	_link.add_theme_color_override("font_hover_color", HudTheme.WATER.lightened(0.3))
	_link.add_theme_stylebox_override("focus", _focus_style())
	_link.pressed.connect(func(): _u.open_release_page())
	buttons.add_child(_link)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(gap)
	_secondary = _make_button("", false)
	_secondary.pressed.connect(_on_secondary)
	buttons.add_child(_secondary)
	_primary = _make_button("", true)
	_primary.pressed.connect(_on_primary)
	buttons.add_child(_primary)

	_root.add_child(_panel)


func _guide_row(n: String, text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(38, 38)
	badge.draw.connect(func():
		var c := badge.size * 0.5
		badge.draw_circle(c, 18.0, HudTheme.LEAF)
		badge.draw_arc(c, 17.0, 0.0, TAU, 32, HudTheme.INK, 2.0, true)
		var f := HudTheme.title_font(650)
		var sz := f.get_string_size(n, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		badge.draw_string(f, c + Vector2(-sz.x * 0.5, sz.y * 0.32), n, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HudTheme.INK))
	row.add_child(badge)
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.text = text
	l.add_theme_font_size_override("normal_font_size", 18)
	l.add_theme_font_size_override("bold_font_size", 18)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	return row


## A little Android-style switch that keeps flicking on, to show which
## control to look for in Settings.
func _switch_glyph() -> Control:
	var sw := Control.new()
	sw.custom_minimum_size = Vector2(64, 38)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := [0.0]
	sw.draw.connect(func():
		var cycle := fmod(t[0], 2.6)
		var on := smoothstep(0.6, 0.95, cycle) * (1.0 - smoothstep(2.2, 2.5, cycle))
		var c := Vector2(32, 19)
		var track := Rect2(c - Vector2(24, 11), Vector2(48, 22))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.4, 0.45, 0.4).lerp(HudTheme.LEAF, on)
		sb.set_corner_radius_all(11)
		sb.anti_aliasing = true
		sw.draw_style_box(sb, track)
		var knob := c + Vector2(lerpf(-13.0, 13.0, on), 0)
		sw.draw_circle(knob + Vector2(0, 1.5), 9.5, Color(0, 0, 0, 0.25))
		sw.draw_circle(knob, 9.5, Color(1, 1, 0.96)))
	var tick := Timer.new()
	tick.wait_time = 1.0 / 30.0
	tick.autostart = true
	tick.timeout.connect(func():
		t[0] += tick.wait_time
		sw.queue_redraw())
	sw.add_child(tick)
	return sw


func _make_button(text: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 19)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if primary:
		var n := HudTheme.pill(Color(0.69, 0.88, 0.47, 0.96), Color(1, 1, 0.9, 0.55), 26)
		n.content_margin_left = 26
		n.content_margin_right = 26
		var h := n.duplicate() as StyleBoxFlat
		h.bg_color = Color(0.78, 0.94, 0.56)
		var p := n.duplicate() as StyleBoxFlat
		p.bg_color = Color(0.55, 0.76, 0.36)
		var d := n.duplicate() as StyleBoxFlat
		d.bg_color = Color(0.4, 0.5, 0.36, 0.6)
		b.add_theme_stylebox_override("normal", n)
		b.add_theme_stylebox_override("hover", h)
		b.add_theme_stylebox_override("pressed", p)
		b.add_theme_stylebox_override("disabled", d)
		for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(k, HudTheme.INK)
		b.add_theme_color_override("font_disabled_color", Color(HudTheme.INK, 0.5))
		b.add_theme_font_override("font", HudTheme.title_font(650))
	else:
		for k in ["normal", "hover", "pressed"]:
			var sb := (HudTheme.theme().get_stylebox(k, "Button") as StyleBoxFlat).duplicate() as StyleBoxFlat
			sb.content_margin_left = 22
			sb.content_margin_right = 22
			sb.set_corner_radius_all(26)
			b.add_theme_stylebox_override(k, sb)
	b.add_theme_stylebox_override("focus", _focus_style())
	return b


func _focus_style() -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = HudTheme.GOLD
	f.set_border_width_all(3)
	f.set_corner_radius_all(28)
	f.set_expand_margin_all(4)
	return f


# ---------------------------------------------------------------------------
# Flow

func _on_state(s: int) -> void:
	match s:
		S.AVAILABLE:
			var tag := str(_u.release.tag)
			if _watching_manual:
				_watching_manual = false
				_hide_toast()
				_open_panel()
			elif tag != _offered_tag:
				_offered_tag = tag
				_parked = false
				_offer_when_in_game()
		S.READY:
			if not _panel.visible:
				if _u.plat == "windows":
					_queue_toast("Update ready", "v%s is downloaded. Restart whenever you like." % _u.release.version, "Restart", _install_from_toast)
				else:
					_queue_toast("Update ready", "v%s is downloaded and waiting." % _u.release.version, "Install", _install_from_toast)
		S.UP_TO_DATE:
			if _watching_manual:
				_watching_manual = false
				_show_toast("You're up to date", "v%s is the newest Weed World." % _u.current_version, "", Callable(), 4.0, true)
		S.FAILED:
			if _watching_manual and _u.release.is_empty():
				_watching_manual = false
				_show_toast("Couldn't check for updates", _u.error_text, "Retry", func(): _manual_check(), 7.0)
			elif not _panel.visible and not _u.release.is_empty():
				_queue_toast("The update hit a snag", "Nothing's lost. Have a look to try again.", "Have a look", _open_panel)
	_sync()


func _offer_when_in_game() -> void:
	var r: Dictionary = _u.release
	var size_text := ""
	if not r.asset.is_empty():
		size_text = " · %s" % UpdateFeed.human_size(int(r.asset.size))
	_queue_toast("A new Weed World is ready", "v%s%s" % [r.version, size_text], "Have a look", _open_panel)


func _queue_toast(title: String, sub: String, action: String, cb: Callable) -> void:
	_queued = [title, sub, action, cb]


func _install_from_toast() -> void:
	_hide_toast()
	_open_panel()
	_u.install()


func _on_card_requested() -> void:
	if _u.release.is_empty() or _u.state in [S.IDLE, S.UP_TO_DATE, S.CHECKING]:
		_manual_check()
	else:
		_open_panel()


func _manual_check() -> void:
	_watching_manual = true
	_show_toast("Looking for updates…", "Asking the forest for news", "", Callable(), 0.0, false, true)
	_u.check(true)


func _on_primary() -> void:
	match _u.state:
		S.AVAILABLE:
			if _u.can_self_install():
				_u.download()
			else:
				_u.open_release_page()
		S.READY, S.INSTALLING:
			_u.install()
		S.NEEDS_PERMISSION:
			_u.open_install_settings()
		S.FAILED:
			_u.retry()
		S.DOWNLOADING:
			_close_panel()


func _on_secondary() -> void:
	match _u.state:
		S.DOWNLOADING:
			_u.cancel()
		_:
			_close_panel()


func _closable() -> bool:
	return _u.state != S.APPLYING


func _open_panel() -> void:
	_hide_toast()
	_parked = false
	_sync()
	_panel.visible = true
	_backdrop.visible = true
	_panel_pop = 0.0
	var gi := get_node_or_null("/root/GameInput")
	if gi and not _locked:
		_prev_lock = gi.ui_locked
		gi.ui_locked = true
		_locked = true
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if gi and gi.method == gi.Method.GAMEPAD:
		_primary.grab_focus.call_deferred()
	_layout()


func _close_panel() -> void:
	if not _panel.visible or not _closable():
		return
	_panel.visible = false
	_backdrop.visible = false
	_parked = true
	var gi := get_node_or_null("/root/GameInput")
	if gi and _locked:
		gi.ui_locked = _prev_lock
		_locked = false
	_sync()


func _show_toast(title: String, sub: String, action: String, cb: Callable, hold := TOAST_HOLD, done := false, busy := false) -> void:
	_toast_title.text = title
	_toast_sub.text = sub
	_toast_sub.visible = sub != ""
	_toast_action.text = action
	_toast_action.visible = action != ""
	_toast_action_cb = cb
	_toast_icon.done = done
	_toast_icon.busy = busy
	_toast_icon.ring = -1.0
	_toast_want = true
	_toast_timer = hold
	_toast.visible = true
	_toast.reset_size()
	_layout()


func _hide_toast() -> void:
	_toast_want = false
	_toast_timer = 0.0


func _in_game() -> bool:
	var scene := get_tree().current_scene
	return scene != null and scene.process_mode != Node.PROCESS_MODE_DISABLED \
			and get_tree().get_first_node_in_group("player") != null


# ---------------------------------------------------------------------------
# Per frame

func _process(delta: float) -> void:
	if _in_game():
		_game_clock += delta
	# Offers wait until you have been in the forest a few seconds.
	if _game_clock > 5.0 and not _panel.visible:
		if _pending_welcome != "":
			var v := _pending_welcome.split("|")
			_pending_welcome = ""
			_show_toast("Welcome to v%s" % v[1], "Updated from v%s · fresh things in the forest" % v[0], "What's new", _open_notes, 9.0, true)
		elif not _queued.is_empty() and not _toast_want:
			var q := _queued
			_queued = []
			_show_toast(q[0], q[1], q[2], q[3])

	if _toast_want and _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_want = false
			if _u.state in [S.AVAILABLE, S.READY]:
				_parked = true
	_toast_shown = move_toward(_toast_shown, 1.0 if _toast_want else 0.0, delta * (3.2 if _toast_want else 4.0))
	_toast.visible = _toast_shown > 0.0
	if _toast.visible:
		var e := _ease_back(_toast_shown) if _toast_want else _toast_shown * _toast_shown
		_toast.position.y = lerpf(-_toast.size.y - 20.0, _top() + 10.0, e)
		_toast.modulate.a = clampf(_toast_shown * 1.6, 0.0, 1.0)

	var chip_on: bool = _parked and not _panel.visible and not _toast_want and _toast_shown <= 0.0 \
			and _u.state in [S.AVAILABLE, S.DOWNLOADING, S.VERIFYING, S.READY, S.NEEDS_PERMISSION, S.INSTALLING] \
			and _game_clock > 0.0
	if chip_on != _chip.visible:
		_chip.visible = chip_on
		_layout()
	if _chip.visible:
		var txt := "Update ready"
		match _u.state:
			S.DOWNLOADING:
				txt = "Downloading · %d%%" % int(_u.progress() * 100.0)
			S.VERIFYING:
				txt = "Checking download…"
			S.READY:
				txt = "Restart to update" if _u.plat == "windows" else "Tap to install"
			S.NEEDS_PERMISSION, S.INSTALLING:
				txt = "Finish installing"
		if _chip.text != txt:
			_chip.text = txt
			_layout()
		_chip_icon.ring = _u.progress() if _u.state == S.DOWNLOADING else -1.0
		_chip_icon.busy = _u.state == S.VERIFYING
		_chip_icon.done = _u.state == S.READY

	if _panel.visible:
		_layout()
		_panel_pop = move_toward(_panel_pop, 1.0, delta * 4.0)
		var k := _ease_back(_panel_pop)
		_panel.pivot_offset = _panel.size * 0.5
		_panel.scale = Vector2.ONE * lerpf(0.92, 1.0, k)
		_panel.modulate.a = clampf(_panel_pop * 2.0, 0.0, 1.0)
		_backdrop.modulate.a = clampf(_panel_pop * 2.5, 0.0, 1.0)
		if _u.state == S.DOWNLOADING:
			_update_progress()


func _input(event: InputEvent) -> void:
	if not _panel.visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("toggle_mouse"):
		if _closable():
			_close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") or event.is_action_pressed("controls_help") or event.is_action_pressed("toggle_debug"):
		get_viewport().set_input_as_handled()


func _update_progress() -> void:
	var p: float = _u.progress()
	if _vine:
		_vine.value = p
	_percent.text = "%d%%" % int(p * 100.0)
	_icon.ring = p
	var parts := PackedStringArray(["%s of %s" % [UpdateFeed.human_size(_u.downloaded), UpdateFeed.human_size(_u.total)]])
	if _u.speed > 1.0:
		parts.append("%s/s" % UpdateFeed.human_size(int(_u.speed)))
	var eta := UpdateFeed.human_eta(_u.eta())
	if eta != "":
		parts.append(eta)
	_status.text = "  ·  ".join(parts)


## Points every part of the card at the current state.
func _sync() -> void:
	if _panel == null:
		return
	var r: Dictionary = _u.release
	var ver := str(r.get("version", ""))
	var asset: Dictionary = r.get("asset", {})
	var size_text := UpdateFeed.human_size(int(asset.size)) if not asset.is_empty() else ""
	var android: bool = _u.plat == "android"
	_notes_frame.visible = false
	_guide.visible = false
	_progress_box.visible = false
	_message.visible = false
	_link.visible = not r.is_empty()
	_secondary.visible = true
	_primary.visible = true
	_primary.disabled = false
	_close.visible = _closable()
	_icon.ring = -1.0
	_icon.busy = false
	_icon.done = false
	_percent.text = ""
	match _u.state:
		S.AVAILABLE, S.CHECKING:
			_title.text = "A new Weed World is ready"
			_sub.text = "v%s  →  v%s%s" % [_u.current_version, ver, ("  ·  %s download" % size_text) if size_text != "" else ""]
			_notes_frame.visible = true
			_set_notes(str(r.get("notes", "")))
			_secondary.text = "Later"
			if _u.can_self_install():
				_primary.text = "Update now"
			else:
				_primary.text = "Open download page"
				_link.visible = false
		S.DOWNLOADING:
			_title.text = "Fetching v%s" % ver
			_sub.text = "Keep playing if you like, it downloads in the background."
			_notes_frame.visible = true
			_progress_box.visible = true
			_fresh_vine()
			_update_progress()
			_secondary.text = "Cancel"
			_primary.text = "Keep playing"
			_link.visible = false
		S.VERIFYING:
			_title.text = "Checking the download"
			_sub.text = "Making sure every byte of v%s arrived safe and sound." % ver
			_notes_frame.visible = true
			_progress_box.visible = true
			_fresh_vine(1.0)
			_status.text = "Checking…"
			_icon.busy = true
			_secondary.text = "Close"
			_primary.visible = false
			_link.visible = false
		S.READY:
			_icon.done = true
			if android:
				_title.text = "Ready to install"
				_sub.text = "v%s is downloaded and checked." % ver
				_message.text = "Android opens its installer next: tap Update there. Your Keling and everything you've done stay just as they are."
				_primary.text = "Install"
			else:
				_title.text = "Ready to update"
				_sub.text = "v%s is downloaded and checked." % ver
				_message.text = "Weed World closes for a moment, swaps in the new version and opens again by itself."
				_primary.text = "Restart and update"
			_message.visible = true
			_secondary.text = "Later"
		S.NEEDS_PERMISSION:
			_title.text = "One quick thing"
			_sub.text = "Android asks once before Weed World can install its own updates."
			_guide.visible = true
			_primary.text = "Open settings"
			_secondary.text = "Later"
		S.INSTALLING:
			_icon.done = true
			_title.text = "Finish in the installer"
			_sub.text = "Tap Update on Android's screen to get v%s." % ver
			_message.text = "Didn't see it, or tapped Cancel? Open it again below. If Android says the app wasn't installed, use the download page to reinstall."
			_message.visible = true
			_primary.text = "Open installer again"
			_secondary.text = "Close"
		S.APPLYING:
			_title.text = "Updating…"
			_sub.text = "See you in a second on v%s." % ver
			_progress_box.visible = true
			_fresh_vine(1.0)
			_status.text = "Swapping in the new version"
			_icon.busy = true
			_primary.visible = false
			_secondary.visible = false
			_link.visible = false
		S.FAILED:
			_title.text = "That didn't work"
			_sub.text = "v%s is still waiting for you." % ver if ver != "" else "No harm done."
			_message.text = _u.error_text
			_message.visible = true
			_primary.text = "Try again"
			_secondary.text = "Close"
		_:
			_title.text = "Weed World is up to date"
			_sub.text = "You're on v%s." % _u.current_version
			_primary.visible = false
			_secondary.text = "Close"
	_layout.call_deferred()


func _set_notes(md: String) -> void:
	if md.strip_edges() == "":
		_notes.text = "[color=#cfd8cc]Fresh fixes and polish for the forest.[/color]"
		return
	_notes.text = "[color=#b8e588][font_size=15]WHAT'S NEW SINCE YOUR VERSION[/font_size][/color]\n" \
			+ HudTheme.notes_bbcode(md.replace("[", "[lb]"))


## A new vine for each download, so it grows from the start (the bar only
## ever grows).
func _fresh_vine(value := 0.0) -> void:
	if _vine and (value >= 1.0 or _vine.value <= 0.0001):
		_vine.value = maxf(_vine.value, value)
		return
	if _vine:
		_vine.queue_free()
	_vine = VineProgress.new()
	_vine.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vine.offset_left = 10
	_vine.offset_right = -10
	_vine.value = value
	_vine_holder.add_child(_vine)


func _open_notes() -> void:
	_hide_toast()
	var hud := get_tree().get_first_node_in_group("hud")
	if hud and hud.has_method("open_notes"):
		hud.open_notes()


# ---------------------------------------------------------------------------
# Layout

func _top() -> float:
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.y <= 0 or safe.size.y <= 0 or not OS.has_feature("mobile"):
		return 0.0
	return safe.position.y * _root.size.y / float(win.y)


func _layout() -> void:
	var s := _root.size
	_toast.reset_size()
	_toast.size.x = minf(_toast.size.x, s.x - 32.0)
	_toast.position.x = (s.x - _toast.size.x) * 0.5
	_chip.reset_size()
	_chip.position = Vector2((s.x - _chip.size.x) * 0.5, _top() + 14.0)
	var w := minf(700.0, s.x - 32.0)
	var h := minf(640.0, s.y - 32.0)
	if not _notes_frame.visible:
		_panel.reset_size()
		_panel.size.x = w
		h = minf(_panel.get_combined_minimum_size().y, h)
	_panel.size = Vector2(w, h)
	_panel.position = (s - _panel.size) * 0.5


static func _ease_back(x: float) -> float:
	var c := 1.6
	x = clampf(x, 0.0, 1.0) - 1.0
	return 1.0 + (c + 1.0) * x * x * x + c * x * x


static func _is_tap(e: InputEvent) -> bool:
	# Touches arrive as emulated mouse clicks too, so only clicks count.
	return e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT
