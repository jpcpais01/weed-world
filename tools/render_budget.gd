extends SceneTree
## Render budget for the Whispering Glade, measured as logic instead of FPS:
## grows the forest headless, then replays Godot's own culling, visibility
## range, mesh LOD and shadow-cascade rules from a set of player camera
## views and reports the triangles and draw calls each view costs.
##   godot --headless --path . -s res://tools/render_budget.gd [-- --groups] [-- --max-tris=N] [-- --mobile]
## --mobile measures the phone settings (cheaper distant tree shadows).
##
## The model follows the Mobile renderer: a MultiMeshInstance3D is culled and
## LOD-ed as one block (its whole AABB), visibility ranges are measured to the
## AABB centre, the LOD is the coarsest one whose edge error stays under
## rendering/mesh_lod/lod_change/threshold_pixels, and each of the sun's
## shadow splits redraws every caster it overlaps. Exits non-zero if any view
## goes over --max-tris (main + shadow passes).

const VIEW_W := 1600.0
const VIEW_H := 900.0
const FOV := 60.0
const FAR := 500.0
# Orbit camera: focus 0.95 m over the Keling, 3.4 m back, pitched down 16°.
const CAM_HEIGHT := 0.95
const CAM_DIST := 3.4
const CAM_PITCH := -16.0

var _forest: Forest
var _views: Array[Dictionary] = []
var _lod_px := 1.0


func _initialize() -> void:
	if "--mobile" in OS.get_cmdline_user_args():
		ForestImpostors.shadow_from = ForestImpostors.SHADOW_FROM_MOBILE
	_forest = load("res://world/forest/forest.tscn").instantiate() as Forest
	_forest.preview_camera_when_alone = false
	root.add_child(_forest)
	_lod_px = float(ProjectSettings.get_setting("rendering/mesh_lod/lod_change/threshold_pixels", 1.0))
	_report.call_deferred()


func _make_views() -> void:
	var L := ForestLayout
	# Player positions and the way they face: the spawn towards the Elder, and
	# the spots people actually stand (glade, pond, grove, hollow, overlook).
	var spots := [
		["spawn", L.SPAWN, L.ELDER],
		["glade", L.GLADE, L.POND],
		["elder", L.ELDER + Vector2(0, 8), L.SPAWN],
		["pond", L.POND + Vector2(-8, 6), L.POND],
		["grove", L.GROVE + Vector2(4, 6), L.GROVE],
		["hollow", L.HOLLOW + Vector2(4, 4), L.HOLLOW],
		["overlook", L.OVERLOOK, L.OVERLOOK + L.vista_dir() * 20.0],
		["rim", Vector2(0, 44), Vector2(0, 0)],
	]
	for s in spots:
		var p: Vector2 = s[1]
		var look: Vector2 = (s[2] as Vector2) - p
		if look.length() < 0.1:
			look = Vector2(0, -1)
		var yaw := atan2(-look.x, -look.y)
		var focus := Vector3(p.x, _forest.ground_height(p.x, p.y) + CAM_HEIGHT, p.y)
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(CAM_PITCH))
		var eye := focus + basis.z * CAM_DIST
		_views.append({"name": s[0], "xf": Transform3D(basis, eye), "focus": focus})


func _report() -> void:
	_make_views()
	var items := _gather(_forest)
	var by_groups := "--groups" in OS.get_cmdline_user_args()
	var max_tris := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--max-tris="):
			max_tris = int(a.get_slice("=", 1))

	var total_inst := 0
	var total_tris := 0
	for it in items:
		# Banded batches hold every instance in each band; count them once.
		var nm := String(it.node.name)
		if "~" in nm and not nm.ends_with("~0"):
			continue
		total_inst += it.count
		total_tris += it.tris0 * it.count
	print("render_budget: %d geometry nodes, %d instances, %s triangles if everything drew at full detail" % [items.size(), total_inst, _n(total_tris)])
	print("render_budget: mesh LOD threshold %.1f px at %dx%d" % [_lod_px, VIEW_W, VIEW_H])

	var worst := 0
	var sums := {}
	for v in _views:
		# Let the forest's level-of-detail streaming settle for this camera.
		if _forest.scatter.lod:
			_forest.scatter.lod.update_now(v.focus, CAM_DIST * ForestLod.ARM_SHARE)
		var r := _measure(items, v.xf)
		worst = maxi(worst, r.tris + r.shadow_tris)
		print("render_budget: view %-9s main %8s tris %4d draws | shadow %8s tris %4d draws | total %8s" % [v.name, _n(r.tris), r.draws, _n(r.shadow_tris), r.shadow_draws, _n(r.tris + r.shadow_tris)])
		for g in r.groups:
			var s: Array = sums.get(g, [0, 0, 0, 0])
			var gr: Array = r.groups[g]
			for k in 4:
				s[k] += gr[k]
			sums[g] = s
	if by_groups:
		print("render_budget: average per view, by group (main tris, main draws, shadow tris, shadow draws)")
		var keys := sums.keys()
		keys.sort_custom(func(a, b): return sums[a][0] + sums[a][2] > sums[b][0] + sums[b][2])
		for g in keys:
			var s: Array = sums[g]
			var n := float(_views.size())
			print("  %-16s %9s %5d | %9s %5d" % [g, _n(int(s[0] / n)), int(s[1] / n), _n(int(s[2] / n)), int(s[3] / n)])
	print("render_budget: worst view %s triangles (main + shadow)" % _n(worst))
	var ok := max_tris <= 0 or worst <= max_tris
	if max_tris > 0:
		print("render_budget: budget %s -> %s" % [_n(max_tris), "PASS" if ok else "FAIL"])
	else:
		print("render_budget: PASS")
	quit(0 if ok else 1)


# ----------------------------------------------------------------------------
# Scene walk

func _gather(n: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_walk(n, out)
	return out


func _walk(n: Node, out: Array[Dictionary]) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		var mesh: Mesh
		var count := 1
		var aabb: AABB
		if g is MultiMeshInstance3D:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm and mm.mesh:
				mesh = mm.mesh
				count = mm.instance_count
				# The headless renderer doesn't track MultiMesh bounds; the forest
				# sets them explicitly.
				aabb = g.global_transform * (g.custom_aabb if g.custom_aabb.has_volume() else mm.mesh.get_aabb())
		elif g is MeshInstance3D and (g as MeshInstance3D).mesh:
			mesh = (g as MeshInstance3D).mesh
			aabb = g.global_transform * mesh.get_aabb()
		if mesh and count > 0:
			var surf := _surfaces(mesh)
			var tris0 := 0
			for s in surf:
				tris0 += s.lods[0][1]
			out.append({
				"node": g, "group": _group_of(g), "count": count, "aabb": aabb, "surfaces": surf, "tris0": tris0,
				"shadow": g.cast_shadow, "vis_begin": g.visibility_range_begin, "vis_end": g.visibility_range_end,
				"scale": g.global_transform.basis.get_scale().length() / sqrt(3.0), "lod_bias": g.lod_bias,
			})
	for c in n.get_children():
		_walk(c, out)


var _surface_cache := {}


## Per surface: [[edge_length, triangles], ...] from full detail down.
func _surfaces(mesh: Mesh) -> Array:
	if _surface_cache.has(mesh):
		return _surface_cache[mesh]
	var out := []
	for s in mesh.get_surface_count():
		var d := RenderingServer.mesh_get_surface(mesh.get_rid(), s)
		var wide: bool = int(d.get("vertex_count", 0)) > 65535
		var count := int(d.get("index_count", 0))
		if count == 0:
			count = int(d.get("vertex_count", 0))
		var lods := [[0.0, count / 3]]
		for l in d.get("lods", []):
			lods.append([float(l.edge_length), (l.index_data as PackedByteArray).size() / (4 if wide else 2) / 3])
		out.append({"lods": lods})
	_surface_cache[mesh] = out
	return out


func _group_of(g: Node) -> String:
	var p := g.get_parent()
	if p and p.name == "Vegetation":
		var parts := String(g.name).get_slice("~", 0).split("_")
		var group := parts[0]
		if parts.size() < 3:
			return group
		# The mesh is the middle of group_mesh_cx_cy.
		var mesh := "_".join(parts.slice(1, parts.size() - 2))
		if group in ["tree", "rock", "far"]:
			return group + ":" + mesh.get_slice("_", 0).get_slice("#", 0)
		return group
	if p and p.name == "Terrain":
		return "terrain"
	var top := g as Node
	while top.get_parent() and top.get_parent() != _forest and top.get_parent().name != "Generated":
		top = top.get_parent()
	return String(top.name)


# ----------------------------------------------------------------------------
# Godot's rules, replayed

func _measure(items: Array[Dictionary], cam: Transform3D) -> Dictionary:
	var planes := _frustum(cam)
	var lod_mult := 2.0 * tan(deg_to_rad(FOV) * 0.5) * VIEW_W / VIEW_H
	var px_threshold := _lod_px / VIEW_W
	# Two shadow splits: 0..22% and 22..100% of 75 m.
	var sun := _forest.atmosphere.sun
	var shadow_far := sun.directional_shadow_max_distance
	var splits := [[0.0, shadow_far * sun.directional_shadow_split_1], [shadow_far * sun.directional_shadow_split_1, shadow_far]]
	if sun.directional_shadow_mode == DirectionalLight3D.SHADOW_ORTHOGONAL:
		splits = [[0.0, shadow_far]]
	elif sun.directional_shadow_mode == DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS:
		var s := [0.0, sun.directional_shadow_split_1, sun.directional_shadow_split_2, sun.directional_shadow_split_3, 1.0]
		splits = []
		for i in 4:
			splits.append([shadow_far * s[i], shadow_far * s[i + 1]])
	var light_dir := sun.global_transform.basis.z.normalized()
	var res := {"tris": 0, "draws": 0, "shadow_tris": 0, "shadow_draws": 0, "groups": {}}
	var eye := cam.origin
	var fwd := -cam.basis.z
	for it in items:
		var node: GeometryInstance3D = it.node
		if not node.is_visible_in_tree():
			continue
		var aabb: AABB = node.global_transform * node.custom_aabb if node.custom_aabb.has_volume() else it.aabb
		var count: int = it.count
		if node is MultiMeshInstance3D:
			var mm := (node as MultiMeshInstance3D).multimesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		var dist := eye.distance_to(aabb.get_center())
		var vb: float = it.vis_begin
		var ve: float = it.vis_end
		if (vb > 0.0 and dist < vb) or (ve > 0.0 and dist > ve):
			continue
		var tris_per := _lod_tris(it, aabb, cam, lod_mult, px_threshold)
		var g: String = it.group
		var gr: Array = res.groups.get(g, [0, 0, 0, 0])
		res.groups[g] = gr
		var surfaces: int = it.surfaces.size()
		var shadow_mode: int = it.shadow
		if shadow_mode != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY and _in_frustum(aabb, planes):
			res.tris += tris_per * count
			res.draws += surfaces
			gr[0] += tris_per * count
			gr[1] += surfaces
		if shadow_mode != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			for sp in splits:
				if _in_split(aabb, cam, planes, sp, light_dir):
					res.shadow_tris += tris_per * count
					res.shadow_draws += surfaces
					gr[2] += tris_per * count
					gr[3] += surfaces
	return res


func _lod_tris(it: Dictionary, aabb: AABB, cam: Transform3D, lod_mult: float, px_threshold: float) -> int:
	var distance := 0.0
	if not aabb.has_point(cam.origin):
		distance = cam.origin.distance_to(aabb.get_support(cam.basis.z))
	distance = maxf(distance, 0.05) * lod_mult
	var scale: float = it.scale * it.lod_bias
	var tris := 0
	for s in it.surfaces:
		var lods: Array = s.lods
		var pick := 0
		for i in range(1, lods.size()):
			if lods[i][0] * scale / distance > px_threshold:
				break
			pick = i
		tris += lods[pick][1]
	return tris


## Outward-facing frustum planes in world space.
func _frustum(cam: Transform3D) -> Array[Plane]:
	var th := tan(deg_to_rad(FOV) * 0.5)
	var tw := th * VIEW_W / VIEW_H
	var r := cam.basis.x.normalized()
	var u := cam.basis.y.normalized()
	var f := -cam.basis.z.normalized()
	var e := cam.origin
	return [
		Plane(-f, e + f * 0.05), Plane(f, e + f * FAR),
		Plane(-(r + f * tw).normalized(), e), Plane((r - f * tw).normalized(), e),
		Plane((u - f * th).normalized(), e), Plane((-u - f * th).normalized(), e),
	]


func _in_frustum(aabb: AABB, planes: Array[Plane]) -> bool:
	for p in planes:
		# The AABB corner furthest along the plane's inside (-normal) direction.
		var c := aabb.get_support(-p.normal)
		if p.is_point_over(c):
			return false
	return true


## Does a caster land in this shadow split? The split covers the camera
## frustum between two depths; anything between the sun and that slice casts
## into it, so the slice is stretched towards the light.
func _in_split(aabb: AABB, cam: Transform3D, planes: Array[Plane], split: Array, light_dir: Vector3) -> bool:
	var near: float = split[0]
	var far: float = split[1]
	var fwd := -cam.basis.z
	# Bounding sphere of the frustum slice.
	var half_h := tan(deg_to_rad(FOV) * 0.5)
	var half_w := half_h * VIEW_W / VIEW_H
	var mid := (near + far) * 0.5
	var center := cam.origin + fwd * mid
	var radius := Vector3(half_w * far, half_h * far, far - mid).length()
	# Sweep the caster box away from the sun by 40 m (tall trees, hills).
	var swept := aabb.merge(AABB(aabb.position - light_dir * 40.0, aabb.size))
	var closest := center.clamp(swept.position, swept.end)
	return closest.distance_to(center) <= radius


func _n(v: int) -> String:
	if v >= 1000000:
		return "%.2fM" % (v / 1000000.0)
	if v >= 1000:
		return "%.1fk" % (v / 1000.0)
	return str(v)
