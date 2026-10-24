class_name KelingWater
extends Node3D
## A Keling and the water: where the surface is, how deep it is wading,
## whether it should be swimming, and every splash it makes.
##
##  * Footsteps in the shallows each drop a ripple ring, and kick up droplets
##    and a splash sound that grow with speed and depth.
##  * Landing in the shallows splashes; dropping into deep water throws a
##    crown of droplets and a foam burst sized by the fall (a jump off the bank
##    is a proper cannonball).
##  * Swimming: every paddle stroke breaks the surface at the paw, the water
##    shader draws a V-shaped wake behind the head (WaterFX), and treading
##    water sends lazy rings out.
##  * Climbing out the Keling drips for a while, and once it stops on dry land
##    it gives itself a good shake, spraying droplets everywhere.
##
## Everything here is derived from the Keling's own state (position, mode,
## velocity, animation), so a friend's puppet splashes, swims and shakes just
## like the real one without any extra network traffic.

const DIR := "res://assets/audio/water/%s.ogg"
const CLIPS := {
	&"step": ["step_0", "step_1", "step_2", "step_3"],
	&"wade": ["wade_0", "wade_1", "wade_2"],
	&"splash": ["splash_0", "splash_1"],
	&"plunge": ["plunge"],
	&"stroke": ["stroke_0", "stroke_1", "stroke_2"],
	&"bloop": ["bloop"],
	&"slosh": ["slosh"],
	&"shake": ["shake"],
}

## Water depth (metres at scale 1, over the bed) where the feet leave the
## bottom and the Keling swims, and where it finds its feet again.
const SWIM_DEPTH := 0.8
const STAND_DEPTH := 0.66

var keling: KelingController

## Water surface height here, or -INF on dry land.
var surface := -INF
## How deep the water stands over the terrain bed here.
var bed_depth := -1.0
## How deep the feet are under the surface (negative above it).
var immersion := -1.0
## 0..1 how soaked the Keling is (drips and the shake-off follow it).
var wetness := 0.0
## Swim stroke cycle, shared with the swim pose and the controller's surge.
var phase := 0.0
var kick := 0.0

var _voices: Array[AudioStreamPlayer3D] = []
var _voice := 0
var _bursts: Array[CPUParticles3D] = []
var _burst := 0
var _crown: CPUParticles3D
var _mist: CPUParticles3D
var _drips: CPUParticles3D
var _skel: Skeleton3D  # the skeleton _feet were found on (a character swap brings a new one)
var _feet := [-1, -1]
var _foot_z := [0.0, 0.0]
var _foot_vz := [0.0, 0.0]
var _since_step := [1.0, 1.0]
var _prev_mode := -1
var _air_vy := 0.0
var _tread_t := 0.0
var _still_t := 0.0
var _can_shake := false
var _swim_amount := 0.0
var _stroke := 0.0
var _roll := 0.0
var _last_phase := 0.0

## Every water clip, loaded once for all Kelings up front (never mid-play).
static var _streams := {}
static var _drop_mat: StandardMaterial3D
static var _mist_mat: StandardMaterial3D


func setup(p_keling: KelingController) -> void:
	keling = p_keling
	name = "Water"
	if _streams.is_empty():
		for kind in CLIPS:
			for clip: String in CLIPS[kind]:
				_streams[clip] = load(DIR % clip)
	for i in 3:
		var v := AudioStreamPlayer3D.new()
		v.name = "WaterSfx%d" % i
		v.unit_size = 3.0
		v.max_distance = 26.0
		v.attenuation_filter_cutoff_hz = 9000.0
		v.bus = &"SFX"
		add_child(v)
		_voices.append(v)
	for i in 2:
		var b := _emitter(24, 0.85, 0.045)
		b.explosiveness = 0.92
		b.one_shot = true
		b.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		b.emission_sphere_radius = 0.08
		b.direction = Vector3.UP
		b.spread = 38.0
		_bursts.append(b)
	_crown = _emitter(40, 1.1, 0.06)
	_crown.explosiveness = 0.85
	_crown.one_shot = true
	_crown.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_crown.emission_ring_axis = Vector3.UP
	_crown.emission_ring_height = 0.02
	_crown.direction = Vector3.UP
	_crown.spread = 14.0
	_mist = _emitter(7, 1.1, 0.5, _mist_material())
	_mist.explosiveness = 0.8
	_mist.one_shot = true
	_mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_mist.emission_sphere_radius = 0.25
	_mist.direction = Vector3.UP
	_mist.spread = 60.0
	_mist.initial_velocity_min = 0.4
	_mist.initial_velocity_max = 1.0
	_mist.gravity = Vector3(0, -0.6, 0)
	_mist.damping_min = 1.0
	_mist.damping_max = 2.0
	# Drips run off the body after a swim, following it around.
	_drips = _emitter(14, 0.55, 0.026)
	_drips.top_level = false
	_drips.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_drips.emission_box_extents = Vector3(0.22, 0.3, 0.2)
	_drips.position = Vector3(0, 0.55, 0)
	_drips.direction = Vector3.DOWN
	_drips.spread = 8.0
	_drips.initial_velocity_min = 0.0
	_drips.initial_velocity_max = 0.3
	_drips.emitting = false


func _emitter(amount: int, lifetime: float, size: float, mat: Material = null) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.top_level = true
	p.emitting = false
	p.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	p.gravity = Vector3(0, -9.0, 0)
	p.damping_min = 0.2
	p.damping_max = 0.6
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(1.0, 0.35))
	p.scale_amount_curve = sc
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.8), Color(1, 1, 1, 0)])
	p.color_ramp = fade
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat if mat else _drop_material()
	p.mesh = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p


static func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	return tex


static func _drop_material() -> StandardMaterial3D:
	if _drop_mat == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _soft_dot()
		m.albedo_color = Color(0.9, 0.97, 1.0, 0.85)
		m.disable_receive_shadows = true
		_drop_mat = m
	return _drop_mat


static func _mist_material() -> StandardMaterial3D:
	if _mist_mat == null:
		var m := _drop_material().duplicate() as StandardMaterial3D
		m.albedo_color = Color(0.92, 0.96, 1.0, 0.32)
		_mist_mat = m
	return _mist_mat


# --- state --------------------------------------------------------------------

## Reads the water around the Keling. The controller calls this before it
## decides how to move.
func sense() -> void:
	var p := keling.global_position
	surface = WaterLevel.surface_at(p.x, p.z)
	if surface == -INF:
		bed_depth = -1.0
		immersion = -1.0
		return
	bed_depth = surface - WaterLevel.ground_at(p.x, p.z)
	immersion = surface - p.y


func body_scale() -> float:
	return keling.visual.scale.y


## Deep enough to float: the bed is out of reach and the body is in it.
func can_swim() -> bool:
	var s := body_scale()
	return bed_depth >= SWIM_DEPTH * s and immersion >= SWIM_DEPTH * s * 0.85


## Shallow enough to stand up again.
func can_stand() -> bool:
	return bed_depth < STAND_DEPTH * body_scale()


## How far under the surface the feet hang while afloat (`stroke` 0..1).
func float_depth(stroke: float) -> float:
	var line := keling.swim.waterline(stroke) if keling.swim else 0.8
	# The tipped-forward head sits a little lower than the rest pose says.
	return (line - 0.07 - 0.05 * stroke) * body_scale()


## Wading slows a Keling down once the water is past its knees.
func wade_factor() -> float:
	if immersion <= 0.0:
		return 1.0
	return lerpf(1.0, 0.55, smoothstep(0.18, 0.7, immersion / body_scale()))


## How strongly this Keling's wake shows on the water (WaterFX).
func wake_strength() -> float:
	if surface == -INF:
		return 0.0
	if _swim_amount > 0.05:
		return _swim_amount
	if immersion > 0.06:
		return clampf(immersion / (0.5 * body_scale()), 0.0, 1.0) * 0.7
	return 0.0


func swim_amount() -> float:
	return _swim_amount


## 0 treading water .. 1 paddling flat out.
func stroke_amount() -> float:
	return _stroke


## Forward push of the current paddle stroke (1 = average).
func stroke_surge() -> float:
	return 1.0 + 0.28 * maxf(sin(phase * 2.0 - 0.6), -0.4) * _stroke


# --- per frame ------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	PerfMeter.add(&"water", Time.get_ticks_usec() - t0)


func _physics_process_timed(delta: float) -> void:
	if keling == null:
		return
	if not keling.is_local:
		sense()
	var mode := keling.mode
	var swimming := mode == KelingController.Mode.SWIM
	var flat := Vector2(keling.velocity.x, keling.velocity.z)
	var speed := flat.length()

	if mode != _prev_mode:
		_on_mode_changed(_prev_mode, mode)
		_prev_mode = mode
	if mode == KelingController.Mode.AIR:
		_air_vy = keling.velocity.y

	_update_swim_pose(delta, swimming, speed)
	if surface != -INF and immersion > 0.0:
		wetness = maxf(wetness, clampf(immersion / (0.75 * body_scale()), 0.0, 1.0))
		_can_shake = wetness > 0.55
	elif wetness > 0.0:
		wetness = maxf(wetness - delta * 0.16, 0.0)

	if swimming:
		_swim_fx(delta, speed)
	elif surface != -INF and immersion > 0.015 and mode != KelingController.Mode.AIR:
		_step_fx(delta, speed)
	else:
		_since_step = [1.0, 1.0]
	_drip_and_shake(delta, speed)


func _on_mode_changed(from: int, to: int) -> void:
	if to == KelingController.Mode.SWIM:
		if from == KelingController.Mode.AIR:
			# Into the deep from a jump or a fall: the bigger the drop, the bigger the splash.
			splash(keling.global_position, clampf(maxf(-_air_vy, 0.0) / 8.0, 0.3, 1.25), true)
		else:
			ripple_here(0.32)
			_sfx(&"bloop", -6.0)
	elif from == KelingController.Mode.SWIM:
		if to == KelingController.Mode.AIR:
			splash(keling.global_position, 0.35, false)
		else:
			ripple_here(0.3)
			_sfx(&"slosh", -5.0, 0.15)


## Called on landing (locally from the controller, for puppets by Net).
func on_landed(impact: float) -> void:
	if surface == -INF or immersion <= 0.015:
		return
	splash(keling.global_position, clampf(0.25 + impact / 14.0, 0.25, 0.9), false)


func ripple_here(strength: float) -> void:
	var p := keling.global_position
	WaterFX.ripple(Vector3(p.x, surface, p.z), strength)


## A splash at `at` (on the surface here): ring, droplets, sound. A plunge
## adds a crown of water and a puff of spray.
func splash(at: Vector3, strength: float, plunge: bool) -> void:
	if surface == -INF:
		return
	var p := Vector3(at.x, surface + 0.02, at.z)
	var s := body_scale()
	WaterFX.ripple(p, strength, 1.6 + strength * 1.2)
	_drops(p, int(8 + strength * 18), 1.4 + strength * 2.2, 0.08 * s)
	if plunge and strength > 0.45:
		_crown.global_position = p
		_crown.emission_ring_radius = 0.22 * s + 0.1 * strength
		_crown.emission_ring_inner_radius = _crown.emission_ring_radius * 0.6
		_crown.initial_velocity_min = 1.6 * strength
		_crown.initial_velocity_max = 3.6 * strength
		_crown.radial_accel_min = 0.6
		_crown.radial_accel_max = 2.4 * strength
		_crown.amount = int(18 + 26 * minf(strength, 1.2))
		_crown.restart()
		_crown.emitting = true
		_mist.global_position = p + Vector3.UP * 0.15
		_mist.restart()
		_mist.emitting = true
		_sfx(&"plunge", lerpf(-8.0, 0.0, clampf(strength - 0.4, 0.0, 1.0)))
		if keling.is_local:
			Input.vibrate_handheld(int(20 + 25 * minf(strength, 1.0)))
			if keling.camera_rig and strength > 0.8:
				keling.camera_rig.shake(0.18 * strength)
	else:
		_sfx(&"splash", lerpf(-12.0, -3.0, clampf(strength, 0.0, 1.0)), 0.1)


func _drops(at: Vector3, amount: int, speed: float, radius: float) -> void:
	var b := _bursts[_burst]
	_burst = (_burst + 1) % _bursts.size()
	b.global_position = at
	b.emission_sphere_radius = radius
	b.amount = clampi(amount, 2, 40)
	b.initial_velocity_min = speed * 0.45
	b.initial_velocity_max = speed
	b.restart()
	b.emitting = true


# --- wading -----------------------------------------------------------------

## A ripple, a few droplets and a splashy footstep each time a foot comes
## down in the water. Steps are found from the animation itself: a foot is
## planted the moment it stops swinging forward.
func _step_fx(delta: float, speed: float) -> void:
	var skel := keling._skeleton
	if skel == null:
		return
	if skel != _skel:
		_skel = skel
		_feet = [skel.find_bone("LeftFoot"), skel.find_bone("RightFoot")]
	for i in 2:
		_since_step[i] += delta
		var bone: int = _feet[i]
		if bone < 0:
			continue
		var z := _skel.get_bone_global_pose(bone).origin.z
		var vz: float = (z - _foot_z[i]) / maxf(delta, 0.001)
		_foot_z[i] = z
		var was: float = _foot_vz[i]
		_foot_vz[i] = vz
		if speed < 0.12 or _since_step[i] < 0.18:
			continue
		if was > 0.08 and vz <= 0.0:
			_since_step[i] = 0.0
			var foot := _skel.global_transform * _skel.get_bone_global_pose(bone).origin
			_footstep(foot, speed)


func _footstep(foot: Vector3, speed: float) -> void:
	var s := body_scale()
	var depth := clampf(immersion / s, 0.0, 1.0)
	var strength := clampf(0.12 + speed * 0.11 + depth * 0.35, 0.1, 0.75)
	var p := Vector3(foot.x, surface + 0.01, foot.z)
	WaterFX.ripple(p, strength, 1.3 + depth)
	if speed > 0.5:
		var fwd := Vector3(keling.velocity.x, 0.0, keling.velocity.z).normalized()
		_drops(p + fwd * 0.05, int(2 + speed * 4.0), 0.9 + speed * 0.7, 0.05 * s)
	var deep := depth > 0.28
	var db := lerpf(-20.0, -7.0, clampf(speed / keling.sprint_speed, 0.0, 1.0)) + (2.0 if deep else 0.0)
	_sfx(&"wade" if deep else &"step", db, 0.12)


# --- swimming ---------------------------------------------------------------

func _update_swim_pose(delta: float, swimming: bool, speed: float) -> void:
	_swim_amount = move_toward(_swim_amount, 1.0 if swimming else 0.0, delta * (3.0 if swimming else 4.0))
	var target_stroke := clampf(inverse_lerp(0.08, keling.swim_speed, speed), 0.0, 1.0) if swimming else 0.0
	_stroke = lerpf(_stroke, target_stroke, 1.0 - exp(-4.0 * delta))
	# Quicker paddling when going fast, a lazy rhythm when treading water.
	var hz := lerpf(0.9, 1.7, _stroke) + clampf(speed - keling.swim_speed, 0.0, 1.0) * 0.6
	phase = fmod(phase + delta * hz * TAU, TAU * 4.0)
	kick = fmod(kick + delta * lerpf(1.3, 3.2, _stroke) * TAU, TAU * 4.0)
	_roll = lerpf(_roll, clampf(-keling.turn_rate() * speed * 0.12, -0.22, 0.22), 1.0 - exp(-5.0 * delta))
	var swim := keling.swim
	if swim:
		swim.amount = smoothstep(0.0, 1.0, _swim_amount)
		swim.stroke = _stroke
		swim.phase = phase
		swim.kick = kick
		swim.roll = _roll
		swim.right_busy = 1.0 if keling.weed and keling.weed.has_joint() and keling.weed.act == KelingWeed.Act.NONE else 0.0


func _swim_fx(delta: float, speed: float) -> void:
	var s := body_scale()
	var fwd := Vector3(sin(keling.facing), 0.0, cos(keling.facing))
	var left := Vector3(fwd.z, 0.0, -fwd.x)
	# A paw breaks the surface as it reaches forward for the next stroke.
	if _stroke > 0.2:
		for side: float in [1.0, -1.0]:
			if side < 0.0 and keling.swim and keling.swim.right_busy > 0.5:
				continue
			var catch_at := PI * 0.5 + (0.0 if side > 0.0 else PI)
			if _crossed(_last_phase, phase, catch_at):
				var p := keling.global_position + fwd * 0.42 * s + left * side * 0.24 * s
				p.y = surface
				WaterFX.ripple(p, 0.14 + 0.2 * _stroke, 1.4)
				_drops(p + Vector3.UP * 0.03, int(2 + 4 * _stroke), 0.7 + 0.9 * _stroke, 0.04 * s)
				_sfx(&"stroke", lerpf(-19.0, -10.0, _stroke), 0.15)
	else:
		# Treading water: slow rings as the body bobs.
		_tread_t += delta
		if _tread_t > 1.3:
			_tread_t = 0.0
			ripple_here(0.12)
	_last_phase = phase


static func _crossed(a: float, b: float, at: float) -> bool:
	var span := wrapf(b - a, 0.0, TAU)
	var to := wrapf(at - a, 0.0, TAU)
	return span < PI and to > 0.0 and to <= span


# --- after a swim -----------------------------------------------------------

func _drip_and_shake(delta: float, speed: float) -> void:
	var out := surface == -INF or immersion < 0.0
	var dripping := out and wetness > 0.08 and not keling.is_sitting()
	if dripping:
		_drips.emission_box_extents = Vector3(0.2, 0.3 * wetness + 0.05, 0.18) * body_scale()
		_drips.position = Vector3(0, (0.25 + 0.3 * wetness) * body_scale(), 0)
	if _drips.emitting != dripping:
		_drips.emitting = dripping
	# A dog-style shake once it stops on dry land after a proper soaking.
	var standing := keling.mode == KelingController.Mode.GROUND and speed < 0.08 and not keling.wants_move()
	_still_t = _still_t + delta if out and standing and _can_shake else 0.0
	if _still_t > 0.35:
		_still_t = 0.0
		_can_shake = false
		wetness = minf(wetness, 0.15)
		keling.shake_off()
		var s := body_scale()
		_crown.global_position = keling.global_position + Vector3.UP * 0.6 * s
		_crown.emission_ring_radius = 0.3 * s
		_crown.emission_ring_inner_radius = 0.2 * s
		_crown.initial_velocity_min = 0.6
		_crown.initial_velocity_max = 1.6
		_crown.radial_accel_min = 4.0
		_crown.radial_accel_max = 8.0
		_crown.amount = 30
		_crown.restart()
		_crown.emitting = true
		_sfx(&"shake", -6.0, 0.1)


# --- sound ------------------------------------------------------------------

func _sfx(kind: StringName, db: float, pitch_jitter := 0.06) -> void:
	var names: Array = CLIPS.get(kind, [])
	if names.is_empty():
		return
	var stream: AudioStream = _streams.get(names.pick_random())
	if stream == null:
		return
	var v := _voices[_voice]
	_voice = (_voice + 1) % _voices.size()
	v.stream = stream
	v.volume_db = db
	v.pitch_scale = randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter) / sqrt(maxf(body_scale(), 0.2))
	v.global_position = keling.global_position + Vector3.UP * 0.2
	v.play()
