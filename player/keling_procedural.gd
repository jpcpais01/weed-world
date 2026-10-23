class_name KelingProcedural
extends SkeletonModifier3D
## Procedural layer applied on top of the animation, before the spring bones:
##  - acceleration / braking pitch of the spine
##  - breathing (rate and depth follow exertion)
##  - head anticipation: looks where the player is steering, or at the camera
##  - landing compression of the hips
##  - two-bone foot IK that plants the feet on slopes and steps

## Inputs written by the controller every frame.
var accel_pitch := 0.0  ## radians, + leans forward
var exertion := 0.0  ## 0 rested .. 1 out of breath
var look_yaw := 0.0  ## radians, head target relative to body facing
var look_pitch := 0.0
var land_compression := 0.0  ## metres the hips sink
var crouch := 0.0  ## metres the hips dip for a low grab (feet stay planted)
var ik_enabled := true
var ik_weight := 1.0
var space_state: PhysicsDirectSpaceState3D
var ray_exclude: Array[RID] = []

var _bones := {}
var _breath_phase := 0.0
var _look := Vector2.ZERO
var _pelvis_offset := 0.0
var _foot_offsets := [0.0, 0.0]
var _foot_normals := [Vector3.UP, Vector3.UP]

const LEGS := [["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], ["RightUpperLeg", "RightLowerLeg", "RightFoot"]]
const MAX_STEP := 0.22  ## how far a foot may reach up or down to find ground


func _ready() -> void:
	var skel := get_skeleton()
	if skel:
		for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "RightShoulder",
				"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot"]:
			_bones[n] = skel.find_bone(n)


func _process_modification_with_delta(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty():
		return
	delta = minf(delta, 0.05)

	# Breathing: slow and shallow at rest, quick and deep when exerted.
	var rate := lerpf(0.28, 1.05, exertion)
	_breath_phase = fmod(_breath_phase + delta * rate * TAU, TAU)
	var breath := sin(_breath_phase)
	var depth := lerpf(0.022, 0.06, exertion)
	_rotate_model(skel, _bones["Chest"], Vector3.RIGHT, -breath * depth * 0.6)
	_rotate_model(skel, _bones["UpperChest"], Vector3.RIGHT, -breath * depth * 0.4)
	var shoulder_lift := (breath * 0.5 + 0.5) * depth * 0.6
	_rotate_model(skel, _bones["LeftShoulder"], Vector3.BACK, shoulder_lift)
	_rotate_model(skel, _bones["RightShoulder"], Vector3.BACK, -shoulder_lift)

	# Lean into acceleration, rock back when braking (spread over the spine).
	_rotate_model(skel, _bones["Spine"], Vector3.RIGHT, accel_pitch * 0.45)
	_rotate_model(skel, _bones["Chest"], Vector3.RIGHT, accel_pitch * 0.35)

	# Head anticipation, smoothed and split between neck and head.
	_look = _look.lerp(Vector2(look_yaw, look_pitch), 1.0 - exp(-7.0 * delta))
	_rotate_model(skel, _bones["Neck"], Vector3.UP, _look.x * 0.35)
	_rotate_model(skel, _bones["Head"], Vector3.UP, _look.x * 0.65)
	_rotate_model(skel, _bones["Head"], Vector3.RIGHT, _look.y)

	_solve_feet(skel, delta)


## Rotates a bone around an axis given in skeleton (model) space.
func _rotate_model(skel: Skeleton3D, bone: int, axis: Vector3, angle: float) -> void:
	if bone < 0 or is_zero_approx(angle):
		return
	var parent := skel.get_bone_parent(bone)
	var parent_q := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	var local_axis := (parent_q.inverse() * axis).normalized()
	skel.set_bone_pose_rotation(bone, Quaternion(local_axis, angle) * skel.get_bone_pose_rotation(bone))


func _solve_feet(skel: Skeleton3D, delta: float) -> void:
	var to_world := skel.global_transform
	var weight := ik_weight if ik_enabled else 0.0
	var lowest := 0.0
	for i in 2:
		var target_offset := 0.0
		var normal := Vector3.UP
		if weight > 0.001 and space_state:
			var ankle_model := skel.get_bone_global_pose(_bones[LEGS[i][2]]).origin
			var ankle := to_world * ankle_model
			var up := to_world.basis.y.normalized()
			var from := ankle + up * (MAX_STEP + 0.1)
			var to := ankle - up * (MAX_STEP + 0.25)
			var q := PhysicsRayQueryParameters3D.create(from, to, 1, ray_exclude)
			var hit := space_state.intersect_ray(q)
			if hit:
				# Height of ground under this foot relative to the character's ground plane.
				var ground_h: float = (to_world.affine_inverse() * hit.position).y
				target_offset = clampf(ground_h, -MAX_STEP, MAX_STEP)
				normal = (to_world.basis.inverse() * hit.normal).normalized()
		_foot_offsets[i] = lerpf(_foot_offsets[i], target_offset * weight, 1.0 - exp(-18.0 * delta))
		var n_target: Vector3 = normal if weight > 0.5 else Vector3.UP
		_foot_normals[i] = (_foot_normals[i] as Vector3).lerp(n_target, 1.0 - exp(-12.0 * delta)).normalized()
		lowest = minf(lowest, _foot_offsets[i])

	# Sink the hips so the lower foot can still reach; add landing compression.
	_pelvis_offset = lerpf(_pelvis_offset, lowest, 1.0 - exp(-14.0 * delta))
	var hips: int = _bones["Hips"]
	var drop := _pelvis_offset - land_compression - crouch
	if absf(drop) > 0.0005:
		skel.set_bone_pose_position(hips, skel.get_bone_pose_position(hips) + Vector3(0, drop, 0))
	for i in 2:
		var lift: float = _foot_offsets[i] - drop
		if absf(lift) > 0.0005 or _foot_normals[i].dot(Vector3.UP) < 0.999:
			_two_bone_ik(skel, LEGS[i], lift, _foot_normals[i])


## Moves the ankle vertically by `lift` (model space) keeping the knee plane.
func _two_bone_ik(skel: Skeleton3D, chain: Array, lift: float, normal: Vector3) -> void:
	var a: int = _bones[chain[0]]
	var b: int = _bones[chain[1]]
	var c: int = _bones[chain[2]]
	var ga := skel.get_bone_global_pose(a)
	var gb := skel.get_bone_global_pose(b)
	var gc := skel.get_bone_global_pose(c)
	var target := gc.origin + Vector3(0, lift, 0)
	var l1 := ga.origin.distance_to(gb.origin)
	var l2 := gb.origin.distance_to(gc.origin)
	var to_target := target - ga.origin
	var dist := clampf(to_target.length(), absf(l1 - l2) + 0.001, l1 + l2 - 0.001)
	var dir := to_target.normalized()
	# Keep the knee bending the way the animation bent it.
	var pole := (gb.origin - ga.origin) - dir * (gb.origin - ga.origin).dot(dir)
	if pole.length_squared() < 1e-8:
		pole = Vector3.FORWARD.cross(dir).cross(dir) * -1.0
	pole = pole.normalized()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var knee := ga.origin + dir * (cos_a * l1) + pole * (sqrt(1.0 - cos_a * cos_a) * l1)
	var ankle := ga.origin + dir * dist

	var foot_rot := gc.basis.get_rotation_quaternion()
	# Upper leg.
	var q_a := Quaternion((gb.origin - ga.origin).normalized(), (knee - ga.origin).normalized())
	_set_global_rotation(skel, a, q_a * ga.basis.get_rotation_quaternion())
	# Lower leg (recompute its global after the parent changed).
	gb = skel.get_bone_global_pose(b)
	var q_b := Quaternion((skel.get_bone_global_pose(c).origin - gb.origin).normalized(), (ankle - gb.origin).normalized())
	_set_global_rotation(skel, b, q_b * gb.basis.get_rotation_quaternion())
	# Foot keeps its animated orientation, tilted to the ground slope.
	var tilt := Quaternion(Vector3.UP, normal.normalized()) if normal.dot(Vector3.UP) < 0.9999 else Quaternion.IDENTITY
	_set_global_rotation(skel, c, tilt * foot_rot)


func _set_global_rotation(skel: Skeleton3D, bone: int, global_q: Quaternion) -> void:
	var parent := skel.get_bone_parent(bone)
	var parent_q := skel.get_bone_global_pose(parent).basis.get_rotation_quaternion() if parent >= 0 else Quaternion.IDENTITY
	skel.set_bone_pose_rotation(bone, (parent_q.inverse() * global_q).normalized())
