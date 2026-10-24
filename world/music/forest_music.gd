class_name ForestMusic
extends Node
## Background music that drifts in now and then, the way nature games do it:
## a gentle piece, then a long quiet stretch of wind and birdsong, then
## another. Lighting up a joint cues a tune sooner. Plays on the
## "Music" bus (its volume is in the pause menu) and keeps playing under it.
## The pieces are original, synthesised by tools/synth_music.py.

const TRACKS := [
	"res://assets/audio/music/glade_morning.ogg",
	"res://assets/audio/music/under_the_elder.ogg",
	"res://assets/audio/music/firefly_drift.ogg",
]
const FIRST_DELAY := Vector2(20.0, 40.0)
const GAP := Vector2(70.0, 160.0)

var _player: AudioStreamPlayer
var _wait := 0.0
var _last := -1
var _rng := RandomNumberGenerator.new()
var _local: Node
var _streams := {}   # track index -> AudioStream, loaded off the main thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_player = AudioStreamPlayer.new()
	_player.name = "Player"
	_player.bus = &"Music"
	_player.volume_db = -9.0  # under the forest, not on top of it
	_player.finished.connect(func(): _wait = _rng.randf_range(GAP.x, GAP.y))
	add_child(_player)
	_wait = _rng.randf_range(FIRST_DELAY.x, FIRST_DELAY.y)
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	# Opening an Ogg on the main thread hitched the frame a tune began on.
	for path in TRACKS:
		ResourceLoader.load_threaded_request(path)


func _process(delta: float) -> void:
	if _local == null or not is_instance_valid(_local):
		_bind_local()
	if _player.playing:
		return
	_wait -= delta
	if _wait <= 0.0:
		play_next()


func play_next() -> void:
	var i := _rng.randi_range(0, TRACKS.size() - 1)
	if i == _last:
		i = (i + 1) % TRACKS.size()
	_last = i
	if not _streams.has(i):
		match ResourceLoader.load_threaded_get_status(TRACKS[i]):
			ResourceLoader.THREAD_LOAD_LOADED:
				_streams[i] = ResourceLoader.load_threaded_get(TRACKS[i])
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				_wait = 2.0
				return
			_:
				_wait = GAP.y
				return
	var stream := _streams[i] as AudioStream
	if stream == null:
		_wait = GAP.y
		return
	_player.stream = stream
	_player.play()


## Something lovely is happening: play soon if nothing is playing.
func cue() -> void:
	if not _player.playing and _wait > 6.0:
		_wait = 4.0


func _bind_local() -> void:
	_local = get_tree().get_first_node_in_group("local_player")
	if _local and _local.has_signal("activity_changed"):
		_local.activity_changed.connect(func(activity: StringName, _data: Dictionary):
			if activity == &"light":
				cue())
