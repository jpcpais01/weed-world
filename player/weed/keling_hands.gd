class_name KelingHands
extends SkeletonModifier3D
## Two-handed poses for rolling and smoking, layered on top of everything else
## (after the grab): each arm reaches its goal with two-bone IK, the hand turns
## to face the way it is told, the fingers curl and spread one by one, and the
## thumb really meets the index finger in a pinch (a little CCD chain IK), so
## a paper or a joint sits between two fingertips. KelingWeed drives it all
## every frame from its choreography.
##
## A goal can be pinned to the wrist, to the pinch (thumb tip on the index
## pad) or to the finger pads, so "put the pinch here" lands the fingertips
## there however the hand is turned. The hands are big (wrist to fingertip is
## about 19 cm), which is what lets the fingertips meet in front of the belly
## even though the stubby arms can't.
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
## How far the fingers fan apart at spread 1 (degrees, index / ring).
const SPREAD_DEG := 16.0
## Where the goal sits on the hand.
enum Pin { WRIST, PINCH, PADS, GRIP }

## Per side:
##  goal     where the pinned point goes (skeleton space)
##  pin      which point of the hand is pinned to the goal (Pin)
##  w        0..1 blend over the animation
##  fingers  desired finger direction, palm: desired palm normal
##  curl     base curl of every finger (0 open .. 1 fist, negative bends back)
##  index / middle / ring / thumb: extra curl per finger
##  spread   fingers fan apart (0..1, negative squeezes them together)
##  pinch    0..1: the thumb tip goes to the index pad (CCD)
##  rub      0..1: the thumb rubs up and down the index (crumbling, twisting)
##  wiggle   0..1: restless fingers
var arms := {
	"Left": _new_arm(),
	"Right": _new_arm(),
}
## Inhale: the round chest swells (0..1).
var chest_swell := 0.0
## Head tips back (radians, +) to blow smoke upwards, forward (-) to look down.
var head_pitch := 0.0
## Head turns (radians, + towards the Keling's left) and tilts (+ left ear down).
var head_yaw := 0.0
var head_roll := 0.0
## Spine bow (radians, + forward) to bring the hands and face together.
var lean := 0.0
## Body sway side to side (radians), for a happy little shimmy.
var sway := 0.0

## How far the chest has moved from its rest spot this frame (sitting, hops,
## breathing). Goals ride along with it so the hands stay with the body.
var body_delta := Vector3.ZERO

var _bones := {}
var _chest_rest := Vector3.ZERO
var _fingers := {}
var _palm_normal := {}
var _finger_dir := {}
var _pin_local := {}       # side -> {Pin: offset in hand space}, measured last frame
var _t := 0.0


static func _new_arm() -> Dictionary:
	return {"goal": Vector3.ZERO, "pin": Pin.WRIST, "w": 0.0, "fingers": Vector3.FORWARD, "palm": Vector3.UP,
		"curl": 0.0, "index": 0.0, "middle": 0.0, "ring": 0.0, "thumb": 0.0, "spread": 0.0,
		"pinch": 0.0, "rub": 0.0, "wiggle": 0.0}


func _ready() -> void:
	var skel := get_skeleton()
	if skel == null:
		return
	for n in ["Hips", "Spine", "Chest", "UpperChest", "Neck", "Head"]:
		_bones[n] = skel.find_bone(n)
	_chest_rest = skel.get_bone_global_rest(_bones["Chest"]).origin
	for s in SIDES:
		for n in ["Shoulder", "UpperArm", "LowerArm", "Hand"]:
			_bones[s + n] = skel.find_bone(s + n)
		_setup_fingers(skel, s)


func active() -> bool:
	return arms.Left.w > 0.001 or arms.Right.w > 0.001 or chest_swell > 0.001 or absf(head_pitch) > 0.001 \
		or absf(head_yaw) > 0.001 or absf(head_roll) > 0.001 or absf(lean) > 0.001 or absf(sway) > 0.001


## Puts an arm back to neutral settings (keeps its goal and weight).
func reset_fingers(side: String) -> void:
	var a: Dictionary = arms[side]
	for k in ["curl", "index", "middle", "ring", "thumb", "spread", "pinch", "rub", "wiggle"]:
		a[k] = 0.0


## Works out, from the rest pose, which way each finger curls and fans (same
## recipe as KelingGrab), and where the pinch and pads sit on the hand.
func _setup_fingers(skel: Skeleton3D, s: String) -> void:
	var rest := func(n: String) -> Transform3D: return skel.get_bone_global_rest(skel.find_bone(s + n))
	var hand_xf: Transform3D = rest.call("Hand")
	var hand_q: Quaternion = hand_xf.basis.get_rotation_quaternion()
	var knuckles := Vector3.ZERO
	for f in ["Index", "Middle", "Ring"]:
		knuckles += rest.call(FINGER_NAMES[f][0]).origin / 3.0
	var mid_base: Vector3 = rest.call("MiddleProximal").origin
	var mid_dir: Vector3 = (rest.call("MiddleIntermediate").origin - mid_base).normalized()
	var thumb_tip: Vector3 = rest.call("ThumbTip").origin
	var palm: Vector3 = thumb_tip - knuckles
	palm = (palm - mid_dir * palm.dot(mid_dir)).normalized()
	_palm_normal[s] = hand_q.inverse() * palm
	_finger_dir[s] = hand_q.inverse() * (knuckles - hand_xf.origin).normalized()
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
		# Fanning: index and ring swing away from the middle finger.
		var lateral := base - mid_base
		lateral = lateral - d * lateral.dot(d)
		var fan := Vector3.ZERO
		if lateral.length() > 0.001 and f != "Thumb":
			fan = hand_q.inverse() * d.cross(lateral.normalized()).normalized()
		_fingers[s][f] = {"bones": bones, "axis": hand_q.inverse() * axis, "fan": fan}
	# First guesses for the pinned points (refined from the live pose every frame).
	var inv := hand_xf.affine_inverse()
	var index_pad: Vector3 = (rest.call("IndexDistal").origin as Vector3).lerp(rest.call("IndexTip").origin, 0.5)
	_pin_local[s] = {
		Pin.WRIST: Vector3.ZERO,
		Pin.PINCH: inv * thumb_tip.lerp(index_pad, 0.5),
		Pin.PADS: inv * (rest.call("IndexIntermediate").origin as Vector3).lerp(rest.call("MiddleIntermediate").origin, 0.5),
		Pin.GRIP: inv * knuckles,
	}


## Skeleton-space transform of a hand bone in the current (modified) pose.
func hand_pose(side: String) -> Transform3D:
	var skel := get_skeleton()
	return skel.get_bone_global_pose(_bones[side + "Hand"]) if skel else Transform3D()


func bone_point(side: String, bone: String) -> Vector3:
	var skel := get_skeleton()
	return skel.get_bone_global_pose(skel.find_bone(side + bone)).origin


## Skeleton-space point between the index and middle knuckles, nudged out
## along the fingers: where a joint is held between puffs.
func grip_point(side: String, along := 0.03) -> Vector3:
	var hand := hand_pose(side).origin
	var k := (bone_point(side, "IndexProximal") + bone_point(side, "MiddleProximal")) * 0.5
	return k + (k - hand).normalized() * along


## Where the thumb tip meets the index pad, in the current pose.
func pinch_point(side: String) -> Vector3:
	return bone_point(side, "ThumbTip").lerp(_index_pad(side), 0.5)


## The flat of the first two fingers (where a paper rests on an open hand).
func pads_point(side: String) -> Vector3:
	return bone_point(side, "IndexIntermediate").lerp(bone_point(side, "MiddleIntermediate"), 0.5)


func finger_direction(side: String) -> Vector3:
	var q := hand_pose(side).basis.get_rotation_quaternion()
	return (q * _finger_dir[side]).normalized()


func palm_direction(side: String) -> Vector3:
	var q := hand_pose(side).basis.get_rotation_quaternion()
	return (q * _palm_normal[side]).normalized()


func _index_pad(side: String) -> Vector3:
	return bone_point(side, "IndexDistal").lerp(bone_point(side, "IndexTip"), 0.55)


## Where the wrist has to be for the pinned point of a hand turned this way to
## land on `goal` (skeleton space, before the body offset).
func wrist_goal(side: String, goal: Vector3, pin: int, fingers: Vector3, palm: Vector3) -> Vector3:
	if pin == Pin.WRIST or not _pin_local.has(side):
		return goal
	return goal - _hand_rotation(side, fingers, palm) * (_pin_local[side][pin] as Vector3)


## The hand rotation that points the fingers along `fingers` and turns the
## palm towards `palm` (whatever the animation had).
func _hand_rotation(s: String, fingers: Vector3, palm: Vector3) -> Quaternion:
	var f_local: Vector3 = _finger_dir[s]
	var p_local: Vector3 = _palm_normal[s]
	p_local = (p_local - f_local * p_local.dot(f_local)).normalized()
	var f := fingers.normalized()
	var p := palm - f * palm.dot(f)
	if p.length() < 0.01:
		p = Vector3.UP - f * f.y
		if p.length() < 0.01:
			p = Vector3.BACK
	p = p.normalized()
	var local := Basis(f_local, p_local, f_local.cross(p_local))
	var world := Basis(f, p, f.cross(p))
	return (world * local.inverse()).get_rotation_quaternion()


func _process_modification_with_delta(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_process_modification_with_delta_timed(delta)
	PerfMeter.add(&"hands IK", Time.get_ticks_usec() - t0)


func _process_modification_with_delta_timed(delta: float) -> void:
	var skel := get_skeleton()
	if skel == null or _bones.is_empty():
		return
	body_delta = skel.get_bone_global_pose(_bones["Chest"]).origin - _chest_rest
	if not active():
		return
	_t += delta
	if absf(sway) > 0.0001:
		_rotate_model(skel, _bones["Spine"], Vector3.FORWARD, sway)
	if absf(lean) > 0.0001:
		_rotate_model(skel, _bones["Spine"], Vector3.RIGHT, lean * 0.55)
		_rotate_model(skel, _bones["Chest"], Vector3.RIGHT, lean * 0.45)
	if chest_swell > 0.0001:
		var c: int = _bones["Chest"]
		skel.set_bone_pose_scale(c, skel.get_bone_pose_scale(c) * Vector3(1.0 + 0.06 * chest_swell, 1.0 + 0.035 * chest_swell, 1.0 + 0.07 * chest_swell))
	if absf(head_pitch) > 0.0001:
		_rotate_model(skel, _bones["Neck"], Vector3.RIGHT, -head_pitch * 0.4)
		_rotate_model(skel, _bones["Head"], Vector3.RIGHT, -head_pitch * 0.6)
	if absf(head_yaw) > 0.0001:
		_rotate_model(skel, _bones["Neck"], Vector3.UP, head_yaw * 0.35)
		_rotate_model(skel, _bones["Head"], Vector3.UP, head_yaw * 0.65)
	if absf(head_roll) > 0.0001:
		_rotate_model(skel, _bones["Head"], Vector3.FORWARD, -head_roll)
	# Goals are relative to the chest, which the edits above (and the
	# animation) move about.
	body_delta = skel.get_bone_global_pose(_bones["Chest"]).origin - _chest_rest
	for s in SIDES:
		var a: Dictionary = arms[s]
		var w: float = a.w
		if w <= 0.001:
			continue
		var hand_bone: int = _bones[s + "Hand"]
		var target_q := _hand_rotation(s, a.fingers, a.palm)
		# Pinned point -> wrist goal, using where that point sat on the hand
		# last frame (the fingers move smoothly, so it is a frame-late guess
		# that settles at once).
		var goal: Vector3 = a.goal + body_delta
		var pin: int = a.pin
		if pin != Pin.WRIST:
			goal -= target_q * (_pin_local[s][pin] as Vector3)
		# The collarbone: back to its rest set first (the idle animations hold
		# the shoulders well back, which costs the stubby arms 15 cm of reach),
		# then slid towards the goal so the arm reaches further still.
		var sh: int = _bones[s + "Shoulder"]
		var sh_rest := skel.get_bone_rest(sh).basis.get_rotation_quaternion()
		skel.set_bone_pose_rotation(sh, skel.get_bone_pose_rotation(sh).slerp(sh_rest, w))
		var sh_pos := skel.get_bone_global_pose(sh).origin
		var arm_root := skel.get_bone_global_pose(_bones[s + "UpperArm"]).origin
		var to_g: Vector3 = goal - sh_pos
		var clav_axis := (arm_root - sh_pos).cross(to_g)
		if clav_axis.length() > 1e-5:
			_rotate_model(skel, sh, clav_axis.normalized(), minf((arm_root - sh_pos).angle_to(to_g), deg_to_rad(24.0)) * w)
		var anim_hand := skel.get_bone_global_pose(hand_bone).origin
		_arm_ik(skel, s, anim_hand.lerp(goal, w))
		var hq := skel.get_bone_global_pose(hand_bone).basis.get_rotation_quaternion()
		_set_global_rotation(skel, hand_bone, hq.slerp(target_q, w))
		_fingers_pose(skel, s, a, w)
		_thumb_pose(skel, s, a, w)
		_measure_pins(skel, s)


func _fingers_pose(skel: Skeleton3D, s: String, a: Dictionary, w: float) -> void:
	var hq := skel.get_bone_global_pose(_bones[s + "Hand"]).basis.get_rotation_quaternion()
	var k := 0
	for f in ["Index", "Middle", "Ring"]:
		var info: Dictionary = _fingers[s][f]
		var axis: Vector3 = (hq * info["axis"]).normalized()
		var curl: float = a.curl + a[f.to_lower()]
		var wig: float = a.wiggle * sin(_t * 14.0 + k * 1.7) * 0.35
		# While rubbing, the index rocks against the thumb.
		if f == "Index":
			wig += a.rub * sin(_t * 19.0 + PI) * 0.18
		curl = clampf(curl + wig, -0.25, 1.1)
		var bones: Array = info["bones"]
		var curls: Array = CURL[f]
		var fan: Vector3 = info["fan"]
		var spread: float = a.spread + a.wiggle * 0.15 * sin(_t * 9.0 + k)
		if fan != Vector3.ZERO and absf(spread) > 0.001:
			_rotate_model(skel, bones[0], (hq * fan).normalized(), deg_to_rad(SPREAD_DEG) * spread * w)
		for j in 3:
			_rotate_model(skel, bones[j], axis, deg_to_rad(curls[j]) * curl * w)
		k += 1


## The thumb curls like a finger, then (as much as `pinch` says) bends its
## three joints so the tip lands on the index pad; `rub` slides that target
## up and down the finger.
func _thumb_pose(skel: Skeleton3D, s: String, a: Dictionary, w: float) -> void:
	var info: Dictionary = _fingers[s]["Thumb"]
	var bones: Array = info["bones"]
	var hq := skel.get_bone_global_pose(_bones[s + "Hand"]).basis.get_rotation_quaternion()
	var axis: Vector3 = (hq * info["axis"]).normalized()
	var curl: float = clampf(a.curl * 0.6 + a.thumb + a.wiggle * sin(_t * 11.0) * 0.3, -0.3, 1.1)
	var curls: Array = CURL["Thumb"]
	for j in 3:
		_rotate_model(skel, bones[j], axis, deg_to_rad(curls[j]) * curl * w)
	var pinch: float = a.pinch * w
	if pinch <= 0.001:
		return
	var along: float = 0.55 + a.rub * 0.35 * sin(_t * 19.0)
	var target := bone_point(s, "IndexIntermediate").lerp(bone_point(s, "IndexTip"), along)
	# Sit on the pad side of the finger, not inside it.
	target += (hq * _palm_normal[s]).normalized() * 0.006
	var tip: int = bones[3]
	for _iter in 4:
		for j in [2, 1, 0]:
			var b: int = bones[j]
			var o := skel.get_bone_global_pose(b).origin
			var to_tip := skel.get_bone_global_pose(tip).origin - o
			var to_target := target - o
			if to_tip.length() < 1e-4 or to_target.length() < 1e-4:
				continue
			var ax := to_tip.cross(to_target)
			if ax.length() < 1e-6:
				continue
			var ang := minf(to_tip.angle_to(to_target), deg_to_rad(35.0)) * pinch
			_rotate_model(skel, b, ax.normalized(), ang)


func _measure_pins(skel: Skeleton3D, s: String) -> void:
	var inv := skel.get_bone_global_pose(_bones[s + "Hand"]).affine_inverse()
	var p: Dictionary = _pin_local[s]
	p[Pin.PINCH] = inv * pinch_point(s)
	p[Pin.PADS] = inv * pads_point(s)
	p[Pin.GRIP] = inv * grip_point(s, 0.0)


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
	var pref := Vector3(sgn * 0.85, -1.0, -0.25)
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
