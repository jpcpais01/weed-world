class_name KelingController
extends CharacterBody3D
## Third-person controller for a Keling.
##
## Movement is camera relative and analog: a light push walks, a full push
## jogs, sprint runs. The body turns with a speed-dependent turn rate and runs
## where it faces, so it carves arcs and banks into them at speed. Standing
## turns use real turn-in-place steps (root motion), reversing at full tilt
## skids, and landings pick between a soft absorb and a crouch land
## depending on impact speed. The grab action reaches out for the nearest
## herb (or just in front) with arm IK and a full finger grip.

signal jumped
signal landed(impact_speed: float, kind: StringName)
signal grabbed(target: Node)

enum Mode { GROUND, AIR, LAND, GRAB, SKID, TURN, EMOTE }

@export_group("Speeds")
@export var walk_speed := 0.45
@export var jog_speed := 1.6
@export var sprint_speed := 2.8
@export var acceleration := 6.5
@export var sprint_acceleration := 4.5
@export var braking := 9.0
@export var skid_braking := 7.5
@export var air_control := 0.3

@export_group("Turning")
## Turn rate (rad/s) at walking pace and at sprint.
@export var turn_rate_slow := 10.0
@export var turn_rate_fast := 4.2
@export var turn_in_place_angle := deg_to_rad(70.0)
@export var reverse_skid_angle := deg_to_rad(135.0)
@export var max_bank := deg_to_rad(13.0)

@export_group("Jump")
@export var jump_height := 0.8
@export var gravity := 19.0
@export var fall_gravity_scale := 1.6
@export var jump_cut_gravity_scale := 2.4
@export var coyote_time := 0.12
@export var jump_buffer_time := 0.15
@export var max_fall_speed := 20.0
## Impact speed (m/s) that triggers a crouch landing.
@export var hard_land_speed := 10.0

@onready var visual: Node3D = $Visual
@onready var model: Node3D = $Visual/Model
@onready var animator: KelingAnimator = $Visual/AnimationTree
@onready var camera_rig: OrbitCamera = $CameraRig
@onready var leaf_puff: CPUParticles3D = $Visual/LeafPuff

var mode: int = Mode.GROUND
var facing := 0.0  ## yaw of the body (0 = +Z)
var procedural: KelingProcedural
var grab: KelingGrab
var springs: SpringBoneSimulator3D

var _skeleton: Skeleton3D
var _coyote := 0.0
var _jump_buffer := 0.0
var _jump_held := false
var _air_time := 0.0
var _peak_fall_speed := 0.0
var _yaw_rate := 0.0
var _bank := 0.0
var _accel_pitch := 0.0
var _prev_speed := 0.0
var _exertion := 0.0
var _idle_time := 0.0
var _next_fidget := 8.0
var _turn_target := 0.0
var _turn_scale := 1.0
var _squash := 0.0
var _squash_vel := 0.0
var _compression := 0.0
var _compression_vel := 0.0
var _emote: StringName = &""
var _input_dir := Vector3.ZERO
var _input_strength := 0.0
var _grab_target: Node3D
var _grab_point := Vector3.ZERO
var _grab_right := true
var _sprig: Node3D


func _ready() -> void:
	add_to_group("player")
	facing = rotation.y
	rotation.y = 0.0
	visual.rotation.y = facing
	camera_rig.set_yaw(facing + PI)
	animator.configure_speeds(walk_speed, jog_speed, sprint_speed)
	animator.state_finished.connect(_on_state_finished)
	_skeleton = model.find_child("Skeleton3D", true, false)
	_setup_rig()


func _setup_rig() -> void:
	# The procedural layer (breathing, look, crouch, foot IK) runs first and the
	# grab arm IK after it, so the hand lands on the target in the final pose.
	procedural = KelingProcedural.new()
	procedural.name = "Procedural"
	_skeleton.add_child(procedural)
	procedural.ray_exclude = [get_rid()]
	grab = KelingGrab.new()
	grab.name = "Grab"
	_skeleton.add_child(grab)
	grab.gripped.connect(_on_gripped)
	grab.modification_processed.connect(_update_sprig)

	# Secondary motion: the leafy crown and its flower stalks bounce.
	springs = SpringBoneSimulator3D.new()
	springs.name = "Springs"
	var chains := ["Crown_FrontR", "Crown_FrontC", "Crown_FrontL", "Crown_Top", "Crown_BackL", "Crown_SideR"]
	springs.setting_count = chains.size()
	for i in chains.size():
		var tip_len := 0.16 if chains[i] != "Crown_Top" else 0.23
		_spring(i, chains[i] + "_1", chains[i] + "_2", tip_len, 1.1 if chains[i] == "Crown_Top" else 1.5, 0.28, 0.04, 0.035)
	_skeleton.add_child(springs)

	# The flowers carry their colour in the vertices.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m and m.resource_name == "Flower":
				var fm := StandardMaterial3D.new()
				fm.vertex_color_use_as_albedo = true
				fm.roughness = 0.45
				fm.cull_mode = BaseMaterial3D.CULL_DISABLED
				fm.backlight_enabled = true
				fm.backlight = Color(0.55, 0.42, 0.05)
				mi.set_surface_override_material(si, fm)

	# A sprig that appears in whichever hand just picked something.
	_sprig = Herb.build(0.16)
	_sprig.visible = false
	add_child(_sprig)


func _spring(i: int, root: String, end: String, tip: float, stiffness: float, drag: float, grav: float, radius: float) -> void:
	springs.set_root_bone_name(i, root)
	springs.set_end_bone_name(i, end)
	springs.set_extend_end_bone(i, true)
	springs.set_end_bone_direction(i, SkeletonModifier3D.BONE_DIRECTION_PLUS_Y)
	springs.set_end_bone_length(i, tip)
	springs.set_stiffness(i, stiffness)
	springs.set_drag(i, drag)
	springs.set_gravity(i, grav)
	springs.set_gravity_direction(i, Vector3.DOWN)
	springs.set_radius(i, radius)


func _physics_process(delta: float) -> void:
	_read_input()
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	_jump_held = Input.is_action_pressed("jump")
	_check_emote_input()
	if Input.is_action_just_pressed("grab"):
		try_grab()

	var on_floor := is_on_floor()
	_coyote = coyote_time if on_floor else maxf(_coyote - delta, 0.0)

	match mode:
		Mode.GROUND:
			_ground(delta)
		Mode.AIR:
			_air(delta)
		Mode.LAND:
			_land(delta)
		Mode.GRAB:
			_grab_mode(delta)
		Mode.SKID:
			_skid(delta)
		Mode.TURN:
			_turn(delta)
		Mode.EMOTE:
			_emote_mode(delta)

	if mode != Mode.AIR:
		velocity.y = -1.0 if on_floor else velocity.y - gravity * delta
		if not on_floor and mode != Mode.TURN and _coyote <= 0.0:
			_enter_air(false)

	var fall_speed := -velocity.y
	move_and_slide()
	if mode == Mode.AIR and is_on_floor() and _air_time > 0.04:
		_on_landed(maxf(fall_speed, _peak_fall_speed))

	_update_visuals(delta)


# --- input -----------------------------------------------------------------

func _read_input() -> void:
	var v := GameInput.get_move_vector()
	_input_strength = minf(v.length(), 1.0)
	var basis := camera_rig.get_flat_basis()
	var dir := basis * Vector3(v.x, 0.0, v.y)
	dir.y = 0.0
	_input_dir = dir.normalized() if dir.length_squared() > 0.0001 else Vector3.ZERO


func _desired_speed() -> float:
	if _input_strength < 0.05:
		return 0.0
	if GameInput.is_sprinting() and _input_strength > 0.45:
		return sprint_speed
	if GameInput.walk_toggled:
		return walk_speed * clampf(_input_strength * 1.4, 0.5, 1.0)
	if _input_strength < 0.6:
		return lerpf(walk_speed * 0.55, walk_speed, inverse_lerp(0.05, 0.6, _input_strength))
	return lerpf(walk_speed, jog_speed, inverse_lerp(0.6, 0.95, minf(_input_strength, 0.95)))


func _check_emote_input() -> void:
	for pair in [["emote_dance", &"Dance"], ["emote_cheer", &"Cheer"], ["emote_sit", &"SitDown"], ["emote_nod", &"Nod"]]:
		if Input.is_action_just_pressed(pair[0]):
			play_emote(pair[1])


## Starts an emote if the Keling is standing on the ground.
func play_emote(emote: StringName) -> void:
	if mode == Mode.EMOTE and _emote == emote:
		return
	if mode not in [Mode.GROUND, Mode.EMOTE] or not is_on_floor():
		return
	mode = Mode.EMOTE
	_emote = emote
	animator.travel(emote)


# --- modes -----------------------------------------------------------------

func _ground(delta: float) -> void:
	var speed := _flat_velocity().length()
	if _try_jump():
		return
	var target_speed := _desired_speed()
	if target_speed > 0.0:
		_idle_time = 0.0
		var desired_yaw := atan2(_input_dir.x, _input_dir.z)
		var diff := wrapf(desired_yaw - facing, -PI, PI)
		# From a standstill, a big direction change is a proper turn on the spot.
		if speed < 0.25 and absf(diff) > turn_in_place_angle and animator.current_state() == &"Move":
			_start_turn(diff)
			return
		# At speed, throwing the stick backwards skids to a stop first.
		if speed > jog_speed * 0.85 and absf(diff) > reverse_skid_angle:
			_start_skid()
			return
		_turn_towards(desired_yaw, speed, delta)
		var heading := Vector3(sin(facing), 0.0, cos(facing))
		# Run where we face; ease off the throttle while still swinging around.
		var align := clampf(cos(wrapf(desired_yaw - facing, -PI, PI)), 0.0, 1.0)
		var accel := sprint_acceleration if target_speed > jog_speed else acceleration
		var target_vel := heading * target_speed * lerpf(0.35, 1.0, align)
		_approach_velocity(target_vel, accel, delta)
	else:
		_yaw_rate = lerpf(_yaw_rate, 0.0, 1.0 - exp(-10.0 * delta))
		if speed > sprint_speed * 0.8:
			_start_skid()
			return
		_approach_velocity(Vector3.ZERO, braking, delta)
		if speed < 0.05:
			GameInput.sprint_toggled = false
			_idle_time += delta
			if _idle_time > _next_fidget:
				_idle_time = 0.0
				_next_fidget = randf_range(9.0, 16.0)
				animator.play_fidget()
	animator.update_locomotion(_flat_velocity().length(), target_speed > 0.0, delta)


func _air(delta: float) -> void:
	_air_time += delta
	var g := gravity
	if velocity.y < 0.0:
		g *= fall_gravity_scale
	elif not _jump_held:
		g *= jump_cut_gravity_scale
	velocity.y = maxf(velocity.y - g * delta, -max_fall_speed)
	_peak_fall_speed = maxf(_peak_fall_speed, -velocity.y)
	# Late jump press inside the coyote window.
	if _coyote > 0.0 and _jump_buffer > 0.0 and velocity.y <= 0.0:
		_do_jump()
		return
	var target_speed := _desired_speed()
	if target_speed > 0.0:
		var desired_yaw := atan2(_input_dir.x, _input_dir.z)
		_turn_towards(desired_yaw, _flat_velocity().length() * 1.6, delta)
		var target := _input_dir * maxf(target_speed, _flat_velocity().length())
		_approach_velocity(target, acceleration * air_control, delta)
	if animator.current_state() == &"JumpStart" and velocity.y < -1.5 and animator.state_progress() > 0.45:
		animator.travel(&"Fall")


func _land(delta: float) -> void:
	_approach_velocity(Vector3.ZERO, braking * 1.5, delta)
	if _try_jump():
		return
	# Moving cancels the recovery once the knees have absorbed the impact.
	if _desired_speed() > 0.0 and animator.state_time() > 0.22:
		_back_to_ground()


## Reaches for the nearest herb in front (or just in front of the Keling).
func try_grab() -> void:
	if mode not in [Mode.GROUND, Mode.EMOTE] or not is_on_floor() or grab == null or grab.grabbing:
		return
	var heading := Vector3(sin(facing), 0.0, cos(facing))
	var best: Node3D = null
	var best_d := 1.4
	for n in get_tree().get_nodes_in_group("grabbable"):
		var node := n as Node3D
		if node == null or (node.has_method("can_grab") and not node.can_grab()):
			continue
		var p: Vector3 = node.grab_point() if node.has_method("grab_point") else node.global_position
		var to := p - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > best_d or to.y < 0.2 or to.y > 1.2:
			continue
		if flat.length() > 0.2 and flat.normalized().dot(heading) < -0.3:
			continue
		best = node
		best_d = flat.length()
	_grab_target = best
	if best:
		_grab_point = best.grab_point() if best.has_method("grab_point") else best.global_position
	else:
		_grab_point = global_position + heading * 0.36 + Vector3(0, 0.55, 0)
	_grab_right = not _grab_right
	mode = Mode.GRAB
	_emote = &""
	animator.travel(&"Move")
	animator.cancel_fidget()
	var to := _grab_point - global_position
	var local_x := to.dot(Vector3(cos(facing), 0.0, -sin(facing)))
	if absf(local_x) > 0.08:
		_grab_right = local_x < 0.0
	grab.start(_grab_point, "Right" if _grab_right else "Left")


func _grab_mode(delta: float) -> void:
	# Step up to arm's length and face the target while winding up.
	var to := _grab_point - global_position
	var flat := Vector3(to.x, 0.0, to.z)
	var hand_offset := 0.2 * (1.0 if _grab_right else -1.0)  # turn so the target sits ahead of the reaching shoulder
	if flat.length() > 0.05:
		var yaw := atan2(flat.x, flat.z) + asin(clampf(hand_offset / maxf(flat.length(), 0.25), -0.9, 0.9))
		_turn_towards(yaw, 0.0, delta)
	var standoff := 0.44 if _grab_point.y - global_position.y < 0.85 else 0.27  # step under things overhead
	var vel := Vector3.ZERO
	if grab.time < 0.5 and flat.length() > standoff + 0.04:
		vel = flat.normalized() * minf((flat.length() - standoff) * 6.0, 1.2)
	_approach_velocity(vel, 12.0, delta)
	animator.update_locomotion(_flat_velocity().length(), vel != Vector3.ZERO, delta)
	if _jump_buffer > 0.0 or (_desired_speed() > 0.0 and grab.time > 1.3):
		grab.cancel()
		_back_to_ground()
		return
	if not grab.grabbing:
		_back_to_ground()


func _on_gripped() -> void:
	if _grab_target and is_instance_valid(_grab_target):
		if _grab_target.has_method("on_grabbed"):
			_grab_target.on_grabbed()
		grabbed.emit(_grab_target)
		_sprig.visible = true
	Input.vibrate_handheld(15)


func _skid(delta: float) -> void:
	_approach_velocity(Vector3.ZERO, skid_braking, delta)
	_yaw_rate = lerpf(_yaw_rate, 0.0, 1.0 - exp(-8.0 * delta))
	if _try_jump():
		return
	var speed := _flat_velocity().length()
	if _desired_speed() > 0.0:
		var desired_yaw := atan2(_input_dir.x, _input_dir.z)
		var diff := absf(wrapf(desired_yaw - facing, -PI, PI))
		# Pushing forward again recovers; a reversal waits until we've stopped.
		if diff < deg_to_rad(60.0) and animator.state_time() > 0.15:
			_back_to_ground()
		elif speed < 0.35:
			_back_to_ground()
			_start_turn(wrapf(desired_yaw - facing, -PI, PI))
	elif speed < 0.05 and animator.state_progress() > 0.6:
		_back_to_ground()
	animator.update_locomotion(0.0, false, delta)


func _turn(delta: float) -> void:
	velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-10.0 * delta))
	velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-10.0 * delta))
	# Root motion yaw from the turn clip, scaled to the exact angle we need.
	var rm := animator.get_root_motion_rotation()
	var step := rm.get_euler().y * _turn_scale
	facing = wrapf(facing + step, -PI, PI)
	_yaw_rate = step / maxf(delta, 0.001)
	if _try_jump():
		return
	var progress := animator.state_progress()
	if _desired_speed() > 0.0:
		var desired_yaw := atan2(_input_dir.x, _input_dir.z)
		var remaining := absf(wrapf(desired_yaw - facing, -PI, PI))
		if progress > 0.42 and remaining < deg_to_rad(35.0):
			_back_to_ground()
	elif progress > 0.62:
		_back_to_ground()


func _emote_mode(delta: float) -> void:
	_approach_velocity(Vector3.ZERO, braking, delta)
	var wants_move := _desired_speed() > 0.0
	var state := animator.current_state()
	if _jump_buffer > 0.0 and state != &"SitIdle" and state != &"SitDown":
		_back_to_ground()
		_try_jump()
		return
	if state == &"SitIdle" or state == &"SitDown":
		if wants_move or _jump_buffer > 0.0:
			animator.travel(&"SitUp")
		return
	if state == &"SitUp":
		if wants_move and animator.state_progress() > 0.7:
			_back_to_ground()
		return
	if wants_move:
		_back_to_ground()
	elif state == &"Move":
		mode = Mode.GROUND
		_emote = &""


# --- transitions -------------------------------------------------------------

func _try_jump() -> bool:
	if _jump_buffer > 0.0 and (is_on_floor() or _coyote > 0.0):
		_do_jump()
		return true
	return false


func _do_jump() -> void:
	_jump_buffer = 0.0
	_coyote = 0.0
	velocity.y = sqrt(2.0 * gravity * jump_height)
	# Keep running momentum, but give a little hop forward from a standstill.
	if _flat_velocity().length() < 0.3 and _input_dir != Vector3.ZERO:
		velocity += _input_dir * 0.6
	_enter_air(true)
	_kick_squash(0.09)
	jumped.emit()


func _enter_air(from_jump: bool) -> void:
	mode = Mode.AIR
	_air_time = 0.0
	_peak_fall_speed = 0.0
	_emote = &""
	animator.travel(&"JumpStart" if from_jump else &"Fall")


func _on_landed(impact: float) -> void:
	_air_time = 0.0
	var speed := _flat_velocity().length()
	var kind: StringName
	if impact > hard_land_speed or (speed < 0.5 and impact > 3.0):
		kind = &"hard" if impact > hard_land_speed else &"stand"
		mode = Mode.LAND
		animator.travel(&"Land")
	else:
		kind = &"soft"
		_back_to_ground()
	var strength := clampf(impact / 12.0, 0.15, 1.0)
	_kick_compression(0.035 + 0.05 * strength)
	_kick_squash(-0.08 * strength)
	_puff(strength)
	if kind == &"hard":
		camera_rig.shake(0.25 * strength)
	landed.emit(impact, kind)


func _on_state_finished(state: StringName) -> void:
	match state:
		&"Land", &"SprintStop", &"Turn90L", &"Turn90R", &"Turn180L", &"Turn180R":
			if mode != Mode.AIR:
				mode = Mode.GROUND
		&"Cheer", &"Nod", &"Surprise", &"SitUp":
			if mode == Mode.EMOTE:
				mode = Mode.GROUND
				_emote = &""


func _back_to_ground() -> void:
	mode = Mode.GROUND
	_emote = &""
	animator.travel(&"Move")


func _start_turn(diff: float) -> void:
	mode = Mode.TURN
	var big := absf(diff) > deg_to_rad(130.0)
	var clip_angle := PI if big else PI * 0.5
	_turn_scale = absf(diff) / clip_angle
	if diff > 0.0:
		animator.travel(&"Turn180L" if big else &"Turn90L")
	else:
		animator.travel(&"Turn180R" if big else &"Turn90R")


func _start_skid() -> void:
	mode = Mode.SKID
	animator.travel(&"SprintStop")
	_puff(0.5)


# --- helpers -----------------------------------------------------------------

func _flat_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _approach_velocity(target: Vector3, accel: float, delta: float) -> void:
	var flat := _flat_velocity()
	flat = flat.move_toward(target, accel * delta)
	velocity.x = flat.x
	velocity.z = flat.z


func _turn_towards(desired_yaw: float, speed: float, delta: float) -> void:
	var t := clampf(inverse_lerp(walk_speed, sprint_speed, speed), 0.0, 1.0)
	var max_rate := lerpf(turn_rate_slow, turn_rate_fast, t)
	var diff := wrapf(desired_yaw - facing, -PI, PI)
	# Critically-damped-ish: fast for big errors, gentle as it settles.
	var rate := clampf(diff * 9.0, -max_rate, max_rate)
	var step := clampf(rate * delta, -absf(diff), absf(diff))
	facing = wrapf(facing + step, -PI, PI)
	_yaw_rate = lerpf(_yaw_rate, step / maxf(delta, 0.001), 1.0 - exp(-12.0 * delta))


func _kick_squash(amount: float) -> void:
	_squash_vel += amount * 40.0


func _kick_compression(amount: float) -> void:
	_compression_vel += amount * 30.0


func _puff(strength: float) -> void:
	if leaf_puff == null:
		return
	leaf_puff.amount = int(lerpf(6, 22, strength))
	leaf_puff.restart()
	leaf_puff.emitting = true


func _update_visuals(delta: float) -> void:
	visual.rotation.y = facing
	var speed := _flat_velocity().length()

	# Bank into turns (pivoting at the feet), more at speed.
	var bank_target := 0.0
	if mode in [Mode.GROUND, Mode.AIR]:
		bank_target = clampf(-_yaw_rate * speed * 0.05, -max_bank, max_bank)
	_bank = lerpf(_bank, bank_target, 1.0 - exp(-6.0 * delta))

	# Forward lean from acceleration, back when braking.
	var accel := (speed - _prev_speed) / maxf(delta, 0.001)
	_prev_speed = speed
	var pitch_target := 0.0
	if mode == Mode.GROUND:
		pitch_target = clampf(accel * 0.035, -0.16, 0.2)
	_accel_pitch = lerpf(_accel_pitch, pitch_target, 1.0 - exp(-5.0 * delta))

	# Squash & stretch spring (y scale), volume-preserving-ish.
	_squash_vel += (-_squash * 180.0 - _squash_vel * 16.0) * delta
	_squash += _squash_vel * delta
	var sy := 1.0 + _squash
	var sxz := 1.0 - _squash * 0.45
	model.transform = Transform3D(Basis(Vector3.BACK, _bank).scaled(Vector3(sxz, sy, sxz)), Vector3.ZERO)

	# Landing compression of the hips (spring back up).
	_compression_vel += (-_compression * 220.0 - _compression_vel * 18.0) * delta
	_compression += _compression_vel * delta

	# Exertion builds while sprinting and slowly recovers.
	if speed > jog_speed * 1.1:
		_exertion = minf(_exertion + delta * 0.12, 1.0)
	else:
		_exertion = maxf(_exertion - delta * (0.05 if speed > 0.1 else 0.08), 0.0)

	if procedural:
		procedural.accel_pitch = _accel_pitch
		procedural.exertion = _exertion
		procedural.land_compression = maxf(_compression, 0.0)
		procedural.space_state = get_world_3d().direct_space_state
		procedural.ik_enabled = mode in [Mode.GROUND, Mode.LAND, Mode.TURN, Mode.SKID, Mode.EMOTE, Mode.GRAB] and is_on_floor()
		procedural.ik_weight = 1.0 - clampf(inverse_lerp(jog_speed, sprint_speed, speed), 0.0, 0.7)
		procedural.crouch = grab.crouch_amount() * 0.1 if grab else 0.0
		_update_look()


## Places the picked sprig in the closed fist: stem through the fingers, bud up.
## Runs when the grab modifier has finished, so it follows the IK'd hand.
func _update_sprig() -> void:
	if _sprig == null:
		return
	if grab == null or not grab.holding:
		_sprig.visible = false
		return
	var s := "Right" if _grab_right else "Left"
	var xf := _skeleton.global_transform
	var hand := xf * _skeleton.get_bone_global_pose(_skeleton.find_bone(s + "Hand")).origin
	var knuckle := xf * _skeleton.get_bone_global_pose(_skeleton.find_bone(s + "MiddleProximal")).origin
	var fingers := (knuckle - hand).normalized()
	var up := (Vector3.UP - fingers * Vector3.UP.dot(fingers)).normalized()
	if up.length_squared() < 0.01:
		up = Vector3.UP
	var rot := Basis(fingers.cross(up).normalized(), up, fingers).orthonormalized()
	var fist := knuckle.lerp(hand, 0.25) + fingers * 0.01
	_sprig.global_transform = Transform3D(rot, fist - up * 0.07)


func _update_look() -> void:
	# Look where the player steers before the body gets there; when idle,
	# glance towards where the camera is looking. The head has no neck to
	# speak of, so it only turns a little.
	var target_yaw := 0.0
	var target_pitch := 0.0
	if mode == Mode.GRAB:
		var to := _grab_point - (global_position + Vector3(0, 1.1, 0))
		target_yaw = wrapf(atan2(to.x, to.z) - facing, -PI, PI)
		target_pitch = clampf(-atan2(to.y, Vector2(to.x, to.z).length()) * 0.5, -0.15, 0.25)
	elif _input_dir != Vector3.ZERO and mode in [Mode.GROUND, Mode.TURN]:
		target_yaw = wrapf(atan2(_input_dir.x, _input_dir.z) - facing, -PI, PI)
	elif mode == Mode.GROUND and _flat_velocity().length() < 0.05:
		var cam_fwd := -camera_rig.get_flat_basis().z
		var rel := wrapf(atan2(cam_fwd.x, cam_fwd.z) - facing, -PI, PI)
		if absf(rel) < deg_to_rad(110.0):
			target_yaw = rel * 0.6
		target_pitch = clampf(-camera_rig.pitch * 0.35, -0.2, 0.25)
	procedural.look_yaw = clampf(target_yaw, -deg_to_rad(15.0), deg_to_rad(15.0))
	procedural.look_pitch = clampf(target_pitch, -0.12, 0.2)


## For HUD/debug.
func get_debug_text() -> String:
	return "mode %s  anim %s\nspeed %.2f m/s  cadence x%.2f\nexertion %.2f  bank %.1f°" % [
		Mode.keys()[mode], animator.current_state(), _flat_velocity().length(),
		animator.get("parameters/Move/cadence/scale"), _exertion, rad_to_deg(_bank)]
