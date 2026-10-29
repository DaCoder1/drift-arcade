class_name Cone
extends Area3D
## Traffic cone. Knocked flying (and worth points) when the car hits it.

signal hit(cone: Cone)

var home := Vector3.ZERO
var knocked := false
var _mesh: Node3D
var _fly_velocity := Vector3.ZERO
var _spin := Vector3.ZERO


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.6
	cyl.height = 1.2
	shape.shape = cyl
	shape.position.y = 0.6
	add_child(shape)
	body_entered.connect(_on_body_entered)

	_mesh = Node3D.new()
	add_child(_mesh)
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(1.0, 0.4, 0.05)
	orange.emission_enabled = true
	orange.emission = Color(1.0, 0.3, 0.0)
	orange.emission_energy_multiplier = 0.4
	var white := StandardMaterial3D.new()
	white.albedo_color = Color(0.95, 0.95, 0.95)

	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.32
	cm.height = 0.85
	cm.radial_segments = 12
	cone.mesh = cm
	cone.material_override = orange
	cone.position.y = 0.48
	_mesh.add_child(cone)

	var stripe := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.15
	sm.bottom_radius = 0.2
	sm.height = 0.14
	sm.radial_segments = 12
	stripe.mesh = sm
	stripe.material_override = white
	stripe.position.y = 0.58
	_mesh.add_child(stripe)

	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.06, 0.7)
	base.mesh = bm
	base.material_override = orange
	base.position.y = 0.03
	_mesh.add_child(base)
	set_process(false)


func reset() -> void:
	knocked = false
	_mesh.position = Vector3.ZERO
	_mesh.rotation = Vector3.ZERO
	_mesh.visible = true
	set_deferred("monitoring", true)
	set_process(false)


func _on_body_entered(body: Node3D) -> void:
	if knocked or not body is DriftCar:
		return
	knocked = true
	set_deferred("monitoring", false)
	var car := body as DriftCar
	var push := car.velocity * 0.7
	push.y = 6.0 + car.speed * 0.25
	_fly_velocity = push + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
	_spin = Vector3(randf_range(-12, 12), randf_range(-6, 6), randf_range(-12, 12))
	set_process(true)
	hit.emit(self)


func _process(delta: float) -> void:
	_fly_velocity.y -= 25.0 * delta
	_mesh.position += _fly_velocity * delta
	_mesh.rotation += _spin * delta
	if _mesh.position.y <= 0.0 and _fly_velocity.y < 0.0:
		# Land on its side and stay there until the next run.
		_mesh.position.y = 0.3
		_mesh.rotation = Vector3(PI / 2.0, randf() * TAU, 0.0)
		set_process(false)
