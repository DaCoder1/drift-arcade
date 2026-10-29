class_name DriftCar
extends CharacterBody3D
## Arcade drift car. Velocity is kept in world space while the body rotates,
## and lateral grip pulls it back toward the heading. Low grip = slide.
## The handbrake and hard steering at speed both drop grip, so the car
## kicks out easily and drifts are easy to hold.

signal crashed(impact: float)

const DRIFT_ENTER_ANGLE := 12.0
const DRIFT_EXIT_ANGLE := 7.0
const DRIFT_MIN_SPEED := 7.0
const BOOST_BURN := 38.0

@export var paint := Color(1.0, 0.35, 0.1)

var controls_enabled := false

# Tuned from GameData by apply_stats().
var top_speed := 30.0
var accel := 17.0
var steer_rate := 2.3
var grip := 7.0
var boost_capacity := 100.0
var boost_fill := 1.0

# Live state read by the game and HUD.
var boost := 0.0
var boosting := false
var speed := 0.0
var forward_speed := 0.0
var drift_angle := 0.0
var drift_side := 0
var is_drifting := false
var throttle := 0.0
var steer := 0.0
var skid_marks: SkidMarks

var _crash_cooldown := 0.0
var _body: Node3D
var _front_pivots: Array[Node3D] = []
var _wheels: Array[MeshInstance3D] = []
var _rear_points: Array[Node3D] = []
var _smoke: Array[CPUParticles3D] = []
var _flames: Array[CPUParticles3D] = []
var _shield_mesh: MeshInstance3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	_build_model()


func apply_stats() -> void:
	top_speed = GameData.top_speed()
	accel = GameData.acceleration()
	steer_rate = GameData.steer_rate()
	grip = GameData.grip()
	boost_capacity = GameData.boost_capacity()
	boost_fill = GameData.boost_fill_rate()
	boost = minf(boost, boost_capacity)


func reset_to(pos: Vector3, yaw: float) -> void:
	global_position = pos
	rotation = Vector3(0.0, yaw, 0.0)
	velocity = Vector3.ZERO
	speed = 0.0
	forward_speed = 0.0
	steer = 0.0
	is_drifting = false
	drift_angle = 0.0
	boosting = false
	if skid_marks:
		for p in _rear_points:
			skid_marks.break_trail(p)


func add_boost(amount: float) -> void:
	boost = clampf(boost + amount * boost_fill, 0.0, boost_capacity)


func set_shield_visible(on: bool) -> void:
	_shield_mesh.visible = on


func _physics_process(delta: float) -> void:
	var steer_in := 0.0
	var handbrake := false
	var want_boost := false
	throttle = 0.0
	if controls_enabled:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer_in = Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
		handbrake = Input.is_action_pressed("handbrake")
		want_boost = Input.is_action_pressed("boost")

	steer = move_toward(steer, steer_in, delta * (7.0 if absf(steer_in) > absf(steer) else 9.0))

	var fwd := -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var fs := velocity.dot(fwd)
	var ls := velocity.dot(right)

	# Boost
	boosting = want_boost and boost > 0.0 and throttle >= 0.0
	if boosting:
		boost = maxf(boost - BOOST_BURN * delta, 0.0)
		throttle = 1.0
	var max_speed := top_speed * (1.4 if boosting else 1.0)

	# Longitudinal
	if throttle > 0.0:
		if fs < max_speed:
			var a := accel * throttle * (1.8 if boosting else 1.0)
			a *= clampf(1.15 - fs / max_speed, 0.25, 1.0)
			fs = minf(fs + a * delta, max_speed)
		else:
			fs = move_toward(fs, max_speed, 12.0 * delta)
	elif throttle < 0.0:
		if fs > 0.5:
			fs = move_toward(fs, 0.0, 32.0 * -throttle * delta)
		else:
			fs = move_toward(fs, -12.0, 14.0 * -throttle * delta)
	else:
		fs = move_toward(fs, 0.0, 4.0 * delta)

	# Lateral grip
	var speed_ratio := clampf(absf(fs) / top_speed, 0.0, 1.2)
	var g := grip * lerpf(1.0, 0.3, absf(steer) * speed_ratio * speed_ratio)
	if is_drifting:
		g *= 0.6
	if handbrake:
		g = 0.8
		fs = move_toward(fs, 0.0, 4.0 * delta)
	var new_ls := ls * exp(-g * delta)
	# Arcade cheat: part of the scrubbed sideways speed is turned into forward speed,
	# so drifting does not kill your momentum.
	if absf(fs) > 1.0:
		fs += signf(fs) * absf(ls - new_ls) * 0.45
	ls = new_ls

	var pre_velocity := fwd * fs + right * ls
	velocity = pre_velocity

	# Steering
	var authority := clampf(absf(fs) / 5.0, 0.0, 1.0) * lerpf(1.0, 0.7, minf(speed_ratio, 1.0))
	if is_drifting:
		authority *= 1.35
	if handbrake:
		authority *= 1.3
	rotate_y(steer * steer_rate * authority * signf(fs) * delta)

	move_and_slide()
	global_position.y = 0.0
	velocity.y = 0.0

	_check_crash(pre_velocity, delta)
	_update_drift_state(fwd, right)
	_update_visuals(delta, handbrake)


func _check_crash(pre_velocity: Vector3, delta: float) -> void:
	_crash_cooldown = maxf(_crash_cooldown - delta, 0.0)
	var impact := 0.0
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		impact = maxf(impact, -pre_velocity.dot(c.get_normal()))
	if impact > 9.0 and _crash_cooldown <= 0.0:
		_crash_cooldown = 0.6
		crashed.emit(impact)


func _update_drift_state(fwd: Vector3, right: Vector3) -> void:
	speed = Vector2(velocity.x, velocity.z).length()
	forward_speed = velocity.dot(fwd)
	var ls := velocity.dot(right)
	drift_angle = rad_to_deg(atan2(absf(ls), maxf(absf(forward_speed), 0.01))) if speed > 1.0 else 0.0
	drift_side = signi(int(signf(ls)))
	var threshold := DRIFT_EXIT_ANGLE if is_drifting else DRIFT_ENTER_ANGLE
	is_drifting = speed > DRIFT_MIN_SPEED and drift_angle > threshold and forward_speed > 0.0


func _update_visuals(delta: float, handbrake: bool) -> void:
	var ls := velocity.dot(global_transform.basis.x)
	var k := 1.0 - exp(-8.0 * delta)
	_body.rotation.z = lerpf(_body.rotation.z, clampf(ls * 0.012, -0.12, 0.12), k)
	_body.rotation.x = lerpf(_body.rotation.x, -throttle * 0.03, k)
	for p in _front_pivots:
		p.rotation.y = steer * 0.5
	for w in _wheels:
		w.rotate_object_local(Vector3.UP, -forward_speed * delta / 0.36)

	var sliding := is_drifting or (handbrake and speed > 5.0)
	for s in _smoke:
		s.emitting = sliding
	for f in _flames:
		f.emitting = boosting
	if skid_marks:
		for p in _rear_points:
			if sliding:
				skid_marks.add_point(p, p.global_position)
			else:
				skid_marks.break_trail(p)


# --- Model ----------------------------------------------------------------------

func _build_model() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9, 1.0, 4.0)
	shape.shape = box
	shape.position.y = 0.55
	add_child(shape)

	_body = Node3D.new()
	_body.position.y = 0.05
	add_child(_body)

	var paint_mat := _mat(paint, 0.35, 0.4)
	var dark_mat := _mat(Color(0.05, 0.05, 0.07), 0.2, 0.2)
	var trim_mat := _mat(Color(0.12, 0.12, 0.14), 0.6, 0.3)

	_add_box(_body, Vector3(1.9, 0.45, 4.0), Vector3(0, 0.6, 0), paint_mat)          # chassis
	_add_box(_body, Vector3(1.95, 0.2, 4.1), Vector3(0, 0.42, 0), trim_mat)          # skirt
	_add_box(_body, Vector3(1.55, 0.45, 1.9), Vector3(0, 1.05, 0.25), dark_mat)      # cabin
	_add_box(_body, Vector3(1.6, 0.06, 1.7), Vector3(0, 1.3, 0.3), paint_mat)        # roof
	_add_box(_body, Vector3(1.9, 0.08, 0.45), Vector3(0, 1.25, 1.85), paint_mat)     # wing
	_add_box(_body, Vector3(0.08, 0.35, 0.2), Vector3(0.6, 1.0, 1.85), trim_mat)     # wing posts
	_add_box(_body, Vector3(0.08, 0.35, 0.2), Vector3(-0.6, 1.0, 1.85), trim_mat)
	_add_box(_body, Vector3(0.5, 0.06, 0.6), Vector3(0, 0.86, -1.4), trim_mat)       # hood scoop
	# racing stripe
	_add_box(_body, Vector3(0.35, 0.02, 4.02), Vector3(0, 0.835, 0), _mat(Color(1, 1, 1), 0.3, 0.2))

	var head_mat := _mat(Color(1, 1, 0.85), 0.2, 0.0)
	head_mat.emission_enabled = true
	head_mat.emission = Color(1, 0.95, 0.8)
	head_mat.emission_energy_multiplier = 3.0
	var tail_mat := _mat(Color(1, 0.1, 0.1), 0.2, 0.0)
	tail_mat.emission_enabled = true
	tail_mat.emission = Color(1, 0.05, 0.05)
	tail_mat.emission_energy_multiplier = 3.0
	for x in [-0.65, 0.65]:
		_add_box(_body, Vector3(0.45, 0.14, 0.05), Vector3(x, 0.65, -2.01), head_mat)
		_add_box(_body, Vector3(0.5, 0.12, 0.05), Vector3(x, 0.7, 2.01), tail_mat)

	# Wheels
	var tire := CylinderMesh.new()
	tire.top_radius = 0.36
	tire.bottom_radius = 0.36
	tire.height = 0.32
	tire.radial_segments = 16
	var tire_mat := _mat(Color(0.03, 0.03, 0.03), 0.0, 0.9)
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.22
	rim_mesh.bottom_radius = 0.22
	rim_mesh.height = 0.34
	rim_mesh.radial_segments = 6
	var rim_mat := _mat(Color(0.8, 0.8, 0.85), 0.9, 0.25)
	for z in [-1.3, 1.3]:
		for x in [-0.9, 0.9]:
			var pivot := Node3D.new()
			pivot.position = Vector3(x, 0.36, z)
			add_child(pivot)
			if z < 0.0:
				_front_pivots.append(pivot)
			var wheel := MeshInstance3D.new()
			wheel.mesh = tire
			wheel.material_override = tire_mat
			wheel.rotation.z = PI / 2.0
			pivot.add_child(wheel)
			var rim := MeshInstance3D.new()
			rim.mesh = rim_mesh
			rim.material_override = rim_mat
			wheel.add_child(rim)
			_wheels.append(wheel)
			if z > 0.0:
				var rp := Node3D.new()
				rp.position = Vector3(x, 0.0, z)
				add_child(rp)
				_rear_points.append(rp)
				_smoke.append(_make_smoke(rp))

	for x in [-0.45, 0.45]:
		var exhaust := Node3D.new()
		exhaust.position = Vector3(x, 0.45, 2.1)
		add_child(exhaust)
		_flames.append(_make_flame(exhaust))

	var glow := OmniLight3D.new()
	glow.light_color = paint.lerp(Color(1, 0, 1), 0.5)
	glow.light_energy = 2.0
	glow.omni_range = 4.5
	glow.position = Vector3(0, 0.25, 0)
	add_child(glow)

	_shield_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 2.6
	sphere.height = 3.2
	_shield_mesh.mesh = sphere
	var shield_mat := StandardMaterial3D.new()
	shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.albedo_color = Color(0.3, 1.0, 1.0, 0.18)
	shield_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_shield_mesh.material_override = shield_mat
	_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_shield_mesh.position.y = 0.8
	_shield_mesh.visible = false
	add_child(_shield_mesh)


func _make_smoke(parent: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 32
	p.lifetime = 1.0
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 1, 0.4)
	p.spread = 35.0
	p.gravity = Vector3(0, 1.0, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 2.0
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 0.9, 0.95, 0.35))
	ramp.set_color(1, Color(0.9, 0.9, 0.95, 0.0))
	p.color_ramp = ramp
	var mesh := SphereMesh.new()
	mesh.radius = 0.4
	mesh.height = 0.8
	mesh.radial_segments = 8
	mesh.rings = 4
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	p.position.y = 0.2
	parent.add_child(p)
	return p


func _make_flame(parent: Node3D) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.25
	p.emitting = false
	p.local_coords = false
	p.direction = Vector3(0, 0, 1)
	p.spread = 8.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 9.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.8, 1.0, 1.0))
	ramp.set_color(1, Color(1.0, 0.3, 0.9, 0.0))
	p.color_ramp = ramp
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.3
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mesh.material = m
	p.mesh = mesh
	parent.add_child(p)
	return p


static func _mat(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	return m


static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
