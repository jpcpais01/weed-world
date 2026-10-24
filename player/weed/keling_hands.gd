class_name KelingHands
extends SkeletonModifier3D
## Two-handed poses for rolling and smoking, layered on top of everything else
## (after the grab): each arm reaches its goal with two-bone IK, the hand turns
## to face the way it is told, and the fingers curl, pinch and wiggle. KelingWeed
## drives the goals every frame from its little choreography.
##
## All goals are in skeleton space: +Z is forward, +X the Keling's left.

const SIDES := ["Left", "Right"]
const FINGER_NAMES := {
	"Index": ["IndexProximal", "IndexIntermediate", "IndexDistal", "IndexTip"],
	"Middle": ["MiddleProximal", "MiddleIntermediate", "MiddleDistal", "MiddleTip"],
	"Ring": ["RingProximal", "RingIntermediate", "RingDistal", "RingTip"],
	"Thumb": ["ThumbMetacarpal", "ThumbProximal", "ThumbDistal", "ThumbTip"],
}
## Full-curl angles per joint (degrees), base to tip.
const CURL := {"Index": [50.0, 75.0, 55.0, 25.0], "Middle": [55.0, 80.0, 55.0, 25.0], "Ring": [60.0, 80.0, 50.0, 25.0], "Thumb": [18.0, 38.0, 40.0, 20.0]}

## Per side: goal, w (0..1 blend), curl, pinch, wiggle, fingers (desired
## finger direction), palm (desired palm normal). Set by KelingWeed.
var arms := {
	"Left": {"goal": Vector3.ZERO, "w": 0.0, "curl": 0.0, "pinch": 0.0, "wiggle": 0.0, "fingers": Vector3.FORWARD, "palm": Vector3.UP},
	"Right": {"goal": Vector3.ZERO, "w": 0.0, "curl": 0.0, "pinch": 0.0, "wiggle": 0.0, "fingers": Vector3.FORWARD, "palm": Vector3.UP},
}
## Inhale: the round chest swells (0..1).
var chest_swell := 0.0
## Head tips back (radians) to blow smoke upwards, forward for a lick.
var head_pitch := 0.0
## Spine bow (radians, + forward) to bring the hands and face together.
var lean := 0.0

## How far the chest has moved from its rest spot this frame (sitting, hops,
## breathing). Goals ride along with it so the hands stay with the body.
var body_delta := Vector3.ZERO

var _bones := {}
var _chest_rest := Vector3.ZERO
var _fingers := {}
var _palm_normal := {}
var _finger_dir := {}
var _t := 0.0


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for n in ["Spine", "Chest", "UpperChest", "Neck", "Head"]:
		_bones[n] = skel.find_bone(n)
	_chest_rest = skel.get_bone_global_rest(_bones["Chest"]).origin
	for s in SIDES:
		for n in ["Shoulder", "UpperArm", "LowerArm", "Hand"]:
			_bones[s + n] = skel.find_bone(s + n)
		_setup_fingers(skel, s)


func active() -> bool:
	return arms.Left.w > 0.001 or arms.Right.w > 0.001 or chest_swell > 0.001 or absf(head_pitch) > 0.001 or absf(lean) > 0.001


## Works out, from the rest pose, which way each finger curls (same recipe
## as KelingGrab).
func _setup_fingers(skel: Skeleton3D, s: String) -> void:
	var rest := func(n: String) -> Transform3D: return skel.get_bone_global_rest(skel.find_bone(s + n))
	var hand_q: Quaternion = rest.call("Hand").basis.get_rotation_quaternion()
	var knuckles := Vector3.ZERO
	for f in ["Index", "Middle", "Ring"]:
		knuckles += rest.call(FINGER_NAMES[f][0]).origin / 3.0
	var mid_dir: Vector3 = (rest.call("MiddleIntermediate").origin - rest.call("MiddleProximal").origin).normalized()
	var thumb_tip: Vector3 = rest.call("ThumbTip").origin
	var palm: Vector3 = thumb_tip - knuckles
	palm = (palm - mid_dir * palm.dot(mid_dir)).normalized()
	_palm_normal[s] = hand_q.inverse() * palm
	_finger_dir[s] = hand_q.inverse() * (knuckles - rest.call("Hand").origin).normalized()
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
		_fingers[s][f] = {"bones": bones, "axis": hand_q.inverse() * axis}


## Skeleton-space transform of a hand bone in the current (modified) pose.
func hand_pose(side: String) -> Transform3D:
	var skel := get_skeleton()
	return skel.get_bone_global_pose(_bones[side + "Hand"]) if skel else Transform3D()


## Skeleton-space point between the index and middle knuckles, nudged out
## along the fingers: where a joint is held.
func grip_point(side: String, along := 0.03) -> Vector3:
	var skel := get_skeleton()
	var hand := skel.get_bone_global_pose(_bones[side + "Hand"]).origin
	var a := skel.get_bone_global_pose(skel.find_bone(side + "IndexProximal")).origin
	var b := skel.get_bone_global_pose(skel.find_bone(side + "MiddleProximal")).origin
	var k := (a + b) * 0.5
	return k + (k - hand).normalized() * along


func finger_direction(side: String) -> Vector3:
	var q := hand_pose(side).basis.get_rotation_quaternion()
	return (q * _finger_dir[side]).normalized()


func palm_direction(side: String) -> Vector3:
	var q := hand_pose(side).basis.get_rotation_quaternion()
	return (q * _palm_normal[side]).normalized()


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty():
		return
	body_delta = skel.get_bone_global_pose(_bones["Chest"]).origin - _chest_rest
	if not active():
		return
	_t += delta
	if absf(lean) > 0.0001:
		_rotate_model(skel, _bones["Spine"], Vector3.RIGHT, lean * 0.55)
		_rotate_model(skel, _bones["Chest"], Vector3.RIGHT, lean * 0.45)
	if chest_swell > 0.0001:
		var c: int = _bones["Chest"]
		skel.set_bone_pose_scale(c, skel.get_bone_pose_scale(c) * Vector3(1.0 + 0.06 * chest_swell, 1.0 + 0.035 * chest_swell, 1.0 + 0.07 * chest_swell))
	if absf(head_pitch) > 0.0001:
		_rotate_model(skel, _bones["Neck"], Vector3.RIGHT, -head_pitch * 0.4)
		_rotate_model(skel, _bones["Head"], Vector3.RIGHT, -head_pitch * 0.6)
	for s in SIDES:
		var a: Dictionary = arms[s]
		var w: float = a.w
		if w <= 0.001:
			continue
		var hand_bone: int = _bones[s + "Hand"]
		# The collarbone slides towards the goal so the stubby arm reaches further.
		var sh: int = _bones[s + "Shoulder"]
		var sh_pos := skel.get_bone_global_pose(sh).origin
		var arm_root := skel.get_bone_global_pose(_bones[s + "UpperArm"]).origin
		var goal: Vector3 = a.goal + body_delta
		var to_g: Vector3 = goal - sh_pos
		var clav_axis := (arm_root - sh_pos).cross(to_g)
		if clav_axis.length() > 1e-5:
			_rotate_model(skel, sh, clav_axis.normalized(), minf((arm_root - sh_pos).angle_to(to_g), deg_to_rad(22.0)) * w)
		var anim_hand := skel.get_bone_global_pose(hand_bone).origin
		_arm_ik(skel, s, anim_hand.lerp(goal, w))
		# Turn the hand: fingers along `fingers`, palm towards `palm`.
		var hq := skel.get_bone_global_pose(hand_bone).basis.get_rotation_quaternion()
		var fd: Vector3 = (hq * _finger_dir[s]).normalized()
		var want_f: Vector3 = (a.fingers as Vector3).normalized()
		var q1 := Quaternion(fd, want_f) if fd.dot(want_f) < 0.9999 and fd.dot(want_f) > -0.9999 else Quaternion.IDENTITY
		var pn: Vector3 = (q1 * hq * _palm_normal[s]).normalized()
		var want_p: Vector3 = a.palm
		want_p = (want_p - want_f * want_p.dot(want_f))
		var q2 := Quaternion.IDENTITY
		if want_p.length() > 0.01:
			want_p = want_p.normalized()
			var pp := (pn - want_f * pn.dot(want_f)).normalized()
			var ang := pp.signed_angle_to(want_p, want_f)
			q2 = Quaternion(want_f, ang)
		var target_q := (q2 * q1 * hq).normalized()
		_set_global_rotation(skel, hand_bone, hq.slerp(target_q, w))
		_fingers_pose(skel, s, a, w)


func _fingers_pose(skel: Skeleton3D, s: String, a: Dictionary, w: float) -> void:
	var hq := skel.get_bone_global_pose(_bones[s + "Hand"]).basis.get_rotation_quaternion()
	var k := 0
	for f in _fingers[s]:
		var info: Dictionary = _fingers[s][f]
		var axis: Vector3 = (hq * info["axis"]).normalized()
		var curl: float = a.curl
		# A pinch closes the thumb and index onto each other, the rest tuck in.
		if f == "Index" or f == "Thumb":
			curl = lerpf(curl, 0.55, a.pinch)
		else:
			curl = lerpf(curl, 0.9, a.pinch)
		var wig: float = a.wiggle * sin(_t * 14.0 + k * 1.7) * 0.35
		curl = clampf(curl + wig, -0.2, 1.0)
		var bones: Array = info["bones"]
		var curls: Array = CURL[f]
		for j in bones.size():
			_rotate_model(skel, bones[j], axis, deg_to_rad(curls[j]) * curl * w)
		k += 1


## Two-bone IK for the arm, elbow pointing out and down (as in KelingGrab).
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
	var pref := Vector3(sgn, -0.8, -0.35)
	pref = pref - dir * pref.dot(dir)
	var pole := (anim_pole.normalized() * 0.3 + pref.normalized()).normalized() if anim_pole.length() > 0.001 else pref.normalized()
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
