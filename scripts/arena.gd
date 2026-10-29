class_name Arena
extends Node3D
## The drift arena: floor, walls, obstacles, cones, lighting and sky.
## Everything is generated in code.

const HALF_SIZE := 75.0
const WALL_HEIGHT := 2.5

const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 base_color : source_color = vec3(0.07, 0.07, 0.10);
uniform vec3 line_color : source_color = vec3(0.0, 0.85, 1.0);
uniform vec3 zone_color : source_color = vec3(1.0, 0.1, 0.8);
uniform float cell = 10.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float ring(float d, float r, float w) {
	return 1.0 - smoothstep(0.0, w + fwidth(d) * 1.5, abs(d - r));
}

void fragment() {
	vec2 g = abs(fract(wpos.xz / cell - 0.5) - 0.5) * cell;
	float aa = fwidth(wpos.x) * 1.5;
	float grid = 1.0 - smoothstep(0.0, 0.06 + aa, min(g.x, g.y));
	float d = length(wpos.xz);
	float zones = ring(d, 16.0, 0.25) + ring(d, 30.0, 0.15);
	vec3 col = base_color + line_color * grid * 0.25 + zone_color * zones * 0.4;
	ALBEDO = col;
	EMISSION = line_color * grid * 0.35 + zone_color * zones * 0.8;
	ROUGHNESS = 0.8;
	METALLIC = 0.1;
}
"""

## Circles (x, z, radius) that spawned items must keep clear of.
var blockers: Array[Vector3] = []
var cones: Array[Cone] = []


func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_walls()
	_build_obstacles()
	_build_cones()


func reset_cones() -> void:
	for c in cones:
		c.reset()


func is_open(p: Vector3, clearance: float) -> bool:
	if absf(p.x) > HALF_SIZE - clearance or absf(p.z) > HALF_SIZE - clearance:
		return false
	for b in blockers:
		if Vector2(p.x - b.x, p.z - b.y).length() < b.z + clearance:
			return false
	return true


func random_open_point(clearance := 3.0, avoid := Vector3.INF, avoid_radius := 0.0) -> Vector3:
	for i in 60:
		var p := Vector3(randf_range(-HALF_SIZE, HALF_SIZE), 0.0, randf_range(-HALF_SIZE, HALF_SIZE))
		if not is_open(p, clearance):
			continue
		if avoid != Vector3.INF and p.distance_to(avoid) < avoid_radius:
			continue
		return p
	return Vector3(0, 0, 40)


# --- Building ------------------------------------------------------------------

func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.08, 0.04, 0.2)
	sky_mat.sky_horizon_color = Color(0.9, 0.35, 0.45)
	sky_mat.ground_horizon_color = Color(0.5, 0.2, 0.35)
	sky_mat.ground_bottom_color = Color(0.05, 0.03, 0.08)
	sky_mat.sun_angle_max = 20.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.45, 0.2, 0.4)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_color = Color(1.0, 0.85, 0.75)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	add_child(sun)


func _build_floor() -> void:
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(HALF_SIZE * 2.0 + 40.0, HALF_SIZE * 2.0 + 40.0)
	floor_mesh.mesh = plane
	var shader := Shader.new()
	shader.code = FLOOR_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	floor_mesh.material_override = mat
	add_child(floor_mesh)


func _build_walls() -> void:
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.15, 0.15, 0.2)
	wall_mat.roughness = 0.6
	var neon := StandardMaterial3D.new()
	neon.albedo_color = Color(1.0, 0.1, 0.8)
	neon.emission_enabled = true
	neon.emission = Color(1.0, 0.1, 0.8)
	neon.emission_energy_multiplier = 3.0
	var span := HALF_SIZE * 2.0 + 4.0
	var t := 2.0
	var walls := [
		[Vector3(0, 0, -HALF_SIZE - t / 2.0), Vector3(span, WALL_HEIGHT, t)],
		[Vector3(0, 0, HALF_SIZE + t / 2.0), Vector3(span, WALL_HEIGHT, t)],
		[Vector3(-HALF_SIZE - t / 2.0, 0, 0), Vector3(t, WALL_HEIGHT, span)],
		[Vector3(HALF_SIZE + t / 2.0, 0, 0), Vector3(t, WALL_HEIGHT, span)],
	]
	for w in walls:
		var body := _static_box(w[0], w[1], wall_mat)
		var strip := MeshInstance3D.new()
		var sm := BoxMesh.new()
		var size: Vector3 = w[1]
		sm.size = Vector3(size.x + 0.05, 0.2, size.z + 0.05)
		strip.mesh = sm
		strip.material_override = neon
		strip.position.y = WALL_HEIGHT - 0.3
		body.add_child(strip)


func _build_obstacles() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.35, 0.35, 0.42)
	concrete.roughness = 0.9
	var cyan := StandardMaterial3D.new()
	cyan.albedo_color = Color(0.0, 0.8, 1.0)
	cyan.emission_enabled = true
	cyan.emission = Color(0.0, 0.8, 1.0)
	cyan.emission_energy_multiplier = 2.5

	# Central donut island: circle it for big drifts.
	_static_cylinder(Vector3.ZERO, 7.0, 1.2, concrete, cyan)
	# Pillars
	for x in [-38.0, 38.0]:
		for z in [-38.0, 38.0]:
			_static_cylinder(Vector3(x, 0, z), 2.5, 6.0, concrete, cyan)
	# Long barriers to drift around
	for z in [-52.0, 52.0]:
		_barrier(Vector3(0, 0, z), 24.0, true, concrete, cyan)
	for x in [-52.0, 52.0]:
		_barrier(Vector3(x, 0, 0), 24.0, false, concrete, cyan)


func _barrier(center: Vector3, length: float, along_x: bool, mat: Material, glow: Material) -> void:
	var size := Vector3(length, 1.2, 1.5) if along_x else Vector3(1.5, 1.2, length)
	var body := _static_box(center, size, mat)
	var strip := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(size.x + 0.05, 0.15, size.z + 0.05)
	strip.mesh = sm
	strip.material_override = glow
	strip.position.y = 1.0
	body.add_child(strip)
	var steps := int(length / 4.0)
	for i in steps + 1:
		var off := -length / 2.0 + i * (length / steps)
		var p := center + (Vector3(off, 0, 0) if along_x else Vector3(0, 0, off))
		blockers.append(Vector3(p.x, p.z, 2.5))


func _build_cones() -> void:
	# Slalom lines between the pillars, plus a ring around the island.
	var lines := [
		[Vector3(-25, 0, 24), Vector3(25, 0, 24)],
		[Vector3(-25, 0, -24), Vector3(25, 0, -24)],
		[Vector3(64, 0, -30), Vector3(64, 0, 30)],
		[Vector3(-64, 0, -30), Vector3(-64, 0, 30)],
	]
	for l in lines:
		var a: Vector3 = l[0]
		var b: Vector3 = l[1]
		for i in 7:
			_add_cone(a.lerp(b, i / 6.0))
	for i in 12:
		var ang := TAU * i / 12.0
		_add_cone(Vector3(cos(ang), 0, sin(ang)) * 11.0)


func _add_cone(p: Vector3) -> void:
	var c := Cone.new()
	c.position = p
	add_child(c)
	cones.append(c)
	blockers.append(Vector3(p.x, p.z, 1.0))


func _static_box(center: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(center.x, 0, center.z)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position.y = size.y / 2.0
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position.y = size.y / 2.0
	body.add_child(mi)
	add_child(body)
	return body


func _static_cylinder(center: Vector3, radius: float, height: float, mat: Material, glow: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position.y = height / 2.0
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 32
	mi.mesh = cm
	mi.material_override = mat
	mi.position.y = height / 2.0
	body.add_child(mi)
	var band := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = radius
	tm.outer_radius = radius + 0.15
	tm.rings = 48
	band.mesh = tm
	band.material_override = glow
	band.position.y = height - 0.2
	body.add_child(band)
	add_child(body)
	blockers.append(Vector3(center.x, center.z, radius))
