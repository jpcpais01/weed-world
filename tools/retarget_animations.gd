extends SceneTree
## Bakes Quaternius' Universal Animation Library clips (CC0) onto the Keling rig.
##
## Run from the project root (the id picks the character, default keling):
##   godot --headless --path . -s res://tools/retarget_animations.gd -- [blossom|sunflower|lavender|toadstool|keling|all]
##
## Godot's import-time retargeting rewrites rest poses, which breaks the extra
## spring bones we add to the Keling (crown and flower stalks). Instead this tool
## does a world-space retarget: every frame, each source bone's rotation
## relative to its rest is applied on top of the matching Keling bone's rest,
## after aligning limbs from the Keling's A-pose to the library's T-pose.
## Turn clips come from the root-motion export; their yaw and drift are moved
## onto the Keling "Root" bone so the controller can consume them.

const SOURCE := "res://art_source/ual_keling_clips.glb"
var TARGET := "res://assets/characters/keling/keling.glb"
var OUTPUT := "res://assets/characters/keling/keling_animations.res"
const FPS := 30.0

## Extra outward swing for the arms so the Keling's short arms clear its round
## belly (the library is authored for a slim mannequin).
const ARM_ABDUCTION_DEG := 24.0

## The Keling's legs are a third of the mannequin's, so locomotion strides are
## tiny. Exaggerating the limb swing of the gait cycles gives longer, bouncier
## steps (and less frantic cadence at gameplay speeds).
const GAIT_BONES := ["thigh_l", "thigh_r", "calf_l", "calf_r", "foot_l", "foot_r"]
const SWING_BONES := ["upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r"]

## The Keling has a huge head and no neck, so it can't nod and swing its head
## like the mannequin. Its head stays level and only follows a fraction of the
## library's head motion (more for emotes that are all about the head).
const HEAD_FOLLOW := 0.35
const HEAD_FOLLOW_CLIP := {"Nod": 1.0, "Dance": 0.6, "Cheer": 0.6, "Surprise": 0.5}
## The library's head hangs ~12 degrees forward in most clips; level it out.
const HEAD_PITCH_BIAS_DEG := 12.0
const HEAD_LIMIT_DEG := Vector3(14.0, 16.0, 8.0)  # pitch (down +), yaw, roll

## The round trunk can't fold like a human spine: forward/back lean of the
## hips and spine is damped (runs no longer topple forward), sway and twist
## mostly kept.
const TORSO_BONES := ["Hips", "Spine", "Chest", "UpperChest"]
const TORSO_FOLLOW := Vector3(0.45, 0.85, 0.7)  # pitch, yaw, roll
## Short arms on a big head: raising the upper arm above this just shears the
## shoulder, so elevation is capped (the forearm still reaches up).
const ARM_MAX_ELEVATION_DEG := 35.0

## Trunk profile written by tools/rig_keling.py: hands, forearms and elbows are
## pushed out of it so the arms rest on the round belly instead of sinking in.
var BODY_PROFILE := "res://assets/characters/keling/keling_body.json"
## Collision radius of each arm part (metres) and how its fix is shared out:
## [bone that rotates, [[point bone, along-bone fraction or -1 for origin, radius, weight]...]]
## The library's folded arms need a slim chest; the Keling's arms are far too
## short to cross over its belly, so they rest on top of it instead: collarbones
## forward, forearms laid over the upper belly, hands patting the middle.
var BELLY_WRIST := Vector3(0.205, 0.665, 0.0)  # z found on the belly surface
var BELLY_FINGERS := Vector3(0.10, 0.63, 0.0)
const BELLY_PROTRACT_DEG := 20.0
const ARM_COLLIDERS := [
	["UpperArm", [["LowerArm", -1.0, 0.04, 1.0], ["UpperArm", 0.5, 0.045, 1.0], ["Hand", -1.0, 0.035, 0.5]]],
	["LowerArm", [["Hand", -1.0, 0.035, 1.0], ["LowerArm", 0.5, 0.04, 1.0], ["MiddleProximal", -1.0, 0.025, 0.7]]],
	["Hand", [["MiddleProximal", -1.0, 0.025, 1.0], ["MiddleTip", -1.0, 0.012, 1.0], ["IndexTip", -1.0, 0.012, 1.0], ["RingTip", -1.0, 0.012, 1.0]]],
]

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
var body_rows := []  # [y, half_width, front_z, back_z]
var descendants := {}  # target bone idx -> [self and every bone below it]


func _init() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		ids = PackedStringArray(["keling"])
	elif ids[0] == "all":
		ids = PackedStringArray(["keling", "blossom", "sunflower", "lavender", "toadstool"])
	var ok := true
	for id in ids:
		ok = _retarget(id) and ok
	quit(0 if ok else 1)


func _retarget(id: String) -> bool:
	TARGET = "res://assets/characters/%s/%s.glb" % [id, id]
	OUTPUT = "res://assets/characters/%s/%s_animations.res" % [id, id]
	BODY_PROFILE = "res://assets/characters/%s/%s_body.json" % [id, id]
	src_rest_global.clear()
	tgt_rest_global.clear()
	align.clear()
	tgt_to_src.clear()
	arm_side.clear()
	descendants.clear()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(SOURCE), state) != OK:
		push_error("cannot read %s" % SOURCE)
		return false
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

	var body: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BODY_PROFILE))
	body_rows = body["rows"]
	if id != "keling":
		# Hands on the belly where the Keling has them: three quarters of the
		# way from the hips to the shoulders, 60% of the way out to the side.
		var hy := tgt_rest_global[tgt_skel.find_bone("Hips")].origin.y as float
		var sy := tgt_rest_global[tgt_skel.find_bone("LeftUpperArm")].origin.y as float
		var wy := lerpf(hy, sy, 0.77)
		BELLY_WRIST = Vector3(_half_width(wy) * 0.62, wy, 0.0)
		BELLY_FINGERS = Vector3(_half_width(wy - 0.035) * 0.3, wy - 0.035, 0.0)
	for i in tgt_skel.get_bone_count():
		descendants[i] = [i]
	for i in range(tgt_skel.get_bone_count() - 1, -1, -1):
		var p := tgt_skel.get_bone_parent(i)
		if p != -1:
			descendants[p].append_array(descendants[i])

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
		var anim := _bake(player.get_animation(clip), skel_path, cfg[1], cfg[2], amp, HEAD_FOLLOW_CLIP.get(cfg[0], HEAD_FOLLOW), cfg[0] == "IdleFoldArms")
		lib.add_animation(StringName(cfg[0]), anim)
		print("baked %-22s -> %-15s %.2fs" % [clip, cfg[0], anim.length])
	var err := ResourceSaver.save(lib, OUTPUT, ResourceSaver.FLAG_COMPRESS)
	print("saved %s (%s)" % [OUTPUT, error_string(err)])
	src_scene.free()
	tgt_scene.free()
	return err == OK


func _half_width(h: float) -> float:
	var best: Array = body_rows[0]
	for r in body_rows:
		if absf(r[0] - h) < absf(best[0] - h):
			best = r
	return best[1]


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


## Level, damped and clamped head rotation (model space) from the source head.
func _stable_head(src_delta: Quaternion, follow: float) -> Quaternion:
	var e := src_delta.get_euler()  # YXZ: x pitch, y yaw, z roll
	var lim := HEAD_LIMIT_DEG * (PI / 180.0)
	var pitch := clampf((e.x - deg_to_rad(HEAD_PITCH_BIAS_DEG)) * follow, -lim.x * 0.7, lim.x)
	var yaw := clampf(e.y * follow, -lim.y, lim.y)
	var roll := clampf(e.z * follow, -lim.z, lim.z)
	return Quaternion.from_euler(Vector3(pitch, yaw, roll))


func _bake(src: Animation, skel_path: String, loop: bool, root_motion: bool, amp: Vector2, head_follow: float, belly_rest := false) -> Animation:
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
	var neck := tgt_skel.find_bone("Neck")
	var head := tgt_skel.find_bone("Head")
	var src_head := src_skel.find_bone("Head")
	var torso := {}
	for n in TORSO_BONES:
		torso[tgt_skel.find_bone(n)] = true
	var upper_arms := [tgt_skel.find_bone("LeftUpperArm"), tgt_skel.find_bone("RightUpperArm")]
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
				if ti == neck or ti == head:
					# Head held level; the neck takes half of the bend from the chest.
					var src_hd: Quaternion = g[src_head].basis.get_rotation_quaternion() * src_rest_global[src_head].basis.get_rotation_quaternion().inverse()
					var head_delta := _stable_head(src_hd, head_follow)
					q = (head_delta if ti == head else chest_delta.slerp(head_delta, 0.5)) * rest_q
				if torso.has(ti):
					var e := (q * rest_q.inverse()).get_euler()
					q = Quaternion.from_euler(e * TORSO_FOLLOW * (0.3 if belly_rest else 1.0)) * rest_q
				if arm_side.has(ti):
					# Swing the whole arm outwards, in the chest's frame.
					var abd := Quaternion(Vector3.BACK, deg_to_rad(ARM_ABDUCTION_DEG) * arm_side[ti])
					q = (chest_delta * abd * chest_delta.inverse()) * q
				if ti in upper_arms:
					var d := Basis(q).y.normalized()
					var over := asin(clampf(d.y, -1.0, 1.0)) - deg_to_rad(ARM_MAX_ELEVATION_DEG)
					if over > 0.0:
						var axis := d.cross(Vector3.UP).normalized()
						q = Quaternion(axis, -over) * q
				tg[ti] = q.normalized()
			else:
				tg[ti] = (parent_q * tgt_skel.get_bone_rest(ti).basis.get_rotation_quaternion()).normalized()
			if ti == upper_chest:
				chest_delta = tg[ti] * rest_q.inverse()

		# Hips translation, scaled to the Keling's leg length.
		var src_off: Vector3 = g[src_pelvis].origin - src_rest_global[src_pelvis].origin
		var hp: Vector3 = tgt_skel.get_bone_rest(hips).origin + src_off * leg_scale
		out.position_track_insert_key(hips_pos, t, hp)

		if belly_rest:
			_rest_arms_on_belly(tg, hips, hp, t)  # already placed on the surface
		else:
			_keep_arms_out_of_body(tg, hips, hp)
		for ti in tgt_to_src:
			var p := tgt_skel.get_bone_parent(ti)
			var parent_q: Quaternion = tg[p] if p != -1 else Quaternion.IDENTITY
			out.rotation_track_insert_key(out_rot[ti], t, (parent_q.inverse() * tg[ti]).normalized())
		if root_motion:
			out.position_track_insert_key(root_pos, t, motion.origin)
			out.rotation_track_insert_key(root_rot, t, motion.basis.get_rotation_quaternion())
	return out


## Model-space bone positions for a pose given as global rotations.
func _positions(tg: Dictionary, hips: int, hips_pos: Vector3) -> Dictionary:
	var pos := {}
	for ti in tgt_skel.get_bone_count():
		var p := tgt_skel.get_bone_parent(ti)
		var local := hips_pos if ti == hips else tgt_skel.get_bone_rest(ti).origin
		pos[ti] = (pos[p] + tg[p] * local) if p != -1 else local
	return pos


## How deep a sphere at p sinks into the trunk, and the way out: [depth, normal].
func _body_depth(p: Vector3, radius: float) -> Array:
	if p.y <= body_rows[0][0] or p.y >= body_rows[-1][0]:
		return [0.0, Vector3.ZERO]
	var k := 0
	while body_rows[k + 1][0] < p.y:
		k += 1
	var a: Array = body_rows[k]
	var b: Array = body_rows[k + 1]
	var f: float = (p.y - a[0]) / (b[0] - a[0])
	var rx: float = lerpf(a[1], b[1], f)
	var front: float = lerpf(a[2], b[2], f)
	var back: float = lerpf(a[3], b[3], f)
	var cz := (front + back) * 0.5
	var rz := (front - back) * 0.5
	var v := Vector2(p.x, p.z - cz)
	if v.length() < 1e-4:
		return [minf(rx, rz) + radius, Vector3.BACK]
	var d := Vector2(v.x / rx, v.y / rz).length()
	var dir := v.normalized()
	var rad := 1.0 / Vector2(dir.x / rx, dir.y / rz).length()
	var n := Vector3(v.x / (rx * rx), 0.0, v.y / (rz * rz)).normalized()
	return [(1.0 - d) * rad + radius, n]


## Swings the upper arm, then the forearm, then the hand out of the trunk
## wherever the library pose (made for a slim mannequin) buries them in it.
func _keep_arms_out_of_body(tg: Dictionary, hips: int, hips_pos: Vector3) -> void:
	for side in ["Left", "Right"]:
		for entry in ARM_COLLIDERS:
			var bone := tgt_skel.find_bone(side + entry[0])
			for _iter in 6:
				var pos := _positions(tg, hips, hips_pos)
				var joint: Vector3 = pos[bone]
				var best_depth := 0.0
				var axis := Vector3.ZERO
				var angle := 0.0
				for c in entry[1]:
					var pb := tgt_skel.find_bone(side + c[0])
					var pt: Vector3 = pos[pb]
					if c[1] >= 0.0:
						var child := tgt_skel.find_bone(side + ("LowerArm" if c[0] == "UpperArm" else "Hand"))
						pt = pt.lerp(pos[child], c[1])
					var hit := _body_depth(pt, c[2])
					var depth: float = hit[0] * c[3]
					var lever := pt - joint
					if depth > best_depth and lever.length() > 0.02:
						var ax: Vector3 = lever.cross(hit[1])
						if ax.length() > 1e-5:
							best_depth = depth
							axis = ax.normalized()
							angle = minf(depth / lever.length(), 0.35)
				if best_depth < 0.002:
					break
				var r := Quaternion(axis, angle * 1.1)
				for d in descendants[bone]:
					tg[d] = (r * tg[d]).normalized()


func _set_global(tg: Dictionary, bone: int, q: Quaternion) -> void:
	var r: Quaternion = q * (tg[bone] as Quaternion).inverse()
	for d in descendants[bone]:
		tg[d] = (r * tg[d]).normalized()


## A point on the belly surface (rest pose), lifted off it by `lift`.
func _belly_point(x: float, y: float, lift: float) -> Vector3:
	var k := 0
	while body_rows[k + 1][0] < y:
		k += 1
	var a: Array = body_rows[k]
	var b: Array = body_rows[k + 1]
	var f: float = (y - a[0]) / (b[0] - a[0])
	var rx: float = lerpf(a[1], b[1], f)
	var front: float = lerpf(a[2], b[2], f)
	var back: float = lerpf(a[3], b[3], f)
	var cz := (front + back) * 0.5
	var rz := (front - back) * 0.5
	var z := cz + rz * sqrt(maxf(1.0 - pow(x / rx, 2.0), 0.0))
	var n := Vector3(x / (rx * rx), 0.0, (z - cz) / (rz * rz)).normalized()
	return Vector3(x, y, z) + n * lift


func _rest_arms_on_belly(tg: Dictionary, hips: int, hips_pos: Vector3, t: float) -> void:
	var chest := tgt_skel.find_bone("Chest")  # the belly rides on the chest bone
	for side in ["Left", "Right"]:
		var sgn := 1.0 if side == "Left" else -1.0
		var sh := tgt_skel.find_bone(side + "Shoulder")
		var ua := tgt_skel.find_bone(side + "UpperArm")
		var la := tgt_skel.find_bone(side + "LowerArm")
		var hand := tgt_skel.find_bone(side + "Hand")
		var pos := _positions(tg, hips, hips_pos)
		var chest_delta: Quaternion = tg[chest] * tgt_rest_global[chest].basis.get_rotation_quaternion().inverse()
		var to_model := func(rest_p: Vector3) -> Vector3:
			return pos[chest] + chest_delta * (rest_p - tgt_rest_global[chest].origin)
		# A slow, contented pat: the hands lift and settle on the belly.
		var pat := 0.012 * maxf(sin(t * TAU / 1.25 + (0.0 if sgn > 0.0 else 0.9)), 0.0)
		var wrist: Vector3 = to_model.call(_belly_point(BELLY_WRIST.x * sgn, BELLY_WRIST.y, 0.032 + pat))
		var tips: Vector3 = to_model.call(_belly_point(BELLY_FINGERS.x * sgn, BELLY_FINGERS.y, 0.02 + pat * 0.5))
		var normal: Vector3 = chest_delta * (_belly_point(BELLY_WRIST.x * sgn, BELLY_WRIST.y, 1.0) - _belly_point(BELLY_WRIST.x * sgn, BELLY_WRIST.y, 0.0))
		# Collarbone forward, from the chest's frame.
		var protract := Quaternion(chest_delta * Vector3.UP, -sgn * deg_to_rad(BELLY_PROTRACT_DEG))
		_set_global(tg, sh, protract * chest_delta * tgt_rest_global[sh].basis.get_rotation_quaternion())
		pos = _positions(tg, hips, hips_pos)
		# Two-bone IK, elbow out to the side and a little back.
		var a: Vector3 = pos[ua]
		var l1: float = a.distance_to(pos[la])
		var l2: float = pos[la].distance_to(pos[hand])
		var to_w: Vector3 = wrist - a
		var dist := clampf(to_w.length(), absf(l1 - l2) + 0.002, (l1 + l2) * 0.999)
		var dir := to_w.normalized()
		var pole: Vector3 = chest_delta * Vector3(sgn, -0.6, -0.35)
		pole = (pole - dir * pole.dot(dir)).normalized()
		var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
		var elbow := a + dir * (cos_a * l1) + pole * (sqrt(1.0 - cos_a * cos_a) * l1)
		var w2 := a + dir * dist
		_set_global(tg, ua, Quaternion((pos[la] - a).normalized(), (elbow - a).normalized()) * tg[ua])
		pos = _positions(tg, hips, hips_pos)
		_set_global(tg, la, Quaternion((pos[hand] - pos[la]).normalized(), (w2 - pos[la]).normalized()) * tg[la])
		pos = _positions(tg, hips, hips_pos)
		# Hand flat on the belly: fingers towards the middle, palm onto it.
		var knuckle := tgt_skel.find_bone(side + "MiddleProximal")
		var thumb := tgt_skel.find_bone(side + "ThumbTip")
		var fdir: Vector3 = (pos[knuckle] - pos[hand]).normalized()
		var want_f: Vector3 = (tips - pos[hand])
		want_f = (want_f - normal * want_f.dot(normal)).normalized()
		var q1: Quaternion = Quaternion(fdir, want_f) * tg[hand]
		_set_global(tg, hand, q1)
		pos = _positions(tg, hips, hips_pos)
		var palm: Vector3 = pos[thumb] - pos[knuckle]
		palm = (palm - want_f * palm.dot(want_f)).normalized()
		var want_p := -(normal - want_f * normal.dot(want_f)).normalized()
		var twist := palm.signed_angle_to(want_p, want_f)
		_set_global(tg, hand, Quaternion(want_f, twist) * tg[hand])
