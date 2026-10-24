class_name UiSound
extends RefCounted
## Soft menu sounds (tools/synth_ui_audio.py): a wooden tick when the
## selection moves, a pluck when a value changes, a pop for switches and a
## leafy whoosh when the menu opens or closes. They play on the "UI" bus,
## which follows the Effects volume but is never muffled by the menu.

const DIR := "res://assets/audio/ui/%s.ogg"
const VOLUME := {"move": -14.0, "change": -11.0, "toggle": -9.0, "open": -8.0, "close": -10.0, "confirm": -8.0, "back": -11.0}

static var _players: Array[AudioStreamPlayer] = []
static var _streams := {}
static var _next := 0
static var _last := {}


static func play(name: String, pitch := 1.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null or DisplayServer.get_name() == "headless":
		return
	# The same sound twice in one frame (a slider dragged fast) plays once.
	var now := Time.get_ticks_msec()
	if now - int(_last.get(name, -1000)) < 45:
		return
	_last[name] = now
	if not _streams.has(name):
		var path := DIR % name
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _streams[name]
	if stream == null:
		return
	if _players.is_empty() or not is_instance_valid(_players[0]):
		warm()
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	if not p.is_inside_tree():
		return
	p.stream = stream
	p.volume_db = VOLUME.get(name, -10.0)
	p.pitch_scale = pitch * randf_range(0.97, 1.03)
	p.play()


## Makes the players ahead of time (the menu does this when it is built), so
## the first sound isn't lost.
static func warm() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	if not _players.is_empty() and is_instance_valid(_players[0]):
		return
	_players.clear()
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.name = "UiSound%d" % i
		p.bus = &"UI"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		tree.root.add_child.call_deferred(p)
		_players.append(p)
