extends SceneTree
## Bakes the distant-tree impostor atlas (see world/forest/forest_impostors.gd)
## from the exact tree meshes the forest grows. Needs a real GPU or lavapipe:
##   xvfb-run -a godot --path . --rendering-method mobile -s res://tools/bake_impostors.gd
## Rerun it whenever a tree generator, a kit tree or a reshape changes; the
## game falls back to real meshes for any tree whose bake is stale.
##
## Per tree type and per frame (FRAMES around it, looking level):
##   albedo atlas: bark colour, or for leaves the canopy's light/dark blend as
##                 grey (the game recolours it per tree); alpha = coverage
##   normal atlas: own-space normal (octahedral, RG), crown mask (B), coverage;
##                 half the albedo's resolution
## Frames render at 2x and are filtered down for clean edges.

const SS := 2
const ATLAS_W := 4096
const PAD := 2
const BAKE_SHADER := preload("res://tools/impostor_bake.gdshader")

var _env: Environment


func _initialize() -> void:
	root.size = Vector2i(64, 64)
	_env = Environment.new()
	_env.background_mode = Environment.BG_CLEAR_COLOR
	_env.background_color = Color(0, 0, 0, 0)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_bake.call_deferred()


func _bake() -> void:
	var t0 := Time.get_ticks_msec()
	# Grow the forest's plan exactly as the game does, for its tree meshes.
	var layout := ForestLayout.new()
	var terrain := ForestTerrain.new(layout)
	terrain.build()
	var kit := NatureKit.new()
	var scatter := ForestScatter.new(layout, terrain, kit)
	scatter.plan()
	kit.set_wind(Vector3.RIGHT, 0.0)
	var meshes: Array[Mesh] = []
	var seen := {}
	var keys := scatter._batches.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = scatter._batches[key]
		if b.group in ForestScatter.IMPOSTOR_GROUPS and not seen.has(b.mesh):
			seen[b.mesh] = true
			meshes.append(b.mesh)
	print("bake_impostors: %d tree types" % meshes.size())

	var entries := []
	var strips := []
	for mesh in meshes:
		var info := _measure(mesh)
		var imgs: Array = await _render(mesh, info)
		strips.append(imgs)
		entries.append({"name": mesh.resource_name, "sig": ForestImpostors.signature(mesh),
				"quad": [info.width, info.height, info.foot], "radius": info.radius, "px": [info.wpx, info.hpx]})
		print("  %-32s %3dx%-3d px  %.1f x %.1f m" % [mesh.resource_name, info.wpx, info.hpx, info.width, info.height])

	# Shelf-pack each type's strip of frames, tallest first.
	var order := range(entries.size())
	order.sort_custom(func(a, b): return entries[a].px[1] > entries[b].px[1])
	var x := 0
	var y := 0
	var shelf := 0
	for i in order:
		var w: int = entries[i].px[0] * ForestImpostors.FRAMES + PAD * 2 * ForestImpostors.FRAMES
		var h: int = entries[i].px[1] + PAD * 2
		if x + w > ATLAS_W:
			x = 0
			y += shelf
			shelf = 0
		entries[i]["at"] = [x, y]
		x += w
		shelf = maxi(shelf, h)
	var height := ceili(float(y + shelf) / 64.0) * 64
	var albedo := Image.create(ATLAS_W, height, false, Image.FORMAT_RGBA8)
	var normal := Image.create(ATLAS_W, height, false, Image.FORMAT_RGBA8)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var wpx: int = e.px[0]
		var hpx: int = e.px[1]
		for k in ForestImpostors.FRAMES:
			var dst := Vector2i(e.at[0] + k * (wpx + PAD * 2) + PAD, e.at[1] + PAD)
			albedo.blit_rect(strips[i][0][k], Rect2i(0, 0, wpx, hpx), dst)
			normal.blit_rect(strips[i][1][k], Rect2i(0, 0, wpx, hpx), dst)
		# Frame k fills cell k (stride wide, drawn part centred): the shader steps cell by cell.
		e["frame"] = [e.at[0], e.at[1] + PAD, wpx + PAD * 2, hpx]
		e["frame_w"] = wpx
		e.erase("at")
	_fix_stride(entries)
	# Bleed colour into the empty pixels so filtering and mipmaps don't pull
	# dark edges in. Normals are smooth: half resolution is plenty.
	albedo.fix_alpha_edges()
	normal.fix_alpha_edges()
	normal.resize(ATLAS_W / 2, height / 2, Image.INTERPOLATE_BILINEAR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ForestImpostors.DIR))
	albedo.save_png(ForestImpostors.ALBEDO)
	normal.save_png(ForestImpostors.NORMAL)
	var f := FileAccess.open(ForestImpostors.INDEX, FileAccess.WRITE)
	f.store_string(JSON.stringify({"frames": ForestImpostors.FRAMES, "px_per_m": ForestImpostors.PX_PER_M,
			"width": ATLAS_W, "height": height, "types": entries}, "\t"))
	f.close()
	print("bake_impostors: %dx%d atlas, %d types, %d s" % [ATLAS_W, height, entries.size(), (Time.get_ticks_msec() - t0) / 1000])
	quit()


## The shader steps frame to frame by the frame rect's width, so the stored
## width is the stride and the drawn width is a fraction of it.
func _fix_stride(entries: Array) -> void:
	for e in entries:
		var f: Array = e.frame
		var stride: float = f[2]
		var drawn: float = e.frame_w
		# Card width is set from the drawn part; stretch it so uv 0..1 over
		# the stride still lands on the drawn pixels: the shader maps
		# uv.x * stride, so pad the card by the same ratio.
		e.quad[0] = e.quad[0] * stride / drawn
		e.erase("frame_w")


## Card size: the tree's full height, and twice the furthest any part of it
## reaches from its trunk axis (so every view fits).
func _measure(mesh: Mesh) -> Dictionary:
	var lo := INF
	var hi := -INF
	var reach := 0.0
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
			reach = maxf(reach, Vector2(v.x, v.z).length())
	reach *= 1.02
	var h := (hi - lo) * 1.01
	var hpx := clampi(ceili(h * ForestImpostors.PX_PER_M), 24, 320)
	var wpx := clampi(ceili(reach * 2.0 * ForestImpostors.PX_PER_M), 12, 320)
	# Snap the card to whole pixels so photo and card agree exactly.
	return {"foot": lo, "height": hpx / ForestImpostors.PX_PER_M, "width": wpx / ForestImpostors.PX_PER_M,
			"radius": reach, "hpx": hpx, "wpx": wpx, "center": Vector3(0, lo + hpx / ForestImpostors.PX_PER_M * 0.5, 0)}


## Renders every frame of one tree in both passes at once.
func _render(mesh: Mesh, info: Dictionary) -> Array:
	var world := World3D.new()
	world.environment = _env
	var holder := Node3D.new()
	root.add_child(holder)
	# Pass A (layer 1): the real materials drawn unshaded, the crown palette
	# swapped to black..white so it reads out as the light/dark blend.
	var colour := _variant(mesh, true)
	var normals := _variant(mesh, false)
	var views := []
	for pi in 2:
		for k in ForestImpostors.FRAMES:
			var vp := SubViewport.new()
			vp.size = Vector2i(info.wpx * SS, info.hpx * SS)
			vp.transparent_bg = true
			vp.world_3d = world
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			if pi == 0:
				vp.debug_draw = Viewport.DEBUG_DRAW_UNSHADED
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.keep_aspect = Camera3D.KEEP_HEIGHT
			cam.size = info.height
			cam.near = 0.05
			cam.far = info.radius * 2.0 + 20.0
			cam.cull_mask = 1 << pi
			cam.environment = _env
			vp.add_child(cam)
			holder.add_child(vp)
			var a := TAU * k / ForestImpostors.FRAMES
			var dir := Vector3(sin(a), 0.0, cos(a))
			cam.look_at_from_position(info.center + dir * (info.radius + 10.0), info.center, Vector3.UP)
			cam.make_current()
			views.append(vp)
	# Both passes live in the one shared world; layers keep them apart.
	for pi in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = colour if pi == 0 else normals
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		# Neutral instance: no hue shift, brightness x1, no magic or autumn.
		mm.set_instance_custom_data(0, Color(0.5, 0.5, 0.0, 0.0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.layers = 1 << pi
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		views[0].add_child(mmi)
	# Let the frame render (twice, so shaders are compiled and drawn).
	for i in 3:
		for vp in views:
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
	var out := [[], []]
	for i in views.size():
		var img: Image = views[i].get_texture().get_image()
		img.convert(Image.FORMAT_RGBA8)
		out[i / ForestImpostors.FRAMES].append(_downsample(img, info.wpx, info.hpx))
	holder.queue_free()
	await process_frame
	return out


## Filters a 2x render down and un-premultiplies the edge pixels so leaves
## don't get dark halos.
func _downsample(img: Image, w: int, h: int) -> Image:
	var src := img
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var r := 0.0
			var g := 0.0
			var b := 0.0
			var a := 0.0
			for oy in SS:
				for ox in SS:
					var c := src.get_pixel(x * SS + ox, y * SS + oy)
					var cov := 1.0 if c.a > 0.5 else 0.0
					r += c.r * cov
					g += c.g * cov
					b += c.b * cov
					a += cov
			if a > 0.0:
				out.set_pixel(x, y, Color(r / a, g / a, b / a, a / (SS * SS)))
			else:
				out.set_pixel(x, y, Color(0, 0, 0, 0))
	return out


## A copy of the mesh dressed for one pass.
func _variant(mesh: Mesh, colour: bool) -> ArrayMesh:
	var m := ArrayMesh.new()
	for s in mesh.get_surface_count():
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		var src := mesh.surface_get_material(s)
		var leafy := src is ShaderMaterial and (src as ShaderMaterial).shader == NatureKit.SH_CANOPY
		var mat: Material
		if colour:
			if leafy:
				var c := (src as ShaderMaterial).duplicate() as ShaderMaterial
				for p in ["color_low", "alt_low", "autumn_low"]:
					c.set_shader_parameter(p, Color.BLACK)
				for p in ["color_high", "alt_high", "autumn_high"]:
					c.set_shader_parameter(p, Color.WHITE)
				c.set_shader_parameter("hue_variation", 0.0)
				mat = c
			else:
				mat = src
		else:
			var n := ShaderMaterial.new()
			n.shader = BAKE_SHADER
			if leafy:
				var sm := src as ShaderMaterial
				n.set_shader_parameter("crown", true)
				n.set_shader_parameter("leaf_tex", sm.get_shader_parameter("leaf_tex"))
				n.set_shader_parameter("canopy_center", sm.get_shader_parameter("canopy_center"))
				n.set_shader_parameter("canopy_radius", sm.get_shader_parameter("canopy_radius"))
				var cut = sm.get_shader_parameter("alpha_cut")
				if cut != null:
					n.set_shader_parameter("alpha_cut", cut)
				var ns = sm.get_shader_parameter("normal_sphere")
				if ns != null:
					n.set_shader_parameter("normal_sphere", ns)
			mat = n
		m.surface_set_material(s, mat)
	return m
