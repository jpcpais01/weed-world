class_name MapState
extends RefCounted
## What the minimap and the world map share: the painted texture, the named
## places, the waypoint, and a snapshot of every Keling in the session.

signal texture_ready
signal waypoint_changed

const EXTENT := MapBaker.EXTENT

var texture: Texture2D
var places: Array[Dictionary] = []
var has_waypoint := false
var waypoint := Vector2.ZERO
var waypoint_name := ""


func set_texture(tex: Texture2D) -> void:
	texture = tex
	texture_ready.emit()


func set_waypoint(p: Vector2, label := "") -> void:
	has_waypoint = true
	waypoint = p
	waypoint_name = label
	waypoint_changed.emit()


func clear_waypoint() -> void:
	has_waypoint = false
	waypoint_name = ""
	waypoint_changed.emit()


## Every Keling in the "player" group: pos (XZ), heading (0 = north,
## clockwise), colour, name and whether it is this device's player. Ready for
## co-op: a player node may expose is_local, player_index and player_name.
static func players(tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var nodes := tree.get_nodes_in_group("player")
	var has_local_flag := false
	for n in nodes:
		if n.get("is_local") != null:
			has_local_flag = true
	for i in nodes.size():
		var n := nodes[i] as Node3D
		if n == null:
			continue
		var p := n.global_position
		var f = n.get("facing")
		var facing: float = f if f != null else n.global_rotation.y
		var idx = n.get("player_index")
		var index: int = idx if idx != null else i
		var nm = n.get("player_name")
		if nm is String and (nm == "" or n.get("is_local") == true):
			nm = null
		var local: bool = n.get("is_local") if has_local_flag else i == 0
		out.append({
			"node": n, "pos": Vector2(p.x, p.z), "heading": atan2(sin(facing), -cos(facing)),
			"color": HudTheme.PLAYER_COLORS[index % 4], "name": nm if nm != null else ("You" if local else "Keling %d" % (index + 1)),
			"local": local,
		})
	return out


static func local_player(tree: SceneTree) -> Dictionary:
	for p in players(tree):
		if p.local:
			return p
	return {}
