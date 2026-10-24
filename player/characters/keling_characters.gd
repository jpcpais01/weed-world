class_name KelingCharacters
extends RefCounted
## The playable Kelings. Every one shares the original Keling's skeleton
## (tools/rig_character.py rebuilds the Meshy rigs onto it), so animations,
## grabs, sitting and the rolling ritual all run on any of them; what differs
## lives in each character's <id>_body.json (trunk profile, landmarks, spring
## chains) and in the entries below.

const IDS := ["keling", "blossom", "sunflower", "lavender", "toadstool"]
const DEFAULT := "keling"
const SAVE_PATH := "user://player.cfg"

## name: shown in the picker. tagline: one line under it.
## colors: the transformation swirl (main, accent, sparkle).
## petal: which flake the swirl sheds (leaf, petal, seed, bloom, spore).
const INFO := {
	"keling": {
		"name": "Sprout", "tagline": "The first Keling. Buttercups in a leafy crown.",
		"colors": [Color(0.42, 0.78, 0.3), Color(1.0, 0.85, 0.25), Color(0.95, 1.0, 0.7)], "petal": "leaf",
	},
	"blossom": {
		"name": "Blossom", "tagline": "A cherry tree in spring, petals everywhere.",
		"colors": [Color(1.0, 0.62, 0.78), Color(0.55, 0.85, 0.4), Color(1.0, 0.92, 0.96)], "petal": "petal",
	},
	"sunflower": {
		"name": "Sunflower", "tagline": "Ripe wheat, a proud moustache, sunshine on top.",
		"colors": [Color(1.0, 0.8, 0.15), Color(0.85, 0.65, 0.3), Color(1.0, 0.97, 0.7)], "petal": "seed",
	},
	"lavender": {
		"name": "Lavender", "tagline": "Silver sage and purple spikes. Smells amazing.",
		"colors": [Color(0.68, 0.5, 0.95), Color(0.66, 0.8, 0.72), Color(0.95, 0.88, 1.0)], "petal": "bloom",
	},
	"toadstool": {
		"name": "Toadstool", "tagline": "Mossy, sturdy, and sprouting little mushrooms.",
		"colors": [Color(0.9, 0.25, 0.2), Color(0.45, 0.62, 0.25), Color(1.0, 0.93, 0.8)], "petal": "spore",
	},
}

static var _bodies := {}


static func valid(id: String) -> bool:
	return INFO.has(id)


static func get_info(id: String) -> Dictionary:
	if not INFO.has(id):
		id = DEFAULT
	var info: Dictionary = INFO[id].duplicate()
	info["id"] = id
	info["scene"] = "res://assets/characters/%s/%s.glb" % [id, id]
	info["animations"] = "res://assets/characters/%s/%s_animations.res" % [id, id]
	info["body"] = "res://assets/characters/%s/%s_body.json" % [id, id]
	return info


static func display_name(id: String) -> String:
	return String(INFO.get(id, INFO[DEFAULT]).name)


## Body measurements and landmarks of a character (cached).
static func body(id: String) -> KelingBody:
	if not INFO.has(id):
		id = DEFAULT
	if not _bodies.has(id):
		_bodies[id] = KelingBody.load_id(id)
	return _bodies[id]


## The model and animation library of a character. Not kept around: only
## the Kelings in the forest right now hold on to theirs.
static func scene(id: String) -> PackedScene:
	return load(get_info(id).scene)


static func animations(id: String) -> AnimationLibrary:
	return load(get_info(id).animations)


static func next_id(id: String, step := 1) -> String:
	var i := IDS.find(id)
	return IDS[posmod(i + step, IDS.size())] if i >= 0 else DEFAULT


## The character this player last picked (the original Keling at first).
static func saved_id() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return DEFAULT
	var id := String(cfg.get_value("player", "character", DEFAULT))
	return id if valid(id) else DEFAULT


static func save_id(id: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("player", "character", id)
	cfg.save(SAVE_PATH)
