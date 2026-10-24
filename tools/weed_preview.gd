extends SceneTree
## Look-only previews of the weed loop in the forest (lavapipe is slow and
## nothing like a phone; use these for looks, never for performance):
## a weed patch, the rolling ritual, lighting up, the exhale and the HUD.
##   xvfb-run godot --path . -s res://tools/weed_preview.gd -- <out_dir>

# Shot list: [name, seconds after the step starts, camera preset]
const ROLL_SHOTS := [["roll_1_crumble", 2.2], ["roll_2_curl", 5.0], ["roll_3_lick", 7.5], ["roll_4_twist", 8.6], ["roll_5_tada", 9.35]]
const SMOKE_SHOTS := [["smoke_1_light", 0.85], ["smoke_2_inhale", 1.5 + 1.2], ["smoke_3_exhale", 1.5 + 3.1]]

var _out := "user://"
var _k
var _forest
var _cam: Camera3D
var _t := 0.0
var _stage := 0
var _stage_t := 0.0
var _shots: Array = []
var _hud_shot := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://weed.cfg"))
	root.size = Vector2i(1280, 720)
	root.add_child(load("res://world/forest/forest_level.tscn").instantiate())


func _snap(name: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("weed_preview: ", name)


func _frame_keling(dist := 1.5, height := 0.95, side := 0.55, look_h := 0.78) -> void:
	var f: float = _k.facing
	var fwd := Vector3(sin(f), 0, cos(f))
	var right := Vector3(cos(f), 0, -sin(f))
	var base: Vector3 = _k.global_position
	_cam.current = true
	_cam.look_at_from_position(base + fwd * dist + right * side + Vector3.UP * height, base + Vector3.UP * look_h + fwd * 0.25)


func _process(delta: float) -> bool:
	_t += delta
	_stage_t += delta
	if _k == null:
		_k = root.find_child("Keling", true, false)
		_forest = root.find_child("Forest", true, false)
		if _k:
			_cam = Camera3D.new()
			_cam.fov = 42
			root.add_child(_cam)
		return false
	if _t > 900.0:
		quit(1)
		return true
	match _stage:
		0:
			# A weed patch by the spawn, from a little way off.
			if _stage_t < 2.0:
				return false
			var plant = _forest.weed.nodes[0]
			var p: Vector3 = plant.global_position
			_cam.current = true
			_cam.look_at_from_position(p + Vector3(1.6, 1.2, 2.2), p + Vector3(0, 0.55, 0))
			if _stage_t > 6.0:
				_snap("patch_close")
				_cam.look_at_from_position(p + Vector3(-3.0, 2.2, 5.0), p + Vector3(0, 0.4, 0))
				_stage = 1
				_stage_t = 0.0
		1:
			if _stage_t < 3.0:
				return false
			_snap("patch_wide")
			# Stand the Keling beside the patch and start rolling.
			var plant = _forest.weed.nodes[0]
			var p: Vector3 = plant.global_position + Vector3(1.0, 0, 0.9)
			_k.global_position = Vector3(p.x, _forest.ground_height(p.x, p.z) + 0.05, p.z)
			_k.velocity = Vector3.ZERO
			_k.facing = 0.6
			_k.weed.add_bud(&"starlit")
			_stage = 2
			_stage_t = 0.0
		2:
			_frame_keling()
			if _stage_t > 1.5:
				_k.weed.use()
				_shots = ROLL_SHOTS.duplicate()
				_stage = 3
				_stage_t = 0.0
		3:
			# Timed by the roll itself (slow frames make physics lag behind).
			_frame_keling()
			if not _shots.is_empty() and _k.weed.act_t >= _shots[0][1]:
				_snap(_shots.pop_front()[0])
			if _shots.is_empty() and _k.weed.act == 0 and _k.weed.has_joint() and _stage_t > 1.0:
				_snap("hold_joint")
				_k.weed.use()
				_shots = SMOKE_SHOTS.duplicate()
				_stage = 4
				_stage_t = 0.0
		4:
			_frame_keling(1.45, 1.0, 0.75, 0.85)
			var el: float = _k.weed.act_t + (1.5 if _k.weed.act == 3 else 0.0)
			if not _shots.is_empty() and _k.weed.act != 0 and el >= _shots[0][1]:
				_snap(_shots.pop_front()[0])
			if _shots.is_empty() and _k.weed.act == 0:
				# Behind the shoulder, like in play, with the HUD and the glow.
				_k.camera_rig.camera.current = true
				_stage = 5
				_stage_t = 0.0
		5:
			if _stage_t > 2.5:
				_snap("hud_glade_glow")
				quit(0)
				return true
	return false
