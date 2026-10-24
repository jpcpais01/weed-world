class_name KelingAnimator
extends AnimationTree
## Builds and drives the Keling's animation graph.
##
## Root state machine:
##   Move ........ idle (+ random fidgets) blended into a phase-synced gait
##                 blend space (walk / jog / sprint) whose cadence follows the
##                 real ground speed, so feet don't slide.
##   JumpStart, Fall, Land, SprintStop, Turn90/180 L/R, emotes.
## (Grabbing is procedural on top of Move, see KelingGrab.)
## Every transition is a short crossfade; "play to end" behaviour is handled
## here in code so any state can still be interrupted instantly.

## Clip data measured from the retargeted animations (tools/foot_slip_test.gd):
## [cycle length s, natural speed m/s, left-foot-forward time s]
## Natural speed is how fast the planted foot sweeps back at 1x playback, so
## playing at speed / natural keeps planted feet still. Runs have very short
## contacts, so their natural speed sits a little under the contact sweep to
## keep the cadence lively.
const GAIT := {
	&"Walk": [1.333, 0.30, 1.27],
	&"Jog": [0.933, 1.85, 0.87],
	&"Sprint": [0.667, 3.0, 0.57],
}

## Play length (s) for clips that should run faster than authored.
const STRETCH := {
	&"Turn90L": 1.25, &"Turn90R": 1.25, &"Turn180L": 1.2, &"Turn180R": 1.2,
	&"Land": 0.95, &"SprintStop": 1.15, &"JumpStart": 1.15,
	&"SitDown": 1.7, &"SitUp": 1.5,
}

## Crossfade time into each state.
const XFADE := {
	&"Move": 0.22, &"JumpStart": 0.07, &"Fall": 0.3, &"Land": 0.06,
	&"SprintStop": 0.14, &"Turn90L": 0.16, &"Turn90R": 0.16, &"Turn180L": 0.16, &"Turn180R": 0.16,
	&"Dance": 0.35, &"Cheer": 0.3, &"SitDown": 0.3, &"SitIdle": 0.25, &"SitUp": 0.2,
	&"Nod": 0.3, &"Surprise": 0.2,
}

## States that hand over to another state when they finish.
const NEXT := {
	&"JumpStart": &"Fall", &"Land": &"Move", &"SprintStop": &"Move",
	&"Turn90L": &"Move", &"Turn90R": &"Move", &"Turn180L": &"Move", &"Turn180R": &"Move",
	&"Cheer": &"Move", &"Nod": &"Move", &"Surprise": &"Move", &"SitDown": &"SitIdle", &"SitUp": &"Move",
}

const LOOPING := [&"Fall", &"Dance", &"SitIdle"]
const FIDGETS := [&"IdleLookAround", &"IdleFoldArms"]

signal state_finished(state: StringName)

var walk_speed := 0.45
var jog_speed := 1.6
var sprint_speed := 2.8
## Natural gait speeds scale with leg length (KelingBody.gait_scale): longer
## legs cover more ground per step, so they step slower at the same speed.
var gait_scale := 1.0

var _playback: AnimationNodeStateMachinePlayback
var _fidget_node: AnimationNodeAnimation
var _move_amount := 0.0
var _state: StringName = &"Move"
var _state_time := 0.0


func _ready() -> void:
	tree_root = _build_tree()
	callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	root_motion_track = NodePath("SmartRigArmature/Skeleton3D:Root")
	active = true
	_playback = get("parameters/playback")
	_playback.start(&"Move")


func configure_speeds(walk: float, jog: float, sprint: float) -> void:
	walk_speed = walk
	jog_speed = jog
	sprint_speed = sprint
	var gait: AnimationNodeBlendSpace1D = (tree_root as AnimationNodeStateMachine).get_node(&"Move").get_node(&"gait")
	gait.set_blend_point_position(0, walk)
	gait.set_blend_point_position(1, jog)
	gait.set_blend_point_position(2, sprint)
	gait.max_space = sprint + 0.5


## Puts another character's clips in (same states, same skeleton layout).
func set_library(lib: AnimationLibrary) -> void:
	if has_animation_library(&""):
		remove_animation_library(&"")
	add_animation_library(&"", lib)
	clear_caches()


## Called every physics frame by the controller with the real ground speed.
func update_locomotion(ground_speed: float, wants_move: bool, delta: float) -> void:
	var target := clampf(inverse_lerp(0.04, walk_speed * 0.7, ground_speed), 0.0, 1.0)
	if not wants_move and ground_speed < walk_speed * 0.5:
		target = minf(target, ground_speed / maxf(walk_speed, 0.01))
	_move_amount = lerpf(_move_amount, target, 1.0 - exp(-14.0 * delta))
	set("parameters/Move/move/blend_amount", _move_amount)
	set("parameters/Move/gait/blend_position", maxf(ground_speed, walk_speed))
	set("parameters/Move/cadence/scale", _cadence(ground_speed))


## Plays an idle fidget once (look around, fold arms...): `clip`, or a random
## one. Returns the clip it played, or &"" if the Keling was busy.
func play_fidget(clip: StringName = &"") -> StringName:
	if _state != &"Move" or _move_amount > 0.05:
		return &""
	_fidget_node.animation = clip if clip in FIDGETS else FIDGETS.pick_random()
	set("parameters/Move/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return _fidget_node.animation


func cancel_fidget() -> void:
	if get("parameters/Move/fidget/active"):
		set("parameters/Move/fidget/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func travel(state: StringName) -> void:
	if state == _state:
		return
	_state = state
	_state_time = 0.0
	if state != &"Move":
		cancel_fidget()
	_playback.travel(state)


func current_state() -> StringName:
	return _state


func state_time() -> float:
	return _state_time


## 0..1 progress through the current (non looping) state.
func state_progress() -> float:
	var length := _playback.get_current_length()
	if _playback.get_current_node() != _state or length <= 0.0:
		return 0.0
	return clampf(_playback.get_current_play_position() / length, 0.0, 1.0)


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	PerfMeter.add(&"player anim", Time.get_ticks_usec() - t0)


func _physics_process_timed(delta: float) -> void:
	_state_time += delta
	if NEXT.has(_state) and _playback.get_current_node() == _state:
		var length := _playback.get_current_length()
		var next: StringName = NEXT[_state]
		if length > 0.0 and _playback.get_current_play_position() >= length - XFADE[next] * 0.5:
			var finished := _state
			travel(next)
			state_finished.emit(finished)


func _cadence(speed: float) -> float:
	# Blend weights of the 1D space, then the blended natural speed.
	var pts := [walk_speed, jog_speed, sprint_speed]
	var names := [&"Walk", &"Jog", &"Sprint"]
	var w := [0.0, 0.0, 0.0]
	if speed <= pts[0]:
		w[0] = 1.0
	elif speed >= pts[2]:
		w[2] = 1.0
	else:
		var i := 0 if speed < pts[1] else 1
		var t := inverse_lerp(pts[i], pts[i + 1], speed)
		w[i] = 1.0 - t
		w[i + 1] = t
	var natural := 0.0
	for i in 3:
		natural += w[i] * GAIT[names[i]][1] * gait_scale
	# Walk steps can slow right down when easing in; runs never go slow-mo.
	var floor_scale := lerpf(0.55, 0.85, clampf(inverse_lerp(walk_speed, jog_speed, speed), 0.0, 1.0))
	return clampf(speed / natural, floor_scale, 2.2)


func _anim(clip: StringName, loop := false) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = clip
	if STRETCH.has(clip):
		node.use_custom_timeline = true
		node.timeline_length = STRETCH[clip]
		node.stretch_time_scale = true
		node.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	return node


func _build_tree() -> AnimationNodeStateMachine:
	var move := AnimationNodeBlendTree.new()
	move.add_node(&"idle", _anim(&"Idle", true), Vector2(-600, -100))
	_fidget_node = _anim(FIDGETS[0])
	move.add_node(&"fidget_clip", _fidget_node, Vector2(-600, 60))
	var fidget := AnimationNodeOneShot.new()
	fidget.fadein_time = 0.45
	fidget.fadeout_time = 0.6
	move.add_node(&"fidget", fidget, Vector2(-350, -40))
	move.connect_node(&"fidget", 0, &"idle")
	move.connect_node(&"fidget", 1, &"fidget_clip")

	var gait := AnimationNodeBlendSpace1D.new()
	gait.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_CYCLIC_MUTABLE
	gait.min_space = 0.0
	gait.max_space = sprint_speed + 0.5
	gait.value_label = "speed m/s"
	var positions := [walk_speed, jog_speed, sprint_speed]
	var i := 0
	for clip in GAIT:
		var node := AnimationNodeAnimation.new()
		node.animation = clip
		node.use_custom_timeline = true
		node.timeline_length = GAIT[clip][0]
		node.stretch_time_scale = false
		node.start_offset = GAIT[clip][2]  # left foot forward at phase 0 for every gait
		node.loop_mode = Animation.LOOP_LINEAR
		gait.add_blend_point(node, positions[i], -1, clip)
		i += 1
	move.add_node(&"gait", gait, Vector2(-600, 220))
	move.add_node(&"cadence", AnimationNodeTimeScale.new(), Vector2(-350, 220))
	move.connect_node(&"cadence", 0, &"gait")
	move.add_node(&"move", AnimationNodeBlend2.new(), Vector2(-100, 60))
	move.connect_node(&"move", 0, &"fidget")
	move.connect_node(&"move", 1, &"cadence")
	move.connect_node(&"output", 0, &"move")

	var sm := AnimationNodeStateMachine.new()
	sm.add_node(&"Move", move, Vector2(0, 0))
	var states := [&"JumpStart", &"Fall", &"Land", &"SprintStop", &"Turn90L", &"Turn90R",
		&"Turn180L", &"Turn180R", &"Dance", &"Cheer", &"SitDown", &"SitIdle", &"SitUp", &"Nod", &"Surprise"]
	var angle := 0.0
	for s in states:
		sm.add_node(s, _anim(s, s in LOOPING), Vector2(cos(angle), sin(angle)) * 420.0)
		angle += TAU / states.size()
	var start := AnimationNodeStateMachineTransition.new()
	start.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	sm.add_transition(&"Start", &"Move", start)
	var all: Array = [&"Move"] + states
	for from in all:
		for to in all:
			if from == to:
				continue
			var t := AnimationNodeStateMachineTransition.new()
			t.xfade_time = XFADE[to]
			t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
			t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_ENABLED
			t.reset = true
			sm.add_transition(from, to, t)
	return sm
