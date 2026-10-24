class_name KelingWeed
extends Node
## A Keling's weed: the pouch of picked buds, rolling a joint and smoking it.
##
##  * Grab a ripe bud off a wild plant and it goes in the pouch (by strain).
##  * Press the weed action (R / right trigger / the leaf button) with a bud:
##    the Keling rolls a joint in a 10 second little ritual: bud and paper
##    float up between its hands, the bud crumbles onto the paper, the paper
##    curls itself up, gets a lick, a twist, and ta-da.
##  * Press again with the joint: a fairy flame lights it, and each press
##    takes one of its three puffs. Every exhale feeds a high (WeedHigh) themed
##    by the bench the Keling sits on, or the dreamy Glade Glow anywhere else.
##
## Works standing still or sitting on a bench; walking off cancels (the bud
## or the puff is kept). Everything runs per Keling, ready for co-op.

signal pouch_changed
signal joint_changed
signal act_changed(act: int)
signal bud_collected(strain: StringName, first: bool)
signal joint_rolled(strain: StringName)
signal puffed(element: StringName, puffs_left: int)
signal note(text: String)

enum Act { NONE, ROLL, LIGHT, HIT }

const ROLL_TIME := 10.0
const LIGHT_TIME := 1.5
const HIT_TIME := 3.8
const HITS := 3
const MAX_BUDS := 12
const SAVE_PATH := "user://weed.cfg"
## Rolling stages for the HUD: start time and caption.
const ROLL_STAGES := [[0.0, "Getting ready"], [0.8, "Breaking up the bud"], [3.4, "Rolling"], [6.6, "Sealing"], [8.0, "Twisting the tip"], [9.0, "Ready!"]]

## Skeleton-space landmarks (+Z forward, +X the Keling's left).
const MOUTH := Vector3(0.0, 0.835, 0.455)
const WORK := Vector3(0.0, 0.80, 0.6)
const TRAY_L := Vector3(0.17, 0.78, 0.46)
const TRAY_R := Vector3(-0.17, 0.78, 0.46)
const HOLD_R := Vector3(-0.25, 0.64, 0.40)
const TO_MOUTH_R := Vector3(-0.15, 0.80, 0.47)
const TADA_R := Vector3(-0.24, 0.97, 0.42)
## Which way the joint points out of the mouth while smoking.
const MOUTH_OUT := Vector3(-0.55, -0.12, 1.0)

var keling: KelingController
var hands: KelingHands
var high: WeedHigh
var hud: Node
var pouch := {}                       # strain -> count
var selected: StringName = &""
var joint_strain: StringName = &""
var joint_puffs := 0
var lit := false
var discovered: Array[StringName] = []
var act: int = Act.NONE
var act_t := 0.0
var local := true

var _skel: Skeleton3D
var _rig: Node3D
var _float_bud: MeshInstance3D
var _float_bud_strain: StringName = &""
var _paper: MeshInstance3D
var _paper_mat: ShaderMaterial
var _joint: Dictionary
var _crumbs: CPUParticles3D
var _sparkle: CPUParticles3D
var _exhale: CPUParticles3D
var _wisp: CPUParticles3D
var _flame: MeshInstance3D
var _fist_bud: Node3D
var _fist_mesh: MeshInstance3D
var _hold := 0.0
var _left_w := 0.0
var _roll_strain: StringName = &""
var _hit_counted := false
var _events := {}
var _prompt: Label3D
var _prompt_alpha := 0.0
var _prompt_tick := 0.0
var _prompt_bud: WeedBud
var _joint_hidden := 0.0
var _remote_element: StringName = &"none"


func setup(p_keling: KelingController, skeleton: Skeleton3D) -> void:
	keling = p_keling
	_skel = skeleton
	name = "Weed"
	hands = KelingHands.new()
	hands.name = "Hands"
	_skel.add_child(hands)
	hands.modification_processed.connect(_place_props)
	_rig = Node3D.new()
	_rig.name = "WeedProps"
	_skel.add_child(_rig)
	high = WeedHigh.new()
	high.name = "High"
	keling.add_child.call_deferred(high)
	high.setup(keling, self)
	keling.grabbed.connect(_on_grabbed)
	_build_props()
	_load()


func _ready() -> void:
	local = is_local()
	if local:
		hud = WeedHud.new()
		hud.name = "WeedHud"
		keling.add_child.call_deferred(hud)
		hud.setup.call_deferred(self)
	_build_prompt()


## False for co-op puppets of other players' Kelings (no HUD, input, saves
## or screen effects; they just replay what the real one does).
func is_local() -> bool:
	var v = keling.get("is_local") if keling else null
	return v == null or bool(v)


# ---------------------------------------------------------------------------
# Pouch

func bud_count(strain: StringName = &"") -> int:
	if strain != &"":
		return pouch.get(strain, 0)
	var n := 0
	for k in pouch:
		n += pouch[k]
	return n


func has_joint() -> bool:
	return joint_strain != &"" and joint_puffs > 0


func add_bud(strain: StringName) -> bool:
	if bud_count() >= MAX_BUDS:
		note.emit("Your pouch is full")
		return false
	pouch[strain] = pouch.get(strain, 0) + 1
	selected = strain
	var first := strain not in discovered
	if first:
		discovered.append(strain)
	bud_collected.emit(strain, first)
	pouch_changed.emit()
	_save()
	return true


## Next strain in the pouch (Q, or tap the pouch).
func cycle_strain() -> void:
	var have: Array[StringName] = []
	for s in WeedStrains.ORDER:
		if bud_count(s) > 0:
			have.append(s)
	if have.is_empty():
		return
	var i := have.find(selected)
	selected = have[(i + 1) % have.size()]
	pouch_changed.emit()


func _take_bud() -> StringName:
	if bud_count(selected) <= 0:
		selected = &""
		for s in WeedStrains.ORDER:
			if bud_count(s) > 0:
				selected = s
				break
	if selected == &"":
		return &""
	var s := selected
	pouch[s] -= 1
	if pouch[s] <= 0:
		pouch.erase(s)
	pouch_changed.emit()
	return s


func _on_grabbed(target: Node) -> void:
	var bud := target as WeedBud
	if bud and local:
		add_bud(bud.strain)
		net_event(&"weed_picked", bud.net_id)


## Tells the other players (when online) about a change to the shared world.
func net_event(kind: StringName, id: Variant, data := {}) -> void:
	var tree := keling.get_tree() if keling else null
	var net := tree.root.get_node_or_null("Net") if tree else null
	if net and net.has_method("send_world_event"):
		net.send_world_event(kind, id, data)


## A bud for the controller to show in the closed fist after a pick. Built
## so the controller's sprig placement (stem down through the fist) works.
func fist_bud(strain: StringName) -> Node3D:
	_fist_mesh.material_override = WeedKit.bud_material(strain)
	return _fist_bud


# ---------------------------------------------------------------------------
# Actions

## What the weed button would do right now: &"roll", &"smoke" or &"".
func next_action() -> StringName:
	if act != Act.NONE:
		return &"busy"
	if has_joint():
		return &"smoke"
	if bud_count() > 0:
		return &"roll"
	return &""


## The weed button.
func use() -> void:
	if act != Act.NONE:
		return
	match next_action():
		&"smoke":
			if keling.begin_weed_act():
				_start(Act.HIT if lit else Act.LIGHT)
		&"roll":
			if keling.begin_weed_act():
				_roll_strain = _take_bud()
				_start(Act.ROLL)
		_:
			note.emit("Pick a bud from a wild weed plant first")


func busy() -> bool:
	return act != Act.NONE


func _start(a: int) -> void:
	act = a
	act_t = 0.0
	_events.clear()
	_hit_counted = false
	if a == Act.ROLL:
		_prepare_roll(_roll_strain)
	elif joint_strain != &"":
		_paint_joint(joint_strain)
	act_changed.emit(act)
	if local:
		match a:
			Act.ROLL:
				keling.activity_changed.emit(&"roll", {"strain": _roll_strain})
			Act.LIGHT:
				keling.activity_changed.emit(&"light", {"strain": joint_strain})
			Act.HIT:
				keling.activity_changed.emit(&"puff", {"strain": joint_strain, "element": keling.weed_element()})


func _announce_rest() -> void:
	if not local:
		return
	if has_joint():
		keling.activity_changed.emit(&"hold", {"strain": joint_strain, "puffs": joint_puffs, "lit": lit})
	else:
		keling.activity_changed.emit(&"idle", {})


## Co-op: mirror another player's activity on their puppet here. Nothing is
## taken from or given to any pouch; it is all for show.
func play_remote(activity: StringName, data: Dictionary) -> void:
	var strain := StringName(data.get("strain", &"ember"))
	if not WeedStrains.STRAINS.has(strain):
		strain = &"ember"
	match activity:
		&"roll":
			_roll_strain = strain
			_start(Act.ROLL)
		&"light":
			joint_strain = strain
			joint_puffs = maxi(joint_puffs, 1)
			_start(Act.LIGHT)
		&"puff":
			joint_strain = strain
			joint_puffs = maxi(joint_puffs, 1)
			lit = true
			_remote_element = StringName(data.get("element", &"none"))
			if act == Act.HIT and act_t < 0.6:
				return  # already playing it (light flows straight into the first puff)
			_start(Act.HIT)
		&"hold":
			if act != Act.NONE:
				_stop_act()
			joint_strain = strain
			joint_puffs = int(data.get("puffs", HITS))
			lit = bool(data.get("lit", false))
			_paint_joint(strain)
		&"idle":
			if act != Act.NONE:
				_stop_act()
			_clear_joint()


## Walking away, jumping or standing up stops what the hands are doing. The
## bud goes back in the pouch, an unfinished puff isn't spent.
func interrupt() -> void:
	if act == Act.NONE:
		return
	if act == Act.ROLL:
		if act_t < 6.6:
			if local:
				pouch[_roll_strain] = pouch.get(_roll_strain, 0) + 1
				pouch_changed.emit()
			_float_bud.visible = false
			_paper.visible = false
			_joint.root.visible = false
		else:
			_finish_roll()
	_stop_act()
	_save()
	_announce_rest()


func _stop_act() -> void:
	_float_bud.visible = false
	_paper.visible = false
	_crumbs.emitting = false
	_flame.visible = false
	hands.chest_swell = 0.0
	hands.head_pitch = 0.0
	act = Act.NONE
	act_changed.emit(act)


func roll_stage() -> String:
	var label := ""
	for s in ROLL_STAGES:
		if act_t >= s[0]:
			label = s[1]
	return label


func progress() -> float:
	match act:
		Act.ROLL:
			return act_t / ROLL_TIME
		Act.LIGHT:
			return act_t / LIGHT_TIME
		Act.HIT:
			return act_t / HIT_TIME
	return 0.0


func _physics_process(delta: float) -> void:
	if keling == null:
		return
	if act != Act.NONE:
		act_t += delta
		if local and not keling.weed_act_allowed():
			interrupt()
	match act:
		Act.ROLL:
			if act_t >= ROLL_TIME:
				_finish_roll()
				act = Act.NONE
				act_changed.emit(act)
				_announce_rest()
		Act.LIGHT:
			if act_t >= LIGHT_TIME:
				lit = true
				_start(Act.HIT)
		Act.HIT:
			if act_t >= HIT_TIME:
				act = Act.NONE
				if joint_puffs <= 0:
					_clear_joint()
				act_changed.emit(act)
				_save()
				_announce_rest()
	# The joint rests in the right hand between puffs; tucked away during grabs.
	var want_hold := 1.0 if has_joint() and act == Act.NONE and keling.mode != KelingController.Mode.GRAB else 0.0
	if act != Act.NONE:
		want_hold = 0.0
	_hold = move_toward(_hold, want_hold, delta * 3.0)
	_joint_hidden = move_toward(_joint_hidden, 1.0 if keling.mode == KelingController.Mode.GRAB else 0.0, delta * 5.0)
	_update_prompt(delta)


func _event(key: String, at: float) -> bool:
	if act_t >= at and not _events.has(key):
		_events[key] = true
		return true
	return false


# ---------------------------------------------------------------------------
# Rolling choreography

func _prepare_roll(strain: StringName) -> void:
	var info := WeedStrains.info(strain)
	_float_bud.material_override = WeedKit.bud_material(strain)
	_float_bud_strain = strain
	_paper_mat.set_shader_parameter("fill_color", info.bud_tint.lerp(Color(0.42, 0.66, 0.28), 0.55))
	_paper_mat.set_shader_parameter("roll", 0.0)
	_paper_mat.set_shader_parameter("fill", 0.0)
	_crumbs.mesh.surface_get_material(0).albedo_color = Color(0.4, 0.62, 0.25).lerp(info.bud_tint, 0.35)
	_paint_joint(strain)


func _finish_roll() -> void:
	joint_strain = _roll_strain
	joint_puffs = HITS
	lit = false
	_float_bud.visible = false
	_paper.visible = false
	joint_rolled.emit(joint_strain)
	joint_changed.emit()
	_save()


func _clear_joint() -> void:
	joint_strain = &""
	joint_puffs = 0
	lit = false
	joint_changed.emit()


func _paint_joint(strain: StringName) -> void:
	var info := WeedStrains.info(strain)
	(_joint.body_mat as StandardMaterial3D).backlight = info.glow * 0.4
	_exhale.color = Color(info.smoke, 0.5)
	_wisp.color = Color(info.smoke, 0.3)


func _e(a: float, b: float) -> float:
	return smoothstep(a, b, act_t)


func _arm(side: String, goal: Vector3, w: float, curl := 0.2, pinch := 0.0, wiggle := 0.0, fingers := Vector3(0, 0.1, 1), palm := Vector3.UP) -> void:
	var a: Dictionary = hands.arms[side]
	a.goal = goal
	a.w = w
	a.curl = curl
	a.pinch = pinch
	a.wiggle = wiggle
	a.fingers = fingers
	a.palm = palm


func _pose_roll() -> void:
	var t := act_t
	var w_in := _e(0.0, 0.6)
	var left_w := w_in * (1.0 - _e(9.2, 9.9))
	var bd := hands.body_delta
	var work := WORK + bd

	# Left hand: offers the paper, conducts the magic, then lets go.
	var lg := TRAY_L
	var lpalm := Vector3(-0.5, 1.0, 0.0)
	var lfing := Vector3(-0.35, 0.1, 1.0)
	var lwig := 0.0
	var lcurl := 0.15
	# Right hand: offers the bud, crumbles it, rolls, licks, shows it off.
	var rg := TRAY_R
	var rpalm := Vector3(0.5, 1.0, 0.0)
	var rfing := Vector3(0.35, 0.1, 1.0)
	var rwig := 0.0
	var rcurl := 0.15
	var rpinch := 0.0

	if t < 3.4:
		var k := _e(0.8, 1.3)
		var circ := Vector3(0.0, sin(t * 7.0) * 0.018, cos(t * 7.0) * 0.014) * k
		lg = TRAY_L.lerp(Vector3(0.15, 0.83, 0.5), k) + circ
		rg = TRAY_R.lerp(Vector3(-0.15, 0.83, 0.5), k) + Vector3(circ.x, -circ.y, circ.z)
		lpalm = lpalm.lerp(Vector3(-1.0, 0.2, 0.1), k)
		rpalm = rpalm.lerp(Vector3(1.0, 0.2, 0.1), k)
		lwig = 0.8 * k
		rwig = 0.5 * k
		rcurl = lerpf(0.15, 0.45 + 0.2 * sin(t * 16.0), k * (1.0 - _e(3.1, 3.4)))
	elif t < 6.6:
		var r := sin(t * 9.0) * 0.03
		var k := _e(3.4, 3.7) * (1.0 - _e(6.3, 6.6))
		lg = Vector3(0.15, 0.82 + absf(r) * 0.3, 0.5 + r * k)
		rg = Vector3(-0.15, 0.82 + absf(r) * 0.3, 0.5 - r * k)
		lpalm = Vector3(-0.7, -1.0, 0.2)
		rpalm = Vector3(0.7, -1.0, 0.2)
		lcurl = 0.1
		rcurl = 0.1
		lwig = 0.25
		rwig = 0.25
	elif t < 8.0:
		# Pinch the tube and lick it closed.
		var up := _e(6.8, 7.3) * (1.0 - _e(7.75, 8.0))
		var slide := sin(clampf((t - 7.3) / 0.45, 0.0, 1.0) * PI * 2.0) * 0.035 * up
		rg = Vector3(-0.15, 0.82, 0.5).lerp(TO_MOUTH_R + Vector3(slide, 0.0, 0.0), up)
		rfing = Vector3(0.6, 0.15, 1.0)
		rpalm = Vector3(0.3, -0.2, 0.0)
		rpinch = _e(6.7, 6.95)
		lg = TRAY_L + Vector3(0.0, -0.03, 0.0)
		hands.head_pitch = -0.12 * up
	elif t < 9.0:
		# The tube floats between the hands and twists its tip.
		var k := _e(8.0, 8.3)
		rg = TO_MOUTH_R.lerp(Vector3(-0.16, 0.82, 0.5), k)
		rpinch = 1.0 - k
		lg = Vector3(0.15, 0.84, 0.5) + Vector3(0.0, sin(t * 18.0) * 0.012, 0.0)
		lpalm = Vector3(-1.0, 0.0, 0.2)
		lwig = 1.0
		rwig = 0.4
		hands.head_pitch = 0.0
	else:
		# Ta-da! Up it goes, then down into a relaxed hold.
		var up := _e(9.0, 9.35) * (1.0 - _e(9.55, 10.0))
		var down := _e(9.55, 10.0)
		rg = Vector3(-0.16, 0.82, 0.5).lerp(TADA_R, up).lerp(HOLD_R, down)
		rpinch = 1.0
		rfing = Vector3(0.0, 0.6, 1.0).lerp(Vector3(0.0, 0.3, 1.0), down)
		rpalm = Vector3(1.0, 0.3, 0.0)
		lg = TRAY_L.lerp(TRAY_L + Vector3(0.05, -0.12, -0.05), _e(9.2, 9.9))
		lcurl = 0.3
	_arm("Left", lg, left_w, lcurl, 0.0, lwig, lfing, lpalm)
	_arm("Right", rg, w_in, rcurl, rpinch, rwig, rfing, rpalm)

	# Props: the bud floats from the right palm to the middle and crumbles.
	var bud_from := TRAY_R + Vector3(0.05, 0.08, 0.06) + bd
	var bud_at := bud_from.lerp(work + Vector3(0, 0.07, 0), _e(0.8, 1.3))
	var bud_s := _e(0.15, 0.55) * (1.0 - _e(1.2, 3.3))
	_float_bud.visible = bud_s > 0.01
	_float_bud.position = bud_at + Vector3(0, sin(t * 3.0) * 0.006, 0)
	_float_bud.rotation = Vector3(0.2 * sin(t * 2.0), t * 2.4, 0.0)
	_float_bud.scale = Vector3.ONE * WeedKit.BUD_SCALE * 0.75 * maxf(bud_s, 0.001)
	_crumbs.position = bud_at - Vector3(0, 0.02, 0)
	var crumbling := t > 1.2 and t < 3.3
	if _crumbs.emitting != crumbling:
		_crumbs.emitting = crumbling
	if _event("bud_in", 0.25):
		_burst(bud_from, WeedStrains.info(_roll_strain).glow, 10)
	if _event("paper_in", 0.45):
		_burst(TRAY_L + Vector3(-0.05, 0.07, 0.06) + bd, Color(1, 0.95, 0.85), 8)

	# Paper: up off the left palm, to the middle, filled, curled, licked, twisted.
	var paper_from := TRAY_L + Vector3(-0.05, 0.07, 0.06) + bd
	var paper_s := _e(0.35, 0.75)
	var fill := _e(1.2, 3.4)
	var roll := _e(3.6, 6.3)
	roll = clampf(roll + sin(t * 9.0) * 0.025 * roll * (1.0 - roll) * 4.0, 0.0, 1.0)
	_paper_mat.set_shader_parameter("fill", fill)
	_paper_mat.set_shader_parameter("roll", roll)
	var paper_pos := paper_from.lerp(work, _e(0.8, 1.4))
	var tube_spin := roll * PI * 0.7
	var joint_show := t >= 6.9
	_paper.visible = paper_s > 0.01 and not joint_show
	_paper.position = paper_pos + Vector3(0, sin(t * 2.6) * 0.004, 0)
	_paper.rotation = Vector3(tube_spin, 0.0, 0.0)
	_paper.scale = Vector3.ONE * maxf(paper_s, 0.001)
	var jroot: Node3D = _joint.root
	jroot.visible = joint_show
	if joint_show:
		var twist: Node3D = _joint.twist
		twist.visible = t > 8.4
		twist.scale = Vector3.ONE * _e(8.3, 8.8)
		if t < 8.0:
			# In the right hand's pinch, licked across the lips.
			var g := hands.grip_point("Right")
			var dir := Vector3(1.0, 0.05, 0.15).normalized()
			_set_joint(g - dir * 0.02, dir)
		elif t < 9.0:
			var k := _e(8.0, 8.3)
			var g := hands.grip_point("Right")
			var dir := Vector3(1.0, 0.0, 0.0)
			var centre := work + Vector3(-JOINT_HALF, 0.02, 0)
			var p := g.lerp(centre, k)
			var spin := (t - 8.0) * 9.0
			_set_joint(p, dir, spin)
		else:
			var k := _e(9.0, 9.3)
			var g := hands.grip_point("Right")
			var hold_dir := _hold_dir()
			var centre := work + Vector3(-JOINT_HALF, 0.02, 0)
			_set_joint(centre.lerp(g, k), Vector3(1, 0, 0).lerp(hold_dir, k).normalized())
	if _event("sealed", 7.85):
		_burst(MOUTH + bd + Vector3(0, 0, 0.05), Color(1, 1, 1), 8)
	if _event("tada", 9.3):
		_burst(hands.grip_point("Right") + Vector3(0, 0.05, 0), WeedStrains.info(_roll_strain).glow, 22)
		Input.vibrate_handheld(20)

const JOINT_HALF := WeedProps.JOINT_L * 0.5


func _hold_dir() -> Vector3:
	var f := hands.finger_direction("Right")
	return (f + Vector3(0, 0.35, 0) + Vector3(-0.25, 0, 0)).normalized()


## Places the joint with its mouth end at `mouth_end`, pointing along `dir`.
func _set_joint(mouth_end: Vector3, dir: Vector3, spin := 0.0) -> void:
	var x := dir.normalized()
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.95 else Vector3.BACK
	var z := x.cross(up).normalized()
	var y := z.cross(x).normalized()
	var b := Basis(x, y, z) * Basis(Vector3.RIGHT, spin)
	var jroot: Node3D = _joint.root
	jroot.transform = Transform3D(b, mouth_end)


# ---------------------------------------------------------------------------
# Smoking choreography

func _pose_smoke() -> void:
	var t := act_t
	var bd := hands.body_delta
	var m := 0.0     # 0 hold .. 1 at the mouth
	var ember := 0.6
	var info := WeedStrains.info(joint_strain)
	if act == Act.LIGHT:
		m = _e(0.0, 0.45)
		# Snap a fairy flame off the left fingertips and send it to the tip.
		var snap := _e(0.1, 0.35) * (1.0 - _e(1.15, 1.5))
		_arm("Left", Vector3(0.2, 0.86, 0.42), snap, 0.2 + 0.6 * _pulse(t, 0.3, 0.12), 0.0, 0.2, Vector3(-0.3, 0.5, 1.0), Vector3(-1, 0, 0))
		var tip := _tip_world_skel()
		var finger := Vector3(0.12, 0.92, 0.52) + bd
		_flame.visible = t > 0.32 and t < 1.3
		_flame.position = finger.lerp(tip, _e(0.4, 0.85))
		_flame.scale = Vector3.ONE * (_e(0.32, 0.42) * (1.0 - _e(1.0, 1.3)) + 0.001)
		if _event("snap", 0.32):
			_burst(finger, Color(1.0, 0.6, 0.2), 10)
		if _event("lit", 0.9):
			_burst(tip, Color(1.0, 0.55, 0.15), 14)
			(_joint.ember as Node3D).visible = true
		ember = 0.6 + 3.0 * _e(0.9, 1.1) * (1.0 - _e(1.2, 1.5))
		hands.chest_swell = 0.4 * _e(0.9, 1.2) * (1.0 - _e(1.3, 1.5))
	else:
		_arm("Left", TRAY_L, 0.0)
		m = _e(0.0, 0.5) * (1.0 - _e(1.7, 2.1))
		var inhale := _e(0.5, 1.6)
		ember = 0.6 + 4.5 * inhale * (1.0 - _e(1.7, 2.0)) + 0.4 * sin(t * 30.0) * inhale * (1.0 - _e(1.6, 1.8))
		hands.chest_swell = inhale * (1.0 - _e(2.4, 3.4))
		hands.head_pitch = 0.28 * _e(2.25, 2.6) * (1.0 - _e(3.3, 3.8))
		if _event("exhale", 2.4):
			_exhale.position = MOUTH + bd + Vector3(0, -0.01, 0.03)
			_exhale.restart()
			_exhale.emitting = true
			_count_puff()
		if joint_puffs <= 0 and t > 3.3:
			# The last of it: the roach vanishes in a twinkle.
			var gone := _e(3.3, 3.75)
			(_joint.root as Node3D).scale = Vector3.ONE * maxf(1.0 - gone, 0.001)
			if _event("roach", 3.4):
				_burst(hands.grip_point("Right"), info.glow, 14)
	var rg := HOLD_R.lerp(TO_MOUTH_R, m)
	_arm("Right", rg, 1.0, 0.2, 1.0, 0.0, Vector3(0.0, 0.3, 1.0).lerp(Vector3(0.6, 0.25, 1.0), m), Vector3(1.0, 0.3, 0.0))
	_set_ember(ember)
	var g := hands.grip_point("Right")
	var at_mouth := MOUTH + bd
	var dir := _hold_dir().lerp(MOUTH_OUT.normalized(), m).normalized()
	_set_joint(g.lerp(at_mouth, m), dir)


func _pulse(t: float, at: float, width: float) -> float:
	return clampf(1.0 - absf(t - at) / width, 0.0, 1.0)


func _count_puff() -> void:
	if _hit_counted:
		return
	_hit_counted = true
	joint_puffs -= 1
	var element := keling.weed_element() if local else _remote_element
	high.add_puff(element, joint_strain)
	puffed.emit(element, joint_puffs)
	joint_changed.emit()


func _tip_world_skel() -> Vector3:
	var jroot: Node3D = _joint.root
	return jroot.transform * Vector3(WeedProps.JOINT_L, 0, 0)


func _set_ember(energy: float) -> void:
	var em: StandardMaterial3D = _joint.ember_mat
	em.emission_energy_multiplier = energy if lit or act == Act.LIGHT else 0.0


# ---------------------------------------------------------------------------
# Every frame, after the hands are posed: drive the poses for the next frame
# and lay the props into the fingers.

func _place_props() -> void:
	if act == Act.ROLL:
		_pose_roll()
	elif act == Act.LIGHT or act == Act.HIT:
		_pose_smoke()
	else:
		_pose_rest()
	var jroot: Node3D = _joint.root
	if act == Act.NONE and has_joint():
		jroot.visible = _joint_hidden < 0.99
		jroot.scale = Vector3.ONE * maxf(1.0 - _joint_hidden, 0.001)
		var g := hands.grip_point("Right")
		_set_joint(g, _hold_dir())
		_set_ember(0.6 + 0.25 * sin(Time.get_ticks_msec() * 0.006))
	elif act == Act.NONE:
		jroot.visible = false
	(_joint.ember as Node3D).visible = lit or (act == Act.LIGHT and act_t > 0.9)
	var wisp := lit and has_joint() and act != Act.HIT and _joint_hidden < 0.5
	if _wisp.emitting != wisp:
		_wisp.emitting = wisp
	_wisp.position = _tip_world_skel()


func _pose_rest() -> void:
	var w := _hold
	_arm("Right", HOLD_R, w * 0.9, 0.2, 1.0, 0.0, Vector3(0.0, 0.3, 1.0), Vector3(1.0, 0.3, 0.0))
	var l: Dictionary = hands.arms["Left"]
	l.w = move_toward(l.w, 0.0, 0.05)
	hands.chest_swell = move_toward(hands.chest_swell, 0.0, 0.05)
	hands.head_pitch = move_toward(hands.head_pitch, 0.0, 0.02)
	if not has_joint():
		(_joint.root as Node3D).scale = Vector3.ONE


# ---------------------------------------------------------------------------
# Props

func _build_props() -> void:
	_float_bud = WeedKit.make_bud(&"ember", 0.75)
	_float_bud.visible = false
	_rig.add_child(_float_bud)
	_paper = WeedProps.paper(Color(0.45, 0.7, 0.3))
	_paper_mat = _paper.material_override
	_paper.visible = false
	_rig.add_child(_paper)
	_joint = WeedProps.joint(Color(0.6, 1.0, 0.4))
	(_joint.root as Node3D).visible = false
	_rig.add_child(_joint.root)
	_crumbs = WeedProps.crumbs(Color(0.5, 0.8, 0.3))
	_rig.add_child(_crumbs)
	_sparkle = WeedProps.sparkles(Color(1, 1, 1))
	_rig.add_child(_sparkle)
	_exhale = WeedProps.smoke_puff(Color(0.9, 0.9, 0.9))
	_exhale.explosiveness = 0.55
	_exhale.direction = Vector3(0, 0.55, 1).normalized()  # out of the mouth (skeleton space)
	_rig.add_child(_exhale)
	_wisp = WeedProps.ember_wisp(Color(0.9, 0.9, 0.9))
	_rig.add_child(_wisp)
	_flame = WeedProps.flame()
	_rig.add_child(_flame)
	# The bud shown in the fist right after a pick (stem-down sprig placement).
	_fist_bud = Node3D.new()
	_fist_bud.name = "FistBud"
	_fist_bud.visible = false
	_fist_mesh = WeedKit.make_bud(&"ember", 0.7)
	_fist_mesh.position = Vector3(0, 0.1, 0)
	_fist_bud.add_child(_fist_mesh)
	keling.add_child.call_deferred(_fist_bud)
	if joint_strain != &"":
		_paint_joint(joint_strain)


func _burst(at: Vector3, color: Color, amount: int) -> void:
	_sparkle.position = at
	_sparkle.amount = amount
	(_sparkle.mesh.surface_get_material(0) as StandardMaterial3D).albedo_color = color * 1.6
	_sparkle.restart()
	_sparkle.emitting = true


# ---------------------------------------------------------------------------
# "Pick" prompt over the nearest ripe bud

func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.name = "PickPrompt"
	_prompt.top_level = true
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.no_depth_test = true
	_prompt.pixel_size = 0.0016
	_prompt.font_size = 40
	_prompt.outline_size = 12
	_prompt.modulate = Color(1, 1, 1, 0)
	_prompt.outline_modulate = Color(0.05, 0.09, 0.05, 0.0)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.line_spacing = -6.0
	_prompt.render_priority = 10
	_prompt.visible = false
	keling.add_child.call_deferred(_prompt)


func _update_prompt(delta: float) -> void:
	if _prompt == null or not local:
		return
	_prompt_tick -= delta
	if _prompt_tick <= 0.0:
		_prompt_tick = 0.12
		_prompt_bud = _nearest_ripe_bud()
	var want := _prompt_bud != null and is_instance_valid(_prompt_bud) and _prompt_bud.ripe and act == Act.NONE and keling.mode in [KelingController.Mode.GROUND, KelingController.Mode.EMOTE]
	_prompt_alpha = move_toward(_prompt_alpha, 1.0 if want else 0.0, delta * 5.0)
	_prompt.visible = _prompt_alpha > 0.01 and _prompt.is_inside_tree()
	if _prompt.visible and _prompt_bud and is_instance_valid(_prompt_bud):
		var bob := sin(Time.get_ticks_msec() * 0.003) * 0.012
		_prompt.global_position = _prompt_bud.global_position + Vector3(0, 0.2 + bob, 0)
		var key := "E"
		match Bench.input_method():
			1:
				key = "X"
			2:
				key = "Tap the hand"
		_prompt.text = "%s\n%s  ·  pick" % [WeedStrains.display_name(_prompt_bud.strain), key]
		_prompt.modulate = Color(1.0, 0.97, 0.88, _prompt_alpha)
		_prompt.outline_modulate = Color(0.05, 0.09, 0.05, 0.75 * _prompt_alpha)


## Same reach rules as the controller's grab.
func _nearest_ripe_bud() -> WeedBud:
	if not keling.is_inside_tree():
		return null
	var best: WeedBud = null
	var best_d := 1.4
	var heading := Vector3(sin(keling.facing), 0.0, cos(keling.facing))
	for n in keling.get_tree().get_nodes_in_group("weed_bud"):
		var b := n as WeedBud
		if b == null or not b.ripe:
			continue
		var to := b.global_position - keling.global_position
		var flat := Vector3(to.x, 0.0, to.z)
		if flat.length() > best_d or to.y < 0.2 or to.y > 1.2:
			continue
		if flat.length() > 0.2 and flat.normalized().dot(heading) < -0.3:
			continue
		best = b
		best_d = flat.length()
	return best


# ---------------------------------------------------------------------------
# Save (the pouch and the joint in hand survive a restart)

func _save() -> void:
	if not local:
		return
	var cfg := ConfigFile.new()
	for s in pouch:
		cfg.set_value("pouch", String(s), pouch[s])
	cfg.set_value("joint", "strain", String(joint_strain))
	cfg.set_value("joint", "puffs", joint_puffs)
	cfg.set_value("joint", "lit", lit)
	var d := PackedStringArray()
	for s in discovered:
		d.append(String(s))
	cfg.set_value("strains", "discovered", d)
	cfg.save(SAVE_PATH)


func _load() -> void:
	if not is_local():
		return
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if cfg.has_section("pouch"):
		for k in cfg.get_section_keys("pouch"):
			var n := int(cfg.get_value("pouch", k, 0))
			if n > 0 and WeedStrains.STRAINS.has(StringName(k)):
				pouch[StringName(k)] = mini(n, MAX_BUDS)
	var js := StringName(cfg.get_value("joint", "strain", ""))
	if WeedStrains.STRAINS.has(js):
		joint_strain = js
		joint_puffs = clampi(int(cfg.get_value("joint", "puffs", 0)), 0, HITS)
		lit = bool(cfg.get_value("joint", "lit", false))
		if joint_puffs <= 0:
			joint_strain = &""
	for s in cfg.get_value("strains", "discovered", PackedStringArray()):
		if WeedStrains.STRAINS.has(StringName(s)):
			discovered.append(StringName(s))
	for s in WeedStrains.ORDER:
		if bud_count(s) > 0:
			selected = s
