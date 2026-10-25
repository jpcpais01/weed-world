class_name SmokeGifts
extends RefCounted
## The smoke gifts: every strain carries one. Smoke a joint of it and each
## puff gives a charge of its gift; while the high lasts, the Gift button
## (V / RB / the touch button) breathes one charge out as a power.
##
##   fireflies · Firefly Swarm   twilight falls and a swarm of fireflies lights
##                               the forest, then leads you to the rarest ripe
##                               plant around
##   cloud     · Cloud Ride      your smoke gathers into a fluffy cloud; sit on
##                               it and fly across the valley
##   bloom     · Bloom Burst     a smoke ring rolls out over the ground and
##                               gigantic glowing flora erupt in its wake:
##                               bouncy titan mushrooms, starlilies, lantern
##                               bells, fiddlehead ferns, lotus on the water
##   slowtime  · Slow Time       the whole world slows to a dream around you
##                               (but not you): leaves hang in the air
##   moonjump  · Moon Jump       a pale moon rises; gravity lets go, every
##                               landing bounces and scatters stardust
##   owl       · Owl Flight      your smoke gathers into a giant ghostly
##                               spirit owl that scoops you onto its back
##                               and soars off over the forest
##
## Smoked at a bench whose view matches the gift's element, it comes out
## stronger and lasts longer.

const GIFTS := {
	&"fireflies": {
		"name": "Firefly Swarm", "icon": "firefly", "element": &"spirit",
		"text": "Twilight falls, the fireflies wake and lead you to rare buds",
		"color": Color(0.85, 1.0, 0.45), "time": 40.0,
	},
	&"cloud": {
		"name": "Cloud Ride", "icon": "cloud", "element": &"air",
		"text": "Your smoke becomes a cloud: hop on and fly",
		"color": Color(0.88, 0.92, 1.0), "time": 32.0,
	},
	&"bloom": {
		"name": "Bloom Burst", "icon": "bloom", "element": &"life",
		"text": "Giant glowing flora burst out of the ground around you",
		"color": Color(1.0, 0.55, 0.85), "time": 48.0,
	},
	&"slowtime": {
		"name": "Slow Time", "icon": "hourglass", "element": &"water",
		"text": "The world slows to a dream around you, but you don't",
		"color": Color(0.55, 0.75, 1.0), "time": 22.0,
	},
	&"moonjump": {
		"name": "Moon Jump", "icon": "moon", "element": &"earth",
		"text": "A pale moon rises and gravity lets go",
		"color": Color(0.8, 0.84, 1.0), "time": 36.0,
	},
	&"owl": {
		"name": "Owl Flight", "icon": "owl", "element": &"spirit",
		"text": "A spirit owl gathers out of your smoke and carries you over the forest",
		"color": Color(0.62, 0.86, 1.0), "time": 34.0,
	},
}

# Owl Flight is only ever a strain's own gift (the rare Moonfeather), never a
# fallback pick, so it stays out of ORDER.
const ORDER: Array[StringName] = [&"fireflies", &"cloud", &"bloom", &"slowtime", &"moonjump"]
## How much more a matching bench view gives (time and strength).
const BOOST := 1.5
const MAX_CHARGES := 3

## The wild strains' gifts (a strain's own "gift" key wins over this).
const WILD := {&"ember": &"fireflies", &"starlit": &"moonjump", &"verdant": &"bloom"}


static func info(id: StringName) -> Dictionary:
	return GIFTS.get(id, GIFTS[&"fireflies"])


static func valid(id: StringName) -> bool:
	return GIFTS.has(id)


## The gift a strain carries: its own "gift" key, else the wild table, else a
## stable pick from its name (the same on every device).
static func of_strain(strain: StringName) -> StringName:
	var s: Dictionary = WeedStrains.STRAINS.get(strain, {})
	var own := StringName(s.get("gift", &""))
	if valid(own):
		return own
	if WILD.has(strain):
		return WILD[strain]
	if strain == &"":
		return &""
	return ORDER[absi(hash(String(strain))) % ORDER.size()]


## Real seconds per game second right now, for things that must keep real
## time while Slow Time stretches the world (gift timers, the HUD).
static func real(delta: float) -> float:
	return delta / maxf(Engine.time_scale, 0.01)


static func script_for(id: StringName) -> Script:
	match id:
		&"fireflies":
			return load("res://player/powers/gift_fireflies.gd")
		&"cloud":
			return load("res://player/powers/gift_cloud.gd")
		&"bloom":
			return load("res://player/powers/gift_bloom.gd")
		&"slowtime":
			return load("res://player/powers/gift_slow_time.gd")
		&"moonjump":
			return load("res://player/powers/gift_moon_jump.gd")
		&"owl":
			return load("res://player/powers/gift_owl.gd")
	return null


## The gifts only appear when someone breathes one: the loading screen shows
## one of everything they draw (every giant flower, the cloud, fireflies,
## leaves, the moon...) so their shaders compile behind the curtain instead of
## hitching the first cast. Returns the holder; the caller frees it.
static func warm_up(cam: Node3D) -> Node3D:
	var holder := Node3D.new()
	holder.name = "GiftsWarmUp"
	cam.add_child(holder)
	holder.position = Vector3(0, -0.3, -4.0)
	var noise := preload("res://assets/fx/smoke_noise.png")
	var mat := func(path: String) -> ShaderMaterial:
		var m := ShaderMaterial.new()
		m.shader = load(path)
		m.set_shader_parameter("noise", noise)
		return m
	var x := -2.0
	for kind in GiantFlora.KINDS:
		var f := GiantFlora.get_flora(kind, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = f.mesh
		mi.material_override = GiantFlora.material()
		holder.add_child(mi)
		mi.position = Vector3(x, -0.5, 0)
		mi.scale = Vector3.ONE * 0.2
		mi.set_instance_shader_parameter("grow", 1.0)
		mi.set_instance_shader_parameter("open", 1.0)
		x += 0.6
	var q := QuadMesh.new()
	q.size = Vector2.ONE * 0.4
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	var swarms := [
		[q, "res://player/powers/soft_puff.gdshader", true],
		[q, "res://player/powers/firefly.gdshader", true],
		[q, "res://player/powers/frozen_leaf.gdshader", true],
		[sphere, "res://player/powers/cloud.gdshader", true],
		[WeedHigh._flower_mesh(), "res://player/powers/bloom_carpet.gdshader", false],
	]
	x = -1.5
	for s in swarms:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = s[2]
		mm.use_custom_data = true
		mm.mesh = s[0]
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3(x, 0.4, 0)))
		if s[2]:
			mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(0.5, 0.5, 0.5, 0.5))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat.call(s[1])
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
		x += 0.75
	var singles := [
		[q, "res://player/powers/moon.gdshader", "alpha"],
		[PlaneMesh.new(), "res://player/powers/dust_ring.gdshader", "strength"],
		[sphere, "res://player/powers/time_bubble.gdshader", "strength"],
	]
	x = -1.0
	for s in singles:
		var mi := MeshInstance3D.new()
		mi.mesh = s[0]
		mi.material_override = mat.call(s[1])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		mi.position = Vector3(x, 0.9, 0)
		mi.set_instance_shader_parameter(s[2], 0.05)
		x += 1.0
	# The spirit owl (its ghost, smoke, feathers and trails).
	GiftOwl.warm_up(holder)
	return holder
