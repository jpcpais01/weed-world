extends Node
## Registers the game's input actions (keyboard, mouse and gamepad) at startup
## and tracks which input method the player used last, so the UI can show
## touch controls or keyboard hints accordingly.

signal input_method_changed(method: int)

enum Method { KEYBOARD_MOUSE, GAMEPAD, TOUCH }

const DEADZONE := 0.18

var method: int = Method.KEYBOARD_MOUSE:
	set(value):
		if value != method:
			method = value
			input_method_changed.emit(method)

## Toggled by the on-screen sprint button and by the walk toggle key.
var sprint_toggled := false
var walk_toggled := false
## Set while the touch joystick is pushed past its ring.
var push_sprint := false
## Set while a full-screen UI (the world map, the pause menu) owns the
## controls: the Keling stands still and ignores jump, grab and emotes.
var ui_locked := false


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add("move_forward", [KEY_W, KEY_UP], [], [[JOY_AXIS_LEFT_Y, -1.0]])
	_add("move_back", [KEY_S, KEY_DOWN], [], [[JOY_AXIS_LEFT_Y, 1.0]])
	_add("move_left", [KEY_A, KEY_LEFT], [], [[JOY_AXIS_LEFT_X, -1.0]])
	_add("move_right", [KEY_D, KEY_RIGHT], [], [[JOY_AXIS_LEFT_X, 1.0]])
	_add("look_left", [], [], [[JOY_AXIS_RIGHT_X, -1.0]])
	_add("look_right", [], [], [[JOY_AXIS_RIGHT_X, 1.0]])
	_add("look_up", [], [], [[JOY_AXIS_RIGHT_Y, -1.0]])
	_add("look_down", [], [], [[JOY_AXIS_RIGHT_Y, 1.0]])
	_add("jump", [KEY_SPACE], [JOY_BUTTON_A], [])
	_add("grab", [KEY_E, KEY_F], [JOY_BUTTON_X], [])
	_add("weed", [KEY_R], [], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	_add("weed_cycle", [KEY_Q], [], [])
	_add("dragon", [KEY_G], [], [])
	_add("gift", [KEY_V], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_add("sprint", [KEY_SHIFT], [JOY_BUTTON_LEFT_STICK, JOY_BUTTON_B], [[JOY_AXIS_TRIGGER_LEFT, 1.0]])
	_add("walk_toggle", [KEY_C, KEY_CTRL], [JOY_BUTTON_RIGHT_STICK], [])
	_add("emote_dance", [KEY_1], [JOY_BUTTON_DPAD_UP], [])
	_add("emote_cheer", [KEY_2], [JOY_BUTTON_DPAD_RIGHT], [])
	_add("emote_sit", [KEY_3], [JOY_BUTTON_DPAD_DOWN], [])
	_add("emote_nod", [KEY_4], [JOY_BUTTON_DPAD_LEFT], [])
	_add("zoom_in", [], [JOY_BUTTON_RIGHT_SHOULDER], [])
	_add("zoom_out", [], [JOY_BUTTON_LEFT_SHOULDER], [])
	_add("map", [KEY_M, KEY_TAB], [JOY_BUTTON_Y], [])
	_add("controls_help", [KEY_H, KEY_F1], [], [])
	_add("coop", [KEY_P], [], [])
	_add("character", [KEY_T], [], [])
	_add("toggle_debug", [KEY_0, KEY_KP_0, KEY_F3], [JOY_BUTTON_BACK], [])
	# Esc / Start: closes whatever panel is open, otherwise opens the pause
	# menu. Panels listen for "toggle_mouse", the menu for "pause".
	_add("toggle_mouse", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_add("pause", [KEY_ESCAPE], [JOY_BUTTON_START], [])
	_add("fullscreen", [KEY_F11], [], [])
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		method = Method.TOUCH


func _add(action: StringName, keys: Array, buttons: Array, axes: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, DEADZONE)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		method = Method.TOUCH
	elif event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.4):
		method = Method.GAMEPAD
	elif event is InputEventKey or (event is InputEventMouseButton and not event.is_echo()):
		method = Method.KEYBOARD_MOUSE
	if event.is_action_pressed("walk_toggle"):
		walk_toggled = not walk_toggled
	if event.is_action_pressed("fullscreen"):
		var mode := DisplayServer.window_get_mode()
		var full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else FULLSCREEN)


## F11's fullscreen. Exclusive on Windows: the plain kind is a window one
## pixel bigger than the screen, so the desktop compositor copies every frame
## and paces it to the refresh rate (vsync off or not). On laptops whose screen
## hangs off the processor's built-in graphics that copy crosses cards and
## caps the frame rate well under what the GPU can do.
const FULLSCREEN := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## Camera-independent move input, 0..1 length (analog aware).
func get_move_vector() -> Vector2:
	if ui_locked:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_forward", "move_back")


func is_sprinting() -> bool:
	if ui_locked:
		return false
	return Input.is_action_pressed("sprint") or sprint_toggled or push_sprint
