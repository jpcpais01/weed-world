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
##  * Hold the press on a lit joint (or press G) and the puff becomes Dragon
##    Breath: a long deep draw, then a blast of blue mist that turns into a
##    water dragon (DragonBreath), flown where the camera looks.
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
signal dragon_breathed

enum Act { NONE, ROLL, LIGHT, HIT, DRAGON }

const ROLL_TIME := 10.0
const LIGHT_TIME := 2.6
const HIT_TIME := 3.8
const HITS := 3
const DRAGON_TIME := 4.8
const DRAGON_HOLD := 0.42       # hold the puff this long and it turns into Dragon Breath
const DRAGON_WINDOW := 1.3      # ...as long as the draw has only just begun
const DRAGON_RELEASE := 2.75    # the blast
const BURN_PER_PUFF := 0.17   # how much of the joint each puff burns away
const MAX_BUDS := 12
const SAVE_PATH := "user://weed.cfg"
## Rolling stages for the HUD: start time and caption.
const ROLL_STAGES := [[0.0, "Taking out a bud"], [0.8, "A good sniff"], [1.6, "Breaking up the bud"], [3.6, "Shaping"], [4.6, "Rolling"], [6.3, "A lick to seal it"], [7.4, "Sealing"], [8.0, "Twisting the tip"], [8.7, "Packing it"], [9.3, "Ready!"]]
## Rolling can be walked away from (bud back in the pouch) until the lick.
const ROLL_POINT_OF_NO_RETURN := 6.3

## Skeleton-space landmarks (+Z forward, +X the Keling's left).
const MOUTH := Vector3(0.0, 0.835, 0.455)
const WORK := Vector3(0.0, 0.80, 0.6)
const TRAY_L := Vector3(0.17, 0.78, 0.46)
const TRAY_R := Vector3(-0.17, 0.78, 0.46)
const HOLD_R := Vector3(-0.25, 0.64, 0.40)
## Swimming, the joint is held up high to keep it dry.
const SWIM_HOLD_R := Vector3(-0.24, 1.04, 0.48)
const TO_MOUTH_R := Vector3(-0.15, 0.80, 0.47)
const TO_MOUTH_FRONT_R := Vector3(-0.09, 0.77, 0.5)
const TADA_R := Vector3(-0.24, 0.97, 0.42)
## Which way the joint points out of the mouth while smoking.
const MOUTH_OUT := Vector3(-0.55, -0.12, 1.0)
## Held straight out in front of the face while it's lit.
const LIGHT_OUT := Vector3(0.0, -0.18, 1.0)
const NOSE := Vector3(0.0, 0.875, 0.5)
const NOSTRIL_X := 0.017

var keling: KelingController
var hands: KelingHands
var high: WeedHigh
var gifts: KelingGifts
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
var _filling: Node3D
var _filling_mat: ShaderMaterial
var _tongue: Node3D
var _glint: MeshInstance3D
var _hearts: CPUParticles3D
var _head_bone := -1
var _mouth_local := Transform3D.IDENTITY
var _voices: Array[AudioStreamPlayer3D] = []
var _voice := 0
var _clips := {}
var _joint: Dictionary
var _crumbs: CPUParticles3D
var _sparkle: CPUParticles3D
var _smoke: WeedSmoke
var _sparks: CPUParticles3D
var _nose_local: Array[Transform3D] = []
var _ember_smoke := 0.0      # how much the ember smokes this frame (0..1.5)
var _burn_k := 1.0           # how much of the joint is left (1 = fresh)
var _flame: MeshInstance3D
var _fist_bud: Node3D
var _fist_mesh: MeshInstance3D
var _hold := 0.0
var _swim_hold := 0.0
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
var dragon_held := false        ## the touch button is held down (WeedHud)
var _charge_hold := -1.0        # how long the puff has been held (-1: let go)
var _dragon_queued := false
var _dragon: DragonBreath
var _dragon_yaw := 0.0
## Whose body the hands are on. The choreography was authored on the
## original Keling; its landmarks and key tracks are fitted to this body.
var body: KelingBody
var _mouth := MOUTH
var _tray_l := TRAY_L
var _hold_r := HOLD_R
var _swim_hold_r := SWIM_HOLD_R
var _to_mouth_r := TO_MOUTH_R
var _w0 := W0
var _to_mouth_front_r := TO_MOUTH_FRONT_R
var _nose := NOSE
var _light_ready := Vector3(0.13, 0.74, 0.54)
var _light_rest := Vector3(0.16, 0.7, 0.5)
var _r_keys: Array = R_KEYS
var _l_keys: Array = L_KEYS


func setup(p_keling: KelingController, skeleton: Skeleton3D) -> void:
	keling = p_keling
	_skel = skeleton
	name = "Weed"
	_fit_body(p_keling.get("body") if p_keling.get("body") is KelingBody else KelingCharacters.body(KelingCharacters.DEFAULT))
	_add_hands()
	_rig = Node3D.new()
	_rig.name = "WeedProps"
	_skel.add_child(_rig)
	high = WeedHigh.new()
	high.name = "High"
	keling.add_child.call_deferred(high)
	high.setup(keling, self)
	# Every strain carries a smoke gift; each puff charges it.
	gifts = KelingGifts.new()
	gifts.setup(keling, self)
	keling.add_child.call_deferred(gifts)
	keling.grabbed.connect(_on_grabbed)
	_build_props()
	_load()


func _add_hands() -> void:
	hands = KelingHands.new()
	hands.name = "Hands"
	_skel.add_child(hands)
	hands.modification_processed.connect(_place_props)


## Moves the hands and props onto another character's skeleton (the player
## swapped Keling). Only while nothing is in the hands.
func rebind(skeleton: Skeleton3D, p_body: KelingBody) -> void:
	_stop_act()
	hands.queue_free()
	_skel = skeleton
	_fit_body(p_body)
	_add_hands()
	_rig.reparent(_skel, false)
	_bind_mouth()


func _fit_body(b: KelingBody) -> void:
	body = b
	_mouth = b.fit(MOUTH)
	_tray_l = b.fit(TRAY_L)
	_hold_r = b.fit(HOLD_R)
	_swim_hold_r = b.fit(SWIM_HOLD_R)
	_to_mouth_r = b.fit(TO_MOUTH_R)
	_w0 = b.fit(W0)
	_to_mouth_front_r = b.fit(TO_MOUTH_FRONT_R)
	_nose = b.fit(NOSE)
	_light_ready = b.fit(Vector3(0.13, 0.74, 0.54))
	_light_rest = b.fit(Vector3(0.16, 0.7, 0.5))
	_r_keys = _fit_keys(R_KEYS)
	_l_keys = _fit_keys(L_KEYS)


func _fit_keys(track: Array) -> Array:
	if body.identity:
		return track
	var out := []
	for k in track:
		var f: Array = k.duplicate()
		f[1] = body.fit(k[1])
		out.append(f)
	return out


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


## Dragon Breath straight away (G): lights the joint if it has to, and the
## puff that follows becomes the dragon.
func use_dragon() -> void:
	if not has_joint():
		note.emit("Roll a joint first, then hold the puff for Dragon Breath")
		return
	if act == Act.HIT and act_t <= DRAGON_WINDOW or act == Act.LIGHT:
		_dragon_queued = true
		return
	if act != Act.NONE:
		return
	_dragon_queued = true
	use()
	if act == Act.NONE:
		_dragon_queued = false


## 0..1 while a held puff is charging up into Dragon Breath (for the HUD).
func dragon_charge() -> float:
	if act == Act.DRAGON:
		return 1.0
	if act != Act.HIT or _charge_hold < 0.0 or act_t > DRAGON_WINDOW:
		return 0.0
	return clampf(_charge_hold / DRAGON_HOLD, 0.0, 1.0)


func busy() -> bool:
	return act != Act.NONE


func _start(a: int) -> void:
	act = a
	act_t = 0.0
	_events.clear()
	_hit_counted = false
	if a == Act.ROLL:
		_prepare_roll(_roll_strain)
		if local:
			_closeup(true)
	elif joint_strain != &"":
		_paint_joint(joint_strain)
	if a == Act.HIT:
		_charge_hold = 0.0 if _puff_held() else -1.0
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
		&"dragon":
			joint_strain = strain
			joint_puffs = maxi(joint_puffs, 1)
			lit = true
			_remote_element = StringName(data.get("element", &"none"))
			if act == Act.DRAGON:
				return
			if act != Act.HIT:
				_start(Act.HIT)
				act_t = DRAGON_HOLD
			_begin_dragon(float(data.get("yaw", keling.facing)), int(data.get("seed", 0)))
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
	_dragon_queued = false
	if act == Act.NONE:
		return
	if act == Act.DRAGON and _dragon and _dragon.phase == DragonBreath.Phase.CHARGE:
		_dragon.fizzle()
		_dragon = null
	if act == Act.ROLL:
		if act_t < ROLL_POINT_OF_NO_RETURN:
			if local:
				pouch[_roll_strain] = pouch.get(_roll_strain, 0) + 1
				pouch_changed.emit()
			_hide_roll_props()
			_joint.root.visible = false
		else:
			_finish_roll()
	_stop_act()
	_save()
	_announce_rest()


func _stop_act() -> void:
	if act == Act.ROLL and local:
		_closeup(false)
	_hide_roll_props()
	_flame.visible = false
	_sparks.emitting = false
	hands.chest_swell = 0.0
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
		Act.DRAGON:
			return act_t / DRAGON_TIME
	return 0.0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_physics_process_timed(delta)
	PerfMeter.add(&"weed actions", Time.get_ticks_usec() - t0)


func _physics_process_timed(delta: float) -> void:
	if keling == null:
		return
	delta *= keling.time_dilation
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
		Act.HIT, Act.DRAGON:
			if act == Act.HIT:
				_check_dragon(delta)
			elif local and act_t < DRAGON_RELEASE and not keling.is_sitting():
				# Turn to face where the dragon will go.
				keling.facing = lerp_angle(keling.facing, _dragon_yaw, 1.0 - exp(-7.0 * delta))
			if act_t >= (HIT_TIME if act == Act.HIT else DRAGON_TIME):
				act = Act.NONE
				_dragon = null
				_dragon_queued = false
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


# ---------------------------------------------------------------------------
# Dragon Breath

func _puff_held() -> bool:
	if not local:
		return false
	return dragon_held or (InputMap.has_action(&"weed") and Input.is_action_pressed(&"weed"))


## A held puff (or a queued G) turns into Dragon Breath early in the draw.
func _check_dragon(delta: float) -> void:
	if not local or act_t > DRAGON_WINDOW:
		return
	if _charge_hold >= 0.0:
		_charge_hold = _charge_hold + delta if _puff_held() else -1.0
	if (_charge_hold >= DRAGON_HOLD or _dragon_queued) and act_t >= DRAGON_HOLD:
		_begin_dragon(_aim_yaw(), randi())


## Where the dragon goes: where the camera looks. Seated on a bench the
## Keling can't turn, so it breathes no further round than over a shoulder.
func _aim_yaw() -> float:
	var cam = keling.get("camera_rig")
	var aim := keling.facing
	if cam:
		aim = wrapf(float(cam.yaw) - PI, -PI, PI)
	if keling.is_sitting():
		aim = keling.facing + clampf(wrapf(aim - keling.facing, -PI, PI), -0.9, 0.9)
	return aim


func _begin_dragon(p_yaw: float, p_seed: int) -> void:
	act = Act.DRAGON
	_dragon_queued = false
	_charge_hold = -1.0
	_dragon_yaw = p_yaw
	_dragon = DragonBreath.new()
	_dragon.name = "DragonBreath"
	_dragon.setup(keling, local, p_yaw, p_seed)
	keling.add_child(_dragon)
	_dragon.play_charge()
	act_changed.emit(act)
	if local:
		keling.activity_changed.emit(&"dragon", {"strain": joint_strain, "yaw": p_yaw, "seed": p_seed, "element": keling.weed_element()})


func _event(key: String, at: float) -> bool:
	if act_t >= at and not _events.has(key):
		_events[key] = true
		return true
	return false


# ---------------------------------------------------------------------------
# Rolling choreography
#
# Ten seconds, beat by beat (the HUD captions follow ROLL_STAGES):
#   0.0  the right hand dips into the hip pouch and comes up pinching a bud
#   0.8  a good sniff (two little sniffs, a happy shiver, hearts); the left
#        hand pops a paper out and shows it off by a corner
#   1.6  the paper lies on the left fingers; the right thumb rubs the bud to
#        crumbs over it, sliding along, until the bud is gone; dust off
#   3.6  both hands take the paper by its ends, fold it round the pile into a
#        taco and rock it to pack a neat log
#   4.6  thumbs tuck the near edge over and roll it up
#   6.4  up to the mouth like a harmonica: the tongue pops out and the gum
#        strip slides along it
#   7.4  back down, pressed shut with a shine running down the seam
#   8.0  the left fingers twist the tip closed
#   8.7  tap, tap on the left palm to pack it
#   9.25 ta-da, held up to admire, then into a relaxed hold
#
# Each hand follows keyframes (below) eased into each other in wrist space,
# with procedural overlays (rubbing, rocking, the lick slide, taps) on top.
# The props are laid into the real fingertips every frame, so the paper
# always sits between the two pinches and the bud between thumb and index.

const W0 := Vector3(0.0, 0.725, 0.62)         # the paper's home, out in front of the beard
const END_X := 0.07                             # pinches hold the paper this far out
const LICK_Y := 0.842
const LICK_Z := 0.535
const P_PINCH := KelingHands.Pin.PINCH
const P_PADS := KelingHands.Pin.PADS
const P_WRIST := KelingHands.Pin.WRIST

## Finger poses (see KelingHands.arms for what each value does).
const POSES := {
	"open": {"curl": 0.08, "spread": 0.2},
	"reach": {"curl": 0.3, "index": 0.0, "middle": 0.15, "ring": 0.3, "thumb": 0.1},
	"pinch": {"curl": 0.2, "index": 0.22, "middle": 0.5, "ring": 0.7, "pinch": 1.0},
	"pinch_soft": {"curl": 0.15, "index": 0.15, "middle": 0.35, "ring": 0.5, "pinch": 0.85},
	"cup": {"curl": 0.18, "index": -0.05, "middle": 0.0, "ring": 0.06, "spread": -0.35, "thumb": 0.25},
	"dust": {"curl": -0.12, "spread": 0.7, "wiggle": 1.0},
	"jazz": {"curl": -0.2, "spread": 1.0, "wiggle": 0.55},
	"hold": {"curl": 0.2, "index": 0.1, "middle": 0.1, "ring": 0.7, "thumb": 0.35},
}

## Keyframes: [time, goal, pinned point, finger direction, palm normal, pose].
const R_KEYS := [
	[0.0, Vector3(-0.27, 0.53, 0.34), P_PINCH, Vector3(0.15, -1.0, 0.35), Vector3(1.0, 0.0, 0.25), "open"],
	[0.3, Vector3(-0.275, 0.49, 0.33), P_PINCH, Vector3(0.15, -1.0, 0.35), Vector3(1.0, 0.0, 0.25), "pinch"],
	[0.82, Vector3(-0.02, 0.868, 0.585), P_PINCH, Vector3(0.65, 0.4, 0.6), Vector3(0.2, -0.3, -1.0), "pinch"],
	[1.45, Vector3(-0.02, 0.868, 0.585), P_PINCH, Vector3(0.65, 0.4, 0.6), Vector3(0.2, -0.3, -1.0), "pinch"],
	[1.78, Vector3(0.0, 0.79, 0.62), P_PINCH, Vector3(0.5, -0.4, 0.65), Vector3(0.4, -1.0, 0.0), "pinch"],
	[3.3, Vector3(0.0, 0.79, 0.62), P_PINCH, Vector3(0.5, -0.4, 0.65), Vector3(0.4, -1.0, 0.0), "pinch"],
	[3.42, Vector3(-0.07, 0.79, 0.6), P_PINCH, Vector3(0.35, -0.1, 1.0), Vector3(0.6, -1.0, 0.0), "dust"],
	[3.62, Vector3(-0.09, 0.77, 0.58), P_PINCH, Vector3(0.35, -0.1, 1.0), Vector3(0.6, -1.0, 0.0), "dust"],
	[3.88, Vector3(-END_X, W0.y, W0.z), P_PINCH, Vector3(0.55, -0.05, 0.85), Vector3(0.9, -0.5, -0.3), "pinch"],
	[6.25, Vector3(-END_X, W0.y, W0.z), P_PINCH, Vector3(0.55, -0.05, 0.85), Vector3(0.9, -0.5, -0.3), "pinch"],
	[6.45, Vector3(-END_X, LICK_Y, LICK_Z), P_PINCH, Vector3(0.45, 0.2, 0.85), Vector3(0.9, -0.4, -0.3), "pinch"],
	[7.22, Vector3(-END_X, LICK_Y, LICK_Z), P_PINCH, Vector3(0.45, 0.2, 0.85), Vector3(0.9, -0.4, -0.3), "pinch"],
	[7.5, Vector3(-END_X, W0.y, W0.z), P_PINCH, Vector3(0.55, -0.05, 0.85), Vector3(0.9, -0.5, -0.3), "pinch"],
	[8.0, Vector3(-0.044, W0.y, W0.z), P_PINCH, Vector3(0.55, -0.05, 0.85), Vector3(0.9, -0.5, -0.3), "pinch"],
	[8.62, Vector3(-0.044, W0.y, W0.z), P_PINCH, Vector3(0.55, -0.05, 0.85), Vector3(0.9, -0.5, -0.3), "pinch"],
	[8.85, Vector3(0.04, 0.78, 0.62), P_PINCH, Vector3(0.6, 0.05, 0.8), Vector3(0.7, -0.2, -0.7), "pinch"],
	[9.22, Vector3(0.04, 0.78, 0.62), P_PINCH, Vector3(0.6, 0.05, 0.8), Vector3(0.7, -0.2, -0.7), "pinch"],
	[9.55, Vector3(-0.3, 0.93, 0.5), P_PINCH, Vector3(0.05, 0.9, 0.3), Vector3(1.0, -0.1, 0.1), "pinch"],
	[9.72, Vector3(-0.3, 0.93, 0.5), P_PINCH, Vector3(0.05, 0.9, 0.3), Vector3(1.0, -0.1, 0.1), "pinch"],
	[10.0, HOLD_R, P_WRIST, Vector3(0.0, 0.3, 1.0), Vector3(1.0, 0.3, 0.0), "hold"],
]
const L_KEYS := [
	[0.0, Vector3(0.2, 0.62, 0.42), P_PINCH, Vector3(-0.2, -0.3, 1.0), Vector3(-1.0, 0.2, 0.0), "open"],
	[0.5, Vector3(0.2, 0.62, 0.42), P_PINCH, Vector3(-0.2, -0.3, 1.0), Vector3(-1.0, 0.2, 0.0), "open"],
	[0.78, Vector3(0.14, 0.8, 0.56), P_PINCH, Vector3(-0.35, 0.35, 1.0), Vector3(-1.0, -0.2, -0.2), "pinch"],
	[1.35, Vector3(0.13, 0.81, 0.57), P_PINCH, Vector3(-0.35, 0.35, 1.0), Vector3(-1.0, -0.2, -0.2), "pinch"],
	[1.62, Vector3(END_X + 0.01, W0.y + 0.01, W0.z), P_PINCH, Vector3(-0.5, 0.05, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[3.55, Vector3(END_X + 0.01, W0.y + 0.01, W0.z), P_PINCH, Vector3(-0.5, 0.05, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[3.88, Vector3(END_X, W0.y, W0.z), P_PINCH, Vector3(-0.55, -0.05, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[6.25, Vector3(END_X, W0.y, W0.z), P_PINCH, Vector3(-0.55, -0.05, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[6.45, Vector3(END_X, LICK_Y, LICK_Z), P_PINCH, Vector3(-0.45, 0.2, 0.85), Vector3(-0.9, -0.4, -0.3), "pinch"],
	[7.22, Vector3(END_X, LICK_Y, LICK_Z), P_PINCH, Vector3(-0.45, 0.2, 0.85), Vector3(-0.9, -0.4, -0.3), "pinch"],
	[7.5, Vector3(END_X, W0.y, W0.z), P_PINCH, Vector3(-0.55, -0.05, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[8.0, Vector3(0.062, W0.y, W0.z), P_PINCH, Vector3(-0.5, 0.0, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[8.6, Vector3(0.062, W0.y, W0.z), P_PINCH, Vector3(-0.5, 0.0, 0.85), Vector3(-0.9, -0.5, -0.3), "pinch"],
	[8.85, Vector3(0.05, 0.665, 0.62), P_PADS, Vector3(-0.6, 0.05, 0.8), Vector3(0.0, 1.0, 0.15), "open"],
	[9.25, Vector3(0.05, 0.665, 0.62), P_PADS, Vector3(-0.6, 0.05, 0.8), Vector3(0.0, 1.0, 0.15), "open"],
	[9.52, Vector3(0.2, 0.9, 0.46), P_PADS, Vector3(-0.15, 1.0, 0.3), Vector3(0.0, 0.0, 1.0), "jazz"],
	[10.0, Vector3(0.22, 0.86, 0.44), P_PADS, Vector3(-0.15, 1.0, 0.3), Vector3(0.0, 0.0, 1.0), "jazz"],
]
## Head: [time, pitch (+ back), yaw (+ left), roll].
const HEAD_KEYS := [
	[0.0, 0.0, 0.0, 0.0],
	[0.3, -0.14, -0.22, 0.05],
	[0.82, -0.04, -0.05, 0.0],
	[1.28, -0.02, 0.0, 0.0],
	[1.48, 0.13, 0.05, 0.16],
	[1.75, -0.16, 0.0, 0.0],
	[3.3, -0.16, 0.0, 0.0],
	[3.5, -0.08, -0.16, -0.06],
	[3.9, -0.15, 0.0, 0.0],
	[6.25, -0.15, 0.0, 0.0],
	[6.45, -0.04, 0.0, 0.07],
	[7.22, -0.04, 0.0, 0.07],
	[7.5, -0.15, 0.0, 0.0],
	[8.0, -0.15, 0.06, -0.06],
	[8.62, -0.15, 0.06, -0.06],
	[8.85, -0.18, 0.0, 0.0],
	[9.22, -0.18, 0.0, 0.0],
	[9.55, 0.08, -0.26, -0.15],
	[9.75, 0.08, -0.26, -0.15],
	[10.0, 0.0, 0.0, 0.0],
]

var _bud_radius := 0.03     # model radius of the bud mesh at scale 1
var _paper_home := W0       # where the paper is this frame (skeleton space)


func _prepare_roll(strain: StringName) -> void:
	var info := WeedStrains.info(strain)
	_float_bud.material_override = WeedKit.bud_material(strain)
	_float_bud_strain = strain
	var crumb: Color = info.bud_tint.lerp(Color(0.42, 0.66, 0.28), 0.55)
	_paper_mat.set_shader_parameter("fill_color", crumb)
	for k in ["fold", "wrap_a", "wrap_b", "fill", "wet"]:
		_paper_mat.set_shader_parameter(k, 0.0)
	_filling_mat.set_shader_parameter("tint", crumb)
	_crumbs.mesh.surface_get_material(0).albedo_color = Color(0.4, 0.62, 0.25).lerp(info.bud_tint, 0.35)
	(_joint.root as Node3D).scale = Vector3.ONE
	(_joint.twist as Node3D).visible = false
	_paint_joint(strain)


func _finish_roll() -> void:
	joint_strain = _roll_strain
	joint_puffs = HITS
	lit = false
	_hide_roll_props()
	(_joint.twist as Node3D).visible = true
	(_joint.twist as Node3D).scale = Vector3.ONE
	_hold = 1.0
	joint_rolled.emit(joint_strain)
	joint_changed.emit()
	_save()


func _hide_roll_props() -> void:
	_float_bud.visible = false
	_paper.visible = false
	_filling.visible = false
	_tongue.visible = false
	_glint.visible = false
	_crumbs.emitting = false


func _clear_joint() -> void:
	joint_strain = &""
	joint_puffs = 0
	lit = false
	joint_changed.emit()


func _paint_joint(strain: StringName) -> void:
	var info := WeedStrains.info(strain)
	(_joint.body_mat as ShaderMaterial).set_shader_parameter("fill_color", Color(0.36, 0.5, 0.2).lerp(info.bud_tint, 0.25))
	_smoke.set_style(info.get("smoke", &"normal"))


func _e(a: float, b: float) -> float:
	return smoothstep(a, b, act_t)


## Sets one arm: goal, weight, pinned point, finger direction, palm normal
## and the finger pose (a POSES entry or a dictionary of finger settings).
func _arm(side: String, goal: Vector3, w: float, pin: int = P_WRIST, fingers := Vector3(0, 0.1, 1), palm := Vector3.UP, pose: Variant = {}) -> void:
	var a: Dictionary = hands.arms[side]
	hands.reset_fingers(side)
	a.goal = goal
	a.w = w
	a.pin = pin
	a.fingers = fingers
	a.palm = palm
	var fs: Dictionary = POSES.get(pose, {}) if pose is String else pose
	for k in fs:
		a[k] = fs[k]


## Eases between the keyframes around time t. Returns the wrist goal (the
## pins are turned into wrist positions first, so a change of pin between
## keys glides), finger direction, palm normal and blended finger settings.
func _keys(track: Array, t: float, side: String) -> Dictionary:
	var i := 0
	while i < track.size() - 1 and t >= track[i + 1][0]:
		i += 1
	var a: Array = track[i]
	var b: Array = track[mini(i + 1, track.size() - 1)]
	var u := smoothstep(a[0], b[0], t) if b[0] > a[0] else 0.0
	var wa := hands.wrist_goal(side, a[1], a[2], a[3], a[4])
	var wb := hands.wrist_goal(side, b[1], b[2], b[3], b[4])
	var pa: Dictionary = POSES[a[5]]
	var pb: Dictionary = POSES[b[5]]
	var fs := {}
	for k in pa:
		fs[k] = lerpf(pa[k], pb.get(k, 0.0), u)
	for k in pb:
		if not fs.has(k):
			fs[k] = lerpf(0.0, pb[k], u)
	return {
		"wrist": wa.lerp(wb, u),
		"fingers": (a[3] as Vector3).normalized().lerp((b[3] as Vector3).normalized(), u),
		"palm": (a[4] as Vector3).normalized().lerp((b[4] as Vector3).normalized(), u),
		"f": fs,
	}


func _head_keys(t: float) -> Vector3:
	var i := 0
	while i < HEAD_KEYS.size() - 1 and t >= HEAD_KEYS[i + 1][0]:
		i += 1
	var a: Array = HEAD_KEYS[i]
	var b: Array = HEAD_KEYS[mini(i + 1, HEAD_KEYS.size() - 1)]
	var u := smoothstep(a[0], b[0], t) if b[0] > a[0] else 0.0
	return Vector3(lerpf(a[1], b[1], u), lerpf(a[2], b[2], u), lerpf(a[3], b[3], u))


func _pose_roll() -> void:
	var t := act_t
	var bd := hands.body_delta
	var w_in := _e(0.0, 0.45)
	var r := _keys(_r_keys, t, "Right")
	var l := _keys(_l_keys, t, "Left")
	var r_off := Vector3.ZERO
	var l_off := Vector3.ZERO
	var rf: Dictionary = r.f
	var lf: Dictionary = l.f

	# Sniff: the bud bobs under the nose with each sniff.
	var sniff := _pulse(t, 1.02, 0.09) + _pulse(t, 1.22, 0.09)
	r_off += Vector3(0.0, -0.006, -0.008) * sniff
	# Crumbling: the thumb rubs, the hand drifts along the paper and dips.
	var crumble := _e(1.75, 1.95) * (1.0 - _e(3.15, 3.3))
	if crumble > 0.0:
		rf["rub"] = crumble
		r_off += Vector3(sin((t - 1.75) * 3.6) * 0.026, -0.006 * absf(sin(t * 9.5)), 0.0) * crumble
		l_off += Vector3(0.0, sin(t * 9.5) * 0.002, 0.0) * crumble
	# Dusting off: a quick shake of the fingers.
	var dust := _e(3.3, 3.4) * (1.0 - _e(3.55, 3.7))
	r_off += Vector3(sin(t * 46.0) * 0.012, sin(t * 31.0) * 0.006, 0.0) * dust
	# Packing the taco: the paper rocks back and forth between the pinches.
	var rock := _e(4.15, 4.3) * (1.0 - _e(4.5, 4.62))
	var rock_a := sin((t - 4.15) * 21.0) * rock
	r_off += Vector3(0.0, 0.006, -0.004) * rock_a
	l_off += Vector3(0.0, 0.006, -0.004) * rock_a
	# Rolling: thumbs push the paper over, fingers walk, hands nudge in and out.
	var rolling := _e(4.6, 4.75) * (1.0 - _e(6.05, 6.25))
	if rolling > 0.0:
		var ph := (t - 4.6) * 11.0
		rf["rub"] = 0.6 * rolling
		lf["rub"] = 0.6 * rolling
		rf["middle"] = rf.get("middle", 0.0) + 0.25 * sin(ph) * rolling
		lf["middle"] = lf.get("middle", 0.0) + 0.25 * sin(ph + PI) * rolling
		var nudge := Vector3(0.0, 0.003 * sin(ph), 0.006 * sin(ph * 0.5)) * rolling
		r_off += nudge
		l_off += nudge
	# The lick: the tube slides along the tongue, left to right and back a bit.
	var lick := _e(6.48, 6.6) * (1.0 - _e(7.08, 7.2))
	var slide := 0.0
	if lick > 0.0:
		slide = lerpf(0.042, -0.042, smoothstep(6.55, 7.05, t)) * lick
		r_off.x += slide
		l_off.x += slide
	# Sealing: thumbs press along the seam.
	var press := _e(7.55, 7.65) * (1.0 - _e(7.85, 7.95))
	rf["rub"] = rf.get("rub", 0.0) + 0.5 * press
	lf["rub"] = lf.get("rub", 0.0) + 0.5 * press
	# Twisting the tip: the left hand rolls back and forth around the joint.
	var twist := _e(8.02, 8.12) * (1.0 - _e(8.5, 8.6))
	var twist_a := sin((t - 8.02) * 22.0) * twist
	var l_palm: Vector3 = l.palm
	if twist > 0.0:
		l_palm = l_palm.rotated(Vector3.RIGHT, 0.75 * twist_a)
		lf["rub"] = twist
		l_off += Vector3(0.0, 0.004 * twist_a, 0.0)
	# Tap, tap: the joint knocks down onto the left palm.
	var tap := _pulse(t, 8.98, 0.07) + _pulse(t, 9.14, 0.07)
	r_off.y -= 0.022 * tap
	# Ta-da wiggle.
	var tada := _e(9.5, 9.6) * (1.0 - _e(9.75, 9.9))
	r_off += Vector3(0.0, sin(t * 30.0) * 0.006, 0.0) * tada

	# While crumbling, the bud hand hovers over wherever the paper really is;
	# while packing, the joint comes down onto wherever the left palm is.
	var over_paper := _e(1.6, 1.78) * (1.0 - _e(3.3, 3.42))
	if over_paper > 0.0:
		var over := _paper_home - bd + Vector3(0.0, 0.065, 0.0)
		r.wrist = (r.wrist as Vector3).lerp(hands.wrist_goal("Right", over, P_PINCH, r.fingers, r.palm), over_paper)
	var over_palm := _e(8.62, 8.85) * (1.0 - _e(9.22, 9.5))
	if over_palm > 0.0:
		var over := hands.pads_point("Left") - bd + Vector3(0.0, WeedProps.JOINT_L * 0.55 + 0.03, 0.0)
		r.wrist = (r.wrist as Vector3).lerp(hands.wrist_goal("Right", over, P_PINCH, r.fingers, r.palm), over_palm)

	var r_w := w_in * lerpf(1.0, 0.9, _e(9.75, 10.0))
	var l_w := w_in * (1.0 - _e(9.68, 9.98))
	_arm("Right", (r.wrist as Vector3) + r_off, r_w, P_WRIST, r.fingers, r.palm, rf)
	_arm("Left", (l.wrist as Vector3) + l_off, l_w, P_WRIST, l.fingers, l_palm, lf)

	# Head and body.
	var head := _head_keys(t)
	hands.head_pitch = head.x - 0.03 * sniff + 0.03 * lick
	hands.head_yaw = head.y - slide * 2.2
	hands.head_roll = head.z
	hands.chest_swell = 0.45 * sniff + 0.3 * _pulse(t, 6.4, 0.25)
	var shiver := _e(1.3, 1.38) * (1.0 - _e(1.62, 1.75))
	hands.sway = sin(t * 40.0) * 0.04 * shiver + sin((t - 9.5) * 13.0) * 0.05 * tada
	hands.lean = 0.1 * _e(1.5, 1.9) * (1.0 - _e(9.3, 9.6)) - 0.05 * _e(6.25, 6.45) * (1.0 - _e(7.22, 7.5))

	_place_roll_props(t, bd)
	_roll_events(t, bd)


## Lays the bud, paper, filling, joint and tongue into the hands (current pose).
func _place_roll_props(t: float, bd: Vector3) -> void:
	var lp := hands.pinch_point("Left")
	var rp := hands.pinch_point("Right")
	var info := WeedStrains.info(_roll_strain)

	# The bud: out of the pouch into the right pinch, crumbled away to nothing.
	var bud_in := _e(0.28, 0.42)
	var crumbled := _e(1.85, 3.25)
	var chunks := floorf(crumbled * 7.0) / 7.0
	var bud_s := bud_in * (1.0 - lerpf(crumbled, chunks, 0.6))
	_float_bud.visible = bud_s > 0.02
	if _float_bud.visible:
		var fd := hands.finger_direction("Right")
		var pd := hands.palm_direction("Right")
		var size := 0.05 * bud_s
		_float_bud.position = rp + fd * size * 0.8 - pd * size * 0.1
		var jolt := sin(crumbled * 7.0 * TAU) * 0.25 * _e(1.85, 2.0)
		# Broad side to the front (the bud model is flat-ish along its Z).
		_float_bud.rotation = Vector3(0.15 * sin(t * 1.7) + jolt, -0.5 + 0.3 * sin(t * 1.3), 0.2 * sin(t * 2.0))
		_float_bud.scale = Vector3.ONE * size / maxf(_bud_radius, 0.001)
	_crumbs.position = rp + Vector3(0, -0.012, 0)
	var crumbling := t > 1.85 and t < 3.25
	if _crumbs.emitting != crumbling:
		_crumbs.emitting = crumbling

	# The paper: by a corner, on the left fingers, then between both pinches.
	var paper_s := _e(0.74, 0.92)
	var joint_show := t >= 7.95
	_paper.visible = paper_s > 0.01 and not joint_show
	var flag := _paper_flag(lp)
	var held := _paper_held(lp)
	var ends := _paper_ends(lp, rp, t)
	var xf := flag.interpolate_with(held, _e(1.38, 1.62))
	xf = xf.interpolate_with(ends, _e(3.62, 3.88))
	if paper_s < 1.0:
		xf.basis = xf.basis.scaled(Vector3.ONE * maxf(paper_s, 0.001))
		# Pop out of the pinch.
		xf.origin = lp.lerp(xf.origin, paper_s)
	_paper.transform = xf
	_paper_home = xf.origin
	var fill := _e(1.9, 3.3)
	var fold := _e(3.92, 4.25)
	var wrap_a := _e(4.62, 5.3)
	var wrap_b := _e(5.3, 6.2) * 0.8 + _e(7.58, 7.88) * 0.2
	_paper_mat.set_shader_parameter("fill", fill * (1.0 - fold))
	_paper_mat.set_shader_parameter("fold", lerpf(0.32 * _e(1.45, 1.75), 1.0, fold))
	_paper_mat.set_shader_parameter("wrap_a", wrap_a)
	_paper_mat.set_shader_parameter("wrap_b", wrap_b)
	_paper_mat.set_shader_parameter("wet", _e(6.55, 7.1))

	# The ground bud: a mound on the sheet, shaped into a log in the taco.
	_filling.visible = fill > 0.01 and not joint_show and _paper.visible
	if _filling.visible:
		var shape := _e(3.95, 4.5)
		var r := WeedProps.PAPER_R * 0.86
		var mound := Vector3(0.35 + 0.35 * fill, 0.15 + 0.4 * fill, 1.5 - 0.3 * fill)
		var sc := mound.lerp(Vector3.ONE, shape)
		var y := lerpf(-WeedProps.PAPER_R + r * sc.y, 0.0, shape)
		_filling.transform = xf * Transform3D(Basis.from_scale(sc), Vector3(0.0, y, 0.0))

	# The joint: swapped in for the sealed tube, twisted, tapped, shown off.
	var jroot: Node3D = _joint.root
	jroot.visible = joint_show
	if joint_show:
		var twist: Node3D = _joint.twist
		twist.visible = t > 8.05
		twist.scale = Vector3.ONE * maxf(_e(8.05, 8.55), 0.001)
		var axis := (lp - rp).normalized() if lp.distance_to(rp) > 0.01 else Vector3.RIGHT
		var mid := (lp + rp) * 0.5 + _up_from(axis) * 0.002
		var spin := sin((t - 8.02) * 22.0) * 0.3 * _e(8.02, 8.12) * (1.0 - _e(8.5, 8.6))
		var held_mid := mid - axis * WeedProps.JOINT_L * 0.5
		var up_dir := Vector3.UP
		var fd := hands.finger_direction("Right")
		var tada_dir := (fd + Vector3(-0.2, 0.5, 0.0)).normalized()
		var dir := axis.lerp(up_dir, _e(8.62, 8.85)).lerp(tada_dir, _e(9.25, 9.55)).normalized()
		var at := held_mid
		var on_r := rp - dir * WeedProps.JOINT_L * lerpf(0.55, 0.25, _e(9.25, 9.55))
		at = held_mid.lerp(on_r, _e(8.62, 8.85))
		# Settle into the everyday hold between the fingers.
		var rest := _e(9.72, 10.0)
		if rest > 0.0:
			at = at.lerp(hands.grip_point("Right"), rest)
			dir = dir.lerp(_hold_dir(), rest).normalized()
		_set_joint(at, dir, spin)

	# The tongue, out under the moustache for the lick.
	var tongue := _e(6.4, 6.52) * (1.0 - _e(7.12, 7.26))
	_tongue.visible = tongue > 0.01
	if _tongue.visible:
		var mouth: Transform3D = _skel.get_bone_global_pose(_head_bone) * _mouth_local
		_tongue.transform = Transform3D(mouth.basis * Basis.from_scale(Vector3(1.0, 1.0, maxf(tongue, 0.001))), mouth.origin)

	# A shine that runs down the seam as it seals.
	var shine := _e(7.58, 7.62) * (1.0 - _e(7.9, 7.96))
	var star := _pulse(t, 9.56, 0.22)
	_glint.visible = shine > 0.01 or star > 0.01
	if shine > 0.01:
		var u := smoothstep(7.6, 7.92, t)
		var seam := rp.lerp(lp, u) + _up_from((lp - rp).normalized()) * (WeedProps.PAPER_R + 0.003)
		_glint.position = seam
		_glint.scale = Vector3.ONE * 0.6
		_glint.set_instance_shader_parameter("strength", shine)
		_glint.set_instance_shader_parameter("spin", t * 3.0)
	elif star > 0.01:
		_glint.position = _tip_world_skel()
		_glint.scale = Vector3.ONE * 1.6
		_glint.set_instance_shader_parameter("strength", star)
		_glint.set_instance_shader_parameter("spin", t * 2.0)


## The paper hanging from the left pinch by its corner, face to the front.
func _paper_flag(lp: Vector3) -> Transform3D:
	var axis := Vector3(1.0, 0.45, 0.1).normalized()
	var face := Vector3(0.1, -0.15, 1.0)
	var b := _paper_basis(axis, face)
	var origin := lp - axis * (WeedProps.PAPER_L * 0.5 - 0.008) + b.y * WeedProps.PAPER_R
	return Transform3D(b, origin)


## The paper held out flat by its end in the left pinch (a little V fold in
## it keeps it stiff), tipped towards the Keling's eyes and the camera.
func _paper_held(lp: Vector3) -> Transform3D:
	var axis := Vector3(1.0, 0.1, -0.05).normalized()
	var b := _paper_basis(axis, Vector3(0.0, 1.0, 0.35))
	return Transform3D(b, lp - axis * (WeedProps.PAPER_L * 0.5 - 0.006) + b.y * WeedProps.PAPER_R)


## The paper held at both ends, rocked and rolled about its own axis.
func _paper_ends(lp: Vector3, rp: Vector3, t: float) -> Transform3D:
	var axis := (lp - rp).normalized() if lp.distance_to(rp) > 0.01 else Vector3.RIGHT
	var turn := 0.35 * sin((t - 4.15) * 21.0) * _e(4.15, 4.3) * (1.0 - _e(4.5, 4.62))
	turn += 0.25 * sin((t - 4.6) * 11.0) * _e(4.6, 4.75) * (1.0 - _e(6.05, 6.25))
	# Gum strip towards the mouth for the lick.
	turn -= 0.35 * _e(6.25, 6.45) * (1.0 - _e(7.22, 7.5))
	var up := _up_from(axis).rotated(axis, turn)
	var b := _paper_basis(axis, up)
	return Transform3D(b, (lp + rp) * 0.5 + b.y * WeedProps.PAPER_R * (1.0 - _e(4.0, 4.4)))


## A paper frame: X along the sheet, Y its face normal (bent towards `face`).
static func _paper_basis(axis: Vector3, face: Vector3) -> Basis:
	var x := axis.normalized()
	var y := face - x * face.dot(x)
	if y.length() < 0.01:
		y = Vector3.UP - x * x.y
	y = y.normalized()
	return Basis(x, y, x.cross(y))


static func _up_from(axis: Vector3) -> Vector3:
	var y := Vector3.UP - axis * axis.dot(Vector3.UP)
	return y.normalized() if y.length() > 0.01 else Vector3.BACK


## One-off beats: pops, bursts, hearts, sounds.
func _roll_events(t: float, bd: Vector3) -> void:
	var info := WeedStrains.info(_roll_strain)
	if _event("pouch", 0.22):
		_sfx("pouch")
	if _event("bud_in", 0.32):
		_burst(hands.pinch_point("Right"), info.glow, 10)
		_sfx("bling", 1.1)
	if _event("paper_in", 0.76):
		_burst(hands.pinch_point("Left"), Color(1, 0.95, 0.85), 8)
		_sfx("paper", 1.25)
	if _event("sniff", 0.96):
		_sfx("sniff")
	if _event("hearts", 1.36):
		_hearts.position = _mouth + bd + Vector3(0.0, 0.08, 0.06)
		_hearts.restart()
		_hearts.emitting = true
		_sfx("happy")
	if _event("crumble", 1.86):
		_sfx("crumble")
	for i in 6:
		if _event("chunk%d" % i, 2.05 + i * 0.2):
			_burst(hands.pinch_point("Right"), info.glow * 0.8, 3)
	if _event("dust", 3.34):
		_sfx("pat")
		_crumbs.restart()
		_crumbs.emitting = true
	if _event("fold", 3.92):
		_sfx("paper", 0.9)
	if _event("roll", 4.62):
		_sfx("roll")
	if _event("lick", 6.5):
		_sfx("lick")
	if _event("seal", 7.58):
		_sfx("glint")
	if _event("sealed", 7.94):
		_burst((hands.pinch_point("Left") + hands.pinch_point("Right")) * 0.5, Color(1, 1, 1), 10)
	if _event("twist", 8.04):
		_sfx("twist")
	if _event("tap1", 8.97):
		_sfx("tap")
	if _event("tap2", 9.13):
		_sfx("tap", 1.08)
	if _event("tada", 9.52):
		_burst(_tip_world_skel(), info.glow, 22)
		_sfx("tada")
		if local:
			Input.vibrate_handheld(20)
	if _event("camera_back", 9.8) and local:
		_closeup(false)

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
	var dt := get_process_delta_time()
	var rig := _rig.global_transform
	var m := 0.0       # 0 held low .. 1 at the lips
	var forward := 0.0 # 1 = held straight out in front (to light it)
	var ember := 0.6
	var info := WeedStrains.info(joint_strain)
	if act == Act.LIGHT:
		m = _e(0.0, 0.45) * (1.0 - _e(1.9, 2.45))
		forward = m
	elif act == Act.DRAGON:
		m = _e(0.0, 0.5) * (1.0 - _e(2.3, 2.65))
	else:
		m = _e(0.0, 0.5) * (1.0 - _e(1.55, 1.95))

	# The right hand brings the joint to the lips, filter first.
	var rg := _hold_r.lerp(_to_mouth_r.lerp(_to_mouth_front_r, forward), m)
	_arm("Right", rg, 1.0, P_WRIST, Vector3(0.0, 0.3, 1.0).lerp(Vector3(0.6, 0.25, 1.0), m), Vector3(1.0, 0.3, 0.0), "hold")
	var g := hands.grip_point("Right")
	var at_mouth := _mouth + bd
	var out := MOUTH_OUT.normalized().lerp(LIGHT_OUT.normalized(), forward)
	var dir := _hold_dir().lerp(out, m).normalized()
	_set_joint(g.lerp(at_mouth, m), dir)
	var tip := _tip_world_skel()
	var up_w := (rig.basis * Vector3.UP).normalized()

	if act == Act.LIGHT:
		# Thumb flicks a fairy flame alight on the left fingertips and holds
		# it under the tip; three short draws pull the flame in until the
		# ember catches, then a shake of the hand puts the flame out.
		var lw := _e(0.1, 0.4) * (1.0 - _e(1.9, 2.35))
		var flick := _pulse(t, 0.5, 0.09)
		var draws := _pulse(t, 0.88, 0.13) + _pulse(t, 1.18, 0.13) + _pulse(t, 1.48, 0.13)
		var shake := _e(1.62, 1.66) * (1.0 - _e(1.86, 1.96))
		var catch := _e(0.85, 1.55)
		var ready := _light_ready + bd
		var under := tip + Vector3(0.012, -0.062, 0.004)
		var goal := ready.lerp(under, _e(0.52, 0.74)).lerp(_light_rest + bd, _e(1.62, 1.95))
		goal += Vector3(sin(t * 46.0) * 0.016 * shake, 0.002 * sin(t * 11.0) * _e(0.7, 0.8), 0.0)
		_arm("Left", goal, lw, P_PINCH, Vector3(-0.35, 0.6, 1.0), Vector3(-1.0, -0.2, -0.2), {"curl": 0.2, "index": 0.22, "middle": 0.5, "ring": 0.7, "pinch": 1.0 - 0.7 * flick, "rub": flick, "wiggle": 0.4 * shake})
		var flame_at := hands.pinch_point("Left") + Vector3(0.0, 0.008, 0.0)
		var flame_k := _e(0.48, 0.56) * (1.0 - _e(1.66, 1.82))
		_flame.visible = flame_k > 0.01
		_flame.position = flame_at
		_flame.scale = Vector3(1.0, 1.0 + 0.45 * draws, 1.0) * maxf(1.8 * flame_k * (0.9 + 0.1 * sin(t * 37.0)), 0.001)
		if _event("flick", 0.5):
			_burst(flame_at, Color(1.0, 0.6, 0.2), 6)
			_sfx("flick")
		for i in 3:
			if _event("light_draw%d" % i, 0.8 + 0.3 * i):
				_sfx("draw", 1.35)
				for k in 2:
					_smoke.puff(rig * tip, up_w * 0.05 + _jitter(0.02), 0.012, 0.09, 1.8, 0.5)
		if _event("flame_out", 1.8):
			_smoke.puff(rig * flame_at, up_w * 0.08, 0.008, 0.06, 1.3, 0.4)
			_sfx("fizzle")
		_sparks.position = tip
		_sparks.emitting = draws > 0.3 and catch > 0.1
		ember = 0.3 + catch * (0.5 + 2.2 * draws)
		_ember_smoke = catch * (1.0 - 0.6 * draws)
		hands.chest_swell = 0.22 * draws + 0.25 * _e(1.5, 1.7) * (1.0 - _e(1.95, 2.4))
		hands.head_pitch = -0.08 * m + 0.12 * _e(1.9, 2.1) * (1.0 - _e(2.3, 2.6))
		# A first small puff of smoke out of the mouth.
		if t > 1.95 and t < 2.45:
			var k := (t - 1.95) / 0.5
			_exhale_stream(rig, dt, 26.0 * pow(1.0 - k, 0.7), lerpf(0.8, 0.3, k), lerpf(0.22, 0.3, k), 2.8, lerpf(0.6, 0.35, k))
		if _event("light_exhale", 1.95):
			_sfx("exhale", 1.25)
	elif act == Act.DRAGON:
		_pose_dragon(t, rig, tip, info)
		return
	else:
		_arm("Left", _tray_l, 0.0)
		# Draw deep (the ember flares and crackles), lower the joint, hold
		# it in for a moment, then tip the head back and let it roll out.
		var inhale := _e(0.5, 1.5)
		var drawing := inhale * (1.0 - _e(1.5, 1.65))
		ember = 0.6 + 4.2 * drawing + 0.5 * sin(t * 31.0) * drawing
		_ember_smoke = lerpf(1.0, 0.1, drawing) + 0.6 * _e(1.6, 1.75) * (1.0 - _e(1.9, 2.6))
		_sparks.position = tip
		_sparks.emitting = drawing > 0.3
		hands.chest_swell = inhale * (1.0 - _e(2.3, 3.5))
		hands.head_pitch = 0.05 * _e(1.6, 2.0) * (1.0 - _e(2.2, 2.35)) + 0.28 * _e(2.25, 2.6) * (1.0 - _e(3.3, 3.8))
		if _event("draw", 0.5):
			_sfx("draw")
		if _event("leak", 1.95):
			var mx := _mouth_xf()
			_smoke.puff(rig * (mx.origin + mx.basis.z * 0.01), up_w * 0.03, 0.008, 0.05, 1.4, 0.35, 1.0)
		if _event("exhale", 2.3):
			_count_puff()
			_sfx("exhale")
		if t > 2.3 and t < 3.65:
			var k := (t - 2.3) / 1.35
			_exhale_stream(rig, dt, 42.0 * pow(1.0 - k, 0.7), lerpf(1.6, 0.4, k), lerpf(0.3, 0.45, k), 3.6, lerpf(0.65, 0.35, k), 1.5)
		if t > 2.3 and t < 2.95 and not _nose_local.is_empty():
			var k := (t - 2.3) / 0.65
			var head := _skel.get_bone_global_pose(_head_bone)
			for i in 2:
				var nx := head * _nose_local[i]
				_smoke.stream(StringName("nose%d" % i), rig * nx.origin, rig.basis * nx.basis.z, 9.0 * (1.0 - k), 0.32, 0.01, 0.1, 1.9, 0.5, 0.12, dt)
		if joint_puffs <= 0 and t > 3.3:
			# The last of it: the roach vanishes in a twinkle.
			var gone := _e(3.3, 3.75)
			(_joint.root as Node3D).scale = Vector3.ONE * maxf(1.0 - gone, 0.001)
			_ember_smoke = 0.0
			if _event("roach", 3.4):
				_burst(hands.grip_point("Right"), info.glow, 14)
	_set_ember(ember)


## Dragon Breath, beat by beat:
##   0.0  the joint comes up to the lips, as for any puff
##   0.5  a long, deep draw: the ember blazes and crackles, the chest swells
##        and keeps swelling, blue light gathers at the lips and wisps of mist
##        spiral into them; the Keling turns to face the way it will go
##   2.3  the joint comes down; the head rears back, holding it in
##   2.75 the blast: the head thrusts forward and the breath roars out as a
##        jet of blue mist, out of which the water dragon swims away
##   3.0  the last wisps trickle out; it settles back, pleased with itself
func _pose_dragon(t: float, rig: Transform3D, tip: Vector3, info: Dictionary) -> void:
	_arm("Left", _tray_l, 0.0)
	var dt := get_process_delta_time()
	var draw := _e(0.5, 2.3)
	var drawing := draw * (1.0 - _e(2.3, 2.45))
	var ember := 0.6 + 5.5 * drawing + 0.8 * sin(t * 37.0) * drawing
	_ember_smoke = lerpf(1.0, 0.05, drawing)
	_sparks.position = tip
	_sparks.emitting = drawing > 0.2
	var rear := _e(2.3, 2.7) * (1.0 - _e(2.74, 2.84))
	var blast := _e(2.74, 2.84) * (1.0 - _e(3.3, 4.4))
	hands.chest_swell = (draw * 1.3 + 0.05 * sin(t * 9.0) * draw) * (1.0 - _e(2.74, 3.1))
	hands.head_pitch = 0.05 * draw * (1.0 - rear) + 0.34 * rear - 0.24 * blast
	hands.lean = -0.1 * rear + 0.3 * blast
	if _event("d_draw", 0.5):
		_sfx("draw", 0.82)
	var mx := _mouth_xf()
	var mouth := Transform3D(rig.basis.orthonormalized() * mx.basis.orthonormalized(), rig * mx.origin)
	if _dragon:
		if t < DRAGON_RELEASE:
			_dragon.charge(mouth, draw * (1.0 - 0.3 * rear) + rear * 0.3)
		elif _event("d_blast", DRAGON_RELEASE):
			_dragon.release(mouth, _dragon_yaw)
			_count_puff()
			dragon_breathed.emit()
			if local:
				var cam = keling.get("camera_rig")
				if cam:
					cam.shake(0.28)
				Input.vibrate_handheld(60)
	# What's left of the breath trickles out after the blast.
	if t > 3.05 and t < 3.9:
		var k := (t - 3.05) / 0.85
		_exhale_stream(rig, dt, 14.0 * (1.0 - k), 0.5, 0.25, 2.4, 0.3 * (1.0 - k))
	if joint_puffs <= 0 and t > 3.9:
		var gone := _e(3.9, 4.35)
		(_joint.root as Node3D).scale = Vector3.ONE * maxf(1.0 - gone, 0.001)
		_ember_smoke = 0.0
		if _event("roach", 4.0):
			_burst(hands.grip_point("Right"), info.glow, 14)
	_set_ember(ember)


## Breath out of the mouth: a stream of puffs leaving the lips.
func _exhale_stream(rig: Transform3D, dt: float, rate: float, speed: float, size: float, life: float, alpha: float, drag := 2.0) -> void:
	var mx := _mouth_xf()
	var o := rig * (mx.origin + mx.basis.z * 0.012)
	var d := rig.basis * (mx.basis.z + Vector3(0.0, 0.5, 0.0))
	_smoke.stream(&"exhale", o, d, rate, speed, 0.03, size, life, alpha, 0.14, dt, drag)


## The mouth in world space, looking out of it (for gifts breathed out).
func mouth_world() -> Transform3D:
	var xf := _rig.global_transform * _mouth_xf()
	return Transform3D(xf.basis.orthonormalized(), xf.origin)


func _mouth_xf() -> Transform3D:
	if _head_bone < 0:
		return Transform3D(Basis.looking_at(Vector3(0.0, -0.35, 1.0), Vector3.UP, true), _mouth + hands.body_delta)
	return _skel.get_bone_global_pose(_head_bone) * _mouth_local


func _jitter(r: float) -> Vector3:
	return Vector3(randf_range(-r, r), randf_range(-r, r), randf_range(-r, r))


## How much of the joint is left: each puff burns a little more of it away.
func _burn() -> float:
	if not has_joint():
		return 1.0
	var k := 1.0 - BURN_PER_PUFF * (HITS - joint_puffs)
	if act == Act.LIGHT:
		k -= 0.03 * _e(0.85, 1.55)
	elif lit:
		k -= 0.03
		if act == Act.HIT and not _hit_counted:
			k -= BURN_PER_PUFF * _e(0.5, 1.5)
		elif act == Act.DRAGON and not _hit_counted:
			k -= BURN_PER_PUFF * _e(0.5, 2.3)
	return clampf(k, 0.3, 1.0)


func _apply_burn(k: float) -> void:
	_burn_k = k
	var body: Node3D = _joint.body
	body.scale = Vector3(1.0, k, 1.0)
	body.position.x = WeedProps.JOINT_L * k * 0.5
	(_joint.ember as Node3D).position.x = WeedProps.JOINT_L * k
	(_joint.twist as Node3D).position.x = WeedProps.JOINT_L * k + 0.01


## The tongue comes out of the mouth and turns with the head.
func _bind_mouth() -> void:
	_head_bone = _skel.find_bone("Head")
	_nose_local.clear()
	if _head_bone >= 0:
		var head_rest := _skel.get_bone_global_rest(_head_bone)
		var mouth := Transform3D(Basis.looking_at(Vector3(0.0, -0.35, 1.0), Vector3.UP, true), _mouth + Vector3(0.0, -0.004, -0.012))
		_mouth_local = head_rest.affine_inverse() * mouth
		# The nostrils, under the nose, breathing out down and away.
		for sx in [-1.0, 1.0]:
			var nose := Transform3D(Basis.looking_at(Vector3(sx * 0.45, -0.75, 0.55), Vector3.UP, true), _nose + Vector3(sx * NOSTRIL_X, 0.0, 0.0))
			_nose_local.append(head_rest.affine_inverse() * nose)


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
	return jroot.transform * Vector3(WeedProps.JOINT_L * _burn_k, 0, 0)


func _set_ember(energy: float) -> void:
	var em: ShaderMaterial = _joint.ember_mat
	em.set_shader_parameter("energy", energy if lit or act == Act.LIGHT else 0.0)


# ---------------------------------------------------------------------------
# Every frame, after the hands are posed: drive the poses for the next frame
# and lay the props into the fingers.

func _place_props() -> void:
	_apply_burn(_burn())
	_ember_smoke = 1.0
	if act == Act.ROLL:
		_pose_roll()
	elif act == Act.LIGHT or act == Act.HIT or act == Act.DRAGON:
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
	if lit or act == Act.LIGHT:
		(_joint.twist as Node3D).visible = false
	if act != Act.LIGHT and act != Act.HIT and act != Act.DRAGON:
		_sparks.emitting = false
	# The ember's own thin stream of smoke.
	var smoking := has_joint() and jroot.visible and _joint_hidden < 0.5 and (lit or act == Act.LIGHT)
	_smoke.set_scale_hint(_rig.global_transform.basis.get_scale().y)
	_smoke.ember(_rig.global_transform * _tip_world_skel(), _ember_smoke * (jroot.scale.x if smoking else 0.0))


func _pose_rest() -> void:
	var w := _hold
	_swim_hold = move_toward(_swim_hold, 1.0 if keling.mode == KelingController.Mode.SWIM else 0.0, 0.04)
	var goal := _hold_r.lerp(_swim_hold_r, smoothstep(0.0, 1.0, _swim_hold))
	_arm("Right", goal, w * 0.9, P_WRIST, Vector3(0.0, 0.3 + 0.5 * _swim_hold, 1.0), Vector3(1.0, 0.3, 0.0), "hold")
	var l: Dictionary = hands.arms["Left"]
	l.w = move_toward(l.w, 0.0, 0.05)
	hands.chest_swell = move_toward(hands.chest_swell, 0.0, 0.05)
	hands.head_pitch = move_toward(hands.head_pitch, 0.0, 0.02)
	hands.head_yaw = move_toward(hands.head_yaw, 0.0, 0.02)
	hands.head_roll = move_toward(hands.head_roll, 0.0, 0.02)
	hands.lean = move_toward(hands.lean, 0.0, 0.01)
	hands.sway = move_toward(hands.sway, 0.0, 0.01)
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
	_filling = WeedProps.filling(Color(0.45, 0.7, 0.3))
	_filling_mat = (_filling.get_child(0) as MeshInstance3D).material_override
	_filling.visible = false
	_rig.add_child(_filling)
	_tongue = WeedProps.tongue()
	_rig.add_child(_tongue)
	_glint = WeedProps.glint()
	_rig.add_child(_glint)
	_hearts = WeedProps.hearts()
	_rig.add_child(_hearts)
	var aabb := WeedKit.bud_mesh().get_aabb()
	_bud_radius = maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	_bind_mouth()
	for i in 3:
		var v := AudioStreamPlayer3D.new()
		v.name = "WeedSfx%d" % i
		v.unit_size = 2.5
		v.max_distance = 18.0
		v.volume_db = -4.0
		v.attenuation_filter_cutoff_hz = 9000.0
		v.bus = &"SFX"
		_rig.add_child(v)
		_voices.append(v)
	_crumbs = WeedProps.crumbs(Color(0.5, 0.8, 0.3))
	_rig.add_child(_crumbs)
	_sparkle = WeedProps.stars(Color(1, 1, 1), 12, 0.035)
	_rig.add_child(_sparkle)
	_smoke = WeedSmoke.new()
	_smoke.name = "Smoke"
	keling.add_child.call_deferred(_smoke)
	_sparks = WeedProps.ember_sparks()
	_rig.add_child(_sparks)
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


## Plays one of the rolling sounds (assets/audio/weed/<name>.ogg) at the hands.
func _sfx(clip: String, pitch := 1.0) -> void:
	if _voices.is_empty():
		return
	if not _clips.has(clip):
		var path := "res://assets/audio/weed/%s.ogg" % clip
		_clips[clip] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _clips[clip]
	if stream == null:
		return
	var v := _voices[_voice]
	_voice = (_voice + 1) % _voices.size()
	v.position = _w0 + hands.body_delta
	v.stream = stream
	v.pitch_scale = pitch * randf_range(0.96, 1.04)
	v.play()


## Swings the camera round to the front for a close look at the rolling.
func _closeup(on: bool) -> void:
	var cam = keling.get("camera_rig") if keling else null
	if cam == null or not cam.has_method("begin_closeup"):
		return
	if on:
		cam.begin_closeup(keling.facing)
	else:
		cam.end_closeup()


func _burst(at: Vector3, color: Color, amount: int) -> void:
	_sparkle.position = at
	_sparkle.amount = amount
	_sparkle.color = color
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
