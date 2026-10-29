class_name Pickup
extends Area3D
## Coins and power-ups. Emits `collected` when the car drives through.

signal collected(pickup: Pickup)

enum Kind { COIN, NITRO, DOUBLE, TIME, MAGNET, SHIELD }

const INFO := {
	Kind.NITRO: {"name": "NITRO", "label": "N", "color": Color(0.2, 0.6, 1.0), "weight": 3},
	Kind.DOUBLE: {"name": "2X SCORE", "label": "2X", "color": Color(1.0, 0.8, 0.1), "weight": 2},
	Kind.TIME: {"name": "+TIME", "label": "+T", "color": Color(0.3, 1.0, 0.4), "weight": 2},
	Kind.MAGNET: {"name": "MAGNET", "label": "M", "color": Color(1.0, 0.25, 0.35), "weight": 2},
	Kind.SHIELD: {"name": "SHIELD", "label": "S", "color": Color(0.3, 1.0, 1.0), "weight": 1},
}
const POWERUP_LIFETIME := 16.0

var kind := Kind.COIN
var _visual: Node3D
var _t := 0.0
var _life := -1.0
var _taken := false


static func random_powerup_kind() -> Kind:
	var total := 0
	for k in INFO:
		total += int(INFO[k]["weight"])
	var roll := randi() % total
	for k in INFO:
		roll -= int(INFO[k]["weight"])
		if roll < 0:
			return k
	return Kind.NITRO


func setup(k: Kind) -> void:
	kind = k
	_t = randf() * TAU
	collision_layer = 0
	collision_mask = 2
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.1 if kind == Kind.COIN else 1.6
	shape.shape = sphere
	shape.position.y = 1.0
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_visual = Node3D.new()
	_visual.position.y = 1.0
	add_child(_visual)
	if kind == Kind.COIN:
		_build_coin()
	else:
		_life = POWERUP_LIFETIME
		_build_powerup()


func is_coin() -> bool:
	return kind == Kind.COIN


func display_name() -> String:
	return "COIN" if kind == Kind.COIN else String(INFO[kind]["name"])


func color() -> Color:
	if kind == Kind.COIN:
		return Color(1.0, 0.85, 0.2)
	return INFO[kind]["color"]


func _process(delta: float) -> void:
	_t += delta
	_visual.rotation.y += delta * (3.0 if kind == Kind.COIN else 1.5)
	_visual.position.y = 1.0 + sin(_t * 3.0) * 0.15
	if _life > 0.0:
		_life -= delta
		_visual.visible = _life > 3.0 or fmod(_life, 0.3) > 0.15
		if _life <= 0.0:
			queue_free()


func _on_body_entered(body: Node3D) -> void:
	if _taken or not body is DriftCar:
		return
	_taken = true
	collected.emit(self)
	queue_free()


func _build_coin() -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.55
	cyl.bottom_radius = 0.55
	cyl.height = 0.12
	cyl.radial_segments = 20
	mi.mesh = cyl
	mi.rotation.x = PI / 2.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.8, 0.15)
	m.metallic = 0.9
	m.roughness = 0.25
	m.emission_enabled = true
	m.emission = Color(1.0, 0.65, 0.0)
	m.emission_energy_multiplier = 0.8
	mi.material_override = m
	_visual.add_child(mi)


func _build_powerup() -> void:
	var c: Color = INFO[kind]["color"]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 2.0

	var core := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	core.mesh = box
	core.rotation = Vector3(PI / 4.0, 0.0, PI / 4.0)
	core.material_override = m
	_visual.add_child(core)

	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.2
	torus.outer_radius = 1.35
	ring.mesh = torus
	ring.material_override = m
	ring.rotation.x = PI / 2.0
	_visual.add_child(ring)

	var label := Label3D.new()
	label.text = String(INFO[kind]["label"])
	label.font_size = 96
	label.outline_size = 24
	label.modulate = Color.WHITE
	label.outline_modulate = c.darkened(0.6)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position.y = 2.6
	add_child(label)

	var light := OmniLight3D.new()
	light.light_color = c
	light.light_energy = 2.5
	light.omni_range = 6.0
	light.position.y = 1.0
	add_child(light)
