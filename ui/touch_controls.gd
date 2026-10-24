class_name TouchControls
extends Control
## Multi-touch controls drawn in one Control:
##  - floating analog joystick on the left (push past the ring to sprint)
##  - jump, grab, sprint toggle and emote buttons on the right
##  - drag anywhere else on the right to orbit the camera, pinch to zoom
## Movement and jump are fed into the regular input actions, so the
## controller does not care where input comes from.

const EMOTES := [[&"Dance", "Dance"], [&"Cheer", "Cheer"], [&"SitDown", "Sit"], [&"Nod", "Nod"]]

@export var joystick_radius := 105.0
@export var knob_radius := 44.0
@export var sprint_push := 1.22  ## push this far past the ring to auto-sprint

var _font: Font
var _joy_finger := -1
var _joy_base := Vector2.ZERO
var _joy_knob := Vector2.ZERO
var _joy_vec := Vector2.ZERO
var _joy_alpha := 0.0
var _push_sprint := false
var _jump_finger := -1
var _button_fingers := {}  # finger -> button id
var _look_fingers := {}  # finger -> last position
var _pinch_dist := 0.0
var _emote_open := false
var _emote_anim := 0.0
var _press_flash := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = HudTheme.title_font(600)


func _notification(what: int) -> void:
	# Hidden mid-gesture (the map opened): let go of everything held.
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_joy_finger = -1
		_joy_vec = Vector2.ZERO
		_push_sprint = false
		_apply_move()
		for f in _button_fingers.keys():
			_release_button(f)
		_look_fingers.clear()
		_emote_open = false


## HUD widgets (minimap, buttons, panels) own the touches that land on them.
func _blocked(p: Vector2) -> bool:
	for n in get_tree().get_nodes_in_group("touch_blockers"):
		var c := n as Control
		if c and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false


func _buttons() -> Dictionary:
	var s := size
	var jump_c := Vector2(s.x - 150.0, s.y - 150.0)
	var b := {
		"jump": [jump_c, 74.0],
		"sprint": [jump_c + Vector2(-150.0, 40.0), 50.0],
		"emote": [jump_c + Vector2(20.0, -150.0), 40.0],
		"grab": [jump_c + Vector2(-125.0, -115.0), 48.0],
	}
	if _emote_open:
		for i in EMOTES.size():
			var a := deg_to_rad(-180.0 + i * 38.0)
			b["emote_%d" % i] = [b["emote"][0] + Vector2(cos(a), sin(a)) * 115.0 * _emote_anim, 36.0]
	return b


func _hit_button(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in _buttons():
		var c: Vector2 = _buttons()[id][0]
		var r: float = _buttons()[id][1] * 1.25
		var d := p.distance_to(c)
		if d < r and d < best_d:
			best = id
			best_d = d
	return best


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var idx: int = event.index
		if event.pressed and (event.position.y < 70.0 or _blocked(event.position)):
			return  # leave the top strip and the HUD widgets alone
		if event.pressed:
			var hit := _hit_button(event.position)
			if hit != "":
				_press_button(idx, hit)
			elif event.position.x < size.x * 0.42 and _joy_finger == -1:
				_joy_finger = idx
				_joy_base = event.position
				_joy_knob = event.position
				_update_joystick()
			else:
				_look_fingers[idx] = event.position
				_pinch_dist = 0.0
				if _emote_open:
					_emote_open = false
			get_viewport().set_input_as_handled()
		else:
			if idx == _joy_finger:
				_joy_finger = -1
				_joy_vec = Vector2.ZERO
				_push_sprint = false
				_apply_move()
			if _button_fingers.has(idx):
				_release_button(idx)
			_look_fingers.erase(idx)
			_pinch_dist = 0.0
	elif event is InputEventScreenDrag:
		var idx: int = event.index
		if idx == _joy_finger:
			_joy_knob = event.position
			_update_joystick()
			get_viewport().set_input_as_handled()
		elif _look_fingers.has(idx):
			if _look_fingers.size() >= 2:
				var keys := _look_fingers.keys()
				_look_fingers[idx] = event.position
				var d: float = (_look_fingers[keys[0]] as Vector2).distance_to(_look_fingers[keys[1]])
				if _pinch_dist > 0.0:
					_camera_call("zoom_by", [clampf(_pinch_dist / maxf(d, 1.0), 0.9, 1.1)])
				_pinch_dist = d
			else:
				_look_fingers[idx] = event.position
				_camera_call("add_touch_look", [event.relative])
			get_viewport().set_input_as_handled()


func _press_button(finger: int, id: String) -> void:
	_button_fingers[finger] = id
	_press_flash[id] = 1.0
	match id:
		"jump":
			Input.action_press("jump")
			Input.vibrate_handheld(18)
		"sprint":
			GameInput.sprint_toggled = not GameInput.sprint_toggled
			Input.vibrate_handheld(10)
		"emote":
			_emote_open = not _emote_open
		"grab":
			var player := get_tree().get_first_node_in_group("local_player")
			if player and player.has_method("try_grab"):
				player.try_grab()
			Input.vibrate_handheld(10)
		_:
			if id.begins_with("emote_"):
				var i := int(id.get_slice("_", 1))
				var player := get_tree().get_first_node_in_group("local_player")
				if player and player.has_method("play_emote"):
					player.play_emote(EMOTES[i][0])
				_emote_open = false
				Input.vibrate_handheld(12)


func _release_button(finger: int) -> void:
	var id: String = _button_fingers[finger]
	_button_fingers.erase(finger)
	if id == "jump":
		Input.action_release("jump")


func _update_joystick() -> void:
	var offset := _joy_knob - _joy_base
	var dist := offset.length()
	# The base follows the thumb if it drifts far, so the stick never "runs out".
	var follow_limit := joystick_radius * 1.6
	if dist > follow_limit:
		_joy_base += offset.normalized() * (dist - follow_limit)
		offset = _joy_knob - _joy_base
		dist = follow_limit
	_push_sprint = dist > joystick_radius * sprint_push
	_joy_vec = offset / joystick_radius
	if _joy_vec.length() > 1.0:
		_joy_vec = _joy_vec.normalized()
	_apply_move()


func _apply_move() -> void:
	var v := _joy_vec
	_set_axis("move_right", "move_left", v.x)
	_set_axis("move_back", "move_forward", v.y)
	GameInput.push_sprint = _push_sprint


func _set_axis(pos: StringName, neg: StringName, value: float) -> void:
	if value > 0.0:
		Input.action_press(pos, value)
		Input.action_release(neg)
	elif value < 0.0:
		Input.action_press(neg, -value)
		Input.action_release(pos)
	else:
		Input.action_release(pos)
		Input.action_release(neg)


func _camera_call(method: StringName, args: Array) -> void:
	var cam := get_tree().get_first_node_in_group("orbit_camera")
	if cam:
		cam.callv(method, args)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_timed(delta)
	PerfMeter.add(&"touch controls", Time.get_ticks_usec() - t0)


func _process_timed(delta: float) -> void:
	if not visible:
		return
	_joy_alpha = lerpf(_joy_alpha, 1.0 if _joy_finger != -1 else 0.0, 1.0 - exp(-14.0 * delta))
	_emote_anim = lerpf(_emote_anim, 1.0 if _emote_open else 0.0, 1.0 - exp(-16.0 * delta))
	for k in _press_flash.keys():
		_press_flash[k] = maxf(_press_flash[k] - delta * 4.0, 0.0)
	queue_redraw()


func _draw() -> void:
	var white := Color(1, 1, 1)
	# Joystick: idle hint in the corner, full stick where the thumb lands.
	var hint_pos := Vector2(190.0, size.y - 190.0)
	var base := _joy_base.lerp(hint_pos, 1.0 - _joy_alpha) if _joy_finger != -1 or _joy_alpha > 0.01 else hint_pos
	var a := lerpf(0.35, 1.0, _joy_alpha)
	draw_circle(base, joystick_radius, Color(0.05, 0.1, 0.05, 0.22 * a))
	draw_arc(base, joystick_radius, 0, TAU, 64, Color(1, 1, 1, 0.35 * a), 3.0, true)
	if _push_sprint:
		draw_arc(base, joystick_radius * sprint_push, 0, TAU, 64, Color(0.75, 1.0, 0.5, 0.7), 4.0, true)
	else:
		draw_arc(base, joystick_radius * sprint_push, 0, TAU, 64, Color(1, 1, 1, 0.08 * a), 2.0, true)
	var knob := base + _joy_vec * joystick_radius if _joy_finger != -1 else base
	draw_circle(knob + Vector2(0, 4), knob_radius, Color(0, 0, 0, 0.18 * a))
	draw_circle(knob, knob_radius, Color(1, 1, 1, 0.55 * a))
	draw_arc(knob, knob_radius, 0, TAU, 48, Color(1, 1, 1, 0.8 * a), 2.0, true)

	var btns := _buttons()
	for id in btns:
		var c: Vector2 = btns[id][0]
		var r: float = btns[id][1]
		var pressed: bool = _button_fingers.values().has(id)
		var active: bool = (id == "sprint" and (GameInput.sprint_toggled or _push_sprint)) or (id == "emote" and _emote_open)
		var flash: float = _press_flash.get(id, 0.0)
		var fill := Color(HudTheme.GLASS, 0.34)
		if active:
			fill = Color(HudTheme.MOSS.lightened(0.15), 0.62)
		if pressed:
			fill = fill.lightened(0.25)
		var rr := r * (1.0 - 0.06 * flash)
		draw_circle(c + Vector2(0, 4), rr, Color(0, 0, 0, 0.15))
		draw_circle(c, rr, fill)
		draw_arc(c, rr, 0, TAU, 64, Color(HudTheme.CREAM, 0.5 + 0.4 * flash), 3.0, true)
		_draw_icon(id, c, rr, white)


func _draw_icon(id: String, c: Vector2, r: float, col: Color) -> void:
	var w := maxf(r * 0.09, 3.0)
	match id:
		"jump":
			var s := r * 0.38
			draw_polyline(PackedVector2Array([c + Vector2(-s, s * 0.35), c + Vector2(0, -s * 0.65), c + Vector2(s, s * 0.35)]), col, w * 1.2, true)
			draw_line(c + Vector2(-s * 0.9, s * 0.95), c + Vector2(s * 0.9, s * 0.95), Color(col, 0.7), w, true)
		"sprint":
			var s := r * 0.32
			for k in 2:
				var o := Vector2(-s * 0.55 + k * s * 0.85, 0)
				draw_polyline(PackedVector2Array([c + o + Vector2(-s * 0.4, -s * 0.8), c + o + Vector2(s * 0.4, 0), c + o + Vector2(-s * 0.4, s * 0.8)]), col, w, true)
		"grab":
			# An open hand: palm and four fingers.
			var s := r * 0.4
			draw_circle(c + Vector2(0, s * 0.35), s * 0.42, col)
			for k in 4:
				var fx := (k - 1.5) * s * 0.3
				draw_line(c + Vector2(fx, s * 0.1), c + Vector2(fx * 1.25, -s * 0.75 + absf(k - 1.5) * s * 0.18), col, w * 1.3, true)
			draw_line(c + Vector2(-s * 0.35, s * 0.4), c + Vector2(-s * 0.85, s * 0.0), col, w * 1.3, true)
		"emote":
			var s := r * 0.42
			draw_arc(c, s, 0, TAU, 32, col, w * 0.8, true)
			draw_circle(c + Vector2(-s * 0.35, -s * 0.2), w * 0.7, col)
			draw_circle(c + Vector2(s * 0.35, -s * 0.2), w * 0.7, col)
			draw_arc(c + Vector2(0, s * 0.05), s * 0.5, deg_to_rad(20), deg_to_rad(160), 16, col, w * 0.8, true)
		_:
			if id.begins_with("emote_"):
				var label: String = EMOTES[int(id.get_slice("_", 1))][1]
				var fs := 20
				var tw := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(_font, c + Vector2(-tw * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col, _emote_anim))
