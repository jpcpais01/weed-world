extends SceneTree
## Headless check of the playable Kelings in the real forest: the Keling
## transforms into each character in turn (the full KelingMorph), and on each
## one the model, clips, pose layers, springs and hands are in place, a grab
## works and a whole joint gets rolled with the fitted choreography. A
## friend's puppet is built as one character and switched to another, and
## the choice is saved. Exits non-zero on failure.
##   godot --headless --path . -s res://tools/character_check.gd

# Untyped on purpose: -s scripts compile before the autoloads exist, and the
# controller names GameInput.
const ROLL_TIME := 10.0
const ACT_NONE := 0
const ACT_ROLL := 1
const MORPH_MODE := 9
const BONES := ["Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "LeftShoulder", "LeftHand",
	"RightHand", "LeftThumbTip", "RightIndexTip", "LeftMiddleTip", "RightRingTip", "LeftFoot", "RightToes"]
const CLIPS := [&"Idle", &"Walk", &"Jog", &"Sprint", &"Cheer", &"SitIdle", &"Fall", &"Turn90L", &"IdleFoldArms"]

var _k
var _t := 0.0
var _step := 0
var _step_t := 0.0
var _fails: Array[String] = []
var _order: Array = []
var _target := ""
var _puppet


func _initialize() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())
	_order = KelingCharacters.IDS.slice(1) + [KelingCharacters.DEFAULT]


func _check(ok: bool, what: String) -> void:
	print("character_check: %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails.append(what)


func _next(step := -1) -> void:
	_step = _step + 1 if step < 0 else step
	_step_t = 0.0


func _physics_process(delta: float) -> bool:
	_t += delta
	_step_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		return false
	if _t > 150.0:
		_check(false, "timed out at step %d (%s)" % [_step, _target])
		return _finish()
	match _step:
		0:
			if _step_t < 1.0:
				return false
			_check(_k.character_id == KelingCharacters.DEFAULT, "a new player starts as the original Keling")
			_check(_k.springs.setting_count == 6, "the original keeps its six crown springs")
			_next()
		1:
			# Transform into the next character.
			if _order.is_empty():
				_next(10)
				return false
			_target = _order.pop_front()
			_check(_k.morph_to(_target), "starts turning into %s" % _target)
			_check(_k.mode == MORPH_MODE and _k.morph != null, "%s: the transformation is playing" % _target)
			_check(not _k.can_morph(), "%s: can't start another one mid-transformation" % _target)
			_next()
		2:
			if _k.morph != null and _step_t < 5.0:
				return false
			_check(_k.morph == null, "%s: the transformation ends (%.1f s)" % [_target, _step_t])
			_inspect(_target)
			_check(KelingCharacters.saved_id() == _target, "%s: the choice is saved" % _target)
			_next()
		3:
			# A grab in front (nothing there) still reaches out and comes back.
			if _step_t > 0.8 and _step_t - delta <= 0.8:
				_k.try_grab()
				_check(_k.grab.grabbing, "%s: reaches out to grab" % _target)
			if _step_t < 3.4:
				return false
			_check(not _k.grab.grabbing, "%s: the grab finishes" % _target)
			_k.weed.add_bud(&"starlit")
			_k.weed.use()
			_check(_k.weed.act == ACT_ROLL, "%s: starts rolling" % _target)
			_check(not _k.can_morph(), "%s: can't transform with full hands" % _target)
			_next()
		4:
			if _step_t < ROLL_TIME + 0.3:
				return false
			_check(_k.weed.has_joint(), "%s: rolled a joint" % _target)
			_check(_k.weed.act == ACT_NONE, "%s: rolling finished" % _target)
			_k.weed.joint_strain = &""
			_k.weed.joint_puffs = 0
			_k.weed._clear_joint()
			_next(1)
		10:
			# A friend's Keling arrives as Toadstool, then switches to Blossom.
			_puppet = load("res://player/keling.tscn").instantiate()
			_puppet.make_remote(77, 1, "Pal", "toadstool")
			_puppet.position = _k.global_position + Vector3(2, 0, 0)
			_k.get_parent().add_child(_puppet)
			_next()
		11:
			if _step_t < 0.5:
				return false
			_check(_puppet.character_id == "toadstool" and _puppet.model.scene_file_path.ends_with("toadstool.glb"), "a friend's puppet wears their character")
			_puppet.apply_net_event(&"character", ["blossom"])
			_check(_puppet.character_id == "blossom" and _puppet.model.scene_file_path.ends_with("blossom.glb"), "a late joiner sees a friend's switch")
			_puppet.apply_net_event(&"morph", ["sunflower"])
			_check(_puppet.morph != null, "a friend's transformation plays on their puppet")
			_next()
		12:
			if _puppet.morph != null and _step_t < 5.0:
				return false
			_check(_puppet.character_id == "sunflower", "the puppet ends up as the friend's new character")
			_check(_puppet.visual.get_node_or_null("ModelOld") == null, "the puppet's old model is gone")
			return _finish()
	return false


## Everything that has to move to the new model did.
func _inspect(id: String) -> void:
	var skel: Skeleton3D = _k.model.find_child("Skeleton3D", true, false)
	_check(_k.character_id == id and _k.model.scene_file_path.ends_with("%s.glb" % id), "%s: wears the %s model" % [id, id])
	var missing := []
	for b in BONES:
		if skel.find_bone(b) < 0:
			missing.append(b)
	_check(missing.is_empty(), "%s: has the Keling skeleton %s" % [id, missing])
	var clips := []
	for c in CLIPS:
		if not _k.animator.has_animation(c):
			clips.append(c)
	_check(clips.is_empty(), "%s: has every clip %s" % [id, clips])
	_check(_k.procedural.get_skeleton() == skel and _k.sit.get_skeleton() == skel and _k.grab.get_skeleton() == skel,
		"%s: pose layers on the new skeleton" % id)
	_check(_k.weed.hands.get_skeleton() == skel, "%s: the hands moved to the new skeleton" % id)
	_check(_k.springs.get_skeleton() == skel and _k.springs.setting_count == _k.body.springs.size() and _k.springs.setting_count > 0,
		"%s: %d spring chains" % [id, _k.springs.setting_count])
	for i in _k.springs.setting_count:
		if skel.find_bone(_k.springs.get_root_bone_name(i)) < 0:
			_check(false, "%s: spring bone %s exists" % [id, _k.springs.get_root_bone_name(i)])
	_check(_k.visual.get_node_or_null("ModelOld") == null, "%s: the old model is gone" % id)
	var mats := 0
	for mi in _k.model.find_children("*", "MeshInstance3D", true, false):
		for si in mi.mesh.get_surface_count():
			var m = mi.get_surface_override_material(si)
			if m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path.ends_with("morph_body.gdshader"):
				mats += 1
	_check(mats == 0, "%s: the model's own materials are back" % id)
	var mouth: Vector3 = _k.body.mouth()
	_check(id == KelingCharacters.DEFAULT or mouth.distance_to(KelingBody.KELING_LANDMARKS.mouth) > 0.01, "%s: the choreography is fitted (mouth %s)" % [id, mouth])
	_check(_k.mode != MORPH_MODE, "%s: back in control after the transformation" % id)


func _finish() -> bool:
	print("character_check: ", "PASS" if _fails.is_empty() else "FAIL (%s)" % ", ".join(_fails))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://player.cfg"))
	quit(0 if _fails.is_empty() else 1)
	return true
