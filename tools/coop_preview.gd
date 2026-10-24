extends SceneTree
## Screenshots of co-op on the test grounds: the Play together card offline
## and hosting a full forest, and three friends' Kelings (each in its own
## flower colour, with name tags) standing round the host. The friends run
## in-process over LoopbackLink. Looks only:
##   xvfb-run -s "-screen 0 1600x900x24" godot --path . --rendering-method gl_compatibility \
##       -s res://tools/coop_preview.gd -- <out_dir>

var _out := "user://coop_preview"
var _t := 0.0
var _step := 0
var _scene: Node
var _hud: Node
var _net: Node
var _guests: Array = []


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(_out)
	_scene = load("res://scenes/test_grounds.tscn").instantiate()
	root.add_child(_scene)


func _guest(i: int, nm: String) -> void:
	var branch := Node3D.new()
	branch.name = "Guest%d" % i
	branch.visible = false  # their own view of the forest; we film ours
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(), branch.get_path())
	var k = load("res://player/keling.tscn").instantiate()
	k.name = "Keling"
	branch.add_child(k)
	k.get_node("Visual").visible = false
	k.get_node("CameraRig/SpringArm3D/Camera3D").current = false
	var net = load("res://autoload/net.gd").new()
	net.name = "Net"
	net.world_root = branch
	net.link_factory = func(): return load("res://net/loopback_link.gd").new()
	branch.add_child(net)
	net.player_name = nm
	_guests.append({"net": net, "keling": k})


func _process(delta: float) -> bool:
	_t += delta
	if _hud == null:
		_hud = root.find_child("HUD", true, false)
		_net = root.get_node_or_null("Net")
		return false
	match _step:
		0:
			if _t > 2.0:
				_net.link_factory = func(): return load("res://net/loopback_link.gd").new()
				_net.set_player_name("Mossy Toes")
				_hud._coop.open()
				_step = 1
		1:
			if _t > 3.0:
				_shot("panel_offline")
				_step = 2
		2:
			if _t > 3.6 and not _net.is_busy():
				_net.host()
			if _t > 4.0 and _net.online:
				for i in 3:
					_guest(i, ["Fern Puff", "Pip Bloom", "Juniper Dew"][i])
				_step = 3
		3:
			if _t > 5.0:
				for g in _guests:
					if g.net.status == 0:
						g.net.join(_net.room_code)
				_step = 4
		4:
			if _t > 8.0:
				_shot("panel_hosting")
				_hud._coop.close()
				var host: Node3D = get_first_node_in_group("local_player")
				var f: float = host.facing
				for i in _guests.size():
					var k = _guests[i].keling
					var a := f + (i - 1) * 0.55
					k.global_position = host.global_position + Vector3(sin(a), 0, cos(a)) * (2.0 + 0.4 * i)
					k.facing = a + PI
				_guests[0].keling.play_emote(&"Cheer")
				_guests[2].keling.play_emote(&"Dance")
				_step = 5
		5:
			if _t > 10.5:
				var host: Node3D = get_first_node_in_group("local_player")
				var cam = host.camera_rig
				cam.yaw = host.facing + PI + 0.0
				cam.pitch = deg_to_rad(-12.0)
				_step = 6
		6:
			if _t > 12.5:
				_shot("friends")
				_step = 7
		7:
			if _t > 13.5:
				quit(0)
	return false


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [_out, name]
	root.get_texture().get_image().save_png(path)
	print("coop_preview: saved ", path)
