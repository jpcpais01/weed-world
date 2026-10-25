class_name PerfReadout
extends Label
## Where the frame time goes, shown under the FPS counter: frame and GPU
## milliseconds, whether the GPU, the CPU or vsync sets the pace, the CPU's
## draw submission, scene prep, scripts and physics, script time per game
## system (see PerfMeter), and what the slowest recent frame spent its time on.
##
## The GPU can't time its passes in a release build, so "measure parts"
## (press 9, or tap the readout) finds each part's cost by switching it off
## for a moment: shadows, trees, grass, water, glow and so on, one at a time,
## and timing the GPU without it. Things blink for about 15 seconds while it
## runs; the results stay on screen.

const WINDOW := 0.5          # seconds averaged per update
const SETTLE := 0.35         # seconds to let a change reach the GPU timings
const SAMPLE := 0.8          # seconds timed per part
const AA_SETTLE := 3.0       # ...and for anti-aliasing, whose pipelines build first

## Main-line text for the FPS counter, refreshed every WINDOW.
var summary := "CPU -- · GPU -- ms"
## Set by the HUD once the forest is found.
var forest: Forest

var _vp: RID
var _t := 0.0
var _frames := 0
var _gpu := 0.0
var _render := 0.0
var _setup := 0.0
var _proc := 0.0              # all _process scripts, summed over the window (ms)
var _phys := 0.0              # all _physics_process scripts
var _avg := {}               # last window's averages, in ms
var _systems := {}           # last window's script time per system, ms per frame
var _adapter := ""
var _worst := ["", 0.0, -INF]  # slowest single frame of any system lately: [system, ms, when]

# Frame anatomy. Two marker nodes run first and last in every process and
# physics pass, so each frame splits into process scripts, physics scripts
# (and how many physics steps ran) and the rest: drawing, the physics engine
# and waiting on the GPU or the screen.
var _f0 := 0                 # when this frame's process pass began (usec)
var _proc_us := 0
var _phys_us := 0
var _phys_t := 0
var _phys_n := 0
var _top := ["", 0.0]        # busiest system of the last process pass
## Slowest frame lately: {ms, proc, phys, steps, draw, rest, top, top_ms, when}
var _slowest := {"ms": 0.0, "when": -INF}

# "Measure parts"
var _steps: Array = []
var _step := -1
var _phase := ""
var _phase_t := 0.0
var _acc_gpu := 0.0
var _acc_cpu := 0.0
var _acc_n := 0
var _base: Array[Vector2] = []
var _results: Array = []     # [name, gpu ms saved, cpu ms saved]


func _ready() -> void:
	_vp = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp, true)
	_adapter = adapter_text()
	var first := _Mark.new()
	first.process_priority = -1000000
	first.process_physics_priority = -1000000
	first.on_process = _frame_start
	first.on_physics = func(): _phys_t = Time.get_ticks_usec()
	var last := _Mark.new()
	last.process_priority = 1000000
	last.process_physics_priority = 1000000
	last.on_process = func():
		_proc_us = Time.get_ticks_usec() - _f0
		_top = PerfMeter.busiest()
	last.on_physics = func():
		_phys_us += Time.get_ticks_usec() - _phys_t
		_phys_n += 1
	add_child(first)
	add_child(last)


class _Mark extends Node:
	var on_process: Callable
	var on_physics: Callable

	func _process(_delta: float) -> void:
		on_process.call()

	func _physics_process(_delta: float) -> void:
		on_physics.call()


## The span since the last frame began: the last process pass, its drawing
## and any wait, then this frame's physics steps.
func _frame_start() -> void:
	var now := Time.get_ticks_usec()
	if _f0 > 0:
		var ms := (now - _f0) / 1000.0
		_proc += _proc_us / 1000.0
		_phys += _phys_us / 1000.0
		var t := now / 1000000.0
		if ms > _slowest.ms or t - _slowest.when > 5.0:
			var top := _top
			var draw := RenderingServer.viewport_get_measured_render_time_cpu(_vp) + RenderingServer.get_frame_setup_time_cpu()
			_slowest = {"ms": ms, "proc": _proc_us / 1000.0, "phys": _phys_us / 1000.0, "steps": _phys_n, "draw": draw,
					"rest": ms - (_proc_us + _phys_us) / 1000.0, "top": top[0], "top_ms": top[1], "when": t}
	_f0 = now
	_phys_us = 0
	_phys_n = 0


## The graphics card the game draws with, its kind and driver API, and the
## renderer, e.g. "NVIDIA GeForce RTX 4060 Laptop GPU (dedicated) · Vulkan
## 1.3 · Forward Plus renderer". Laptops can quietly run games on the processor's
## built-in graphics instead of the dedicated card.
static func adapter_text() -> String:
	var kinds := {RenderingDevice.DEVICE_TYPE_DISCRETE_GPU: "dedicated", RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU: "built-in",
			RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU: "virtual", RenderingDevice.DEVICE_TYPE_CPU: "software"}
	var kind: String = kinds.get(RenderingServer.get_video_adapter_type(), "unknown kind")
	var method := RenderingServer.get_current_rendering_method().replace("_", " ").capitalize()
	var driver := RenderingServer.get_current_rendering_driver_name()
	var api: String = {"vulkan": "Vulkan", "d3d12": "Direct3D 12", "metal": "Metal"}.get(driver, driver)
	return "%s (%s) · %s %s · %s renderer" % [RenderingServer.get_video_adapter_name(), kind, api,
			RenderingServer.get_video_adapter_api_version(), method]


func _process(delta: float) -> void:
	var gpu := RenderingServer.viewport_get_measured_render_time_gpu(_vp)
	var render := RenderingServer.viewport_get_measured_render_time_cpu(_vp)
	_gpu += gpu
	_render += render
	_setup += RenderingServer.get_frame_setup_time_cpu()
	_frames += 1
	_t += delta
	if _step >= 0:
		_probe_tick(delta, gpu, render + RenderingServer.get_frame_setup_time_cpu())
	if _t >= WINDOW:
		_summarise()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_9:
		measure_parts()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_8:
		var on := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED if on else DisplayServer.VSYNC_ENABLED)
		get_viewport().set_input_as_handled()


func _summarise() -> void:
	var n := float(maxi(_frames, 1))
	var fps := _frames / _t
	_avg = {"fps": fps, "frame": 1000.0 / maxf(fps, 0.001), "gpu": _gpu / n, "render": _render / n,
			"setup": _setup / n, "proc": _proc / n, "phys": _phys / n}
	_systems = {}
	var taken := PerfMeter.take()
	for k in taken.total:
		_systems[k] = taken.total[k] / 1000.0 / n
	# Hitches hide in averages: keep the slowest frame of any one system in
	# view for a few seconds.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _worst[2] > 5.0:
		_worst = ["", 0.0, -INF]
	for k in taken.peak:
		if String(k).ends_with("(background)"):
			continue  # off the main thread: slow, but no stutter
		var ms: float = taken.peak[k] / 1000.0
		if ms > _worst[1]:
			_worst = [k, ms, now]
	_t = 0.0
	_frames = 0
	_gpu = 0.0
	_render = 0.0
	_setup = 0.0
	_proc = 0.0
	_phys = 0.0
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	summary = "%.1f ms a frame · GPU %.1f ms  ·  %s draws" % [_avg.frame, _avg.gpu, _thousands(draws)]
	if visible:
		text = _panel()


func _panel() -> String:
	var lines: Array[String] = []
	var hz := DisplayServer.screen_get_refresh_rate()
	var vsync := DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	# The main thread's measured work each frame (the physics engine's own
	# step aside): what it can't overlap with the GPU.
	var cpu: float = _avg.render + _avg.setup + _avg.proc + _avg.phys
	# A few frames that miss a vblank pull the average a little under the
	# refresh rate, so "near it" still counts as capped.
	if vsync and hz > 0.0 and _avg.frame < 1150.0 / hz:
		lines.append("Capped by vsync at %d Hz: GPU %.1f ms and CPU about %.1f ms of each %.1f ms, so lower settings can't raise the frame rate%s" % [
				roundi(hz), _avg.gpu, cpu, 1000.0 / hz, "" if OS.has_feature("mobile") else " (8 turns vsync off to see how fast it could go)"])
	elif _avg.gpu >= _avg.frame * 0.8:
		lines.append("GPU-bound: the graphics card is busy %.1f of each %.1f ms" % [_avg.gpu, _avg.frame])
	elif cpu >= _avg.frame * 0.75:
		lines.append("CPU-bound: the processor is busy about %.1f of each %.1f ms (the graphics card %.1f)" % [cpu, _avg.frame, _avg.gpu])
	else:
		# Neither is full: the time goes on uneven frames (stalls, catch-up
		# physics steps, waiting on the driver or screen).
		lines.append("Uneven frames: the GPU needs %.1f and the CPU about %.1f of each %.1f ms; the rest is lost to slow frames (see below)" % [
				_avg.gpu, cpu, _avg.frame])
	lines.append(_adapter)
	var sync := "vsync %s" % ("on" if vsync else "off")
	if hz > 0.0:
		sync += " · %d Hz screen" % roundi(hz)
	if not OS.has_feature("mobile"):
		sync += "  (8 toggles vsync)"
	lines.append(sync)
	lines.append("CPU per frame: draw submit %.1f · scene prep %.1f · scripts %.1f · physics scripts %.1f ms" % [
			_avg.render, _avg.setup, _avg.proc, _avg.phys])
	var names := _systems.keys()
	names.sort_custom(func(a, b): return _systems[a] > _systems[b])
	var parts: Array[String] = []
	for k in names:
		if _systems[k] >= 0.01:
			parts.append("%s %.2f" % [k, _systems[k]])
	if not parts.is_empty():
		lines.append("  scripts per frame (ms): " + " · ".join(parts.slice(0, 7)))
	if hz > 0.0 and _slowest.ms > 1500.0 / hz:
		var w := _slowest
		var line := "slowest frame lately %.1f ms: scripts %.1f · physics scripts %.1f (%d step%s) · drawing, physics engine and waiting %.1f (draw submit %.1f)" % [
				w.ms, w.proc, w.phys, w.steps, "" if w.steps == 1 else "s", w.rest, w.draw]
		if w.top != "":
			line += " · busiest system %s %.1f" % [w.top, w.top_ms]
		lines.append(line)
	if _worst[1] >= 4.0:
		lines.append("  slowest system frame lately: %s %.1f ms" % [_worst[0], _worst[1]])
	if _step >= 0:
		lines.append("GPU by part: measuring %s... (%d of %d)" % [_steps[_step].name if _step < _steps.size() else "baseline",
				mini(_step + 1, _steps.size()), _steps.size()])
	elif _results.is_empty():
		lines.append("GPU by part: press 9 or tap here to measure (things blink ~20 s)")
	else:
		lines.append("GPU (and CPU) each part costs, measured by switching it off:")
		var row: Array[String] = []
		for r in _results:
			row.append("%s %.2f (%.2f)" % [r[0], r[1], r[2]])
			if row.size() == 4:
				lines.append("  " + " · ".join(row))
				row = []
		if not row.is_empty():
			lines.append("  " + " · ".join(row))
	return "\n".join(lines)


static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


# ----------------------------------------------------------------------------
# Measuring each part

func measure_parts() -> void:
	if _step >= 0:
		return
	_steps = _make_steps()
	_results = []
	_base = []
	_step = 0
	_start_phase("base")


func _start_phase(phase: String) -> void:
	_phase = phase
	_phase_t = 0.0
	_acc_gpu = 0.0
	_acc_cpu = 0.0
	_acc_n = 0


## Baseline, then for each part: switch off, settle, time, switch on, settle;
## then a second baseline so a drifting frame time doesn't skew the parts.
func _probe_tick(delta: float, gpu: float, cpu: float) -> void:
	_phase_t += delta
	match _phase:
		"base", "time":
			var settle := _settle()
			if _phase_t >= settle:
				_acc_gpu += gpu
				_acc_cpu += cpu
				_acc_n += 1
			if _phase_t < settle + SAMPLE:
				return
			var m := Vector2(_acc_gpu, _acc_cpu) / maxf(_acc_n, 1)
			if _phase == "base":
				_base.append(m)
				if _step >= _steps.size():
					_finish_probe()
					return
				_steps[_step].off.call()
				_start_phase("time")
			else:
				_steps[_step].m = m
				_steps[_step].on.call()
				_start_phase("restore")
		"restore":
			if _phase_t < _settle():
				return
			_step += 1
			if _step >= _steps.size():
				_start_phase("base")
			else:
				_steps[_step].off.call()
				_start_phase("time")


## How long the current phase waits before timing: a step can ask for
## longer, when switching it makes the GPU build new pipelines first.
func _settle() -> float:
	if _phase == "base" or _step < 0 or _step >= _steps.size():
		return SETTLE
	return _steps[_step].get("settle", SETTLE)


func _finish_probe() -> void:
	var base := Vector2.ZERO
	for b in _base:
		base += b
	base /= _base.size()
	for s in _steps:
		if s.has("m"):
			var saved: Vector2 = base - s.m
			_results.append([s.name, saved.x, saved.y])
	_results.sort_custom(func(a, b): return a[1] > b[1])
	_step = -1
	if visible:
		text = _panel()


func _make_steps() -> Array:
	var steps := []
	var vp := get_viewport()
	if forest and forest.atmosphere and forest.atmosphere.sun:
		var sun := forest.atmosphere.sun
		steps.append(_toggle("Shadows", sun, "shadow_enabled", false))
	var lod: ForestLod = forest.scatter.lod if forest and forest.scatter else null
	if lod:
		for part in [["Trees", ["tree", "far", "Impostors"]], ["Bushes & plants", ["bush", "plant", "small", "litter", "roots"]],
				["Grass", ["grass"]], ["Rocks & logs", ["rock"]]]:
			steps.append({"name": part[0], "off": _hide_groups.bind(lod, part[1], true), "on": _hide_groups.bind(lod, part[1], false)})
	if forest:
		for part in [["Ground", ["Terrain"]], ["Water", ["Water", "Waterfalls", "Lilies"]], ["Magic & mist", ["Magic"]],
				["Wildlife", ["Life"]], ["Weed & benches", ["WeedPatches", "Benches"]], ["Distant hills", ["DistantRanges"]]]:
			var nodes: Array[Node3D] = []
			for n in part[1]:
				var node := forest.get_node_or_null("Generated/" + n) as Node3D
				if node:
					nodes.append(node)
			if not nodes.is_empty():
				steps.append({"name": part[0], "off": _show_nodes.bind(nodes, false), "on": _show_nodes.bind(nodes, true)})
	# Fog and the sky make the GPU compile pipeline variants, and it runs on
	# slow stand-in shaders meanwhile, so they'd read as costing less than
	# nothing. Anti-aliasing does too, so it waits for them to be built.
	if forest and forest.atmosphere and forest.atmosphere.environment:
		steps.append(_toggle("Glow", forest.atmosphere.environment, "glow_enabled", false))
	if vp.msaa_3d != Viewport.MSAA_DISABLED or vp.screen_space_aa != Viewport.SCREEN_SPACE_AA_DISABLED:
		var msaa := vp.msaa_3d
		var ssaa := vp.screen_space_aa
		steps.append({"name": "Anti-aliasing", "settle": AA_SETTLE,
				"off": _set_aa.bind(vp, Viewport.MSAA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED), "on": _set_aa.bind(vp, msaa, ssaa)})
	steps.append(_toggle("75% resolution would save", vp, "scaling_3d_scale", vp.scaling_3d_scale * 0.75))
	return steps


## A step that sets one property for the measurement and puts it back after.
static func _toggle(label: String, obj: Object, property: StringName, off_value: Variant) -> Dictionary:
	return {"name": label, "off": obj.set.bind(property, off_value), "on": obj.set.bind(property, obj.get(property))}


static func _set_aa(vp: Viewport, msaa: Viewport.MSAA, ssaa: Viewport.ScreenSpaceAA) -> void:
	vp.msaa_3d = msaa
	vp.screen_space_aa = ssaa


static func _hide_groups(lod: ForestLod, groups: Array, hidden: bool) -> void:
	for g in groups:
		lod.set_group_hidden(g, hidden)


static func _show_nodes(nodes: Array[Node3D], shown: bool) -> void:
	for node in nodes:
		node.visible = shown
