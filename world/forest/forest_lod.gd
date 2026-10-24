@tool
class_name ForestLod
extends Node3D
## Per-instance level of detail for everything ForestScatter plants.
##
## Godot picks a MultiMesh's LOD and visibility range for the whole batch at
## once, from the corner of its bounding box nearest the camera, so a 40 m
## block of trees beside the player drew every tree in it at full detail, and
## grass kept drawing (shrunk to nothing by its shader) 10 m and more past
## its fade. Here every batch is cut into small sub-cells and each sub-cell
## goes to the band whose level of detail suits its own distance:
##
##   band 0 .. full mesh, then progressively simplified copies, until the cut
##   distance (the material's fade end or the group's range), past which it
##   isn't drawn at all.
##
## Levels switch by Godot's own rule (the simplification error must stay
## under PX pixels on a 1920 px wide screen), just measured per sub-cell
## instead of per block. Shadow casters get their own, coarser bands: the
## shadow map is far blurrier than the screen.
##
## Re-banding runs on a worker thread whenever the camera has moved half a
## metre; the main thread only uploads the batches that changed.

const REF_WIDTH := 1920.0
## 2·tan(horizontal half-FOV) for the 60° orbit camera at 16:9.
const LOD_MULT := 2.05
## Allowed simplification error on screen, in pixels.
const PX := 2.0
## Bark hidden inside a crown can be simplified harder than what frames it.
const PX_BARK_IN_CROWN := 4.0
## Shadow casters are judged by the shadow map instead of the screen: the
## near split (out to ~17 m) resolves ~2 cm, the far split ~9 cm and blurs
## them further, so a caster may be off by this much (metres) in each.
## Distances here and below are for a copy at scale 1.
const SHADOW_SPLIT := 14.0
const SHADOW_ERROR := [0.025, 0.1]
## Level id for "trunk only" shadow bark, see _trunk().
const TRUNK_LEVEL := 1000
const MAX_BANDS := 5
## Leaf cards thin out instead of simplifying: a share of them is dropped and
## the rest grow to cover the same area, so a crown keeps its fullness (the
## trick tree middleware uses). Fraction kept at each level:
const THIN := [0.5, 0.25, 0.125]
## ...reached when a card is this many pixels across on screen,
const THIN_PX := [20.0, 10.0, 5.0]
## Shadow casters keep every card in the near split, where leaf dapples land
## round the Keling, then thin to a quarter and an eighth.
const THIN_SHADOW := [[SHADOW_SPLIT, 2], [30.0, 3]]
## Grass blades turn into single triangles from here (they're ~20 px tall by
## then and their curve is under a pixel)...
const BLADE_TRI := 9.0
## ...and from here a share of them goes, the rest widening to fill in.
const BLADE_THIN := 16.0
const BLADE_KEEP := 0.6
## A new level only earns a band if it switches this much further out.
const BAND_RATIO := 1.3
const MOVE_STEP := 0.5
## Casters past the sun's shadow distance (75 m) are dropped.
const SHADOW_CUT := 80.0

enum Shadow { NONE, SAME, PROXY, ONLY }
## Shadow casters get at most this many levels.
const MAX_SHADOW_BANDS := 3
## Trees far enough out become impostor cards (see ForestImpostors). Their
## cards don't go into per-batch bands but into shared MultiMeshes, one per
## IMP_CELL square of the valley, so the whole far forest is a few draws.
const IMP_CELL := 96.0
const IMP_FLOATS := 20

## One MultiMesh slice of a batch: the instances that currently fall in it.
class Band:
	var start := 0.0              # distance this band begins at
	var mmi: MultiMeshInstance3D  # null for the impostor band
	var count := 0


class Batch:
	var key := ""
	var mesh: Mesh
	var shadow := Shadow.NONE
	var px_scale := 1.0
	var count := 0
	var data := PackedFloat32Array()      # 16 floats per instance, grouped by sub-cell
	var sub_lo := PackedVector3Array()    # sub-cell bounds (instances' AABBs)
	var sub_hi := PackedVector3Array()
	var sub_start := PackedInt32Array()
	var sub_count := PackedInt32Array()
	var sub_scale := PackedFloat32Array()  # largest instance scale in the sub-cell
	var scale_lo := 1.0
	var scale_hi := 1.0
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	var cut := INF
	var bands: Array[Band] = []
	var state := PackedInt32Array()       # band per sub-cell, -1 when culled
	var shadow_cut := INF
	var shadow_bands: Array[Band] = []
	var shadow_state := PackedInt32Array()
	var imp_type := -1
	var imp_band := -1                    # index of the impostor band (always the last), or -1
	var imp_shadow_band := -1
	var imp_from := INF                   # true distances, not per unit scale: the atlas
	var imp_shadow_from := INF            # has a fixed number of pixels per metre
	var imp_data := PackedFloat32Array()  # IMP_FLOATS per instance, same order as data
	var imp_grow := 0.0                   # how far a card can swing past the mesh bounds
	var sub_imp_cell := PackedInt32Array()


## One square of impostors: the sub-cells whose centre falls in it.
class ImpCell:
	var members := PackedInt32Array()     # batch index, sub-cell, batch index, ...
	var capacity := 0
	var main: MultiMeshInstance3D
	var shadow: MultiMeshInstance3D


## Set before adding batches to let trees turn into impostors.
var impostors: ForestImpostors
var _imp_cells: Array[ImpCell] = []
var batches: Array[Batch] = []
var _task := -1
var _task_eye := Vector3.ZERO
var _results: Array = []
var _last_eye := Vector3(INF, INF, INF)
var _chains := {}
var _uploads := 0


# ----------------------------------------------------------------------------
# Building

## Adds one batch. `cut` is the distance past which nothing is drawn, `sub`
## the sub-cell size. Shadow.SAME lets the drawn bands cast, Shadow.PROXY
## gives the batch its own coarser shadow casters, Shadow.ONLY makes a batch
## of nothing but shadow casters. `px_scale` loosens the pixel budget (for
## silhouettes in the haze). `imp_type` is the batch's ForestImpostors type,
## or -1 to keep the real mesh at every distance. Call build() once every
## batch is in.
func add_batch(key: String, mesh: Mesh, data: PackedFloat32Array, cut: float, sub: float, shadow: Shadow, px_scale := 1.0,
		imp_type := -1) -> void:
	var b := Batch.new()
	b.key = key
	b.mesh = mesh
	b.count = data.size() / 16
	b.cut = cut
	b.shadow = shadow
	b.px_scale = px_scale
	b.shadow_cut = SHADOW_CUT
	_split(b, mesh, data, sub)
	if impostors != null and imp_type >= 0:
		b.imp_type = imp_type
		b.imp_from = ForestImpostors.FROM if ForestImpostors.FROM < cut else INF
		b.imp_shadow_from = ForestImpostors.shadow_from if ForestImpostors.shadow_from < SHADOW_CUT else INF
	b.state.resize(b.sub_start.size())
	b.state.fill(-1)
	b.shadow_state.resize(b.sub_start.size())
	b.shadow_state.fill(-1)
	batches.append(b)


## Works out every mesh's levels of detail, the slow part of growing the
## forest, on all cores at once (one job per mesh, building only the levels
## some copy of it can reach), then makes the bands and impostor squares.
func build() -> void:
	var jobs := {}
	for b in batches:
		if not jobs.has(b.mesh):
			# Reading a mesh back from the RenderingServer can wait on this
			# thread, so the workers get plain arrays.
			jobs[b.mesh] = {"mesh": b.mesh, "raw": _raw_surfaces(b.mesh), "chains": {}}
		var job: Dictionary = jobs[b.mesh]
		if b.shadow != Shadow.ONLY:
			_want(job, b.px_scale, false, minf(b.cut, b.imp_from) / b.scale_lo)
		if b.shadow == Shadow.PROXY or b.shadow == Shadow.ONLY:
			_want(job, b.px_scale, true, minf(SHADOW_CUT, b.imp_shadow_from) / b.scale_lo)
	var list := jobs.values()
	# Biggest first, so no core is left with a heavy mesh at the end.
	for job in list:
		job.size = 0
		for sf in job.raw:
			job.size += (sf.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	list.sort_custom(func(x, y): return x.size > y.size)
	var task := WorkerThreadPool.add_group_task(func(i: int) -> void: _run_job(list[i]), list.size(), -1, true, "ForestLod levels")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for job in list:
		_sources[job.mesh] = job.src
		for k in job.chains:
			_chains[k] = _finish_chain(job.src, job.chains[k].chain)
	for b in batches:
		_make_bands(b)
	finish_impostors()


static func _chain_key(mesh: Mesh, px_scale: float, shadow: bool) -> String:
	return "%d/%.2f/%s" % [mesh.get_instance_id(), px_scale, shadow]


static func _want(job: Dictionary, px_scale: float, shadow: bool, reach: float) -> void:
	var want: Dictionary = job.chains.get_or_add(_chain_key(job.mesh, px_scale, shadow), {"px": px_scale, "shadow": shadow, "reach": 0.0})
	want.reach = maxf(want.reach, reach)


## Runs on a worker: touches nothing but its own job, and no server.
func _run_job(job: Dictionary) -> void:
	job.src = _make_source(job.mesh, job.raw)
	for k in job.chains:
		var want: Dictionary = job.chains[k]
		want.chain = _make_chain(job.src, want.px, want.shadow, want.reach)


func _make_bands(b: Batch) -> void:
	var chain := lod_chain(b.mesh, b.px_scale, false) if b.shadow != Shadow.ONLY else []
	for level in chain:
		# The smallest copies reach a level first; levels none reaches before
		# the cut or the impostors are skipped.
		if level.from * b.scale_lo >= minf(b.cut, b.imp_from):
			break
		var band := _band(b, level, false)
		if b.shadow == Shadow.SAME:
			band.mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		b.bands.append(band)
	if not b.bands.is_empty() and b.imp_from < INF:
		b.imp_band = b.bands.size()
		b.bands.append(_imp_band(b.imp_from))
	else:
		b.imp_from = INF
	if b.shadow == Shadow.PROXY or b.shadow == Shadow.ONLY:
		for level in lod_chain(b.mesh, b.px_scale, true):
			if level.from * b.scale_lo >= minf(SHADOW_CUT, b.imp_shadow_from):
				break
			b.shadow_bands.append(_band(b, level, true))
	if not b.shadow_bands.is_empty() and b.imp_shadow_from < INF:
		b.imp_shadow_band = b.shadow_bands.size()
		b.shadow_bands.append(_imp_band(b.imp_shadow_from))
	else:
		b.imp_shadow_from = INF
	if b.imp_band >= 0 or b.imp_shadow_band >= 0:
		b.imp_data = _imp_data(b.data, b.imp_type)
		var box := b.mesh.get_aabb()
		b.imp_grow = maxf(box.size.x, box.size.z) * b.scale_hi
	else:
		b.imp_type = -1


func _band(b: Batch, level: Dictionary, shadow: bool) -> Band:
	var band := Band.new()
	band.start = level.from
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = level.mesh
	mm.instance_count = b.count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "%s~%s%d" % [b.key, "s" if shadow else "", b.shadow_bands.size() if shadow else b.bands.size()]
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	band.mmi = mmi
	add_child(mmi)
	return band


func _imp_band(from: float) -> Band:
	var band := Band.new()
	band.start = from
	return band


## Instance data for the impostor MultiMeshes: the transform, the type in the
## colour's red, then the tree's own custom data.
static func _imp_data(data: PackedFloat32Array, type: int) -> PackedFloat32Array:
	var n := data.size() / 16
	var out := PackedFloat32Array()
	out.resize(n * IMP_FLOATS)
	for i in n:
		var o := i * IMP_FLOATS
		var d := i * 16
		for f in 12:
			out[o + f] = data[d + f]
		out[o + 12] = type
		out[o + 15] = 1.0
		for f in 4:
			out[o + 16 + f] = data[d + 12 + f]
	return out


## Sorts the impostor sub-cells into squares and makes each square's
## MultiMeshes.
func finish_impostors() -> void:
	if impostors == null:
		return
	var index := {}
	for bi in batches.size():
		var b := batches[bi]
		if b.imp_type < 0:
			continue
		b.sub_imp_cell.resize(b.sub_start.size())
		for i in b.sub_start.size():
			var c := (b.sub_lo[i] + b.sub_hi[i]) * 0.5
			var k := Vector2i(floori(c.x / IMP_CELL), floori(c.z / IMP_CELL))
			if not index.has(k):
				index[k] = _imp_cells.size()
				_imp_cells.append(ImpCell.new())
			var cell := _imp_cells[index[k]]
			cell.members.append(bi)
			cell.members.append(i)
			cell.capacity += b.sub_count[i]
			b.sub_imp_cell[i] = index[k]
	for ci in _imp_cells.size():
		var cell := _imp_cells[ci]
		cell.main = _imp_mmi(cell.capacity, "Impostors~%d" % ci, false)
		cell.shadow = _imp_mmi(cell.capacity, "Impostors~s%d" % ci, true)


func _imp_mmi(capacity: int, node_name: String, shadow: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = impostors.quad
	mm.instance_count = capacity
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	return mmi


## Regroups a batch's instances by sub-cell so each sub-cell is one
## contiguous run of the buffer, and records each run's bounds.
func _split(b: Batch, mesh: Mesh, data: PackedFloat32Array, sub: float) -> void:
	var local := mesh.get_aabb()
	var cells := {}
	var n := data.size() / 16
	for i in n:
		var o := i * 16
		var k := Vector2i(floori(data[o + 3] / sub), floori(data[o + 11] / sub))
		if not cells.has(k):
			cells[k] = []
		cells[k].append(i)
	var keys := cells.keys()
	keys.sort()
	var out := PackedFloat32Array()
	out.resize(data.size())
	var w := 0
	var first := true
	for k in keys:
		var ids: Array = cells[k]
		var box := AABB()
		var top := 0.0
		b.sub_start.append(w / 16)
		b.sub_count.append(ids.size())
		for j in ids.size():
			var o: int = ids[j] * 16
			for f in 16:
				out[w + f] = data[o + f]
			w += 16
			var xf := Transform3D(Vector3(data[o], data[o + 4], data[o + 8]), Vector3(data[o + 1], data[o + 5], data[o + 9]),
					Vector3(data[o + 2], data[o + 6], data[o + 10]), Vector3(data[o + 3], data[o + 7], data[o + 11]))
			var ib := xf * local
			box = ib if j == 0 else box.merge(ib)
			top = maxf(top, maxf(xf.basis.x.length(), maxf(xf.basis.y.length(), xf.basis.z.length())))
		b.sub_lo.append(box.position)
		b.sub_hi.append(box.end)
		b.sub_scale.append(top)
		if first:
			b.lo = box.position
			b.hi = box.end
			b.scale_lo = top
			b.scale_hi = top
			first = false
		else:
			b.lo = b.lo.min(box.position)
			b.hi = b.hi.max(box.end)
			b.scale_lo = minf(b.scale_lo, top)
			b.scale_hi = maxf(b.scale_hi, top)
	b.data = out


# ----------------------------------------------------------------------------
# Levels of detail

## [{from: distance, mesh: Mesh}], nearest first, for a copy at scale 1
## (bigger copies switch proportionally further out). Each surface simplifies
## on its own schedule; a level changes whichever surfaces are ready to.
func lod_chain(mesh: Mesh, px_scale: float, shadow: bool) -> Array:
	var key := _chain_key(mesh, px_scale, shadow)
	if not _chains.has(key):
		var src := _lod_source(mesh)
		_chains[key] = _finish_chain(src, _make_chain(src, px_scale, shadow, INF))
	return _chains[key]


## The chain itself, with levels built only out to `reach` (per unit scale):
## [{from, levels}], the arrays of each level made but not yet its mesh.
static func _make_chain(src: Dictionary, px_scale: float, shadow: bool, reach: float) -> Array:
	var surfaces: Array = src.surfaces
	var crowned := false
	for sf in surfaces:
		crowned = crowned or sf.kind == "cards"
	# Switch distance of every level of every surface: [[distance, level], ...]
	var switches := []
	var edges: Array[float] = []
	for sf in surfaces:
		var list := []
		match sf.kind:
			"cards":
				if shadow:
					list = THIN_SHADOW.duplicate()
				else:
					for l in THIN.size():
						list.append([sf.card * REF_WIDTH / (LOD_MULT * THIN_PX[l] * px_scale), l + 1])
			"blades":
				if not shadow:
					list = [[BLADE_TRI, 1], [BLADE_THIN, 2]]
			_:
				var im: ImporterMesh = src.im
				if shadow and crowned and sf.bark:
					# Past the near split a crown's shadow already covers its
					# branches: only the trunk and low limbs still cast.
					list.append([SHADOW_SPLIT, TRUNK_LEVEL])
					for l in im.get_surface_lod_count(sf.index):
						if im.get_surface_lod_size(sf.index, l) <= SHADOW_ERROR[0]:
							list.push_front([0.0, l + 1])
				elif shadow:
					# The coarsest level within each split's tolerance.
					for split in 2:
						var pick := 0
						for l in im.get_surface_lod_count(sf.index):
							if im.get_surface_lod_size(sf.index, l) <= SHADOW_ERROR[split]:
								pick = l + 1
						if pick > 0:
							list.append([0.0 if split == 0 else SHADOW_SPLIT, pick])
				else:
					var px := PX_BARK_IN_CROWN if crowned and sf.bark else PX
					var k := REF_WIDTH / (LOD_MULT * px * px_scale)
					for l in im.get_surface_lod_count(sf.index):
						list.append([im.get_surface_lod_size(sf.index, l) * k, l + 1])
		for sw in list:
			edges.append(sw[0])
		switches.append(list)
	edges.sort()
	# Keep the levels that are worth a band of their own.
	var kept: Array[float] = [0.0]
	var most := MAX_SHADOW_BANDS if shadow else MAX_BANDS
	for e in edges:
		if e > kept[kept.size() - 1] * BAND_RATIO and e > 1.0 and kept.size() < most:
			kept.append(e)
	var chain := []
	var meshes := {}
	for start in kept:
		if start >= reach and not chain.is_empty():
			break
		var levels := PackedInt32Array()
		for s in surfaces.size():
			var lv := 0
			for sw in switches[s]:
				if sw[0] <= start:
					lv = sw[1]
			levels.append(lv)
		var mk := str(levels)
		if not meshes.has(mk):
			meshes[mk] = true
			if levels.count(0) != surfaces.size():
				_level_arrays(src, levels)
			chain.append({"from": start, "levels": levels})
	return chain


## Turns a chain's levels into meshes (on the main thread, or the thread
## that grows the forest).
static func _finish_chain(src: Dictionary, chain: Array) -> Array:
	for level in chain:
		var levels: PackedInt32Array = level.levels
		level.mesh = src.mesh if levels.count(0) == levels.size() else _level_mesh(src, levels)
	return chain


var _sources := {}


## How each surface of a mesh simplifies: leaf cards and grass blades thin
## out (see THIN), everything else gets meshoptimizer levels.
func _lod_source(mesh: Mesh) -> Dictionary:
	if not _sources.has(mesh):
		_sources[mesh] = _make_source(mesh, _raw_surfaces(mesh))
	return _sources[mesh]


static func _raw_surfaces(mesh: Mesh) -> Array:
	var raw := []
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var shader: Shader = (mat as ShaderMaterial).shader if mat is ShaderMaterial else null
		var tint: bool = shader == NatureKit.SH_PLANT and (mat as ShaderMaterial).get_shader_parameter("ground_tint")
		raw.append({"arrays": mesh.surface_get_arrays(s), "material": mat, "shader": shader, "ground_tint": tint})
	return raw


static func _make_source(mesh: Mesh, raw: Array) -> Dictionary:
	var im := ImporterMesh.new()
	var surfaces := []
	for s in raw.size():
		var arrays: Array = raw[s].arrays
		if arrays[Mesh.ARRAY_INDEX] == null or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			var idx := PackedInt32Array()
			idx.resize(count)
			for i in count:
				idx[i] = i
			arrays[Mesh.ARRAY_INDEX] = idx
		var mat: Material = raw[s].material
		var shader: Shader = raw[s].shader
		var sf := {"index": s, "arrays": arrays, "material": mat, "kind": "mesh", "bark": shader == NatureKit.SH_BARK, "levels": {}}
		if shader == NatureKit.SH_CANOPY or raw[s].ground_tint:
			var comps := _components(arrays)
			if comps.size() >= (24 if shader == NatureKit.SH_CANOPY else 6):
				sf.kind = "cards" if shader == NatureKit.SH_CANOPY else "blades"
				sf.comps = comps
				sf.card = _median_size(arrays, comps)
		surfaces.append(sf)
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	# The crown's extent, for telling the branches it hides from the trunk.
	var crown := AABB()
	for sf in surfaces:
		if sf.kind == "cards":
			for c in sf.comps:
				var cb := AABB(c.center, Vector3.ZERO).grow(c.size * 0.5)
				crown = cb if crown.size == Vector3.ZERO else crown.merge(cb)
	return {"im": im, "mesh": mesh, "surfaces": surfaces, "crown": crown}


## Each surface's arrays at the given level, unused vertices dropped so the
## simplified copy really is smaller. Cached per surface and level.
static func _level_arrays(src: Dictionary, levels: PackedInt32Array) -> void:
	var surfaces: Array = src.surfaces
	for s in surfaces.size():
		var sf: Dictionary = surfaces[s]
		var lv := levels[s]
		if not sf.levels.has(lv):
			var arrays: Array = sf.arrays
			if lv > 0:
				match sf.kind:
					"cards":
						arrays = _thin_cards(arrays, sf.comps, THIN[lv - 1])
					"blades":
						arrays = _blade_tris(arrays, sf.comps, 1.0 if lv == 1 else BLADE_KEEP)
					_:
						if lv == TRUNK_LEVEL:
							arrays = _trunk(arrays, src.crown)
						else:
							var im: ImporterMesh = src.im
							arrays = _compact(im.get_surface_arrays(s), im.get_surface_lod_indices(s, lv - 1))
			sf.levels[lv] = arrays


static func _level_mesh(src: Dictionary, levels: PackedInt32Array) -> ArrayMesh:
	_level_arrays(src, levels)
	var out := ArrayMesh.new()
	var surfaces: Array = src.surfaces
	for s in surfaces.size():
		var sf: Dictionary = surfaces[s]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sf.levels[levels[s]])
		out.surface_set_material(s, sf.material)
	out.resource_name = "%s@%s" % [(src.mesh as Mesh).resource_name, ",".join(Array(levels).map(str))]
	return out


## Bark with the branches inside the crown left out, then simplified to the
## far shadow split's tolerance.
static func _trunk(arrays: Array, crown: AABB) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var floor_y := crown.position.y + crown.size.y * 0.12
	var keep := PackedInt32Array()
	for c in _components(arrays):
		var lo := INF
		var inside := true
		for v in c.verts:
			lo = minf(lo, verts[v].y)
		var cc: Vector3 = c.center
		inside = lo > floor_y and crown.grow(0.2).has_point(cc)
		if inside:
			continue
		for t in c.tris:
			keep.append_array([idx[t], idx[t + 1], idx[t + 2]])
	if keep.is_empty():
		return arrays
	var trunk := _compact(arrays, keep)
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, trunk)
	im.generate_lods(25.0, 60.0, [])
	var pick := -1
	for l in im.get_surface_lod_count(0):
		if im.get_surface_lod_size(0, l) <= SHADOW_ERROR[1]:
			pick = l
	if pick < 0:
		return trunk
	return _compact(im.get_surface_arrays(0), im.get_surface_lod_indices(0, pick))


# ----------------------------------------------------------------------------
# Thinning leaf cards and grass blades

## Triangles grouped into connected pieces (one leaf card, one blade):
## [{tris: PackedInt32Array (first index of each triangle), verts: PackedInt32Array, center: Vector3, size: float}]
static func _components(arrays: Array) -> Array:
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for i in verts.size():
		parent[i] = i
	for t in range(0, idx.size(), 3):
		var a := _root(parent, idx[t])
		for c in range(1, 3):
			var r := _root(parent, idx[t + c])
			if r != a:
				parent[r] = a
	var by_root := {}
	var comps := []
	for t in range(0, idx.size(), 3):
		var r := _root(parent, idx[t])
		if not by_root.has(r):
			by_root[r] = comps.size()
			comps.append({"tris": [], "verts": {}})
		var c: Dictionary = comps[by_root[r]]
		c.tris.append(t)
		for k in 3:
			c.verts[idx[t + k]] = true
	for c in comps:
		var vs := PackedInt32Array(c.verts.keys())
		var box := AABB(verts[vs[0]], Vector3.ZERO)
		var sum := Vector3.ZERO
		for v in vs:
			box = box.expand(verts[v])
			sum += verts[v]
		c.verts = vs
		c.tris = PackedInt32Array(c.tris)
		c.center = sum / vs.size()
		c.size = box.size[box.size.max_axis_index()]
	return comps


static func _root(parent: PackedInt32Array, v: int) -> int:
	while parent[v] != v:
		parent[v] = parent[parent[v]]
		v = parent[v]
	return v


static func _median_size(arrays: Array, comps: Array) -> float:
	var sizes := PackedFloat32Array()
	for c in comps:
		sizes.append(c.size)
	sizes.sort()
	return sizes[sizes.size() / 2]


## Which pieces survive thinning to `keep`: a stable random pick that favours
## the outside of the crown, where the silhouette is.
static func _survivors(comps: Array, keep: float) -> PackedInt32Array:
	var mid := Vector3.ZERO
	for c in comps:
		mid += c.center
	mid /= comps.size()
	var reach := 0.001
	for c in comps:
		reach = maxf(reach, (c.center - mid).length())
	var rng := RandomNumberGenerator.new()
	rng.seed = comps.size() * 7919 + int(reach * 1000.0)
	var scored := []
	for i in comps.size():
		var outer: float = (comps[i].center - mid).length() / reach
		scored.append([rng.randf() * (0.55 + 0.45 * outer), i])
	scored.sort_custom(func(a, b): return a[0] > b[0])
	var out := PackedInt32Array()
	for k in maxi(1, roundi(comps.size() * keep)):
		out.append(scored[k][1])
	return out


## Keeps a share of the leaf cards and grows each survivor about its centre
## so the crown covers as much sky as before.
static func _thin_cards(arrays: Array, comps: Array, keep: float) -> Array:
	var grow := 1.0 / sqrt(keep)
	var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out_idx := PackedInt32Array()
	for ci in _survivors(comps, keep):
		var c: Dictionary = comps[ci]
		var center: Vector3 = c.center
		for v in c.verts:
			verts[v] = center + (verts[v] - center) * grow
		for t in c.tris:
			out_idx.append_array([idx[t], idx[t + 1], idx[t + 2]])
	var a := arrays.duplicate()
	a[Mesh.ARRAY_VERTEX] = verts
	return _compact(a, out_idx)


## Distant grass: every blade becomes one tapering triangle from its root to
## its tip; `keep` < 1 also drops some blades and widens the rest.
static func _blade_tris(arrays: Array, comps: Array, keep: float) -> Array:
	var widen := 1.0 / sqrt(keep)
	var verts: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	var out_idx := PackedInt32Array()
	for ci in _survivors(comps, keep):
		var c: Dictionary = comps[ci]
		var vs: PackedInt32Array = c.verts
		var order := Array(vs)
		order.sort_custom(func(a, b): return verts[a].y < verts[b].y)
		var b0: int = order[0]
		var b1: int = order[1]
		var tip: int = order[order.size() - 1]
		if widen != 1.0:
			var m := (verts[b0] + verts[b1]) * 0.5
			verts[b0] = m + (verts[b0] - m) * widen
			verts[b1] = m + (verts[b1] - m) * widen
		out_idx.append_array([b0, b1, tip])
	var a := arrays.duplicate()
	a[Mesh.ARRAY_VERTEX] = verts
	return _compact(a, out_idx)


static func _compact(arrays: Array, indices: PackedInt32Array) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var remap := PackedInt32Array()
	remap.resize(verts.size())
	remap.fill(-1)
	var order := PackedInt32Array()
	var idx := PackedInt32Array()
	idx.resize(indices.size())
	for i in indices.size():
		var v := indices[i]
		var r := remap[v]
		if r < 0:
			r = order.size()
			remap[v] = r
			order.append(v)
		idx[i] = r
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for a in Mesh.ARRAY_MAX:
		var arr = arrays[a]
		if arr == null or a == Mesh.ARRAY_INDEX:
			continue
		out[a] = _pick(arr, order, verts.size())
	out[Mesh.ARRAY_INDEX] = idx
	return out


static func _pick(arr, order: PackedInt32Array, vcount: int):
	if arr is PackedVector3Array:
		var src: PackedVector3Array = arr
		var o := PackedVector3Array()
		o.resize(order.size())
		for i in order.size():
			o[i] = src[order[i]]
		return o
	if arr is PackedVector2Array:
		var src: PackedVector2Array = arr
		var o := PackedVector2Array()
		o.resize(order.size())
		for i in order.size():
			o[i] = src[order[i]]
		return o
	if arr is PackedColorArray:
		var src: PackedColorArray = arr
		var o := PackedColorArray()
		o.resize(order.size())
		for i in order.size():
			o[i] = src[order[i]]
		return o
	if arr is PackedFloat32Array:
		var src: PackedFloat32Array = arr
		var stride := src.size() / vcount
		var o := PackedFloat32Array()
		o.resize(order.size() * stride)
		for i in order.size():
			for c in stride:
				o[i * stride + c] = src[order[i] * stride + c]
		return o
	if arr is PackedInt32Array:
		var src: PackedInt32Array = arr
		var stride := src.size() / vcount
		var o := PackedInt32Array()
		o.resize(order.size() * stride)
		for i in order.size():
			for c in stride:
				o[i * stride + c] = src[order[i] * stride + c]
		return o
	if arr is PackedByteArray:
		var src: PackedByteArray = arr
		var stride := src.size() / vcount
		var o := PackedByteArray()
		o.resize(order.size() * stride)
		for i in order.size():
			for c in stride:
				o[i * stride + c] = src[order[i] * stride + c]
		return o
	return arr


# ----------------------------------------------------------------------------
# Banding

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply(_results)
		_results = []
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	if eye.distance_squared_to(_last_eye) < MOVE_STEP * MOVE_STEP:
		return
	_last_eye = eye
	_task_eye = eye
	_task = WorkerThreadPool.add_task(_evaluate_task, false, "ForestLod")


## Re-bands everything for a camera at `eye` right now, on this thread.
func update_now(eye: Vector3) -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_results = []
	_last_eye = eye
	_apply(_evaluate(eye))


func _evaluate_task() -> void:
	_results = _evaluate(_task_eye)


## Works out the new band of every sub-cell and builds the buffers for each
## batch that changed. Touches no nodes, so it can run on a worker.
func _evaluate(eye: Vector3) -> Array:
	var changes := []
	# Impostor squares whose contents change, and the batches' new states.
	var dirty := {}
	var dirty_shadow := {}
	var next := {}
	var next_shadow := {}
	for bi in batches.size():
		var b := batches[bi]
		var main := _assign(b, eye, b.bands, b.cut, b.state, b.imp_band, b.imp_from)
		var shadow := _assign(b, eye, b.shadow_bands, b.shadow_cut, b.shadow_state, b.imp_shadow_band, b.imp_shadow_from) \
				if not b.shadow_bands.is_empty() else PackedInt32Array()
		if main.is_empty() and shadow.is_empty():
			continue
		var change := {"batch": b}
		if not main.is_empty():
			change["state"] = main
			change["bands"] = _buffers(b, main, b.bands.size(), b.imp_band)
			if b.imp_band >= 0:
				next[bi] = main
				_mark(b, b.state, main, b.imp_band, dirty)
		if not shadow.is_empty():
			change["shadow_state"] = shadow
			change["shadow_bands"] = _buffers(b, shadow, b.shadow_bands.size(), b.imp_shadow_band)
			if b.imp_shadow_band >= 0:
				next_shadow[bi] = shadow
				_mark(b, b.shadow_state, shadow, b.imp_shadow_band, dirty_shadow)
		changes.append(change)
	for ci in dirty:
		changes.append(_imp_buffer(ci, next, false))
	for ci in dirty_shadow:
		changes.append(_imp_buffer(ci, next_shadow, true))
	return changes


## Flags the impostor squares of sub-cells that join or leave the impostors.
static func _mark(b: Batch, old: PackedInt32Array, now: PackedInt32Array, band: int, dirty: Dictionary) -> void:
	for i in now.size():
		if (old[i] == band) != (now[i] == band):
			dirty[b.sub_imp_cell[i]] = true


## The cards of one impostor square, as an upload for _apply.
func _imp_buffer(ci: int, next: Dictionary, shadow: bool) -> Dictionary:
	var cell := _imp_cells[ci]
	var buf := PackedFloat32Array()
	var count := 0
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	for m in range(0, cell.members.size(), 2):
		var bi := cell.members[m]
		var i := cell.members[m + 1]
		var b := batches[bi]
		var state: PackedInt32Array = next[bi] if next.has(bi) else (b.shadow_state if shadow else b.state)
		if state[i] != (b.imp_shadow_band if shadow else b.imp_band):
			continue
		var s := b.sub_start[i]
		buf.append_array(b.imp_data.slice(s * IMP_FLOATS, (s + b.sub_count[i]) * IMP_FLOATS))
		# Cards turn to face the camera; shadow cards also step back from the sun.
		var g := b.imp_grow * (0.9 if shadow else 0.1)
		var grow := Vector3(g, 0.0, g)
		var blo := b.sub_lo[i] - grow
		var bhi := b.sub_hi[i] + grow
		lo = blo if count == 0 else lo.min(blo)
		hi = bhi if count == 0 else hi.max(bhi)
		count += b.sub_count[i]
	var out := {"imp": ci, "shadow": shadow, "count": count}
	if count > 0:
		buf.resize(cell.capacity * IMP_FLOATS)
		out["buffer"] = buf
		out["aabb"] = AABB(lo, hi - lo)
	return out


## New band per sub-cell, or an empty array if nothing changed. Sub-cells at
## `imp_from` or further go to band `imp` (if there is one).
func _assign(b: Batch, eye: Vector3, bands: Array[Band], cut: float, current: PackedInt32Array, imp: int, imp_from: float) -> PackedInt32Array:
	var nb := bands.size()
	if nb == 0:
		return PackedInt32Array()
	if imp >= 0:
		nb = imp
	# The whole batch in one band (or culled) is the common case: skip the
	# per-cell work when it was already like that.
	# Levels are chosen per unit scale: a copy twice the size switches twice
	# as far away.
	var near := _dist(eye, b.lo, b.hi)
	var far := eye.distance_to(_far_corner(eye, b.lo, b.hi))
	var whole := -2
	if near >= cut:
		whole = -1
	elif near >= imp_from:
		whole = imp
	else:
		var bn := _band_of(bands, nb, near / b.scale_hi)
		if far < cut and far < imp_from and _band_of(bands, nb, far / b.scale_lo) == bn:
			whole = bn
	var out := PackedInt32Array()
	out.resize(current.size())
	if whole != -2:
		out.fill(whole)
	else:
		for i in current.size():
			var d := _dist(eye, b.sub_lo[i], b.sub_hi[i])
			if d >= cut:
				out[i] = -1
			elif d >= imp_from:
				out[i] = imp
			else:
				out[i] = _band_of(bands, nb, d / b.sub_scale[i])
	if out == current:
		return PackedInt32Array()
	return out


func _buffers(b: Batch, state: PackedInt32Array, nb: int, skip: int) -> Array:
	var out := []
	for k in nb:
		if k == skip:
			out.append({"count": 0})
			continue
		var buf := PackedFloat32Array()
		var count := 0
		var lo := Vector3.ZERO
		var hi := Vector3.ZERO
		var all := true
		for i in state.size():
			if state[i] != k:
				all = false
				continue
			var s := b.sub_start[i]
			var c := b.sub_count[i]
			if count == 0:
				lo = b.sub_lo[i]
				hi = b.sub_hi[i]
			else:
				lo = lo.min(b.sub_lo[i])
				hi = hi.max(b.sub_hi[i])
			count += c
		if count == 0:
			out.append({"count": 0})
			continue
		if all:
			buf = b.data
		else:
			for i in state.size():
				if state[i] == k:
					buf.append_array(b.data.slice(b.sub_start[i] * 16, (b.sub_start[i] + b.sub_count[i]) * 16))
			buf.resize(b.count * 16)
		out.append({"count": count, "buffer": buf, "aabb": AABB(lo, hi - lo)})
	return out


func _apply(changes: Array) -> void:
	for ch in changes:
		if ch.has("imp"):
			var cell := _imp_cells[ch.imp]
			_show(cell.shadow if ch.shadow else cell.main, ch)
			continue
		var b: Batch = ch.batch
		if ch.has("state"):
			b.state = ch.state
			_upload(b.bands, ch.bands)
		if ch.has("shadow_state"):
			b.shadow_state = ch.shadow_state
			_upload(b.shadow_bands, ch.shadow_bands)


func _upload(bands: Array[Band], data: Array) -> void:
	for k in bands.size():
		var band := bands[k]
		var d: Dictionary = data[k]
		var count: int = d.count
		if count == 0 and band.count == 0:
			continue
		_show(band.mmi, d)
		band.count = count


func _show(mmi: MultiMeshInstance3D, d: Dictionary) -> void:
	var count: int = d.count
	if count == 0:
		mmi.visible = false
		mmi.multimesh.visible_instance_count = 0
		return
	var mm := mmi.multimesh
	mm.buffer = d.buffer
	mm.visible_instance_count = count
	mmi.custom_aabb = d.aabb
	mmi.visible = true
	_uploads += 1


static func _band_of(bands: Array[Band], nb: int, d: float) -> int:
	var k := 0
	for i in range(1, nb):
		if d >= bands[i].start:
			k = i
	return k


static func _dist(eye: Vector3, lo: Vector3, hi: Vector3) -> float:
	return eye.distance_to(eye.clamp(lo, hi))


static func _far_corner(eye: Vector3, lo: Vector3, hi: Vector3) -> Vector3:
	return Vector3(lo.x if eye.x > (lo.x + hi.x) * 0.5 else hi.x, lo.y if eye.y > (lo.y + hi.y) * 0.5 else hi.y,
			lo.z if eye.z > (lo.z + hi.z) * 0.5 else hi.z)
