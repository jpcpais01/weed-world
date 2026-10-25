class_name GiftSlowTime
extends SmokeGift
## Slow Time: a soap-film bubble swells out of the Keling over the forest and
## the whole world slows to a dream: falling leaves hang in the air, the
## waterfalls crawl, birds glide in slow motion, smoke curls lazily, and
## sound sinks into a deep, stretched hum. The Keling itself is outside
## time and moves at full speed, brushing through the frozen leaves.
##
## Only the caster's own game slows (Engine.time_scale). The controller,
## camera, weed actions and the network clock are given the dilation back so
## they keep real time. Friends see the bubble and the leaves round you.
## Menus (and a solo pause) let time run normally while they're open.

const SCALE := 0.28
const LEAVES := 72
const LEAF_RADIUS := 8.5
const RAMP_IN := 1.1
const RAMP_OUT := 1.6
const TINT := Color(0.55, 0.72, 1.0)
const LEAF_COLORS := [Color(0.95, 0.62, 0.22), Color(0.88, 0.36, 0.2), Color(0.98, 0.82, 0.35),
	Color(0.62, 0.78, 0.3), Color(1.0, 0.7, 0.82), Color(0.95, 0.95, 0.9)]

static var _leaf_mat: ShaderMaterial
static var _bubble_mat: ShaderMaterial

var _scale := 1.0           # the world's time scale right now (caster)
var _overlay_layer: CanvasLayer
var _overlay: ColorRect
var _overlay_mat: ShaderMaterial
var _shock := -1.0
var _bubble: MeshInstance3D
var _bubble_t := 99.0
var _shell: MeshInstance3D
var _leaves: MultiMeshInstance3D
var _l_pos := PackedVector3Array()
var _l_vel := PackedVector3Array()
var _l_rot := PackedVector3Array()
var _l_spin := PackedVector3Array()
var _l_fade := PackedFloat32Array()
var _l_kind := PackedFloat32Array()
var _l_col := PackedColorArray()
var _glints: CPUParticles3D
var _hum: AudioStreamPlayer
var _wall := 0.0


func _build() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _leaf_mat == null:
		_leaf_mat = ShaderMaterial.new()
		_leaf_mat.shader = preload("res://player/powers/frozen_leaf.gdshader")
		_bubble_mat = ShaderMaterial.new()
		_bubble_mat.shader = preload("res://player/powers/time_bubble.gdshader")
		_bubble_mat.set_shader_parameter("noise", preload("res://assets/fx/smoke_noise.png"))
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	_bubble = MeshInstance3D.new()
	_bubble.name = "TimeBubble"
	_bubble.mesh = sphere
	_bubble.material_override = _bubble_mat
	_bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bubble.visible = false
	add_child(_bubble)
	if not local:
		_shell = MeshInstance3D.new()
		_shell.name = "OutsideTime"
		_shell.mesh = sphere
		_shell.material_override = _bubble_mat
		_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shell)
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.12)
	_leaves = multimesh(q, LEAVES, _leaf_mat)
	_leaves.name = "FrozenLeaves"
	_l_pos.resize(LEAVES)
	_l_vel.resize(LEAVES)
	_l_rot.resize(LEAVES)
	_l_spin.resize(LEAVES)
	_l_fade.resize(LEAVES)
	_l_kind.resize(LEAVES)
	_l_col.resize(LEAVES)
	_glints = WeedProps.stars(Color(0.75, 0.88, 1.0), 30, 0.05)
	_glints.name = "HangingDew"
	_glints.one_shot = false
	_glints.explosiveness = 0.0
	_glints.lifetime = 5.0
	_glints.gravity = Vector3.ZERO
	_glints.initial_velocity_min = 0.0
	_glints.initial_velocity_max = 0.04
	_glints.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_glints.emission_sphere_radius = 4.0
	add_child(_glints)


func _start(_data: Dictionary) -> void:
	var c := feet()
	for i in LEAVES:
		_spawn_leaf(i, c, true)
	_leaves.multimesh.visible_instance_count = LEAVES
	_burst_bubble()
	play("slow_in", c + Vector3.UP, 0.0)
	if local:
		_build_overlay()
		_hum = AudioStreamPlayer.new()
		_hum.bus = &"SFX"
		var path := "res://assets/audio/gifts/slow_hum.ogg"
		if ResourceLoader.exists(path):
			_hum.stream = load(path)
			(_hum.stream as AudioStreamOggVorbis).loop = true
			_hum.volume_db = -60.0
			add_child(_hum)
			_hum.play()


func _refreshed() -> void:
	_burst_bubble()
	play("slow_in", feet() + Vector3.UP, -4.0)


func _on_end() -> void:
	play("slow_out", feet() + Vector3.UP, -1.0)
	_shock = 0.0


func fade_out() -> float:
	return RAMP_OUT + 0.3


func _burst_bubble() -> void:
	_bubble_t = 0.0
	_bubble.visible = true
	_shock = 0.0


func _build_overlay() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = -5
	add_child(_overlay_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = preload("res://ui/weed/slow_time_overlay.gdshader")
	_overlay_mat.set_shader_parameter("tint", TINT)
	_overlay.material = _overlay_mat
	_overlay_layer.add_child(_overlay)


func _process(delta: float) -> void:
	var tree := get_tree()
	if tree and tree.paused:
		# Solo pause: let the menu run at normal speed, carry on after.
		_set_world_scale(1.0)
		return
	super._process(delta)


func _tick(dt: float, real: float) -> void:
	_wall += real
	var c := feet()
	if local:
		var target := SCALE / boost
		if _menu_open():
			target = 1.0
		var k: float
		if ending:
			k = 1.0 - clampf(out_t / RAMP_OUT, 0.0, 1.0)
		else:
			k = clampf(age / RAMP_IN, 0.0, 1.0)
		k = k * k * (3.0 - 2.0 * k)
		var want := lerpf(1.0, target, k)
		# Ease towards it (the menu snap-back is quick too).
		_scale = move_toward(_scale, want, real * 2.5)
		_set_world_scale(_scale)
		_update_overlay(real, k)
		if _hum:
			_hum.volume_db = lerpf(-60.0, -8.0, k)
	_update_bubble(real)
	_update_leaves(dt, real, c)
	_glints.global_position = c + Vector3(0, 1.4, 0)
	_glints.emitting = not ending


func _menu_open() -> bool:
	var input := get_node_or_null("/root/GameInput")
	return input != null and bool(input.get("ui_locked"))


func _set_world_scale(s: float) -> void:
	if not local:
		return
	s = clampf(s, 0.05, 1.0)
	Engine.time_scale = s
	AudioServer.playback_speed_scale = lerpf(1.0, 0.7, clampf(inverse_lerp(1.0, SCALE, s), 0.0, 1.0))
	if caster and is_instance_valid(caster):
		caster.time_dilation = 1.0 / s
		if caster.camera_rig:
			caster.camera_rig.time_dilation = 1.0 / s


func _update_overlay(real: float, k: float) -> void:
	if _overlay == null:
		return
	if _shock >= 0.0:
		_shock += real * 1.4
		if _shock > 1.9:
			_shock = -1.0
	var show := k > 0.005 or _shock >= 0.0
	_overlay.visible = show
	if not show:
		return
	var cam := get_viewport().get_camera_3d()
	var vp := get_viewport().get_visible_rect().size
	var centre := Vector2(0.5, 0.6)
	if cam and not cam.is_position_behind(feet() + Vector3(0, 0.7, 0)):
		centre = cam.unproject_position(feet() + Vector3(0, 0.7, 0)) / vp
	_overlay_mat.set_shader_parameter("intensity", k)
	_overlay_mat.set_shader_parameter("shock", _shock)
	_overlay_mat.set_shader_parameter("center", centre)
	_overlay_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	_overlay_mat.set_shader_parameter("time_s", _wall)


func _update_bubble(real: float) -> void:
	if _bubble.visible:
		_bubble_t += real
		var k := clampf(_bubble_t / 1.6, 0.0, 1.0)
		var r := 0.6 + 15.0 * (1.0 - pow(1.0 - k, 3.0))
		_bubble.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * r), feet() + Vector3(0, 0.6, 0))
		_bubble.set_instance_shader_parameter("strength", (1.0 - k) * 1.4)
		_bubble.set_instance_shader_parameter("phase", _bubble_t * 3.0)
		if k >= 1.0:
			_bubble.visible = false
	if _shell:
		var e := envelope(0.8)
		_shell.visible = e > 0.01
		_shell.global_transform = Transform3D(Basis.from_scale(Vector3(0.75, 0.95, 0.75) * caster.visual.scale.x), feet() + Vector3(0, 0.7, 0))
		_shell.set_instance_shader_parameter("strength", e * 0.55)
		_shell.set_instance_shader_parameter("phase", _wall)


func _spawn_leaf(i: int, c: Vector3, anywhere: bool) -> void:
	var a := rng.randf() * TAU
	var d := rng.randf_range(1.0, LEAF_RADIUS) if anywhere else rng.randf_range(LEAF_RADIUS * 0.6, LEAF_RADIUS)
	var x := c.x + cos(a) * d
	var z := c.z + sin(a) * d
	var y := floor_at(x, z) + rng.randf_range(0.25, 2.6)
	_l_pos[i] = Vector3(x, y, z)
	# Caught mid-fall: a slow drift down and sideways, a slow tumble.
	_l_vel[i] = Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.6, -0.15), rng.randf_range(-0.25, 0.25))
	_l_rot[i] = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	_l_spin[i] = Vector3(rng.randf_range(-2.5, 2.5), rng.randf_range(-3.0, 3.0), rng.randf_range(-2.5, 2.5))
	_l_fade[i] = 0.0
	var kind := rng.randf()
	_l_kind[i] = 0.1 if kind < 0.6 else (0.5 if kind < 0.85 else 0.9)
	var col: Color = LEAF_COLORS[rng.randi() % LEAF_COLORS.size()]
	if _l_kind[i] > 0.66:
		col = Color(0.97, 0.96, 0.92)
	_l_col[i] = col.lightened(rng.randf_range(-0.05, 0.12))


func _update_leaves(dt: float, real: float, c: Vector3) -> void:
	var mm := _leaves.multimesh
	var fade_all := envelope(0.8)
	var me := caster.global_position + Vector3(0, 0.6, 0)
	for i in LEAVES:
		var p := _l_pos[i]
		var v := _l_vel[i]
		# The Keling (outside time) brushes the leaves aside as it passes.
		var to := p - me
		var dist := to.length()
		if dist < 0.9 and dist > 0.001:
			v += to / dist * (0.9 - dist) * 6.0 * real
		v.y = lerpf(v.y, -0.35, 0.2 * dt)
		v.x *= 1.0 - 0.3 * dt
		v.z *= 1.0 - 0.3 * dt
		p += v * dt
		_l_vel[i] = v
		_l_rot[i] += _l_spin[i] * dt
		var fl := floor_at(p.x, p.z)
		var far := Vector2(p.x - c.x, p.z - c.z).length() > LEAF_RADIUS * 1.35
		if p.y < fl + 0.02 or far:
			if far or not ending:
				_spawn_leaf(i, c, false)
				p = _l_pos[i]
		else:
			_l_pos[i] = p
		_l_fade[i] = minf(_l_fade[i] + real * 1.5, 1.0)
		var r: Vector3 = _l_rot[i]
		var b := Basis.from_euler(r)
		mm.set_instance_transform(i, Transform3D(b, _l_pos[i]))
		mm.set_instance_color(i, _l_col[i])
		mm.set_instance_custom_data(i, Color(_l_fade[i] * fade_all, _l_kind[i], 0, 0))


func _cleanup() -> void:
	if local:
		if Engine.time_scale != 1.0:
			Engine.time_scale = 1.0
		AudioServer.playback_speed_scale = 1.0
		if caster and is_instance_valid(caster):
			caster.time_dilation = 1.0
			if caster.camera_rig:
				caster.camera_rig.time_dilation = 1.0
