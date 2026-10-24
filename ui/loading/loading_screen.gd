class_name LoadingScreen
extends Node
## Boot scene. Shows the Whispering Glade key art (the same picture as the
## engine's boot splash, so the hand-over is seamless), fireflies and a growing
## vine while the level gets ready without ever blocking the main thread:
##
##   1. load   - the level scene and everything it preloads, on loader threads
##   2. grow   - the forest is grown off-tree on a worker thread
##   3. plant  - the finished world joins the scene tree a slice per frame
##   4. warm   - a hidden camera sweeps the glade behind the curtain until the
##               GPU stops compiling pipelines, so nothing hitches on first sight
##   5. reveal - the curtain dissolves and the forest sounds swell in
##
## Run with --verbose-loading (after --) to log each phase's timing.

signal finished(level: Node)

const LEVEL := "res://world/forest/forest_level.tscn"
const SPLASH := preload("res://branding/splash.png")
const FONT := preload("res://ui/fonts/Fredoka.ttf")

## Frame budget for attaching the world in phase 3.
const ATTACH_BUDGET_USEC := 6000
## Warm-up sweep: headings x frames per heading.
const WARM_HEADINGS := 8
const WARM_FRAMES_PER_HEADING := 3
## Frames without new pipeline compilations before we trust the cache is hot.
const WARM_QUIET_FRAMES := 12
const WARM_MAX_SEC := 6.0

const TIPS := [
	"Push the joystick past its ring to sprint.",
	"Hold jump to leap higher.",
	"Walk up to a herb and press grab. Your Keling will pluck it and take a sniff.",
	"Follow the creek uphill to find the waterfalls.",
	"The sunset overlook has a campfire and two benches. Bring friends.",
	"Wade into the pond and watch the ripples follow you.",
	"Try the emotes: dance, cheer, sit and nod.",
	"The lilac Elder tree watches over the whole glade.",
	"Fireflies gather in the glowshroom hollow.",
	"Five Kelings to be: Sprout, Blossom, Sunflower, Lavender and Toadstool. Swap whenever you like.",
	"Find wild weed, pick the buds and roll one up with your friends.",
	"Up to four Kelings can explore the glade together.",
]
const STAGES := [
	"Waking the forest", "Shaping the valley", "Planting the trees", "Rolling out the meadow",
	"Sowing wildflowers", "Filling the pond", "Lighting the wisps", "Waking the critters",
	"Sweeping the paths",
]

enum Phase { LOAD, GROW, PLANT, WARM, REVEAL, DONE }

var _phase := Phase.LOAD
var _phase_t := 0.0
var _clock := 0.0
var _verbose := false
var _t0 := 0
var _worst := 0.0

var _level: Node
var _forest: Forest
var _task := -1
var _pending: Array[Node] = []
var _pending_parent: Node
var _pending_total := 1

var _warm_cam: Camera3D
var _warm_frame := 0
var _warm_quiet := 0
var _warm_last := -1
var _warm_extras: Array[Node] = []
var _game_cam: Camera3D

# UI
var _layer: CanvasLayer
var _curtain: Control
var _art: TextureRect
var _fireflies: Control
var _roster: KelingRoster
var _stage: Label
var _tip: Label
var _shade: Control
var _tip_i := 0
var _tip_t := 0.0
var _stage_text := ""


func _ready() -> void:
	_verbose = "--verbose-loading" in OS.get_cmdline_user_args()
	_t0 = Time.get_ticks_msec()
	_build_ui()
	_tip_i = randi() % TIPS.size()
	_tip.text = TIPS[_tip_i]
	var err := ResourceLoader.load_threaded_request(LEVEL, "", true)
	if err != OK:
		push_error("LoadingScreen: could not start loading %s (%s)" % [LEVEL, error_string(err)])
		set_process(false)
		return
	# Hold the forest's voice back until the reveal.
	_fade_audio(0.0)


## Fades the whole mix in under the player's own master volume.
func _fade_audio(f: float) -> void:
	var settings := get_node_or_null("/root/Settings")
	if settings:
		settings.set_master_fade(f)
	else:
		AudioServer.set_bus_volume_db(0, linear_to_db(maxf(f, 0.001)))


# --- Phases -------------------------------------------------------------------

func _process(delta: float) -> void:
	_worst = maxf(_worst, delta)
	if _verbose and delta > 0.034:
		print("loading_screen:   long frame %.1f ms in %s" % [delta * 1000.0, Phase.keys()[_phase]])
	_clock += delta
	_phase_t += delta
	match _phase:
		Phase.LOAD:
			_step_load()
		Phase.GROW:
			_step_grow()
		Phase.PLANT:
			_step_plant()
		Phase.WARM:
			_step_warm()
		Phase.REVEAL:
			_step_reveal(delta)
	_animate_ui(delta)


func _goto(p: Phase) -> void:
	if _verbose:
		print("loading_screen: %s done after %d ms (total %d ms, longest frame %.1f ms)" % [Phase.keys()[_phase], int(_phase_t * 1000.0), Time.get_ticks_msec() - _t0, _worst * 1000.0])
	_worst = 0.0
	_phase = p
	_phase_t = 0.0


func _step_load() -> void:
	var progress := []
	var status := ResourceLoader.load_threaded_get_status(LEVEL, progress)
	_set_progress(0.0, 0.18, progress[0] if progress.size() > 0 else 0.0, STAGES[0])
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		push_error("LoadingScreen: failed to load %s" % LEVEL)
		set_process(false)
		return
	var packed: PackedScene = ResourceLoader.load_threaded_get(LEVEL)
	_level = packed.instantiate()
	_forest = _level.get_node_or_null("Forest") as Forest
	if _level.has_method("prepare_threaded") and OS.has_feature("threads"):
		_task = WorkerThreadPool.add_task(_level.prepare_threaded, true, "Grow the forest")
	_goto(Phase.GROW)


func _step_grow() -> void:
	var step := _forest.build_step if _forest else 0
	var steps := Forest.BUILD_STEPS
	# Creep within the current step so the vine never stalls on a long one.
	var within := 1.0 - exp(-_phase_t_in_step(step) / 1.6)
	var f := (float(step) + within * 0.85) / float(steps)
	_set_progress(0.18, 0.78, f, STAGES[mini(step, STAGES.size() - 2)])
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	# Without threads the level simply grows itself when it enters the tree.
	_begin_plant()


var _last_step := -1
var _step_since := 0.0


func _phase_t_in_step(step: int) -> float:
	if step != _last_step:
		_last_step = step
		_step_since = _clock
	return _clock - _step_since


func _begin_plant() -> void:
	# Hold the world still until it is all there and warmed up.
	_level.process_mode = Node.PROCESS_MODE_DISABLED
	# Take the grown forest apart so it can join the tree a slice per frame.
	if _forest and _forest.is_built:
		_pending_parent = _forest.get_node_or_null("Generated")
		if _pending_parent:
			for c in _pending_parent.get_children():
				_pending_parent.remove_child(c)
				_pending.append(c)
	_pending_total = maxi(1, _pending.size())
	_pending.reverse()
	get_tree().root.add_child(_level)
	get_tree().current_scene = _level
	_goto(Phase.PLANT)


func _step_plant() -> void:
	var start := Time.get_ticks_usec()
	while not _pending.is_empty() and Time.get_ticks_usec() - start < ATTACH_BUDGET_USEC:
		_pending_parent.add_child(_pending.pop_back())
	var done := 1.0 - float(_pending.size()) / _pending_total
	_set_progress(0.78, 0.86, done, STAGES[STAGES.size() - 1])
	if _pending.is_empty():
		_begin_warm()


func _begin_warm() -> void:
	_game_cam = get_viewport().get_camera_3d()
	_warm_cam = Camera3D.new()
	_warm_cam.name = "WarmUpCamera"
	_warm_cam.fov = 75.0
	_warm_cam.far = _game_cam.far if _game_cam else 400.0
	_level.add_child(_warm_cam)
	var spawn := _spawn_point()
	_warm_cam.global_position = spawn + Vector3.UP * 1.6
	_warm_cam.make_current()
	# One-shot effects that have not fired yet would compile on first use:
	# fire a looping copy of each in front of the lens while the curtain is down.
	for p in _level.find_children("*", "GPUParticles3D", true, false) + _level.find_children("*", "CPUParticles3D", true, false):
		if p.emitting:
			continue
		var copy: Node3D = p.duplicate()
		copy.one_shot = false
		_warm_cam.add_child(copy)
		copy.top_level = false
		copy.position = Vector3(0, -0.4, -2.5)
		copy.emitting = true
		_warm_extras.append(copy)
	_warm_frame = 0
	_warm_quiet = 0
	_warm_last = -1
	_goto(Phase.WARM)


func _spawn_point() -> Vector3:
	var players := get_tree().get_nodes_in_group("player")
	for p in players:
		if p is Node3D and _level.is_ancestor_of(p):
			return (p as Node3D).global_position
	if _forest:
		return _forest.get_spawn_transform(0).origin
	return Vector3.ZERO


func _step_warm() -> void:
	var sweep := WARM_HEADINGS * WARM_FRAMES_PER_HEADING
	_warm_frame += 1
	if _warm_frame <= sweep:
		# Look all the way round, then down at the ground and up at the canopy.
		var heading := floori(float(_warm_frame - 1) / WARM_FRAMES_PER_HEADING)
		_warm_cam.rotation = Vector3(deg_to_rad(-8.0 if heading % 2 == 0 else 12.0), TAU * heading / WARM_HEADINGS, 0.0)
	else:
		_warm_cam.rotation = Vector3(deg_to_rad(-12.0), _warm_cam.rotation.y + 0.35, 0.0)
	var compiles := _pipeline_compilations()
	if compiles == _warm_last:
		_warm_quiet += 1
	else:
		_warm_quiet = 0
		_warm_last = compiles
	var f := clampf(float(_warm_frame) / (sweep + WARM_QUIET_FRAMES), 0.0, 1.0)
	_set_progress(0.86, 1.0, f, "Catching the golden hour")
	var settled := _warm_frame > sweep and _warm_quiet >= WARM_QUIET_FRAMES
	if settled or _phase_t > WARM_MAX_SEC:
		if _verbose:
			print("loading_screen: warm-up saw %d pipeline compilations" % compiles)
		_end_warm()


func _pipeline_compilations() -> int:
	var total := 0
	for info in [
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW,
		RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION,
	]:
		total += RenderingServer.get_rendering_info(info)
	return total


func _end_warm() -> void:
	for e in _warm_extras:
		e.queue_free()
	_warm_extras.clear()
	_warm_cam.queue_free()
	if is_instance_valid(_game_cam):
		_game_cam.make_current()
	# Let the world settle (cameras snap behind the Keling, feet find the
	# ground) for a moment before lifting the curtain.
	_level.process_mode = Node.PROCESS_MODE_INHERIT
	_roster.wake_all()
	_goto(Phase.REVEAL)


func _step_reveal(_delta: float) -> void:
	# Long enough to see the last Kelings hop up and start dancing.
	var hold := 0.8
	var fade := 1.1
	var t := clampf((_phase_t - hold) / fade, 0.0, 1.0)
	var e := t * t * (3.0 - 2.0 * t)
	_curtain.modulate.a = 1.0 - e
	_art.scale = Vector2.ONE * (_art_zoom() + e * 0.06)
	_fade_audio(e)
	if t >= 1.0:
		_fade_audio(1.0)
		_goto(Phase.DONE)
		finished.emit(_level)
		print("loading_screen: done in %d ms" % (Time.get_ticks_msec() - _t0))
		queue_free()


func _set_progress(lo: float, hi: float, f: float, stage: String) -> void:
	_roster.value = maxf(_roster.value, lerpf(lo, hi, clampf(f, 0.0, 1.0)))
	if stage != _stage_text:
		_stage_text = stage


# --- UI -----------------------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 100
	add_child(_layer)

	_curtain = Control.new()
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_curtain)

	var bg := ColorRect.new()
	bg.color = ProjectSettings.get_setting("application/boot_splash/bg_color", Color.BLACK)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.add_child(bg)

	# Same picture and the same "cover" fit as the boot splash.
	_art = TextureRect.new()
	_art.texture = SPLASH
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_curtain.add_child(_art)

	_fireflies = LoadingFireflies.new()
	_fireflies.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.add_child(_fireflies)

	# A soft dusk shadow rising from the bottom edge, so the words always read.
	var shade_g := Gradient.new()
	shade_g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	shade_g.colors = PackedColorArray([Color(0.02, 0.05, 0.03, 0.0), Color(0.02, 0.05, 0.03, 0.45), Color(0.02, 0.05, 0.03, 0.8)])
	var shade_t := GradientTexture2D.new()
	shade_t.gradient = shade_g
	shade_t.fill_from = Vector2(0, 0)
	shade_t.fill_to = Vector2(0, 1)
	shade_t.width = 4
	shade_t.height = 64
	var shade := TextureRect.new()
	shade.texture = shade_t
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0.0
	shade.anchor_right = 1.0
	shade.anchor_top = 1.0
	shade.anchor_bottom = 1.0
	shade.offset_top = -420
	_curtain.add_child(shade)
	_shade = shade

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 10)
	_curtain.add_child(bottom)
	bottom.anchor_left = 0.1
	bottom.anchor_right = 0.9
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 0
	bottom.offset_right = 0
	bottom.offset_top = -360
	bottom.offset_bottom = -26
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN

	# All five Kelings along the growing vine: each wakes up as it arrives.
	_roster = KelingRoster.new()
	_roster.custom_minimum_size = Vector2(0, 236)
	bottom.add_child(_roster)

	_stage = _label(30, 600, Color(1.0, 0.97, 0.86))
	bottom.add_child(_stage)

	_tip = _label(23, 450, Color(0.93, 0.96, 0.88, 0.9))
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_tip)


func _label(px: int, weight: int, color: Color) -> Label:
	var font := FontVariation.new()
	font.base_font = FONT
	font.variation_opentype = {"wght": weight}
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.06, 0.03, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 8)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _art_zoom() -> float:
	# A slow drift in: barely there, but the picture breathes.
	return 1.0 + 0.035 * (1.0 - exp(-_clock / 9.0))


func _animate_ui(delta: float) -> void:
	_art.pivot_offset = _art.size * Vector2(0.5, 0.42)
	if _phase != Phase.REVEAL:
		_art.scale = Vector2.ONE * _art_zoom()
	# Fade the words in after the splash hand-over so the first frame matches it.
	var ui_a := clampf((_clock - 0.15) / 0.6, 0.0, 1.0)
	_roster.modulate.a = ui_a
	_shade.modulate.a = ui_a

	var dots := ".".repeat(1 + int(_clock * 2.5) % 3)
	_stage.text = _stage_text + dots
	_stage.modulate.a = ui_a

	_tip_t += delta
	if _tip_t > 5.5:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		_tip.text = TIPS[_tip_i]
	var tip_fade := minf(clampf(_tip_t / 0.5, 0.0, 1.0), clampf((5.5 - _tip_t) / 0.5, 0.0, 1.0))
	_tip.modulate.a = ui_a * tip_fade
