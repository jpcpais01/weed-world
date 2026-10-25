class_name GameSettings
extends Node
## Every player setting in one place: graphics, audio, controls and the HUD.
## Values live in user://settings.cfg and apply the moment they change, so the
## pause menu can show the result live behind it.
##
## Graphics land on the root viewport (resolution scale, anti-aliasing), the
## RenderingServer (shadow atlas and filter), the forest's sun and sky (shadow
## distance, bloom) and ForestLod (tree detail and grass density). Audio gets
## its own buses: Music and UI go straight to Master; Ambience and SFX go
## through "World", which the pause menu muffles. The camera reads its look
## settings from here, and keyboard keys can be rebound.

signal changed(key: String)
signal bindings_changed

const PATH := "user://settings.cfg"

enum Shadows { OFF, LOW, MEDIUM, HIGH, ULTRA }
enum Detail { LOW, MEDIUM, HIGH, ULTRA }
enum AA { OFF, FXAA, MSAA_2X, MSAA_4X, SMAA }  # values are saved: append only

const PRESETS := ["low", "medium", "high", "ultra"]
## What each quality preset sets. "high" is how the game always looked.
const PRESET_VALUES := {
	"low": {"render_scale": 0.67, "shadows": Shadows.LOW, "trees": Detail.LOW, "grass": 0.45, "aa": AA.FXAA, "bloom": false},
	"medium": {"render_scale": 0.85, "shadows": Shadows.MEDIUM, "trees": Detail.MEDIUM, "grass": 0.75, "aa": AA.FXAA, "bloom": true},
	"high": {"render_scale": 1.0, "shadows": Shadows.HIGH, "trees": Detail.HIGH, "grass": 1.0, "aa": AA.MSAA_2X, "bloom": true},
	"ultra": {"render_scale": 1.0, "shadows": Shadows.ULTRA, "trees": Detail.ULTRA, "grass": 1.0, "aa": AA.MSAA_4X, "bloom": true},
}
const PRESET_KEYS := ["render_scale", "shadows", "trees", "grass", "aa", "bloom"]

## High's anti-aliasing on PC. MSAA multiplies the depth work of every leaf
## layer yet leaves the cut-out leaf edges jagged (they come from the
## texture, not the triangles); SMAA smooths those edges too, for a small
## fixed cost. Phones keep MSAA, which tiled mobile GPUs do almost for free.
const HIGH_AA_DESKTOP := AA.SMAA

## Resolution scale the High preset (and a first launch) uses on desktop
## screens taller than 1080 px, where the pixel count is the GPU's biggest
## cost. 1.0 keeps full resolution everywhere; set e.g. 0.85 to switch on.
const HI_RES_DEFAULT_SCALE := 1.0

## Shadow levels as [atlas size, distance m, soft filter quality]. High is
## the project's own setting on each platform (4096 / 2048).
const SHADOW_DESKTOP := [[0, 0.0, 0], [1024, 45.0, 0], [2048, 60.0, 1], [4096, 75.0, 2], [4096, 75.0, 3]]
const SHADOW_MOBILE := [[0, 0.0, 0], [1024, 40.0, 0], [1024, 60.0, 1], [2048, 75.0, 1], [4096, 75.0, 2]]
## ForestLod band distance multiplier per tree detail level.
const TREE_DETAIL := [0.6, 0.8, 1.0, 1.35]
const FPS_CAPS := [0, 30, 60, 90, 120, 144]

## The camera's own defaults (camera/orbit_camera.gd), scaled by the sliders.
const MOUSE_BASE := 0.0032
const TOUCH_BASE := 0.0055
const PAD_BASE := 2.8

## Keys that can be rebound, in the order the menu lists them.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"], ["move_right", "Move right"],
	["jump", "Jump"], ["sprint", "Sprint"], ["walk_toggle", "Walk / run"], ["grab", "Grab · pick · sit"],
	["weed", "Roll · light · smoke"], ["weed_cycle", "Change strain"], ["dragon", "Dragon Breath"], ["gift", "Smoke gift"], ["map", "Map"], ["coop", "Play together"], ["character", "Change Keling"],
	["emote_dance", "Dance"], ["emote_cheer", "Cheer"], ["emote_sit", "Sit down"], ["emote_nod", "Nod"],
	["controls_help", "Show controls"], ["toggle_debug", "Frame-time readout"],
]
## Never bindable: the menu key itself and the system keys.
const RESERVED := [KEY_ESCAPE, KEY_F11, KEY_META, KEY_CAPSLOCK, KEY_PRINT]

const DEFAULTS := {
	# graphics
	"preset": "high",
	"render_scale": 1.0,
	"shadows": Shadows.HIGH,
	"trees": Detail.HIGH,
	"grass": 1.0,
	"aa": AA.MSAA_2X,
	"bloom": true,
	"vsync": true,
	"fps_cap": 0,
	# audio (linear 0..1)
	"master": 1.0,
	"music": 0.7,
	"ambience": 1.0,
	"sfx": 1.0,
	"mute_unfocused": true,
	# controls
	"mouse_sens": 1.0,
	"touch_sens": 1.0,
	"pad_sens": 1.0,
	"invert_y": false,
	"invert_x": false,
	"auto_camera": true,
	"fov": 60.0,
	# interface
	"show_fps": true,
	"show_hints": true,
}
const SECTIONS := {
	"graphics": ["preset", "render_scale", "shadows", "trees", "grass", "aa", "bloom", "vsync", "fps_cap"],
	"audio": ["master", "music", "ambience", "sfx", "mute_unfocused"],
	"controls": ["mouse_sens", "touch_sens", "pad_sens", "invert_y", "invert_x", "auto_camera", "fov"],
	"interface": ["show_fps", "show_hints"],
}

var values := {}
var bindings := {}            ## action -> physical keycode of its main key
var default_keys := {}        ## action -> the main key GameInput gave it
var default_keysets := {}     ## action -> every key GameInput gave it, main first
var _forest: Node
var _master_fade := 1.0
var _focused := true
var _muffle := 0.0
var _muffle_target := 0.0
var _lowpass: AudioEffectLowPassFilter
var _save_timer: SceneTreeTimer

## Desktop frame-rate cap, timed here instead of by Engine.max_fps. Godot's cap
## sleeps the whole gap on the OS timer, and on Windows every sleep wakes a
## millisecond or two late, so a 120 cap ran at about 95. This one sleeps to
## just short of the deadline and spins the rest, right after the frame is
## drawn (where Godot's own cap waits).
const CAP_SPIN_US := 2000
var _cap_us := 0             # frame period in usec, 0 = uncapped
var _cap_due := 0            # when the next frame may start
## How long the cap held the last frame, and which frame (for PerfReadout).
var cap_held_us := 0
var cap_frame := -1


func _enter_tree() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	values = DEFAULTS.duplicate()
	values["render_scale"] = default_scale()
	_load()
	_sync_preset()
	_ensure_buses()


func _ready() -> void:
	# GameInput registered the actions in its own _enter_tree, before ours.
	for pair in REBINDABLE:
		var keys: Array = []
		if InputMap.has_action(pair[0]):
			for e in InputMap.action_get_events(pair[0]):
				if e is InputEventKey:
					keys.append((e as InputEventKey).physical_keycode)
		default_keysets[pair[0]] = keys
		if not keys.is_empty():
			default_keys[pair[0]] = keys[0]
	_apply_bindings()
	apply_all()


# --- values -------------------------------------------------------------------

func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


## Changes one setting, applies it and saves soon after. Touching any
## graphics knob by hand turns the preset into "custom".
func set_value(key: String, value: Variant) -> void:
	if key == "preset":
		apply_preset(String(value))
		return
	if values.get(key) == value:
		return
	values[key] = value
	if key in PRESET_KEYS:
		values["preset"] = _matching_preset()
		changed.emit("preset")
	_apply(key)
	changed.emit(key)
	_save_soon()


func apply_preset(name: String) -> void:
	if not PRESET_VALUES.has(name):
		values["preset"] = "custom"
		changed.emit("preset")
		_save_soon()
		return
	values["preset"] = name
	for k in PRESET_VALUES[name]:
		values[k] = preset_value(name, k)
	apply_graphics()
	changed.emit("preset")
	for k in PRESET_KEYS:
		changed.emit(k)
	_save_soon()


## Full resolution, or HI_RES_DEFAULT_SCALE on big desktop screens.
static func default_scale() -> float:
	if OS.has_feature("mobile") or DisplayServer.get_name() == "headless":
		return 1.0
	var h := DisplayServer.screen_get_size().y
	return HI_RES_DEFAULT_SCALE if h > 1080 else 1.0


## One preset's value; High's resolution follows default_scale().
static func preset_value(name: String, key: String) -> Variant:
	if name == "high" and key == "render_scale":
		return default_scale()
	if name == "high" and key == "aa" and not OS.has_feature("mobile"):
		return HIGH_AA_DESKTOP
	return PRESET_VALUES[name][key]


## A named preset follows its current definition, so players on it pick up
## changes to it (and platform differences); custom picks stay as they are.
func _sync_preset() -> void:
	if values.preset in PRESETS:
		for k in PRESET_VALUES[values.preset]:
			values[k] = preset_value(values.preset, k)


## The preset whose values match the current ones, or "custom".
func _matching_preset() -> String:
	for name in PRESETS:
		var ok := true
		for k in PRESET_VALUES[name]:
			if not is_equal_approx(float(values[k]), float(preset_value(name, k))):
				ok = false
				break
		if ok:
			return name
	return "custom"


## Puts one section (graphics, audio, controls, interface) back to defaults.
func reset_section(section: String) -> void:
	for k in SECTIONS.get(section, []):
		values[k] = default_scale() if k == "render_scale" else DEFAULTS[k]
	_sync_preset()
	if section == "controls":
		bindings.clear()
		_apply_bindings()
		bindings_changed.emit()
	apply_all()
	for k in SECTIONS.get(section, []):
		changed.emit(k)
	_save_soon()


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in SECTIONS:
		for k in SECTIONS[section]:
			var v = cfg.get_value(section, k, values[k])
			if typeof(v) == typeof(DEFAULTS[k]) or (typeof(DEFAULTS[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				values[k] = v
	var saved = cfg.get_value("controls", "keys", {})
	if saved is Dictionary:
		for a in saved:
			bindings[String(a)] = int(saved[a])


func save() -> void:
	var cfg := ConfigFile.new()
	for section in SECTIONS:
		for k in SECTIONS[section]:
			cfg.set_value(section, k, values[k])
	cfg.set_value("controls", "keys", bindings)
	cfg.save(PATH)


func _save_soon() -> void:
	if not is_inside_tree():
		save()
		return
	if _save_timer:
		return
	_save_timer = get_tree().create_timer(0.6, true)
	_save_timer.timeout.connect(func():
		_save_timer = null
		save())


# --- applying -------------------------------------------------------------------

func apply_all() -> void:
	apply_graphics()
	apply_audio()
	apply_cameras()


func _apply(key: String) -> void:
	if key in SECTIONS.graphics:
		apply_graphics()
	elif key in SECTIONS.audio:
		apply_audio()
	elif key in SECTIONS.controls:
		apply_cameras()


static func is_mobile() -> bool:
	return OS.has_feature("mobile")


func shadow_level() -> Array:
	var table: Array = SHADOW_MOBILE if is_mobile() else SHADOW_DESKTOP
	return table[clampi(int(values.shadows), 0, table.size() - 1)]


func apply_graphics() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		_apply_forest_lod()
		return
	var vp := get_tree().root
	var scale := clampf(float(values.render_scale), 0.5, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = scale
	var aa := int(values.aa)
	vp.msaa_3d = Viewport.MSAA_2X if aa == AA.MSAA_2X else (Viewport.MSAA_4X if aa == AA.MSAA_4X else Viewport.MSAA_DISABLED)
	vp.screen_space_aa = {AA.FXAA: Viewport.SCREEN_SPACE_AA_FXAA, AA.SMAA: Viewport.SCREEN_SPACE_AA_SMAA}.get(aa, Viewport.SCREEN_SPACE_AA_DISABLED)
	if not is_mobile():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if values.vsync else DisplayServer.VSYNC_DISABLED)
	# Phones keep Godot's cap: it saves battery and a late wake costs nothing.
	var cap := int(values.fps_cap)
	Engine.max_fps = cap if is_mobile() else 0
	_cap_us = 0
	if not is_mobile() and cap > 0:
		# Vsync already holds frames to the screen; a cap at or over its rate
		# would only fight it.
		var hz := DisplayServer.screen_get_refresh_rate()
		if not (values.vsync and hz > 0.0 and cap >= hz - 1.0):
			_cap_us = 1000000 / cap
			if not RenderingServer.frame_post_draw.is_connected(_hold_frame):
				RenderingServer.frame_post_draw.connect(_hold_frame)
	var sh := shadow_level()
	if sh[0] > 0:
		RenderingServer.directional_shadow_atlas_set_size(sh[0], true)
		RenderingServer.directional_soft_shadow_filter_set_quality(sh[2])
	_apply_forest()
	_apply_forest_lod()


func _hold_frame() -> void:
	if _cap_us <= 0:
		return
	var now := Time.get_ticks_usec()
	_cap_due += _cap_us
	if _cap_due < now - _cap_us:
		_cap_due = now  # well behind after a slow frame: start over, no sprint
	if _cap_due - now > CAP_SPIN_US:
		OS.delay_usec(_cap_due - now - CAP_SPIN_US)
	while Time.get_ticks_usec() < _cap_due:
		pass
	cap_held_us = Time.get_ticks_usec() - now
	cap_frame = Engine.get_process_frames()


func _apply_forest_lod() -> void:
	ForestLod.detail = TREE_DETAIL[clampi(int(values.trees), 0, TREE_DETAIL.size() - 1)]
	ForestLod.density = clampf(float(values.grass), 0.1, 1.0)
	if is_inside_tree():
		get_tree().call_group("forest_lod", "refresh")


## The level's forest (set by the HUD once it finds it): its sun and sky.
func attach_forest(forest: Node) -> void:
	_forest = forest
	_apply_forest()


func _apply_forest() -> void:
	if _forest == null or not is_instance_valid(_forest):
		return
	var atmo = _forest.get("atmosphere")
	if atmo == null:
		return
	var sun: DirectionalLight3D = atmo.get("sun")
	if sun:
		var sh := shadow_level()
		sun.shadow_enabled = sh[0] > 0
		if sh[0] > 0:
			sun.directional_shadow_max_distance = sh[1]
	var env: Environment = atmo.get("environment")
	if env:
		env.glow_enabled = bool(values.bloom)


# --- audio ----------------------------------------------------------------------

## Master <- Music, UI, World <- (Ambience, SFX).
func _ensure_buses() -> void:
	for pair in [["World", "Master"], ["Music", "Master"], ["UI", "Master"], ["Ambience", "World"], ["SFX", "World"]]:
		if AudioServer.get_bus_index(pair[0]) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, pair[0])
			AudioServer.set_bus_send(i, pair[1])
	var world := AudioServer.get_bus_index("World")
	if AudioServer.get_bus_effect_count(world) == 0:
		_lowpass = AudioEffectLowPassFilter.new()
		_lowpass.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(world, _lowpass)
		AudioServer.set_bus_effect_enabled(world, 0, false)
	else:
		_lowpass = AudioServer.get_bus_effect(world, 0) as AudioEffectLowPassFilter


static func _db(linear: float) -> float:
	return linear_to_db(maxf(linear, 0.0001)) if linear > 0.001 else -80.0


func apply_audio() -> void:
	var master := float(values.master) * _master_fade
	if not _focused and values.mute_unfocused and not is_mobile():
		master = 0.0
	_set_bus("Master", master)
	_set_bus("Music", float(values.music))
	_set_bus("Ambience", float(values.ambience))
	_set_bus("SFX", float(values.sfx))
	_set_bus("UI", float(values.sfx))
	# The world drops back a little while the menu is open.
	_set_bus("World", lerpf(1.0, 0.55, _muffle))


func _set_bus(name: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, _db(linear))
	AudioServer.set_bus_mute(i, linear <= 0.001)


## For the loading screen's fade-in: scales the master volume, 0..1.
func set_master_fade(f: float) -> void:
	_master_fade = clampf(f, 0.0, 1.0)
	apply_audio()


## Muffles the forest (ambience and effects) while a menu is open.
func set_muffled(on: bool) -> void:
	_muffle_target = 1.0 if on else 0.0
	set_process(true)


func _process(delta: float) -> void:
	_muffle = move_toward(_muffle, _muffle_target, delta * 3.0)
	var world := AudioServer.get_bus_index("World")
	if world >= 0 and _lowpass:
		AudioServer.set_bus_effect_enabled(world, 0, _muffle > 0.001)
		_lowpass.cutoff_hz = lerpf(20000.0, 700.0, pow(_muffle, 0.5))
	apply_audio()
	if is_equal_approx(_muffle, _muffle_target):
		set_process(false)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_focused = false
			apply_audio()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_focused = true
			apply_audio()


# --- camera ---------------------------------------------------------------------

func apply_cameras() -> void:
	if not is_inside_tree():
		return
	for cam in get_tree().get_nodes_in_group("orbit_camera"):
		apply_camera(cam)


func apply_camera(cam: Node) -> void:
	cam.set("mouse_sensitivity", MOUSE_BASE * float(values.mouse_sens))
	cam.set("touch_sensitivity", TOUCH_BASE * float(values.touch_sens))
	cam.set("gamepad_speed", PAD_BASE * float(values.pad_sens))
	cam.set("invert_y", bool(values.invert_y))
	cam.set("invert_x", bool(values.invert_x))
	cam.set("auto_follow", bool(values.auto_camera))
	cam.set("base_fov", float(values.fov))


# --- key bindings ---------------------------------------------------------------

func key_of(action: String) -> int:
	return int(bindings.get(action, default_keys.get(action, KEY_NONE)))


## Short printable name of an action's main key ("E", "Space", "Shift").
func key_label(action: String) -> String:
	var k := key_of(action)
	if k == KEY_NONE:
		return "—"
	var s := OS.get_keycode_string(DisplayServer.keyboard_get_label_from_physical(k) if DisplayServer.get_name() != "headless" else k)
	if s == "":
		s = OS.get_keycode_string(k)
	return {"Escape": "Esc", "Control": "Ctrl", "BackSpace": "Bksp", "Kp 0": "Num 0"}.get(s, s)


## Binds `key` as the main key of `action`. A rebindable action that already
## used it as its main key swaps over to this action's old key. Returns that
## other action, or "".
func bind_key(action: String, key: int) -> String:
	if key in RESERVED or key == KEY_NONE:
		return ""
	var old := key_of(action)
	if old == key:
		return ""
	var swapped := ""
	for pair in REBINDABLE:
		var other: String = pair[0]
		if other != action and key_of(other) == key:
			_set_binding(other, old)
			swapped = other
	_set_binding(action, key)
	_apply_bindings()
	bindings_changed.emit()
	_save_soon()
	return swapped


func _set_binding(action: String, key: int) -> void:
	if key == default_keys.get(action, KEY_NONE):
		bindings.erase(action)
	else:
		bindings[action] = key


## Rebuilds each rebindable action's keyboard events: its main key first,
## then the alternates it shipped with (arrow keys...) unless another action
## now uses them as its main key.
func _apply_bindings() -> void:
	var mains := {}
	for pair in REBINDABLE:
		mains[key_of(pair[0])] = pair[0]
	for pair in REBINDABLE:
		var action: StringName = pair[0]
		if not InputMap.has_action(action):
			continue
		var others: Array[InputEvent] = []
		for e in InputMap.action_get_events(action):
			if not e is InputEventKey:
				others.append(e)
		InputMap.action_erase_events(action)
		var main := key_of(action)
		var keys: Array[int] = [main]
		var shipped: Array = default_keysets.get(action, [])
		for i in range(1, shipped.size()):
			var k: int = shipped[i]
			if k != main and mains.get(k, action) == action:
				keys.append(k)
		for k in keys:
			if k == KEY_NONE:
				continue
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for e in others:
			InputMap.action_add_event(action, e)
