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
## herb (or just in front) with arm IK and a full finger grip. Near a bench
## the same button walks up, turns round and hops onto the seat to take in
## the view.
##
## In co-op the same scene stands in for a friend's Keling: make_remote()
## strips the camera and input, and KelingSync plays their snapshots back
## through the same animation, lean, look and sit layers.

signal jumped
signal landed(impact_speed: float, kind: StringName)
signal grabbed(target: Node)
signal sat_down(bench: Node)
signal stood_up(bench: Node)
## Something a friend's copy of this Keling should replay (grab, seat...).
signal net_event(kind: StringName, args: Array)
## Weed activity for co-op to mirror on this Keling's puppets: &"roll",
## &"light", &"puff", &"hold" or &"idle" (see KelingWeed.play_remote).
signal activity_changed(name: StringName, data: Dictionary)

enum Mode { GROUND, AIR, LAND, GRAB, SKID, TURN, EMOTE, SIT, CRAFT }

const FLOWER_SHADER := preload("res://player/keling_flower.gdshader")
## Hue turn and saturation of the crown flowers for each co-op colour slot
## (buttercup gold, coral, forget-me-not blue, lilac), matching the map dots.
const FLOWER_TINTS := [Vector2(0.0, 1.0), Vector2(-0.13, 0.78), Vector2(0.44, 0.82), Vector2(0.6, 0.62)]
enum SitPhase { APPROACH, ALIGN, DOWN, SEATED, UP }

## Hop onto and off a bench seat (seconds).
const SIT_DOWN_TIME := 0.75
const SIT_UP_TIME := 0.6

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
@onready var camera_rig: OrbitCamera = get_node_or_null("CameraRig")
@onready var leaf_puff: CPUParticles3D = $Visual/LeafPuff

var mode: int = Mode.GROUND
var facing := 0.0  ## yaw of the body (0 = +Z)
var procedural: KelingProcedural
var grab: KelingGrab
var sit: KelingSit
var weed: KelingWeed
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
var _held: Node3D  # whatever is in the fist after a pick: the sprig or a bud
var _bench: Bench
var _seat := -1
var _sit_phase: int = SitPhase.APPROACH
var _sit_t := 0.0
var _sit_from := Vector3.ZERO
var _sit_landed := false
var _hip_offset := Vector3.ZERO  # hip joint from the body origin (model space)

## Co-op identity. A friend's Keling has is_local false and is driven by
## `remote` instead of input and physics.
var is_local := true
var peer_id := 1
var player_index := 0
var player_name := ""
var remote: KelingSync
var _wants_move := false
var _remote_floor := true
var _remote_state: StringName = &""
var _remote_grab_hit := false
var _remote_grab_strain: StringName = &""
var _flower_mats: Array[ShaderMaterial] = []
var _tag: Label3D


func _ready() -> void:
	add_to_group("player")
	if is_local:
		add_to_group("local_player")
	facing = rotation.y
	rotation.y = 0.0
	visual.rotation.y = facing
	if camera_rig:
		camera_rig.set_yaw(facing + PI)
	animator.configure_speeds(walk_speed, jog_speed, sprint_speed)
	animator.state_finished.connect(_on_state_finished)
	_skeleton = model.find_child("Skeleton3D", true, false)
	_setup_rig()
	set_player(player_index, player_name)


func _setup_rig() -> void:
	# The procedural layer (breathing, look, crouch, foot IK) runs first and the
	# grab arm IK after it, so the hand lands on the target in the final pose.
	procedural = KelingProcedural.new()
	procedural.name = "Procedural"
	_skeleton.add_child(procedural)
	procedural.ray_exclude = [get_rid()]
	# The bench sit pose goes on top of breathing and look, under the grab.
	sit = KelingSit.new()
	sit.name = "Sit"
	_skeleton.add_child(sit)
	_hip_offset = _skeleton.get_bone_global_rest(_skeleton.find_bone("Hips")).origin
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

	# The flowers carry their colour in the vertices; each co-op player's
	# Keling wears its own colour of them.
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.mesh.surface_get_material(si)
			if m and m.resource_name == "Flower":
				var fm := ShaderMaterial.new()
				fm.shader = FLOWER_SHADER
				mi.set_surface_override_material(si, fm)
				_flower_mats.append(fm)

	# A sprig that appears in whichever hand just picked something.
	_sprig = Herb.build(0.16)
	_sprig.visible = false
	add_child(_sprig)
	_held = _sprig

	# Weed: the pouch, rolling and smoking (two-handed poses go on top).
	weed = KelingWeed.new()
	weed.setup(self, _skeleton)
	add_child(weed)


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
	var t0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	PerfMeter.add(&"player", Time.get_ticks_usec() - t0)


func _physics_process_timed(delta: float) -> void:
	if not is_local:
		_puppet_physics(delta)
		return
	_read_input()
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if not GameInput.ui_locked:
		if Input.is_action_just_pressed("jump"):
			_jump_buffer = jump_buffer_time
		_check_emote_input()
		if Input.is_action_just_pressed("grab"):
			try_grab()
		if Input.is_action_just_pressed("weed"):
			weed.use()
		if Input.is_action_just_pressed("weed_cycle"):
			weed.cycle_strain()
	_jump_held = Input.is_action_pressed("jump") and not GameInput.ui_locked

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
		Mode.SIT:
			_sit_mode(delta)
		Mode.CRAFT:
			_craft_mode(delta)

	# On the seat the body is placed by hand: no gravity, no sliding.
	if mode == Mode.SIT and _sit_phase >= SitPhase.DOWN:
		velocity = Vector3.ZERO
		_update_visuals(delta)
		return

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
	_wants_move = _desired_speed() > 0.0


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
		# From a standstill, a gentle push the other way is a proper turn on the
		# spot; asking to run pivots and pushes off straight away instead.
		var wants_run := target_speed > walk_speed * 1.5
		if speed < 0.25 and absf(diff) > turn_in_place_angle and not wants_run and animator.current_state() == &"Move":
			_start_turn(diff)
			return
		# At speed, throwing the stick backwards skids to a stop first.
		if speed > jog_speed * 0.85 and absf(diff) > reverse_skid_angle:
			_start_skid()
			return
		_turn_towards(desired_yaw, speed, delta)
		var heading := Vector3(sin(facing), 0.0, cos(facing))
		# Run where we face, easing off the throttle while still swinging round.
		# Slow or stopped, the body pivots while the feet already push off
		# towards the stick, so a turn-and-run flows as one curve.
		var align := clampf(cos(wrapf(desired_yaw - facing, -PI, PI)), 0.0, 1.0)
		var accel := sprint_acceleration if target_speed > jog_speed else acceleration
		var pivot := 1.0 - clampf(speed / jog_speed, 0.0, 1.0)
		var dir := heading.lerp(_input_dir.normalized(), pivot * (1.0 - align)).normalized()
		var throttle := lerpf(lerpf(0.35, 0.55, pivot), 1.0, align)
		_approach_velocity(dir * target_speed * throttle, accel, delta)
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
				var clip := animator.play_fidget()
				if clip != &"":
					net_event.emit(&"fidget", [clip])
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
## Next to a bench it sits down instead, and on a bench it stands back up.
func try_grab() -> void:
	if weed and weed.busy():
		return
	if mode == Mode.SIT:
		stand_up()
		return
	if try_sit():
		return
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
	var strain: StringName = (best as WeedBud).strain if best is WeedBud else &""
	net_event.emit(&"grab", [_grab_point, _grab_right, best != null, strain])


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
		net_event.emit(&"grab_cancel", [])
		_back_to_ground()
		return
	if not grab.grabbing:
		_back_to_ground()


func _on_gripped() -> void:
	if _grab_target and is_instance_valid(_grab_target):
		if _grab_target.has_method("on_grabbed"):
			_grab_target.on_grabbed()
		_held = _sprig
		if _grab_target is WeedBud and weed:
			_held = weed.fist_bud((_grab_target as WeedBud).strain)
		grabbed.emit(_grab_target)
		_held.visible = true
	elif not is_local and _remote_grab_hit:
		# A friend's pick: the right bud in their fist (the world event takes
		# it off the plant).
		_held = weed.fist_bud(_remote_grab_strain) if weed and _remote_grab_strain != &"" else _sprig
		_held.visible = true
	if is_local:
		Input.vibrate_handheld(15)


# --- benches -----------------------------------------------------------------

## Walks to the nearest free bench seat in reach and sits down. Returns true
## if a seat was taken.
func try_sit() -> bool:
	if mode not in [Mode.GROUND, Mode.EMOTE] or not is_on_floor() or (grab and grab.grabbing):
		return false
	var found := Bench.find_free_seat(get_tree(), global_position)
	if found.is_empty() or not (found.bench as Bench).claim(found.seat, self):
		return false
	_bench = found.bench
	_seat = found.seat
	net_event.emit(&"seat", [_bench.site.get("id", ""), _seat])
	mode = Mode.SIT
	_sit_phase = SitPhase.APPROACH
	_sit_t = 0.0
	_emote = &""
	animator.travel(&"Move")
	animator.cancel_fidget()
	return true


## Hops off the bench (or gives up walking to it).
func stand_up() -> void:
	if mode != Mode.SIT:
		return
	if _sit_phase < SitPhase.DOWN:
		_leave_bench()
		_back_to_ground()
	elif _sit_phase == SitPhase.SEATED or (_sit_phase == SitPhase.DOWN and _sit_t > SIT_DOWN_TIME * 0.6):
		_begin_stand()


func is_sitting() -> bool:
	if not is_local:
		return sit != null and sit.amount > 0.5
	return mode == Mode.SIT and _sit_phase >= SitPhase.DOWN


## The bench this Keling is sitting on, if any.
func current_bench() -> Bench:
	return _bench if is_sitting() and _sit_phase == SitPhase.SEATED else null


# --- weed --------------------------------------------------------------------

## Stops to roll or smoke: standing still on the ground, or seated on a bench.
## Returns false when the Keling is busy (mid-air, grabbing, hopping up...).
func begin_weed_act() -> bool:
	if mode == Mode.SIT:
		return _sit_phase == SitPhase.SEATED
	if mode not in [Mode.GROUND, Mode.EMOTE, Mode.CRAFT] or not is_on_floor():
		return false
	mode = Mode.CRAFT
	_emote = &""
	animator.travel(&"Move")
	animator.cancel_fidget()
	return true


func weed_act_allowed() -> bool:
	return mode == Mode.CRAFT or (mode == Mode.SIT and _sit_phase == SitPhase.SEATED)


## The bench power in play: the view tag of the bench we sit on, or none.
func weed_element() -> StringName:
	var b := current_bench()
	return StringName(b.site.get("element", &"none")) if b else &"none"


## Co-op: replays another player's weed activity on this (puppet) Keling.
func play_remote_activity(activity: StringName, data: Dictionary) -> void:
	if weed:
		weed.play_remote(activity, data)


func _craft_mode(delta: float) -> void:
	_approach_velocity(Vector3.ZERO, braking, delta)
	animator.update_locomotion(_flat_velocity().length(), false, delta)
	# Walking off or jumping puts it away; the weed keeps the bud or the puff.
	if _desired_speed() > 0.0 or _jump_buffer > 0.0:
		weed.interrupt()
		_back_to_ground()
		_try_jump()
		return
	if not weed.busy():
		_back_to_ground()


func _sit_mode(delta: float) -> void:
	if _bench == null or not is_instance_valid(_bench):
		_leave_bench()
		_back_to_ground()
		return
	_sit_t += delta
	var stand := _bench.stand_point(_seat)
	var seat_yaw := _bench.facing_yaw()
	match _sit_phase:
		SitPhase.APPROACH:
			# Walk (or trot) up to the front of the seat.
			var to := stand - global_position
			to.y = 0.0
			var d := to.length()
			if _desired_speed() > 0.0 and _sit_t > 0.3:
				_leave_bench()
				_back_to_ground()
				return
			if d < 0.06 or _sit_t > 4.0:
				_sit_phase = SitPhase.ALIGN
				_sit_t = 0.0
			else:
				var speed := clampf(d * 2.2, 0.3, walk_speed * 2.2)
				_turn_towards(atan2(to.x, to.z), speed, delta)
				var vel := to / d * minf(speed, d / maxf(delta, 0.001))
				_approach_velocity(vel, acceleration * 1.5, delta)
			animator.update_locomotion(_flat_velocity().length(), d > 0.06, delta)
		SitPhase.ALIGN:
			# Turn round to put our back to the bench.
			_approach_velocity(Vector3.ZERO, braking * 2.0, delta)
			_turn_towards(seat_yaw, 0.0, delta)
			animator.update_locomotion(_flat_velocity().length(), false, delta)
			if absf(wrapf(seat_yaw - facing, -PI, PI)) < 0.08 or _sit_t > 1.2:
				_sit_phase = SitPhase.DOWN
				_sit_t = 0.0
				_sit_from = global_position
				_sit_landed = false
		SitPhase.DOWN:
			# A little crouch and a hop back up onto the seat.
			var t := clampf(_sit_t / SIT_DOWN_TIME, 0.0, 1.0)
			facing = lerp_angle(facing, seat_yaw, 1.0 - exp(-14.0 * delta))
			_place_on_seat(_sit_from, smoothstep(0.15, 0.85, t))
			sit.amount = smoothstep(0.1, 0.75, t)
			sit.legs = smoothstep(0.35, 0.95, t)
			sit.hop = sin(clampf((t - 0.15) / 0.6, 0.0, 1.0) * PI) * 0.07 - (1.0 - smoothstep(0.0, 0.2, t)) * 0.03 * t * 5.0
			if not _sit_landed and t > 0.72:
				_sit_landed = true
				_kick_squash(-0.07)
				_kick_compression(0.03)
				Input.vibrate_handheld(12)
				var ignore: Array[RID] = [_bench.body.get_rid()]
				camera_rig.frame_view(_bench.view_point, _bench.site.get("cam", 3.4), ignore)
				BenchCaption.show_for(get_tree(), _bench)
				sat_down.emit(_bench)
			if t >= 1.0:
				_sit_phase = SitPhase.SEATED
				_sit_t = 0.0
		SitPhase.SEATED:
			_place_on_seat(_sit_from, 1.0)
			sit.amount = 1.0
			sit.legs = 1.0
			sit.hop = 0.0
			if _desired_speed() > 0.0 or _jump_buffer > 0.0:
				_begin_stand()
		SitPhase.UP:
			# Scoot forward and drop back onto our feet.
			var t := clampf(_sit_t / SIT_UP_TIME, 0.0, 1.0)
			_place_on_seat(_sit_from, 1.0 - smoothstep(0.1, 0.8, t))
			sit.amount = 1.0 - smoothstep(0.2, 0.9, t)
			sit.legs = 1.0 - smoothstep(0.0, 0.45, t)
			sit.hop = sin(clampf(t / 0.7, 0.0, 1.0) * PI) * 0.05
			if t >= 1.0:
				_jump_buffer = 0.0
				_kick_compression(0.03)
				_leave_bench()
				_back_to_ground()


func _begin_stand() -> void:
	_sit_phase = SitPhase.UP
	_sit_t = 0.0
	_jump_buffer = 0.0
	if camera_rig:
		camera_rig.release_view()
	BenchCaption.dismiss(get_tree())


## Puts the body between where it stood (blend 0) and on the seat (blend 1),
## and tells the sit pose where the hips belong.
func _place_on_seat(from: Vector3, blend: float) -> void:
	var hip := _bench.hip_point(_seat)
	var off := Basis(Vector3.UP, facing) * Vector3(_hip_offset.x, 0.0, _hip_offset.z)
	var seated := Vector3(hip.x - off.x, from.y, hip.z - off.z)
	global_position = from.lerp(seated, blend)
	sit.hip_world = hip


func _leave_bench() -> void:
	if _bench and is_instance_valid(_bench):
		var was := _bench
		_bench.release(self)
		net_event.emit(&"unseat", [])
		if _sit_phase >= SitPhase.DOWN:
			stood_up.emit(was)
	_bench = null
	_seat = -1
	sit.amount = 0.0
	sit.legs = 0.0
	sit.hop = 0.0
	if camera_rig:
		camera_rig.release_view()


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
		# Step out of the turn as soon as it roughly faces the way to go: the
		# ground move finishes the swing while already walking.
		if (progress > 0.22 and remaining < deg_to_rad(60.0)) or _desired_speed() > walk_speed * 1.5:
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
	if kind == &"hard" and camera_rig:
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
		var walking := mode in [Mode.GROUND, Mode.LAND, Mode.TURN, Mode.SKID, Mode.EMOTE, Mode.GRAB, Mode.CRAFT] or (mode == Mode.SIT and _sit_phase < SitPhase.DOWN)
		procedural.ik_enabled = walking and (is_on_floor() if is_local else _remote_floor)
		procedural.ik_weight = 1.0 - clampf(inverse_lerp(jog_speed, sprint_speed, speed), 0.0, 0.7)
		procedural.crouch = grab.crouch_amount() * 0.1 if grab else 0.0
		if is_local:
			_update_look()


## Places the picked sprig in the closed fist: stem through the fingers, bud up.
## Runs when the grab modifier has finished, so it follows the IK'd hand.
func _update_sprig() -> void:
	if _held == null:
		return
	if grab == null or not grab.holding:
		_held.visible = false
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
	_held.global_transform = Transform3D(rot, fist - up * 0.07)


func _update_look() -> void:
	# Look where the player steers before the body gets there; when idle,
	# glance towards where the camera is looking. The head has no neck to
	# speak of, so it only turns a little.
	var target_yaw := 0.0
	var target_pitch := 0.0
	if is_sitting() and _bench:
		# Drink in the view, glancing now and then towards the camera.
		var to := _bench.view_point - (global_position + Vector3(0, 1.1, 0))
		target_yaw = wrapf(atan2(to.x, to.z) - facing, -PI, PI)
		target_pitch = clampf(-atan2(to.y, Vector2(to.x, to.z).length()) * 0.6, -0.12, 0.2)
		if sin(Time.get_ticks_msec() * 0.00041) > 0.93:
			target_yaw += 0.25
	elif mode == Mode.CRAFT:
		target_pitch = 0.14  # eyes on the hands
	elif mode == Mode.GRAB:
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


## True while the player is steering somewhere (the gait wants to walk).
func wants_move() -> bool:
	return _wants_move


func current_bench_id() -> String:
	return String(_bench.site.get("id", "")) if _bench and is_instance_valid(_bench) else ""


func current_seat() -> int:
	return _seat


# --- co-op -------------------------------------------------------------------

## Colour slot (0..3) and name of whoever plays this Keling: tints the crown
## flowers to match their map dot, and floats a name over a friend's head.
func set_player(slot: int, display_name: String) -> void:
	player_index = slot
	player_name = display_name
	var tint: Vector2 = FLOWER_TINTS[clampi(slot, 0, 3)]
	for fm in _flower_mats:
		fm.set_shader_parameter("hue_shift", tint.x)
		fm.set_shader_parameter("saturation", tint.y)
	if is_local or not is_inside_tree():
		return
	if _tag == null:
		_tag = Label3D.new()
		_tag.name = "NameTag"
		_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		# Same size on screen near or far, like a name you can always read.
		_tag.fixed_size = true
		_tag.pixel_size = 0.0007
		_tag.font = HudTheme.title_font(600)
		_tag.font_size = 44
		_tag.outline_size = 14
		_tag.position = Vector3(0, 1.58, 0)
		_tag.render_priority = 5
		_tag.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
		add_child(_tag)
	_tag.text = display_name
	_tag.modulate = HudTheme.PLAYER_COLORS[clampi(slot, 0, 3)].lightened(0.25)
	_tag.outline_modulate = Color(0.04, 0.08, 0.05, 0.85)


## Turns this Keling into a friend's: no camera, no input, no physics of its
## own. Call before it enters the tree.
func make_remote(id: int, slot: int, display_name: String) -> void:
	is_local = false
	peer_id = id
	player_index = slot
	player_name = display_name
	remote = KelingSync.new()
	var rig := get_node_or_null("CameraRig")
	if rig:
		remove_child(rig)
		rig.free()


## Drops this (local) Keling at `pos` facing `yaw`: used when joining a friend.
func arrive_at(pos: Vector3, yaw: float) -> void:
	if mode == Mode.SIT:
		_leave_bench()
	if grab and grab.grabbing:
		grab.cancel()
	global_position = pos
	velocity = Vector3.ZERO
	facing = yaw
	visual.rotation.y = facing
	mode = Mode.GROUND
	_emote = &""
	animator.travel(&"Move")
	reset_physics_interpolation()
	if camera_rig:
		camera_rig.set_yaw(facing + PI)
		camera_rig.snap()
	_puff(0.8)


## Someone with a lower id took our seat at the same moment: step back.
func yield_seat() -> void:
	if mode != Mode.SIT:
		return
	_leave_bench()
	_back_to_ground()
	if is_on_floor():
		play_emote(&"Surprise")


## Replays an event from the real Keling on this puppet.
func apply_net_event(kind: StringName, args: Array) -> void:
	match kind:
		&"jump":
			_kick_squash(0.09)
		&"land":
			var strength := clampf(float(args[0]) / 12.0, 0.15, 1.0)
			_kick_compression(0.035 + 0.05 * strength)
			_kick_squash(-0.08 * strength)
			_puff(strength)
		&"grab":
			_grab_point = args[0]
			_grab_right = args[1]
			_remote_grab_hit = args[2]
			_remote_grab_strain = StringName(args[3]) if args.size() > 3 else &""
			if grab:
				grab.start(_grab_point, "Right" if _grab_right else "Left")
		&"grab_cancel":
			if grab:
				grab.cancel()
		&"fidget":
			animator.play_fidget(args[0])
		&"seat":
			_remote_seat(String(args[0]), int(args[1]))
		&"unseat":
			if _bench and is_instance_valid(_bench):
				_bench.release(self)
			_bench = null
			_seat = -1


func _remote_seat(bench_id: String, seat: int) -> void:
	if _bench and is_instance_valid(_bench):
		_bench.release(self)
	_bench = null
	_seat = -1
	for n in get_tree().get_nodes_in_group("bench"):
		var b := n as Bench
		if b == null or String(b.site.get("id", "")) != bench_id or seat < 0 or seat >= b.occupants.size():
			continue
		var holder = b.occupants[seat]
		if holder != null and is_instance_valid(holder) and holder != self:
			# Both hopped for the same seat: the lower id keeps it.
			if holder.get("is_local") == true and peer_id < int(holder.peer_id):
				holder.yield_seat()
			else:
				return
		if b.claim(seat, self):
			_bench = b
			_seat = seat
		return


func _puppet_physics(delta: float) -> void:
	if remote == null:
		return
	var s := remote.sample()
	if s.is_empty():
		return
	var prev := facing
	global_position = s.pos
	if s.teleport:
		reset_physics_interpolation()
		prev = s.facing
	velocity = s.vel
	facing = s.facing
	_yaw_rate = lerpf(_yaw_rate, wrapf(facing - prev, -PI, PI) / maxf(delta, 0.001), 1.0 - exp(-12.0 * delta))
	mode = s.mode
	_remote_floor = s.floor
	_wants_move = s.moving
	# Follow their state changes, but let our own animator run states on to
	# their next (JumpStart into Fall...) without being dragged back.
	if s.state != _remote_state:
		_remote_state = s.state
		animator.travel(s.state)
	animator.update_locomotion(_flat_velocity().length(), s.moving, delta)
	if _bench and is_instance_valid(_bench) and s.sit > 0.001:
		sit.hip_world = _bench.hip_point(_seat)
		sit.amount = s.sit
		sit.legs = s.legs
		sit.hop = s.hop
	else:
		sit.amount = 0.0
		sit.legs = 0.0
		sit.hop = 0.0
	# Size comes from their high; replayed puffs grow ours in step, so only
	# catch up from the snapshot when we didn't see the puff (joined late).
	if absf(s.scale - visual.scale.y) > 0.001 and not (weed and weed.high and weed.high.active()):
		visual.scale = Vector3.ONE * clampf(s.scale, 0.2, 5.0)
	_update_visuals(delta)
	procedural.look_yaw = s.look_yaw
	procedural.look_pitch = s.look_pitch
	_update_tag()


func _update_tag() -> void:
	if _tag == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var d := cam.global_position.distance_to(global_position)
	var a := (1.0 - smoothstep(16.0, 28.0, d)) * smoothstep(0.8, 1.6, d)
	_tag.visible = a > 0.01
	_tag.modulate.a = a
	_tag.outline_modulate.a = 0.85 * a
	_tag.position.y = 1.58 * visual.scale.y + (0.12 if is_sitting() or sit.amount > 0.5 else 0.0)


## For HUD/debug.
func get_debug_text() -> String:
	return "mode %s  anim %s\nspeed %.2f m/s  cadence x%.2f\nexertion %.2f  bank %.1f°" % [
		Mode.keys()[mode], animator.current_state(), _flat_velocity().length(),
		animator.get("parameters/Move/cadence/scale"), _exertion, rad_to_deg(_bank)]
