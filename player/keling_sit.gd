class_name KelingSit
extends SkeletonModifier3D
## Procedural bench sit, layered over the idle animation after the procedural
## touches: the hips settle onto the seat, the thighs rest flat along it and
## the stubby shins dangle over the edge. Kelings sit like happy toddlers, so
## the feet swing in little alternating kicks that come and go, the body rocks
## along with them, and the arms hang relaxed at the sides.
##
## The controller drives `amount` (0 standing .. 1 seated) through its sit and
## stand hops and tells the modifier where the hip joint belongs in the world.

## 0 = whatever the animation does, 1 = fully seated.
var amount := 0.0
## World position the hip joint settles to (the seat spot on the bench).
var hip_world := Vector3.ZERO
## Extra hip lift (metres) for the little hop on and off the seat.
var hop := 0.0
## How far the legs have swung up onto the seat, 0..1 (lags the hips a touch).
var legs := 0.0
## Leg length against the original Keling's: long legs rest further out
## over the edge so their feet clear the ground.
var leg_reach := 1.0

var _bones := {}
var _t := 0.0
var _kick := 0.0         # current kicking intensity
var _kick_target := 0.0
var _kick_timer := 1.5
var _rock := 0.0

const LEGS := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes", 1.0], ["RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes", -1.0]]
const ARMS := [["LeftUpperArm", "LeftLowerArm", 1.0], ["RightUpperArm", "RightLowerArm", -1.0]]


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for n in ["Hips", "Spine", "Chest", "Head", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
			"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes", "LeftUpperArm", "LeftLowerArm",
			"RightUpperArm", "RightLowerArm"]:
		_bones[n] = skel.find_bone(n)


func _process_modification_with_delta(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_modification_with_delta_timed(delta)
	PerfMeter.add(&"sitting pose", Time.get_ticks_usec() - t0)


func _process_modification_with_delta_timed(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty() or amount <= 0.001:
		_kick = 0.0
		return
	delta = minf(delta, 0.05)
	_t += delta

	# Moods: a burst of happy kicking, then a still, contented gaze.
	_kick_timer -= delta
	if _kick_timer <= 0.0:
		_kick_timer = randf_range(2.5, 6.5)
		_kick_target = 0.0 if _kick_target > 0.3 or randf() < 0.35 else randf_range(0.55, 1.0)
	_kick = lerpf(_kick, _kick_target * legs, 1.0 - exp(-1.8 * delta))

	var hips: int = _bones["Hips"]
	# Hips onto the seat (position in the parent's space), pelvis rolled back.
	var to_model := skel.global_transform.affine_inverse()
	var target_model := to_model * (hip_world + Vector3.UP * hop)
	var parent := skel.get_bone_parent(hips)
	var parent_xf := skel.get_bone_global_pose(parent) if parent >= 0 else Transform3D()
	var target_local := parent_xf.affine_inverse() * target_model
	skel.set_bone_pose_position(hips, skel.get_bone_pose_position(hips).lerp(target_local, amount))
	_rock = lerpf(_rock, sin(_t * 3.4) * _kick, 1.0 - exp(-8.0 * delta))
	_rotate_model(skel, hips, Vector3.RIGHT, -0.12 * amount)
	_rotate_model(skel, hips, Vector3.BACK, _rock * 0.035 * amount)
	# A soft, contented slouch that straightens while kicking.
	_rotate_model(skel, _bones["Spine"], Vector3.RIGHT, (0.1 - 0.05 * _kick) * amount)
	_rotate_model(skel, _bones["Chest"], Vector3.RIGHT, 0.04 * amount)
	_rotate_model(skel, _bones["Chest"], Vector3.BACK, -_rock * 0.05 * amount)

	for leg in LEGS:
		var side: float = leg[4]
		# Alternating kicks: one shin swings forward as the other tucks back.
		var phase := _t * 6.2 + (0.0 if side > 0.0 else PI)
		var swing := 0.32 + 0.5 * clampf(leg_reach - 1.0, 0.0, 1.0) + sin(phase) * 0.42 * _kick + sin(_t * 0.9 + side) * 0.05
		var thigh := Vector3(side * 0.2, -0.06 + 0.06 * _kick * sin(phase), 1.0).normalized()
		var shin := Vector3(side * 0.05, -cos(swing), sin(swing)).normalized()
		var foot := Vector3(0.0, -cos(swing + 1.25), sin(swing + 1.25)).normalized()
		_aim(skel, _bones[leg[0]], _bones[leg[1]], thigh, legs)
		_aim(skel, _bones[leg[1]], _bones[leg[2]], shin, legs)
		_aim(skel, _bones[leg[2]], _bones[leg[3]], foot, legs * 0.8)

	# Arms hang closer to the body so seat neighbours don't bump hands.
	for arm in ARMS:
		var side: float = arm[2]
		var dir := Vector3(side * 0.28, -1.0, 0.12 + 0.05 * sin(_t * 1.3 + side)).normalized()
		_aim(skel, _bones[arm[0]], _bones[arm[1]], dir, amount * 0.75)


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
