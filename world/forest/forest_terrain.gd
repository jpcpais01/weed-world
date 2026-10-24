class_name ForestTerrain
extends RefCounted
## Sculpts the forest floor from ForestLayout: a 0.5 m heightfield with the
## pond, creek, stream and footpaths carved in, plus per-vertex masks that the
## terrain shader turns into grass, worn dirt, wet banks, moss and rock.

const EXTENT := 60.0          # detailed grid covers [-EXTENT, EXTENT]
const STEP := 0.5
const N := 241                # int(2 * EXTENT / STEP) + 1
const CHUNKS := 4             # detailed mesh is split so lights and culling stay local
const OUTER_EXTENT := 140.0
const OUTER_STEP := 2.5

const CREEK_DEPTH := 0.28
const STREAM_DEPTH := 0.34

var layout: ForestLayout
var heights := PackedFloat32Array()
var path_dist := PackedFloat32Array()
var water_dist := PackedFloat32Array()
var shade := PackedFloat32Array()      # canopy occlusion, painted by the scatter pass
var water_level := PackedFloat32Array() # surface height of the water over each cell, or -INF
var normals := PackedVector3Array()

var pond_level := 0.0
var creek_points := PackedVector2Array()
var creek_surface := PackedFloat32Array()
var stream_points := PackedVector2Array()
var stream_surface := PackedFloat32Array()
var falls: Array[Dictionary] = []      # {index, lip: Vector3, dir: Vector2, drop: float}
var path_points: Array[PackedVector2Array] = []
var bench_sites: Array[Dictionary] = []  # see BenchSites.plan()


func _init(p_layout: ForestLayout) -> void:
	layout = p_layout


func build() -> void:
	var count := N * N
	heights.resize(count)
	path_dist.resize(count)
	water_dist.resize(count)
	shade.resize(count)
	water_level.resize(count)
	water_level.fill(-1.0e6)
	path_dist.fill(1.0e6)
	water_dist.fill(1.0e6)
	shade.fill(0.0)

	for gz in N:
		for gx in N:
			heights[gz * N + gx] = layout.landform(_gx(gx), _gx(gz))

	_flatten_landmarks()
	_carve_pond()
	_carve_creek()
	_carve_stream()
	bench_sites = BenchSites.plan(self)
	_trace_paths()
	_compute_normals()


# ----------------------------------------------------------------------------
# Queries

static func _gx(i: int) -> float:
	return -EXTENT + i * STEP


func height_at(x: float, z: float) -> float:
	var fx := (x + EXTENT) / STEP
	var fz := (z + EXTENT) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= N - 1 or fz >= N - 1:
		return layout.landform(x, z)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	# Match the mesh triangulation (diagonal from (0,0) to (1,1)).
	var h00 := heights[i]
	var h11 := heights[i + N + 1]
	if tx >= tz:
		var h10 := heights[i + 1]
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	var h01 := heights[i + N]
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func _field(arr: PackedFloat32Array, x: float, z: float, fallback: float) -> float:
	var fx := (x + EXTENT) / STEP
	var fz := (z + EXTENT) / STEP
	if fx < 0.0 or fz < 0.0 or fx >= N - 1 or fz >= N - 1:
		return fallback
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var a := lerpf(arr[i], arr[i + 1], tx)
	var b := lerpf(arr[i + N], arr[i + N + 1], tx)
	return lerpf(a, b, tz)


func path_distance(x: float, z: float) -> float:
	return _field(path_dist, x, z, 1.0e6)


func water_distance(x: float, z: float) -> float:
	return _field(water_dist, x, z, 1.0e6)


func shade_at(x: float, z: float) -> float:
	return _field(shade, x, z, 0.0)


## Nearest grid normal: cheap enough to call tens of thousands of times.
func grid_normal(x: float, z: float) -> Vector3:
	var ix := clampi(int(round((x + EXTENT) / STEP)), 0, N - 1)
	var iz := clampi(int(round((z + EXTENT) / STEP)), 0, N - 1)
	return normals[iz * N + ix]


func normal_at(x: float, z: float) -> Vector3:
	if absf(x) < EXTENT - 1.0 and absf(z) < EXTENT - 1.0:
		return grid_normal(x, z)
	var e := 0.35
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()


func slope_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))


## Is the ground here below the surface of the pond, the creek or the stream?
func is_under_water(x: float, z: float) -> bool:
	var ix := clampi(int(round((x + EXTENT) / STEP)), 0, N - 1)
	var iz := clampi(int(round((z + EXTENT) / STEP)), 0, N - 1)
	var i := iz * N + ix
	return water_level[i] > heights[i] - 0.03


## How deep the water stands over the ground here (negative or zero when dry).
func water_depth_at(x: float, z: float) -> float:
	if absf(x) >= EXTENT or absf(z) >= EXTENT:
		return -1.0
	var gx := int(floor((x + EXTENT) / STEP))
	var gz := int(floor((z + EXTENT) / STEP))
	var surface := -1.0e6
	for dz in 2:
		for dx in 2:
			var i := clampi(gz + dz, 0, N - 1) * N + clampi(gx + dx, 0, N - 1)
			surface = maxf(surface, water_level[i])
	if surface < -1.0e5:
		return -1.0
	return surface - height_at(x, z)


func is_in_pond(x: float, z: float, margin: float = 0.0) -> bool:
	var v := Vector2(x, z) - ForestLayout.POND
	return v.length() < layout.pond_radius(v.angle()) + margin


## Paints soft canopy occlusion around a tree so the floor darkens beneath it.
func paint_shade(center: Vector2, radius: float, strength: float) -> void:
	var r := radius * 1.25
	var i0 := maxi(0, int((center.x - r + EXTENT) / STEP))
	var i1 := mini(N - 1, int((center.x + r + EXTENT) / STEP) + 1)
	var j0 := maxi(0, int((center.y - r + EXTENT) / STEP))
	var j1 := mini(N - 1, int((center.y + r + EXTENT) / STEP) + 1)
	for gz in range(j0, j1 + 1):
		for gx in range(i0, i1 + 1):
			var d := Vector2(_gx(gx), _gx(gz)).distance_to(center) / r
			if d >= 1.0:
				continue
			var s := (1.0 - d * d) * strength
			var idx := gz * N + gx
			shade[idx] = 1.0 - (1.0 - shade[idx]) * (1.0 - s)


# ----------------------------------------------------------------------------
# Sculpting

func _flatten_landmarks() -> void:
	var glade_h := layout.landform(ForestLayout.GLADE.x, ForestLayout.GLADE.y)
	for gz in N:
		for gx in N:
			var p := Vector2(_gx(gx), _gx(gz))
			var i := gz * N + gx
			var h := heights[i]
			var dg := p.distance_to(ForestLayout.GLADE)
			var g := 1.0 - ForestLayout.sstep(ForestLayout.GLADE_RADIUS * 0.45, ForestLayout.GLADE_RADIUS * 1.6, dg)
			# Keep a little of the natural roll so the meadow is not a table top.
			h = lerpf(h, glade_h + (h - glade_h) * 0.25, g)
			var do := p.distance_to(ForestLayout.OVERLOOK)
			var o := 1.0 - ForestLayout.sstep(ForestLayout.OVERLOOK_RADIUS, ForestLayout.OVERLOOK_RADIUS + 11.0, do)
			h = lerpf(h, ForestLayout.OVERLOOK_HEIGHT + (h - ForestLayout.OVERLOOK_HEIGHT) * 0.08, o)
			heights[i] = h


func _carve_pond() -> void:
	var c := ForestLayout.POND
	var ring := 0.0
	for k in 24:
		var a := TAU * k / 24.0
		var r := layout.pond_radius(a) + 2.5
		ring += height_at(c.x + cos(a) * r, c.y + sin(a) * r)
	pond_level = ring / 24.0 - 0.45
	var reach := ForestLayout.POND_RADIUS + 6.0
	for gz in N:
		for gx in N:
			var p := Vector2(_gx(gx), _gx(gz))
			var v := p - c
			var d := v.length()
			if d > reach:
				continue
			var i := gz * N + gx
			var r := layout.pond_radius(v.angle())
			var h := heights[i]
			if d < r:
				var k := 1.0 - (d / r) * (d / r)
				h = pond_level - 0.12 - 1.35 * pow(k, 0.8)
			else:
				var s := ForestLayout.sstep(r, r + 3.5, d)
				h = lerpf(pond_level - 0.1, maxf(h, pond_level + 0.28), s)
			heights[i] = h
			water_dist[i] = minf(water_dist[i], d - r)
			if d < r + 2.5:
				water_level[i] = pond_level


func _carve_creek() -> void:
	creek_points = ForestLayout.resample(ForestLayout.CREEK, 0.5)
	var bed := _monotonic_bed(creek_points, 0.5, 0.02)
	var n := bed.size()
	# The creek must meet the pond surface where it spills in.
	for k in n:
		var to_pond := creek_points[k].distance_to(ForestLayout.POND) - ForestLayout.POND_RADIUS
		if to_pond < 4.0:
			bed[k] = minf(bed[k], lerpf(pond_level - CREEK_DEPTH - 0.05, bed[k], clampf(to_pond / 4.0, 0.0, 1.0)))
	# Terrace the bed into a staircase of pools so the creek tumbles down the
	# ridge in little waterfalls instead of sliding down a ramp. Walk upstream
	# from the pond holding each pool level until the natural bed has climbed a
	# full step above it.
	var level := bed[n - 1]
	var last := n - 1
	var step := 0.75
	var stepped := PackedFloat32Array()
	stepped.resize(n)
	for k in range(n - 1, -1, -1):
		var to_pond := creek_points[k].distance_to(ForestLayout.POND) - ForestLayout.POND_RADIUS
		var pool := 2.0 + 2.6 * fposmod(sin(float(last) * 12.9898) * 43758.5453, 1.0)
		if bed[k] >= level + step and (last - k) * 0.5 >= pool and to_pond > 1.0:
			level = bed[k]
			last = k
		stepped[k] = minf(level, bed[k])
	creek_surface.resize(n)
	for k in n:
		creek_surface[k] = stepped[k] + CREEK_DEPTH
	# Each drop gets a plunge pool scoured out below it.
	falls.clear()
	var dug := stepped.duplicate()
	for k in n - 1:
		var drop := creek_surface[k] - creek_surface[k + 1]
		if drop < 0.2:
			continue
		var dir := (creek_points[k + 1] - creek_points[k]).normalized()
		falls.append({"index": k, "lip": Vector3(creek_points[k].x, creek_surface[k], creek_points[k].y), "dir": dir, "drop": drop})
		for j in range(k + 1, mini(k + 6, n)):
			var f := float(j - k - 1) / 5.0
			dug[j] -= (0.18 + minf(drop, 2.0) * 0.12) * (1.0 - f * f)
	_carve_channel(creek_points, dug, creek_surface, 0.55, 2.3)


func _carve_stream() -> void:
	stream_points = ForestLayout.resample(ForestLayout.STREAM, 0.5)
	var n := stream_points.size()
	var raw := PackedFloat32Array()
	raw.resize(n)
	for k in n:
		raw[k] = height_at(stream_points[k].x, stream_points[k].y)
	var bed := PackedFloat32Array()
	bed.resize(n)
	bed[0] = pond_level - STREAM_DEPTH - 0.02
	for k in range(1, n):
		bed[k] = minf(bed[k - 1] - 0.006, raw[k] - 0.55)
	stream_surface.resize(n)
	for k in n:
		stream_surface[k] = bed[k] + STREAM_DEPTH
	_carve_channel(stream_points, bed, stream_surface, 0.95, 2.8)


func _monotonic_bed(pts: PackedVector2Array, carve: float, min_drop: float) -> PackedFloat32Array:
	var bed := PackedFloat32Array()
	bed.resize(pts.size())
	var lowest := INF
	for k in pts.size():
		var h := height_at(pts[k].x, pts[k].y) - carve
		lowest = minf(lowest - min_drop, h)
		bed[k] = lowest
	return bed


func _carve_channel(pts: PackedVector2Array, bed: PackedFloat32Array, surface: PackedFloat32Array, w_bed: float, w_bank: float) -> void:
	var reach := w_bank + 2.5
	var d_field := PackedFloat32Array()
	d_field.resize(N * N)
	d_field.fill(1.0e6)
	var b_field := PackedFloat32Array()
	b_field.resize(N * N)
	var s_field := PackedFloat32Array()
	s_field.resize(N * N)
	_rasterize(pts, reach, d_field, bed, b_field, surface, s_field)
	for i in N * N:
		var d := d_field[i]
		if d > reach:
			continue
		# Leave the pond basin alone where a channel runs into or out of it.
		var gx := i % N
		var gz := i / N
		if is_in_pond(_gx(gx), _gx(gz), 0.6):
			continue
		var h := heights[i]
		var levee := maxf(h, lerpf(s_field[i] + 0.14, h, ForestLayout.sstep(w_bank, reach, d)))
		var dip := (1.0 - clampf(d / w_bed, 0.0, 1.0)) * 0.08
		heights[i] = lerpf(b_field[i] - dip, levee, ForestLayout.sstep(w_bed * 0.6, w_bank, d))
		water_dist[i] = minf(water_dist[i], d - w_bed)
		if d < w_bank:
			water_level[i] = maxf(water_level[i], s_field[i])


## Writes distance-to-polyline into `out_d`, and for each cell the value of the
## closest segment interpolated from per-point arrays (`va` -> `out_a`, ...).
func _rasterize(pts: PackedVector2Array, reach: float, out_d: PackedFloat32Array,
		va := PackedFloat32Array(), out_a := PackedFloat32Array(),
		vb := PackedFloat32Array(), out_b := PackedFloat32Array()) -> void:
	var has_a := not va.is_empty()
	var has_b := not vb.is_empty()
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var ab := b - a
		var len2 := maxf(ab.length_squared(), 1.0e-6)
		var i0 := maxi(0, int((minf(a.x, b.x) - reach + EXTENT) / STEP))
		var i1 := mini(N - 1, int((maxf(a.x, b.x) + reach + EXTENT) / STEP) + 1)
		var j0 := maxi(0, int((minf(a.y, b.y) - reach + EXTENT) / STEP))
		var j1 := mini(N - 1, int((maxf(a.y, b.y) + reach + EXTENT) / STEP) + 1)
		for gz in range(j0, j1 + 1):
			for gx in range(i0, i1 + 1):
				var p := Vector2(_gx(gx), _gx(gz))
				var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
				var d := p.distance_to(a + ab * t)
				var idx := gz * N + gx
				if d < out_d[idx]:
					out_d[idx] = d
					if has_a:
						out_a[idx] = lerpf(va[k], va[k + 1], t)
					if has_b:
						out_b[idx] = lerpf(vb[k], vb[k + 1], t)


func _trace_paths() -> void:
	path_points = [
		ForestLayout.resample(ForestLayout.PATH_MAIN, 0.5),
		ForestLayout.resample(ForestLayout.PATH_POND, 0.5),
		ForestLayout.resample(ForestLayout.PATH_HOLLOW, 0.5),
	]
	for pts in path_points:
		_rasterize(pts, 4.0, path_dist)
	# Spur trails and trodden pads out to the scenic benches.
	for site in bench_sites:
		for pts in site.trails:
			_rasterize(pts, 4.0, path_dist)
	# Footpaths are trodden smooth: relax the terrain along them.
	var relaxed := heights.duplicate()
	for gz in range(2, N - 2):
		for gx in range(2, N - 2):
			var i := gz * N + gx
			var w := 1.0 - ForestLayout.sstep(0.6, 2.4, path_dist[i])
			if w <= 0.0 or water_dist[i] < 1.5:
				continue
			var sum := 0.0
			for oz in range(-2, 3):
				for ox in range(-2, 3):
					sum += heights[i + oz * N + ox]
			relaxed[i] = lerpf(heights[i], sum / 25.0 - 0.03, w * 0.85)
	heights = relaxed


func _compute_normals() -> void:
	normals.resize(N * N)
	for gz in N:
		for gx in N:
			var l := heights[gz * N + maxi(gx - 1, 0)]
			var r := heights[gz * N + mini(gx + 1, N - 1)]
			var u := heights[maxi(gz - 1, 0) * N + gx]
			var d := heights[mini(gz + 1, N - 1) * N + gx]
			normals[gz * N + gx] = Vector3(l - r, 2.0 * STEP, u - d).normalized()


# ----------------------------------------------------------------------------
# Mesh and collision

## The terrain masks of grid sample i: R worn path, G bare rock, B wet bank,
## A canopy shade. Baked into the mesh colours and into ForestGround's mask.
func mask_color(i: int) -> Color:
	var path := 1.0 - ForestLayout.sstep(0.55, 1.65, path_dist[i])
	var rock := ForestLayout.sstep(0.80, 0.62, normals[i].y)
	var wet := 1.0 - ForestLayout.sstep(-0.2, 2.2, water_dist[i])
	return Color(path, rock, wet, shade[i])


## Vertex colours are mask_color(); UV.x is the water depth over the vertex.
func build_meshes(material: Material) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var cells := (N - 1) / CHUNKS
	for cz in CHUNKS:
		for cx in CHUNKS:
			var mesh := _chunk_mesh(cx * cells, cz * cells, cells)
			mesh.surface_set_material(0, material)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainChunk_%d_%d" % [cx, cz]
			mi.mesh = mesh
			# build_shadow_meshes() casts the terrain's shadows, far cheaper.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			out.append(mi)
	return out


## Shadow casters for the hills at half the grid resolution (a quarter of the
## triangles). Each vertex takes the lowest height around it, so the coarse
## surface always stays under the real one and never shadows it by mistake;
## ridges still throw their long evening shadows across the valley.
func build_shadow_meshes(material: Material) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var cells := (N - 1) / CHUNKS / 2
	var w := cells + 1
	for cz in CHUNKS:
		for cx in CHUNKS:
			var verts := PackedVector3Array()
			var norms := PackedVector3Array()
			verts.resize(w * w)
			norms.resize(w * w)
			for lz in w:
				for lx in w:
					var gx := (cx * cells + lx) * 2
					var gz := (cz * cells + lz) * 2
					var h := INF
					for oz in range(-1, 2):
						for ox in range(-1, 2):
							h = minf(h, heights[clampi(gz + oz, 0, N - 1) * N + clampi(gx + ox, 0, N - 1)])
					verts[lz * w + lx] = Vector3(_gx(gx), h - 0.03, _gx(gz))
					norms[lz * w + lx] = normals[gz * N + gx]
			var idx := PackedInt32Array()
			for lz in cells:
				for lx in cells:
					var a := lz * w + lx
					idx.append_array([a, a + 1, a + w + 1, a, a + w + 1, a + w])
			# Same vertex layout as the drawn chunks so it shares their shadow pipeline.
			var cols := PackedColorArray()
			cols.resize(w * w)
			var uvs := PackedVector2Array()
			uvs.resize(w * w)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_COLOR] = cols
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, material)
			var mi := MeshInstance3D.new()
			mi.name = "TerrainShadow_%d_%d" % [cx, cz]
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			out.append(mi)
	return out


func _chunk_mesh(x0: int, z0: int, cells: int) -> ArrayMesh:
	var w := cells + 1
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(w * w)
	norms.resize(w * w)
	cols.resize(w * w)
	uvs.resize(w * w)
	for lz in w:
		for lx in w:
			var gx := x0 + lx
			var gz := z0 + lz
			var i := gz * N + gx
			var k := lz * w + lx
			verts[k] = Vector3(_gx(gx), heights[i], _gx(gz))
			norms[k] = normals[i]
			cols[k] = mask_color(i)
			# UV.x: depth under water. UV.y: a wet film on the bank just above
			# the waterline, fading out over the first 15 cm of height.
			var above := heights[i] - water_level[i]
			uvs[k] = Vector2(maxf(-above, 0.0), 1.0 - clampf(above / 0.15, 0.0, 1.0) if above > -0.05 else 0.0)
	var idx := PackedInt32Array()
	idx.resize(cells * cells * 6)
	var t := 0
	for lz in cells:
		for lx in cells:
			var a := lz * w + lx
			idx[t] = a
			idx[t + 1] = a + 1
			idx[t + 2] = a + w + 1
			idx[t + 3] = a
			idx[t + 4] = a + w + 1
			idx[t + 5] = a + w
			t += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Low-detail landform that reaches to the horizon behind the rim. It dips a
## little under the detailed grid so the two never z-fight.
func build_outer_mesh(material: Material) -> MeshInstance3D:
	var w := int(2.0 * OUTER_EXTENT / OUTER_STEP) + 1
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(w * w)
	cols.resize(w * w)
	for lz in w:
		for lx in w:
			var x := -OUTER_EXTENT + lx * OUTER_STEP
			var z := -OUTER_EXTENT + lz * OUTER_STEP
			var h := layout.landform(x, z)
			# Sink it well below the detailed grid (carved pond, creek beds) but
			# keep the border ring so both meshes meet at the seam.
			if maxf(absf(x), absf(z)) < EXTENT - 0.5:
				h -= 12.0
			verts[lz * w + lx] = Vector3(x, h, z)
			# Distant hills sit under dense canopy: give them shade.
			var far := ForestLayout.sstep(EXTENT, EXTENT + 20.0, maxf(absf(x), absf(z)))
			cols[lz * w + lx] = Color(0.0, 0.0, 0.0, 0.35 + far * 0.4)
	var idx := PackedInt32Array()
	for lz in w - 1:
		for lx in w - 1:
			var a := lz * w + lx
			idx.append_array([a, a + 1, a + w + 1, a, a + w + 1, a + w])
	var norms := PackedVector3Array()
	norms.resize(w * w)
	for lz in w:
		for lx in w:
			var l := verts[lz * w + maxi(lx - 1, 0)].y
			var r := verts[lz * w + mini(lx + 1, w - 1)].y
			var u := verts[maxi(lz - 1, 0) * w + lx].y
			var d := verts[mini(lz + 1, w - 1) * w + lx].y
			norms[lz * w + lx] = Vector3(l - r, 2.0 * OUTER_STEP, u - d).normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "TerrainHorizon"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func build_collision() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := HeightMapShape3D.new()
	shape.map_width = N
	shape.map_depth = N
	# The shape spans one unit per sample; it is scaled down by STEP below, so
	# pre-scale the heights up to compensate (uniform scale keeps Jolt happy).
	var data := PackedFloat32Array()
	data.resize(N * N)
	for i in N * N:
		data[i] = heights[i] / STEP
	shape.map_data = data
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * STEP
	body.add_child(cs)
	# Soft invisible walls at the edge of the playable square.
	var wall_h := 80.0
	for k in 4:
		var wall := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(ForestLayout.HALF * 2.0 + 4.0, wall_h, 2.0)
		wall.shape = box
		var dir := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][k] as Vector3
		wall.position = dir * (ForestLayout.HALF + 1.0) + Vector3.UP * 10.0
		wall.rotation.y = k * PI * 0.5
		body.add_child(wall)
	return body
