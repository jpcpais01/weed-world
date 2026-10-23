extends SceneTree
## Bakes Quaternius' Universal Animation Library clips (CC0) onto the Keling rig.
##
## Run from the project root:
##   godot --headless --path . -s res://tools/retarget_animations.gd
##
## Godot's import-time retargeting rewrites rest poses, which breaks the extra
## spring bones we add to the Keling (crown, stalks, basket). Instead this tool
## does a world-space retarget: every frame, each source bone's rotation
## relative to its rest is applied on top of the matching Keling bone's rest,
## after aligning limbs from the Keling's A-pose to the library's T-pose.
## Turn clips come from the root-motion export; their yaw and drift are moved
## onto the Keling "Root" bone so the controller can consume them.

const SOURCE := "res://art_source/ual_keling_clips.glb"
const TARGET := "res://assets/characters/keling/keling.glb"
const OUTPUT := "res://assets/characters/keling/keling_animations.res"
const FPS := 30.0

## Extra outward swing for the arms so the Keling's short arms clear its round
## belly (the library is authored for a slim mannequin).
const ARM_ABDUCTION_DEG := 24.0

## The Keling's legs are a third of the mannequin's, so locomotion strides are
## tiny. Exaggerating the limb swing of the gait cycles gives longer, bouncier
## steps (and less frantic cadence at gameplay speeds).
const GAIT_BONES := ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"]
const SWING_BONES := ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]

## source clip -> [output name, loop, extract root motion, (gait amplify, arm amplify)]
const CLIPS := {
	"Idle_Loop": ["Idle", true, false],
	"Idle_LookAround_Loop": ["IdleLookAround", true, false],
	"Idle_FoldArms_Loop": ["IdleFoldArms", true, false],
	"Walk_Loop": ["Walk", true, false, 1.25, 1.2],
	"Jog_Fwd_Loop": ["Jog", true, false, 1.2, 1.15],
	"Jog_Fwd_LeanL_Loop": ["JogLeanL", true, false, 1.2, 1.15],
	"Jog_Fwd_LeanR_Loop": ["JogLeanR", true, false, 1.2, 1.15],
	"Sprint_Loop": ["Sprint", true, false, 1.15, 1.1],
	"Sprint_Exit": ["SprintStop", false, false],
	"Jump_Start": ["JumpStart", false, false],
	"Jump_Loop": ["Fall", true, false],
	"Jump_Land": ["Land", false, false],
	"Roll": ["Roll", false, false],
	"Turn90_L": ["Turn90L", false, true],
	"Turn90_R": ["Turn90R", false, true],
	"Turn180_L": ["Turn180L", false, true],
	"Turn180_R": ["Turn180R", false, true],
	"Dance_Loop": ["Dance", true, false],
	"Celebration": ["Cheer", false, false],
	"GroundSit_Enter": ["SitDown", false, false],
	"GroundSit_Idle_Loop": ["SitIdle", true, false],
	"GroundSit_Exit": ["SitUp", false, false],
	"Surprise": ["Surprise", false, false],
	"Yes": ["Nod", false, false],
}

const BONE_MAP := {
	"pelvis": "Hips", "spine_01": "Spine", "spine_02": "Chest", "spine_03": "UpperChest",
	"neck_01": "Neck", "Head": "Head",
	"clavicle_l": "LeftShoulder", "upperarm_l": "LeftUpperArm", "lowerarm_l": "LeftLowerArm", "hand_l": "LeftHand",
	"clavicle_r": "RightShoulder", "upperarm_r": "RightUpperArm", "lowerarm_r": "RightLowerArm", "hand_r": "RightHand",
	"thumb_01_l": "LeftThumbMetacarpal", "thumb_02_l": "LeftThumbProximal", "thumb_03_l": "LeftThumbDistal",
	"thumb_01_r": "RightThumbMetacarpal", "thumb_02_r": "RightThumbProximal", "thumb_03_r": "RightThumbDistal",
	"index_01_l": "LeftIndexProximal", "index_02_l": "LeftIndexIntermediate", "index_03_l": "LeftIndexDistal",
	"index_01_r": "RightIndexProximal", "index_02_r": "RightIndexIntermediate", "index_03_r": "RightIndexDistal",
	"middle_01_l": "LeftMiddleProximal", "middle_02_l": "LeftMiddleIntermediate", "middle_03_l": "LeftMiddleDistal",
	"middle_01_r": "RightMiddleProximal", "middle_02_r": "RightMiddleIntermediate", "middle_03_r": "RightMiddleDistal",
	"ring_01_l": "LeftRingProximal", "ring_02_l": "LeftRingIntermediate", "ring_03_l": "LeftRingDistal",
	"ring_01_r": "RightRingProximal", "ring_02_r": "RightRingIntermediate", "ring_03_r": "RightRingDistal",
	"thigh_l": "LeftUpperLeg", "calf_l": "LeftLowerLeg", "foot_l": "LeftFoot", "ball_l": "LeftToes",
	"thigh_r": "RightUpperLeg", "calf_r": "RightLowerLeg", "foot_r": "RightFoot", "ball_r": "RightToes",
}

## Limb bones aligned A-pose -> T-pose: target bone -> [target child, source child].
const ALIGN := {
	"LeftShoulder": ["LeftUpperArm", "upperarm_l"], "LeftUpperArm": ["LeftLowerArm", "lowerarm_l"],
	"LeftLowerArm": ["LeftHand", "hand_l"], "LeftHand": ["LeftMiddleProximal", "middle_01_l"],
	"RightShoulder": ["RightUpperArm", "upperarm_r"], "RightUpperArm": ["RightLowerArm", "lowerarm_r"],
	"RightLowerArm": ["RightHand", "hand_r"], "RightHand": ["RightMiddleProximal", "middle_01_r"],
	"LeftUpperLeg": ["LeftLowerLeg", "calf_l"], "LeftLowerLeg": ["LeftFoot", "foot_l"],
	"LeftFoot": ["LeftToes", "ball_l"], "LeftToes": ["LeftToesEnd", "ball_leaf_l"],
	"RightUpperLeg": ["RightLowerLeg", "calf_r"], "RightLowerLeg": ["RightFoot", "foot_r"],
	"RightFoot": ["RightToes", "ball_r"], "RightToes": ["RightToesEnd", "ball_leaf_r"],
	"LeftThumbMetacarpal": ["LeftThumbProximal", "thumb_02_l"], "LeftThumbProximal": ["LeftThumbDistal", "thumb_03_l"],
	"LeftThumbDistal": ["LeftThumbTip", "thumb_04_leaf_l"],
	"RightThumbMetacarpal": ["RightThumbProximal", "thumb_02_r"], "RightThumbProximal": ["RightThumbDistal", "thumb_03_r"],
	"RightThumbDistal": ["RightThumbTip", "thumb_04_leaf_r"],
}

var src_skel: Skeleton3D
var tgt_skel: Skeleton3D
var src_rest_global := {}  # bone idx -> Transform3D
var tgt_rest_global := {}
var align := {}  # target bone idx -> Quaternion
var tgt_to_src := {}  # target bone idx -> source bone idx
var leg_scale := 1.0
var arm_side := {}  # target bone idx (upper arm and below) -> +1 left / -1 right


func _init() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(SOURCE), state) != OK:
		push_error("cannot read %s" % SOURCE)
		quit(1)
		return
	var src_scene: Node = doc.generate_scene(state)
	src_skel = _find_skeleton(src_scene)
	var player: AnimationPlayer = src_scene.find_child("AnimationPlayer", true, false)
	var tgt_scene: Node = (load(TARGET) as PackedScene).instantiate()
	tgt_skel = _find_skeleton(tgt_scene)

	_cache_rests(src_skel, src_rest_global)
	_cache_rests(tgt_skel, tgt_rest_global)
	for s in BONE_MAP:
		tgt_to_src[tgt_skel.find_bone(BONE_MAP[s])] = src_skel.find_bone(s)
	for t in ALIGN:
		var ti := tgt_skel.find_bone(t)
		var tc := tgt_skel.find_bone(ALIGN[t][0])
		var si: int = tgt_to_src[ti]
		var sc := src_skel.find_bone(ALIGN[t][1])
		var dt: Vector3 = (tgt_rest_global[tc].origin - tgt_rest_global[ti].origin).normalized()
		var ds: Vector3 = (src_rest_global[sc].origin - src_rest_global[si].origin).normalized()
		align[ti] = Quaternion(dt, ds)
	# Finger segments without an explicit pair inherit their parent's alignment.
	for ti in tgt_to_src:
		if not align.has(ti):
			var p := tgt_skel.get_bone_parent(ti)
			while p != -1 and not align.has(p):
				p = tgt_skel.get_bone_parent(p)
			var name := tgt_skel.get_bone_name(ti)
			var is_limb := name.contains("Left") or name.contains("Right")
			align[ti] = align[p] if (p != -1 and is_limb) else Quaternion.IDENTITY

	for i in tgt_skel.get_bone_count():
		var b := i
		while b != -1:
			var n := tgt_skel.get_bone_name(b)
			if n == "LeftUpperArm" or n == "RightUpperArm":
				arm_side[i] = 1.0 if n.begins_with("Left") else -1.0
				break
			b = tgt_skel.get_bone_parent(b)

	var src_leg: float = src_rest_global[src_skel.find_bone("thigh_l")].origin.distance_to(src_rest_global[src_skel.find_bone("calf_l")].origin) \
		+ src_rest_global[src_skel.find_bone("calf_l")].origin.distance_to(src_rest_global[src_skel.find_bone("foot_l")].origin)
	var tgt_leg: float = tgt_rest_global[tgt_skel.find_bone("LeftUpperLeg")].origin.distance_to(tgt_rest_global[tgt_skel.find_bone("LeftLowerLeg")].origin) \
		+ tgt_rest_global[tgt_skel.find_bone("LeftLowerLeg")].origin.distance_to(tgt_rest_global[tgt_skel.find_bone("LeftFoot")].origin)
	leg_scale = tgt_leg / src_leg
	print("leg scale %.3f" % leg_scale)

	var skel_path := String(tgt_scene.get_path_to(tgt_skel))
	var lib := AnimationLibrary.new()
	for clip in CLIPS:
		var cfg: Array = CLIPS[clip]
		var amp := Vector2(cfg[3], cfg[4]) if cfg.size() > 3 else Vector2.ONE
		var anim := _bake(player.get_animation(clip), skel_path, cfg[1], cfg[2], amp)
		lib.add_animation(StringName(cfg[0]), anim)
		print("baked %-22s -> %-15s %.2fs" % [clip, cfg[0], anim.length])
	var err := ResourceSaver.save(lib, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (%s)" % [OUTPUT, error_string(err)])
	src_scene.free()
	tgt_scene.free()
	quit(0 if err == OK else 1)


func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var s := _find_skeleton(c)
		if s:
			return s
	return null


func _cache_rests(skel: Skeleton3D, out: Dictionary) -> void:
	for i in skel.get_bone_count():
		var p := skel.get_bone_parent(i)
		out[i] = (out[p] if p != -1 else Transform3D.IDENTITY) * skel.get_bone_rest(i)


func _yaw_of(q: Quaternion) -> float:
	var f := q * Vector3.BACK
	return atan2(f.x, f.z)


func _bake(src: Animation, skel_path: String, loop: bool, root_motion: bool, amp: Vector2) -> Animation:
	var amplify := {}
	for b in GAIT_BONES:
		amplify[src_skel.find_bone(b)] = amp.x
	for b in SWING_BONES:
		amplify[src_skel.find_bone(b)] = amp.y
	var rot_tracks := {}
	var pos_tracks := {}
	for i in src.get_track_count():
		var bone := src_skel.find_bone(String(src.track_get_path(i).get_concatenated_subnames()))
		if bone == -1:
			continue
		match src.track_get_type(i):
			Animation.TYPE_ROTATION_3D:
				rot_tracks[bone] = i
			Animation.TYPE_POSITION_3D:
				pos_tracks[bone] = i

	var out := Animation.new()
	out.length = src.length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var out_rot := {}
	for ti in tgt_to_src:
		var tr := out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(tr, NodePath("%s:%s" % [skel_path, tgt_skel.get_bone_name(ti)]))
		out_rot[ti] = tr
	var hips := tgt_skel.find_bone("Hips")
	var hips_pos := out.add_track(Animation.TYPE_POSITION_3D)
	out.track_set_path(hips_pos, NodePath("%s:Hips" % skel_path))
	var root := tgt_skel.find_bone("Root")
	var root_pos := -1
	var root_rot := -1
	if root_motion:
		root_pos = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(root_pos, NodePath("%s:Root" % skel_path))
		root_rot = out.add_track(Animation.TYPE_ROTATION_3D)
		out.track_set_path(root_rot, NodePath("%s:Root" % skel_path))

	var src_root := src_skel.find_bone("root")
	var src_pelvis := src_skel.find_bone("pelvis")
	var upper_chest := tgt_skel.find_bone("UpperChest")
	var prev_yaw := 0.0
	var frames := int(round(src.length * FPS))
	for f in frames + 1:
		var t: float = min(f / FPS, src.length)
		# Source global pose.
		var g := {}
		for i in src_skel.get_bone_count():
			var rest := src_skel.get_bone_rest(i)
			var pos: Vector3 = src.position_track_interpolate(pos_tracks[i], t) if pos_tracks.has(i) else rest.origin
			var rest_q := rest.basis.get_rotation_quaternion()
			var rot: Quaternion = src.rotation_track_interpolate(rot_tracks[i], t) if rot_tracks.has(i) else rest_q
			if amplify.has(i) and amplify[i] != 1.0:
				rot = rest_q * Quaternion.IDENTITY.slerp(rest_q.inverse() * rot, amplify[i])
			var local := Transform3D(Basis(rot), pos)
			var p := src_skel.get_bone_parent(i)
			g[i] = (g[p] if p != -1 else Transform3D.IDENTITY) * local

		# Root motion lives on the source "root" bone in the RM export.
		var motion := Transform3D.IDENTITY
		if root_motion:
			var delta: Transform3D = g[src_root] * src_rest_global[src_root].affine_inverse()
			var yaw := _yaw_of(delta.basis.get_rotation_quaternion())
			yaw = prev_yaw + wrapf(yaw - prev_yaw, -PI, PI)
			prev_yaw = yaw
			motion = Transform3D(Basis(Vector3.UP, yaw), Vector3(delta.origin.x, 0.0, delta.origin.z) * leg_scale)
			var inv := Transform3D(Basis(Vector3.UP, -yaw), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -Vector3(delta.origin.x, 0.0, delta.origin.z))
			for i in g:
				g[i] = inv * g[i]

		# Target global rotations, parents first (bone indices are topologically sorted).
		var tg := {}
		var chest_delta := Quaternion.IDENTITY
		for ti in tgt_skel.get_bone_count():
			var p := tgt_skel.get_bone_parent(ti)
			var parent_q: Quaternion = tg[p] if p != -1 else Quaternion.IDENTITY
			var rest_q: Quaternion = tgt_rest_global[ti].basis.get_rotation_quaternion()
			if tgt_to_src.has(ti):
				var si: int = tgt_to_src[ti]
				var sq: Quaternion = g[si].basis.get_rotation_quaternion()
				var srest: Quaternion = src_rest_global[si].basis.get_rotation_quaternion()
				var q: Quaternion = (sq * srest.inverse()) * align[ti] * rest_q
				if arm_side.has(ti):
					# Swing the whole arm outwards, in the chest's frame.
					var abd := Quaternion(Vector3.BACK, deg_to_rad(ARM_ABDUCTION_DEG) * arm_side[ti])
					q = (chest_delta * abd * chest_delta.inverse()) * q
				tg[ti] = q.normalized()
				out.rotation_track_insert_key(out_rot[ti], t, (parent_q.inverse() * tg[ti]).normalized())
			else:
				tg[ti] = (parent_q * tgt_skel.get_bone_rest(ti).basis.get_rotation_quaternion()).normalized()
			if ti == upper_chest:
				chest_delta = tg[ti] * rest_q.inverse()

		# Hips translation, scaled to the Keling's leg length.
		var src_off: Vector3 = g[src_pelvis].origin - src_rest_global[src_pelvis].origin
		var hp: Vector3 = tgt_skel.get_bone_rest(hips).origin + src_off * leg_scale
		out.position_track_insert_key(hips_pos, t, hp)
		if root_motion:
			out.position_track_insert_key(root_pos, t, motion.origin)
			out.rotation_track_insert_key(root_rot, t, motion.basis.get_rotation_quaternion())
	return out
