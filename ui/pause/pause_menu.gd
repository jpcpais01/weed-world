class_name PauseMenu
extends Control
## The pause menu: Esc, gamepad Start, the pause button in the corner or
## Android's back gesture. The forest blurs and quietens behind a card with
## Resume, Settings, Play together, What's new and Quit.
##
## Playing alone, the world really stops (the tree pauses; this menu and the
## soundscape keep running). In co-op nothing freezes: friends keep playing,
## your Keling just stands still and they see "taking a break" under your
## name. Alt-tabbing away or the phone switching apps opens the menu too.

signal opened
signal closed

const SIDE_WIDTH := 400.0

var is_open := false
## Asks the HUD whether another panel (map, co-op, notes) is open, which Esc
## should close first.
var blocked := func() -> bool: return false
var hud: Node

var _net: Node
var _settings_node: Node
var _blur: ColorRect
var _blur_mat: ShaderMaterial
var _side: PanelContainer
var _title: Label
var _sub: Label
var _foot: Label
var _art: Control
var _resume: MenuRow
var _settings_btn: MenuRow
var _coop_btn: MenuRow
var _char_btn: MenuRow
var _notes_btn: MenuRow
var _quit: MenuRow
var _settings: SettingsPanel
var _confirm: PanelContainer
var _confirm_body: Label
var _confirm_stay: MenuRow
var _confirm_backdrop: ColorRect
var _anim := 0.0
var _settings_t := 0.0
var _confirm_t := 0.0
var _settings_open := false
var _confirm_open := false
var _t := 0.0
var _prev_lock := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE
var _froze_tree := false
var _sent_away := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_net = get_node_or_null("/root/Net")
	_settings_node = get_node_or_null("/root/Settings")
	_build()
	resized.connect(_layout)
	if _net:
		_net.status_changed.connect(_sync)
		_net.roster_changed.connect(_sync)
	UiSound.warm()


# ---------------------------------------------------------------------------
# Building

func _build() -> void:
	_blur = ColorRect.new()
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = preload("res://ui/pause/pause_blur.gdshader")
	_blur.material = _blur_mat
	_blur.mouse_filter = Control.MOUSE_FILTER_STOP
	_blur.add_to_group("touch_blockers")
	_blur.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and not _settings_open:
			if not _side.get_global_rect().has_point(e.global_position):
				close())
	add_child(_blur)

	_side = PanelContainer.new()
	_side.add_theme_stylebox_override("panel", HudTheme.glass(30, 0.86, 24.0))
	_side.add_to_group("touch_blockers")
	_side.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_side)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_side.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	_art = Control.new()
	_art.custom_minimum_size = Vector2(64, 64)
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.draw.connect(_draw_art)
	head.add_child(_art)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(titles)
	_title = Label.new()
	HudTheme.style_label(_title, 40, HudTheme.CREAM, HudTheme.title_font(600))
	titles.add_child(_title)
	_sub = Label.new()
	HudTheme.style_label(_sub, 15, Color(HudTheme.CREAM, 0.65), HudTheme.body_font(700), false)
	titles.add_child(_sub)

	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	box.add_child(gap)

	_resume = _menu_button(box, "Resume", "play", HudTheme.LEAF)
	_resume.activated.connect(close)
	_settings_btn = _menu_button(box, "Settings", "gear", HudTheme.GOLD)
	_settings_btn.activated.connect(open_settings)
	_coop_btn = _menu_button(box, "Play together", "friends", HudTheme.WATER)
	_coop_btn.activated.connect(_open_coop)
	_char_btn = _menu_button(box, "Choose your Keling", "swap", HudTheme.BLOSSOM)
	_char_btn.activated.connect(_open_picker)
	_notes_btn = _menu_button(box, "What's new", "notes", HudTheme.LILAC)
	_notes_btn.activated.connect(_open_notes)
	_quit = _menu_button(box, "Quit to desktop" if not OS.has_feature("mobile") else "Quit game", "door", HudTheme.BLOSSOM)
	_quit.danger = true
	_quit.activated.connect(_ask_quit)

	_foot = Label.new()
	HudTheme.style_label(_foot, 14, Color(HudTheme.CREAM, 0.5), HudTheme.body_font(700), false)
	_foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_foot)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.close_requested.connect(close_settings)
	add_child(_settings)

	_build_confirm()
	_sync()


func _menu_button(box: Container, text: String, glyph: String, tint: Color) -> MenuRow:
	var b := MenuRow.make_button(text, glyph, tint)
	box.add_child(b)
	return b


func _build_confirm() -> void:
	_confirm_backdrop = ColorRect.new()
	_confirm_backdrop.color = Color(0.01, 0.03, 0.02, 0.5)
	_confirm_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_confirm_backdrop.visible = false
	_confirm_backdrop.add_to_group("touch_blockers")
	_confirm_backdrop.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			_close_confirm())
	add_child(_confirm_backdrop)
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel", HudTheme.glass(28, 0.94, 26.0))
	_confirm.visible = false
	_confirm.add_to_group("touch_blockers")
	add_child(_confirm)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_confirm.add_child(box)
	var t := Label.new()
	t.text = "Leave the forest?"
	HudTheme.style_label(t, 30, HudTheme.CREAM, HudTheme.title_font(600))
	box.add_child(t)
	_confirm_body = Label.new()
	HudTheme.style_label(_confirm_body, 17, Color(HudTheme.CREAM, 0.75), HudTheme.body_font(650), false)
	_confirm_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_body.custom_minimum_size.x = 380
	box.add_child(_confirm_body)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	box.add_child(gap)
	_confirm_stay = MenuRow.make_button("Stay a little longer", "play", HudTheme.LEAF)
	_confirm_stay.activated.connect(_close_confirm)
	box.add_child(_confirm_stay)
	var go := MenuRow.make_button("Quit", "door", HudTheme.BLOSSOM)
	go.danger = true
	go.activated.connect(_quit_now)
	box.add_child(go)


## A crescent moon, with a sleepy "z" and twinkling stars (paused), or two
## little leaves (in co-op, where nothing sleeps).
func _draw_art() -> void:
	var c := Vector2(32, 34)
	var online: bool = _net != null and _net.online
	_art.draw_circle(c + Vector2(0, 3), 26.0, Color(0, 0, 0, 0.22))
	_art.draw_circle(c, 26.0, Color(HudTheme.GLASS, 0.9))
	_art.draw_arc(c, 26.0, 0.0, TAU, 40, Color(HudTheme.CREAM, 0.25), 2.0, true)
	if online:
		MapIcons.leaf(_art, c + Vector2(-4, 12), Vector2(-0.5, -0.86), 22.0 + sin(_t * 2.0), 11.0, HudTheme.LEAF)
		MapIcons.leaf(_art, c + Vector2(-2, 12), Vector2(0.55, -0.8), 19.0 + cos(_t * 2.0), 10.0, HudTheme.WATER)
		return
	# Crescent: a cream disc with a glass bite.
	_art.draw_circle(c + Vector2(-2, 1), 14.0, HudTheme.GOLD)
	_art.draw_circle(c + Vector2(5, -4), 12.5, Color(HudTheme.GLASS, 1.0).lerp(Color(0.1, 0.16, 0.12), 0.5))
	for k in 3:
		var p: Vector2 = c + [Vector2(13, 10), Vector2(-14, -13), Vector2(15, -15)][k]
		var tw := 0.5 + 0.5 * sin(_t * 2.6 + k * 2.1)
		var r := 1.6 + 1.6 * tw
		_art.draw_line(p - Vector2(r, 0), p + Vector2(r, 0), Color(HudTheme.CREAM, 0.5 + 0.5 * tw), 1.6, true)
		_art.draw_line(p - Vector2(0, r), p + Vector2(0, r), Color(HudTheme.CREAM, 0.5 + 0.5 * tw), 1.6, true)
	var zf := HudTheme.title_font(650)
	var zt := fmod(_t * 0.5, 1.0)
	_art.draw_string(zf, c + Vector2(8 + zt * 8, -10 - zt * 12), "z", HORIZONTAL_ALIGNMENT_LEFT, -1, int(11 + zt * 6),
			Color(HudTheme.CREAM, sin(zt * PI)))


func _sync() -> void:
	var online: bool = _net != null and _net.online
	_title.text = "Menu" if online else "Paused"
	if online:
		var n: int = _net.players().size()
		_sub.text = "Your friends keep exploring" if n > 1 else "Your forest stays open"
		_coop_btn.subtitle = "%d here" % n
		_foot.text = "v%s  ·  forest code %s" % [ProjectSettings.get_setting("application/config/version", "0.1"), _net.pretty_code(_net.room_code)]
	else:
		_sub.text = "The forest waits for you"
		_coop_btn.subtitle = ""
		_foot.text = "Weed World v%s" % ProjectSettings.get_setting("application/config/version", "0.1")
	if is_open:
		_apply_freeze()
	_coop_btn.queue_redraw()
	_art.queue_redraw()


# ---------------------------------------------------------------------------
# Opening and closing

func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	if is_open:
		return
	is_open = true
	visible = true
	_prev_lock = GameInput.ui_locked
	GameInput.ui_locked = true
	_prev_mouse = Input.mouse_mode
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_settings_open = false
	_settings.visible = false
	_settings_t = 0.0
	_close_confirm(true)
	_sync()
	_apply_freeze()
	if _settings_node:
		_settings_node.set_muffled(true)
	UiSound.play("open")
	_layout()
	_layout.call_deferred()
	if GameInput.method != GameInput.Method.TOUCH:
		MenuRow.quiet_focus(_resume)
	opened.emit()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_settings_open = false
	_close_confirm(true)
	_settings.visible = false
	GameInput.ui_locked = _prev_lock
	_unfreeze()
	if _settings_node:
		_settings_node.set_muffled(false)
	get_viewport().gui_release_focus()
	UiSound.play("close")
	if _prev_mouse == Input.MOUSE_MODE_CAPTURED and GameInput.method == GameInput.Method.KEYBOARD_MOUSE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


## Solo: stop the world. Online: never freeze (friends play on); tell them
## we're away instead.
func _apply_freeze() -> void:
	var online: bool = _net != null and _net.online
	var tree := get_tree()
	if online:
		if _froze_tree:
			tree.paused = false
			_froze_tree = false
		_send_away(true)
	else:
		_send_away(false)
		if not tree.paused:
			tree.paused = true
			_froze_tree = true


func _unfreeze() -> void:
	if _froze_tree:
		get_tree().paused = false
		_froze_tree = false
	_send_away(false)


func _send_away(away: bool) -> void:
	if away == _sent_away:
		return
	var me := get_tree().get_first_node_in_group("local_player")
	if me and me.has_signal("net_event"):
		me.emit_signal("net_event", &"away", [away])
		_sent_away = away
	elif not away:
		_sent_away = false


func open_settings() -> void:
	_settings_open = true
	_settings.visible = true
	_settings.show_tab(0 if _settings_t <= 0.0 else _settings._tab)
	_layout()


func close_settings() -> void:
	if not _settings_open:
		return
	_settings_open = false
	UiSound.play("back")
	if GameInput.method != GameInput.Method.TOUCH:
		MenuRow.quiet_focus(_settings_btn)
	else:
		get_viewport().gui_release_focus()


func _open_coop() -> void:
	close()
	if hud and hud.has_method("open_coop"):
		hud.open_coop()


func _open_picker() -> void:
	close()
	if hud and hud.has_method("open_picker"):
		hud.open_picker()


func _open_notes() -> void:
	close()
	if hud and hud.has_method("open_notes"):
		hud.open_notes()


func _ask_quit() -> void:
	var online: bool = _net != null and _net.online
	if online and _net.is_host():
		var n: int = _net.players().size() - 1
		_confirm_body.text = "Your forest closes and %s back home." % ("your friend heads" if n == 1 else "your friends head") \
				if n > 0 else "Your forest closes to visitors. Everything you found stays with you."
	elif online:
		_confirm_body.text = "You'll leave your friends' forest. They can keep exploring without you."
	else:
		_confirm_body.text = "Your pouch and joints are saved. The forest will be right here when you come back."
	_confirm_open = true
	_confirm.visible = true
	_confirm_backdrop.visible = true
	_confirm_t = 0.0
	_layout()
	if GameInput.method != GameInput.Method.TOUCH:
		MenuRow.quiet_focus(_confirm_stay)


func _close_confirm(silent := false) -> void:
	if not _confirm_open:
		return
	_confirm_open = false
	_confirm.visible = false
	_confirm_backdrop.visible = false
	if not silent:
		UiSound.play("back")
		if GameInput.method != GameInput.Method.TOUCH:
			MenuRow.quiet_focus(_quit)


func _quit_now() -> void:
	if _settings_node:
		_settings_node.save()
	if _net and _net.online:
		_net.leave()
	# Let the goodbye reach the relay before the window goes.
	get_tree().create_timer(0.25, true).timeout.connect(get_tree().quit)


# ---------------------------------------------------------------------------
# Input

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("pause") and not event.is_echo() and not blocked.call():
			open()
			get_viewport().set_input_as_handled()
		return
	if _settings_open and _settings.is_listening():
		return
	if _settings_open and _settings.handle_tab_keys(event):
		get_viewport().set_input_as_handled()
		return
	var back: bool = event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if back and not event.is_echo():
		go_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		# Nothing else reaches the game while the menu is up.
		if not (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F11):
			get_viewport().set_input_as_handled()
		if get_viewport().gui_get_focus_owner() == null and (event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up")):
			MenuRow.quiet_focus(_resume if not _settings_open else _settings_btn)
			if _settings_open:
				_settings.focus_first()


## Back one step: the quit question, then settings, then the menu itself.
func go_back() -> void:
	if _confirm_open:
		_close_confirm()
	elif _settings_open:
		close_settings()
	else:
		close()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if is_open:
				go_back()
			elif not blocked.call():
				open()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			# Stepping away (alt-tab, a phone call) pauses the game.
			if not is_open and is_inside_tree() and not blocked.call() and DisplayServer.get_name() != "headless" \
					and not OS.has_feature("editor"):
				open()


# ---------------------------------------------------------------------------
# Layout and motion

func _layout() -> void:
	if not is_inside_tree():
		return
	var s := size
	var inset: Vector4 = hud.call("safe_insets") if hud and hud.has_method("safe_insets") else Vector4.ZERO
	var left := 40.0 + inset.x
	var w := minf(SIDE_WIDTH, s.x - left - 24.0)
	_side.custom_minimum_size.x = w
	_side.reset_size()
	_side.size.x = w
	var narrow := s.x < 1240.0
	_side.position = Vector2(left, maxf((s.y - _side.size.y) * 0.5, 16.0))
	var sx := left + w + 28.0 if not narrow else left
	var sw := minf(940.0, s.x - sx - 32.0 - inset.z)
	var sh := s.y - 64.0 - inset.y - inset.w
	_settings.size = Vector2(sw, sh)
	_settings.position = Vector2(sx, 32.0 + inset.y)
	_confirm.reset_size()
	_confirm.position = (s - _confirm.size) * 0.5
	_confirm.pivot_offset = _confirm.size * 0.5
	_settings.pivot_offset = Vector2(0, sh * 0.5)


func _process(delta: float) -> void:
	_t += delta
	_anim = move_toward(_anim, 1.0 if is_open else 0.0, delta * (4.0 if is_open else 5.5))
	if not is_open and _anim <= 0.0:
		visible = false
		_blur_mat.set_shader_parameter("amount", 0.0)
		return
	var e := ease(_anim, -2.2)
	_blur_mat.set_shader_parameter("amount", e)
	var narrow := size.x < 1240.0
	_settings_t = move_toward(_settings_t, 1.0 if _settings_open else 0.0, delta * 5.0)
	var se := ease(_settings_t, -2.2)
	var side_hide := se if narrow else 0.0
	_side.modulate.a = e * (1.0 - side_hide) * (1.0 - 0.35 * se * (0.0 if narrow else 1.0))
	_side.position.x = 40.0 + _inset_left() - 60.0 * (1.0 - e) - 40.0 * side_hide
	_side.visible = _side.modulate.a > 0.01
	_settings.visible = _settings_t > 0.0
	_settings.modulate.a = se * e
	_settings.scale = Vector2.ONE * lerpf(0.96, 1.0, se)
	_settings.position.x = (40.0 + _inset_left() + _side.size.x + 28.0 if not narrow else 40.0 + _inset_left()) + 50.0 * (1.0 - se)
	if _confirm_open:
		_confirm_t = move_toward(_confirm_t, 1.0, delta * 6.0)
		var ce := ease(_confirm_t, -2.4)
		_confirm.scale = Vector2.ONE * lerpf(0.92, 1.0, ce)
		_confirm.modulate.a = ce
		_confirm_backdrop.modulate.a = ce
	_art.queue_redraw()


func _inset_left() -> float:
	var inset: Vector4 = hud.call("safe_insets") if hud and hud.has_method("safe_insets") else Vector4.ZERO
	return inset.x
