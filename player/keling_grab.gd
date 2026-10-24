class_name KelingGrab
extends SkeletonModifier3D
## Procedural grab, layered on top of the idle animation before the other
## procedural touches: wind up, stretch the arm out to the target with the
## fingers spread wide, close the fingers around it, tug it free, bring it up
## to the chest for a look, then let the arm fall back.
##
## The arm is solved with two-bone IK so the hand really meets the target;
## the spine leans (and the controller crouches the hips) for low targets.

signal gripped  ## fingers just closed around the target

const DURATION := 1.9
const T_REACH := Vector2(0.18, 0.62)   ## arm travels out
const T_GRIP := Vector2(0.60, 0.74)    ## fingers close
const T_PULL := Vector2(0.80, 1.15)    ## tug back to the chest
const T_RETURN := Vector2(1.45, 1.9)   ## arm falls back to the idle pose
const MIN_LEAN := deg_to_rad(-15.0)
const MAX_LEAN := deg_to_rad(58.0)
const GRIP_OFFSET := 0.05  ## wrist to the centre of the closed fist (metres)

## Full-grip curl per finger joint (degrees), base to tip.
const CURL := {"Index": [50.0, 75.0, 55.0, 25.0], "Middle": [55.0, 80.0, 55.0, 25.0], "Ring": [60.0, 80.0, 50.0, 25.0], "Thumb": [18.0, 38.0, 40.0, 20.0]}
const STAGGER := {"Index": 0.0, "Middle": 0.025, "Ring": 0.05, "Thumb": 0.015}
const FINGER_NAMES := {
	"Index": ["IndexProximal", "IndexIntermediate", "IndexDistal", "IndexTip"],
	"Middle": ["MiddleProximal", "MiddleIntermediate", "MiddleDistal", "MiddleTip"],
	"Ring": ["RingProximal", "RingIntermediate", "RingDistal", "RingTip"],
	"Thumb": ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip"],
}

var grabbing := false
var time := 0.0
var side := "Right"
var target_world := Vector3.ZERO
## 0..1 while the hand holds its catch (for the controller to show the sprig).
var holding := false
## Whose body this is: the tug back to the chest lands on its chest.
var body: KelingBody

var _bones := {}
var _fingers := {}  # side -> finger -> {bones: [..], axis: Vector3 (hand space), splay: float}
var _palm_normal := {}  # side -> palm-facing direction in hand space
var _finger_dir := {}  # side -> wrist-to-knuckles direction in hand space
var _gripped_emitted := false
var _target_model := Vector3.ZERO
var _lean := 0.0


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for n in ["Spine", "Chest", "UpperChest"]:
		_bones[n] = skel.find_bone(n)
	for s in ["Left", "Right"]:
		for n in ["Shoulder", "UpperArm", "LowerArm", "Hand"]:
			_bones[s + n] = skel.find_bone(s + n)
		_setup_fingers(skel, s)


## Works out, from the rest pose, which way each finger curls and splays.
func _setup_fingers(skel: Skeleton3D, s: String) -> void:
	var rest := func(n: String) -> Transform3D: return skel.get_bone_global_rest(skel.find_bone(s + n))
	var hand_q: Quaternion = rest.call("Hand").basis.get_rotation_quaternion()
	var knuckles := Vector3.ZERO
	for f in ["Index", "Middle", "Ring"]:
		knuckles += rest.call(FINGER_NAMES[f][0]).origin / 3.0
	var mid_dir: Vector3 = (rest.call("MiddleIntermediate").origin - rest.call("MiddleProximal").origin).normalized()
	var thumb_tip: Vector3 = rest.call("ThumbTip").origin
	# The palm faces the thumb side: that is where the fingers curl to.
	var palm := KelingBody.palm_normal(thumb_tip, knuckles, mid_dir, rest.call("IndexProximal").origin, rest.call("RingProximal").origin)
	_palm_normal[s] = hand_q.inverse() * palm
	_finger_dir[s] = hand_q.inverse() * (knuckles - rest.call("Hand").origin).normalized()
	var lateral := palm.cross(mid_dir).normalized()
	_fingers[s] = {}
	for f in FINGER_NAMES:
		var names: Array = FINGER_NAMES[f]
		var bones := []
		for n in names:
			bones.append(skel.find_bone(s + n))
		var base: Vector3 = rest.call(names[0]).origin
		var d: Vector3 = (rest.call(names[1]).origin - base).normalized()
		var towards := palm
		if f == "Thumb":
			towards = (knuckles + mid_dir * 0.03 - base).normalized()
		var axis := d.cross(towards - d * towards.dot(d)).normalized()
		var splay := signf((base - rest.call("MiddleProximal").origin).dot(lateral)) if f != "Middle" else 0.0
		_fingers[s][f] = {"bones": bones, "axis": hand_q.inverse() * axis, "splay": splay}


## Starts a grab towards a world-space point with the given hand.
func start(target: Vector3, hand_side: String) -> void:
	target_world = target
	side = hand_side
	time = 0.0
	grabbing = true
	holding = false
	_gripped_emitted = false


func cancel() -> void:
	grabbing = false
	holding = false


## How far the hips dip for this grab, 0..1 (used by the controller); negative
## rises onto the toes for something overhead.
func crouch_amount() -> float:
	if not grabbing:
		return 0.0
	var low := clampf(inverse_lerp(0.55, 0.2, _target_model.y), 0.0, 1.0)
	var high := clampf(inverse_lerp(0.9, 1.15, _target_model.y), 0.0, 1.0)
	return (low - 0.45 * high) * _ease(T_REACH.x, T_REACH.y + 0.05) * (1.0 - _ease(T_PULL.x, T_PULL.y + 0.2))


func _ease(a: float, b: float) -> float:
	return smoothstep(a, b, time)


func _process_modification_with_delta(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_modification_with_delta_timed(delta)
	PerfMeter.add(&"grab pose", Time.get_ticks_usec() - t0)


func _process_modification_with_delta_timed(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or not grabbing:
		return
	time += minf(delta, 0.05)
	if time >= DURATION:
		grabbing = false
		holding = false
		return
	_target_model = skel.global_transform.affine_inverse() * target_world

	var reach := _ease(T_REACH.x, T_REACH.y) * (1.0 - _ease(T_RETURN.x, T_RETURN.y))
	var grip := _ease(T_GRIP.x, T_GRIP.y) * (1.0 - 0.75 * _ease(T_RETURN.x + 0.1, T_RETURN.y))
	var spread := _ease(0.08, 0.45) * (1.0 - _ease(T_GRIP.x - 0.04, T_GRIP.x + 0.06))
	var pull := _ease(T_PULL.x, T_PULL.y)
	holding = time > T_GRIP.x + 0.08 and time < T_RETURN.x + 0.15
	if not _gripped_emitted and time >= T_GRIP.x + 0.06:
		_gripped_emitted = true
		gripped.emit()

	# Lean towards the target: bend at the spine just enough for the shoulder to
	# bring it within arm's reach (stubby arms on a round body need a real bow
	# for anything near the ground), plus anticipation and the tug.
	var sgn := 1.0 if side == "Left" else -1.0
	var flat := Vector3(_target_model.x, 0.0, _target_model.z)
	var fwd := flat.normalized() if flat.length() > 0.05 else Vector3.BACK
	var lean_axis := Vector3.UP.cross(fwd).normalized()
	_lean = lerpf(_lean, _needed_lean(skel, lean_axis), 1.0 - exp(-10.0 * delta)) if time > 0.05 else _needed_lean(skel, lean_axis)
	var lean := _lean * reach * (1.0 - 0.8 * pull)
	lean -= deg_to_rad(5.0) * sin(PI * clampf(time / 0.25, 0.0, 1.0)) * (1.0 - _ease(0.15, 0.3))  # wind-up
	lean -= deg_to_rad(7.0) * sin(PI * clampf((time - T_PULL.x) / (T_PULL.y - T_PULL.x), 0.0, 1.0))  # tug
	_rotate_model(skel, _bones["Spine"], lean_axis, lean * 0.6)
	_rotate_model(skel, _bones["Chest"], lean_axis, lean * 0.4)
	# The free arm keeps hanging with gravity instead of swinging up with the bow.
	var other := "Left" if side == "Right" else "Right"
	_rotate_model(skel, _bones[other + "UpperArm"], lean_axis, -lean * 0.65)
	# Twist the chest a little towards the reaching side.
	var twist := deg_to_rad(10.0) * reach * (1.0 - pull) * -sgn
	_rotate_model(skel, _bones["UpperChest"], Vector3.UP, -twist)
	# Reach with the collarbone too: the shoulder slides towards the target.
	var sh: int = _bones[side + "Shoulder"]
	var sh_pos := skel.get_bone_global_pose(sh).origin
	var arm_root := skel.get_bone_global_pose(_bones[side + "UpperArm"]).origin
	var to_t := _target_model - sh_pos
	var clav_axis := (arm_root - sh_pos).cross(to_t)
	if clav_axis.length() > 1e-5:
		var clav := minf((arm_root - sh_pos).angle_to(to_t), deg_to_rad(18.0)) * reach * (1.0 - pull)
		_rotate_model(skel, sh, clav_axis.normalized(), clav)

	# Hand path: out to the target (with a small overshoot), then up to the chest.
	var chest_point := body.fit(Vector3(0.15 * sgn, 0.74, 0.42)) if body else Vector3(0.15 * sgn, 0.74, 0.42)
	var hand_bone: int = _bones[side + "Hand"]
	var anim_hand := skel.get_bone_global_pose(hand_bone).origin
	var reach_dir := (_target_model - anim_hand).normalized()
	var overshoot := 0.025 * sin(PI * clampf((time - T_GRIP.x + 0.06) / 0.2, 0.0, 1.0))
	# The wrist stops short so the closing fingers wrap around the target.
	var goal := _target_model + reach_dir * (overshoot - GRIP_OFFSET)
	goal = goal.lerp(chest_point, pull)
	goal += Vector3(0, 0.04, -0.03) * sin(PI * clampf(time / 0.3, 0.0, 1.0)) * (1.0 - reach)  # wind-up lift
	var w := clampf(reach + 0.35 * sin(PI * clampf(time / 0.3, 0.0, 1.0)) * (1.0 - reach), 0.0, 1.0)
	var hand_goal := anim_hand.lerp(goal, w)
	_arm_ik(skel, side, hand_goal)

	# Hand orientation: fingers point along the reach, then cup towards the chest.
	var hand_q := skel.get_bone_global_pose(hand_bone).basis.get_rotation_quaternion()
	var fingers_dir: Vector3 = (hand_q * _finger_dir[side]).normalized()
	var want := reach_dir.lerp((chest_point + Vector3(0, 0.08, 0.15) - goal).normalized(), pull).normalized()
	var align := Quaternion(fingers_dir, want) if fingers_dir.dot(want) < 0.9999 else Quaternion.IDENTITY
	align = Quaternion.IDENTITY.slerp(align, 0.75 * w)
	_set_global_rotation(skel, hand_bone, align * hand_q)

	# Fingers: stretch and splay while reaching, close with a stagger, relax at the end.
	hand_q = skel.get_bone_global_pose(hand_bone).basis.get_rotation_quaternion()
	var palm: Vector3 = hand_q * _palm_normal[side]
	for f in _fingers[side]:
		var info: Dictionary = _fingers[side][f]
		var g := smoothstep(T_GRIP.x + STAGGER[f], T_GRIP.y + STAGGER[f], time) * (1.0 - 0.75 * _ease(T_RETURN.x + 0.1, T_RETURN.y))
		var axis: Vector3 = (hand_q * info["axis"]).normalized()
		var curls: Array = CURL[f]
		var bones: Array = info["bones"]
		var splay_angle: float = deg_to_rad(14.0) * spread * info["splay"] * (1.0 - g)
		if absf(splay_angle) > 0.0001:
			_rotate_model(skel, bones[0], palm, splay_angle)
		for k in bones.size():
			var angle := deg_to_rad(curls[k]) * g - deg_to_rad(14.0 if k < 2 else 8.0) * spread
			_rotate_model(skel, bones[k], axis, angle)


## Smallest spine bend (radians, + forward) that puts the target within reach
## of the shoulder, searched from a gentle default bow.
func _needed_lean(skel: Skeleton3D, axis: Vector3) -> float:
	var spine := skel.get_bone_global_pose(_bones["Spine"]).origin
	var chest := skel.get_bone_global_pose(_bones["Chest"]).origin
	var arm := skel.get_bone_global_pose(_bones[side + "UpperArm"]).origin
	var reach := _arm_length(skel) * 0.9
	var base := deg_to_rad(10.0) if _target_model.y < 0.75 else deg_to_rad(-6.0)
	var best := base
	var best_d := INF
	for i in 15:
		var cand := base + deg_to_rad(5.0) * float((i + 1) / 2) * (1.0 if i % 2 == 1 else -1.0)
		cand = clampf(cand, MIN_LEAN, MAX_LEAN)
		var q1 := Quaternion(axis, cand * 0.6)
		var c1 := spine + q1 * (chest - spine)
		var a1 := spine + q1 * (arm - spine)
		var a2 := c1 + Quaternion(axis, cand * 0.4) * (a1 - c1)
		var d := a2.distance_to(_target_model) - reach
		if d <= 0.0:
			return cand
		if d < best_d:
			best_d = d
			best = cand
	return best


func _arm_length(skel: Skeleton3D) -> float:
	var a := skel.get_bone_global_pose(_bones[side + "UpperArm"]).origin
	var b := skel.get_bone_global_pose(_bones[side + "LowerArm"]).origin
	var c := skel.get_bone_global_pose(_bones[side + "Hand"]).origin
	return a.distance_to(b) + b.distance_to(c)


## Two-bone IK for the arm, elbow pointing out and down.
func _arm_ik(skel: Skeleton3D, s: String, goal: Vector3) -> void:
	var a: int = _bones[s + "UpperArm"]
	var b: int = _bones[s + "LowerArm"]
	var c: int = _bones[s + "Hand"]
	var ga := skel.get_bone_global_pose(a)
	var gb := skel.get_bone_global_pose(b)
	var gc := skel.get_bone_global_pose(c)
	var l1 := ga.origin.distance_to(gb.origin)
	var l2 := gb.origin.distance_to(gc.origin)
	var to_goal := goal - ga.origin
	var dist := clampf(to_goal.length(), absf(l1 - l2) + 0.002, (l1 + l2) * 0.999)
	var dir := to_goal.normalized()
	var sgn := 1.0 if s == "Left" else -1.0
	var anim_pole := (gb.origin - ga.origin) - dir * (gb.origin - ga.origin).dot(dir)
	var pref := Vector3(sgn, -0.7, -0.5)
	pref = pref - dir * pref.dot(dir)
	var pole := (anim_pole.normalized() * 0.4 + pref.normalized()).normalized() if anim_pole.length() > 0.001 else pref.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var elbow := ga.origin + dir * (cos_a * l1) + pole * (sqrt(1.0 - cos_a * cos_a) * l1)
	var wrist := ga.origin + dir * dist
	var hand_q := gc.basis.get_rotation_quaternion()
	var q_a := Quaternion((gb.origin - ga.origin).normalized(), (elbow - ga.origin).normalized())
	_set_global_rotation(skel, a, q_a * ga.basis.get_rotation_quaternion())
	gb = skel.get_bone_global_pose(b)
	var q_b := Quaternion((skel.get_bone_global_pose(c).origin - gb.origin).normalized(), (wrist - gb.origin).normalized())
	_set_global_rotation(skel, b, q_b * gb.basis.get_rotation_quaternion())
	_set_global_rotation(skel, c, hand_q)


func _rotate_model(skel: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or is_zero_approx(angle):
		return
	var parent := skel.get_bone_parent(bone)
	var parent_q := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skel.set_bone_pose_rotation(bone, Quaternion((parent_q.inverse() * axis).normalized(), angle) * skel.get_bone_pose_rotation(bone))


func _set_global_rotation(skel: Skeleton3D, bone: int, global_q: Quaternion) -> void:
	var parent := skel.get_bone_parent(bone)
	var parent_q := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skel.set_bone_pose_rotation(bone, (parent_q.inverse() * global_q).normalized())
