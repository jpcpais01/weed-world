class_name KelingSwim
extends SkeletonModifier3D
## Procedural swimming, layered over the idle animation after the procedural
## touches. Kelings swim like puppies: the round body tips forward, the back
## arches to keep that big head above the water, the stubby arms paddle in
## alternating circles under the chin and the little legs flutter behind.
## Standing still in deep water they tread it instead: upright, hands sculling
## in and out, feet pedalling.
##
## Only humanoid bone names are used and every limb is aimed by direction, so
## the same paddle fits any Keling rig. The controller drives `amount` (0 on
## land .. 1 afloat), `stroke` (0 treading .. 1 swimming flat out) and the
## stroke cycle, and asks `waterline()` how deep to float.

## 0 = whatever the animation does, 1 = fully swimming.
var amount := 0.0
## 0 = treading water, 1 = paddling along at full stroke.
var stroke := 0.0
## Arm stroke cycle (radians); the left arm leads, the right is half a turn behind.
var phase := 0.0
## Leg kick cycle (radians).
var kick := 0.0
## Lean into turns (radians, same sense as the controller's bank).
var roll := 0.0
## 0..1: the right hand is busy (holding a joint up out of the water).
var right_busy := 0.0

var _bones := {}
var _hips_y := 0.31
var _spine_y := 0.51
var _chin_y := 0.84

const ARMS := [["LeftUpperArm", "LeftLowerArm", "LeftHand", "LeftMiddleProximal", 1.0],
	["RightUpperArm", "RightLowerArm", "RightHand", "RightMiddleProximal", -1.0]]
const LEGS := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", 1.0],
	["RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes", -1.0]]


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for n in ["Hips", "Spine", "Chest", "Neck", "Head"]:
		_bones[n] = skel.find_bone(n)
	for limb in ARMS + LEGS:
		for i in 4:
			_bones[limb[i]] = skel.find_bone(limb[i])
	# Body landmarks from the rest pose, so a taller or rounder Keling floats
	# with its own chin at the waterline.
	var hips: int = _bones["Hips"]
	var spine: int = _bones["Spine"]
	var neck: int = _bones["Neck"]
	var head: int = _bones["Head"]
	if hips >= 0 and spine >= 0 and neck >= 0 and head >= 0:
		_hips_y = skel.get_bone_global_rest(hips).origin.y
		_spine_y = skel.get_bone_global_rest(spine).origin.y
		var neck_y := skel.get_bone_global_rest(neck).origin.y
		_chin_y = neck_y - (skel.get_bone_global_rest(head).origin.y - neck_y) * 0.5


## Forward tip of the body (radians) for a stroke amount.
static func tilt_for(s: float) -> float:
	return lerpf(0.3, 0.95, s)


## How far the back arches to hold the head up (radians).
static func arch_for(s: float) -> float:
	return lerpf(0.12, 0.45, s)


## Height of the chin above the feet's origin (skeleton metres) in the pose
## for stroke `s`: float this far under the surface to keep the face dry.
func waterline(s: float) -> float:
	var tilt := tilt_for(s)
	var upper := tilt - arch_for(s) * 0.8
	return _hips_y + (_spine_y - _hips_y) * cos(tilt) + (_chin_y - _spine_y) * cos(upper)


func _process_modification_with_delta(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_modification_with_delta_timed(delta)
	PerfMeter.add(&"swim pose", Time.get_ticks_usec() - t0)


func _process_modification_with_delta_timed(_delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or amount <= 0.001:
		return
	var w := clampf(amount, 0.0, 1.0)
	var s := clampf(stroke, 0.0, 1.0)

	# Tip forward from the hips (rocking a little with every stroke), lean
	# into turns, and arch the back so the head looks ahead, not down.
	var surge := sin(phase * 2.0) * 0.05 * s
	var tilt := (tilt_for(s) + surge) * w
	var arch := arch_for(s) * w
	var body_roll := (roll + sin(phase) * 0.08 * s) * w
	_rotate_model(skel, _bones["Hips"], Vector3.RIGHT, tilt)
	_rotate_model(skel, _bones["Hips"], Vector3.BACK, body_roll)
	_rotate_model(skel, _bones["Spine"], Vector3.RIGHT, -arch * 0.35)
	_rotate_model(skel, _bones["Spine"], Vector3.UP, sin(phase) * 0.07 * s * w)
	_rotate_model(skel, _bones["Chest"], Vector3.RIGHT, -arch * 0.35)
	_rotate_model(skel, _bones["Neck"], Vector3.RIGHT, -arch * 0.1)
	_rotate_model(skel, _bones["Head"], Vector3.RIGHT, -arch * 0.2 - surge * 0.5 * w)

	# Limb directions are written in the body's own frame and turned with it.
	var body := Basis(Vector3.BACK, body_roll) * Basis(Vector3.RIGHT, tilt)
	var chest := body * Basis(Vector3.RIGHT, -arch * 0.7)

	for arm in ARMS:
		var side: float = arm[4]
		var a := phase + (0.0 if side > 0.0 else PI)
		# Paddle: reach forward along the top, catch, pull down and back,
		# then fold the elbow and bring the paw up and forward again.
		var paddle := Vector3(side * (0.42 - 0.08 * cos(a)), -0.2 + 0.45 * cos(a), 0.55 + 0.45 * sin(a)).normalized()
		var bend := 0.5 + 0.45 * cos(a)
		var paddle_fore := (paddle + Vector3(-side * 0.25, -0.2, 0.6) * bend).normalized()
		# Tread: both hands scull in and out in front of the belly.
		var scull := Vector3(side * (0.6 + 0.25 * sin(phase)), -0.5, 0.42 + 0.12 * cos(phase)).normalized()
		var scull_fore := (scull + Vector3(-side * 0.4, 0.1, 0.5) * 0.6).normalized()
		var upper := chest * scull.lerp(paddle, s).normalized()
		var fore := chest * scull_fore.lerp(paddle_fore, s).normalized()
		var aw := w * (1.0 - (clampf(right_busy, 0.0, 1.0) if side < 0.0 else 0.0))
		_aim(skel, _bones[arm[0]], _bones[arm[1]], upper, aw)
		_aim(skel, _bones[arm[1]], _bones[arm[2]], fore, aw)
		# Paws cupped, palms pushing back against the water.
		_aim(skel, _bones[arm[2]], _bones[arm[3]], (fore + chest * Vector3(0.0, -0.3, -0.1)).normalized(), aw * 0.6)

	for leg in LEGS:
		var side: float = leg[4]
		var k := kick + (0.0 if side > 0.0 else PI)
		# Flutter behind when swimming, pedal underneath when treading.
		var flutter_thigh := Vector3(side * 0.14, -1.0, -0.15 + 0.32 * sin(k))
		var flutter_shin := Vector3(side * 0.1, -1.0, -0.3 + 0.35 * sin(k - 0.9))
		var pedal_thigh := Vector3(side * 0.2, -0.8, 0.35 + 0.3 * sin(k))
		var pedal_shin := Vector3(side * 0.08, -1.0, -0.05 + 0.3 * cos(k))
		var thigh := body * pedal_thigh.lerp(flutter_thigh, s).normalized()
		var shin := body * pedal_shin.lerp(flutter_shin, s).normalized()
		var toes := body * Vector3(0.0, -0.3, 1.0).lerp(Vector3(0.0, -0.45, -0.9), s).normalized()
		_aim(skel, _bones[leg[0]], _bones[leg[1]], thigh, w)
		_aim(skel, _bones[leg[1]], _bones[leg[2]], shin, w)
		_aim(skel, _bones[leg[2]], _bones[leg[3]], toes, w * 0.8)


## Turns `bone` so the direction to `child` points along `dir` (model space),
## blended by `weight`.
func _aim(skel: Skeleton3D, bone: int, child: int, dir: Vector3, weight: float) -> void:
	if bone < 0 or child < 0 or weight <= 0.001:
		return
	var g := skel.get_bone_global_pose(bone)
	var cur := skel.get_bone_global_pose(child).origin - g.origin
	if cur.length_squared() < 1e-8:
		return
	var q := g.basis.get_rotation_quaternion()
	var target := Quaternion(cur.normalized(), dir) * q
	_set_global_rotation(skel, bone, q.slerp(target, clampf(weight, 0.0, 1.0)))


func _rotate_model(skel: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or is_zero_approx(angle):
		return
	var parent := skel.get_bone_parent(bone)
	var parent_q := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var local_axis := (parent_q.inverse() * axis).normalized()
	skel.set_bone_pose_rotation(bone, Quaternion(local_axis, angle) * skel.get_bone_pose_rotation(bone))


func _set_global_rotation(skel: Skeleton3D, bone: int, global_q: Quaternion) -> void:
	var parent := skel.get_bone_parent(bone)
	var parent_q := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skel.set_bone_pose_rotation(bone, (parent_q.inverse() * global_q).normalized())
