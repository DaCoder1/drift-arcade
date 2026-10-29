class_name ChaseCamera
extends Camera3D
## Third-person chase camera. It follows a blend of the car's heading and its
## direction of travel, so you can see the car sliding sideways in a drift.
## In orbit mode (menus) it slowly circles the car.

var target: DriftCar
var orbit_mode := true

var _yaw := 0.0
var _orbit_angle := 0.0
var _shake := 0.0


func _ready() -> void:
	fov = 70.0
	far = 600.0


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 1.2)


func snap() -> void:
	if target == null:
		return
	_yaw = target.rotation.y
	global_position = _desired_position(8.5)
	look_at(target.global_position + Vector3.UP, Vector3.UP)


func _physics_process(delta: float) -> void:
	if target == null:
		return
	if orbit_mode:
		_orbit_angle += delta * 0.25
		var p := target.global_position + Vector3(cos(_orbit_angle) * 11.0, 4.0, sin(_orbit_angle) * 11.0)
		global_position = global_position.lerp(p, 1.0 - exp(-3.0 * delta))
		look_at(target.global_position + Vector3.UP * 0.8, Vector3.UP)
		fov = lerpf(fov, 60.0, 1.0 - exp(-3.0 * delta))
		return

	var heading := target.rotation.y
	var desired := heading
	var v := target.velocity
	if target.forward_speed > 4.0:
		var vel_yaw := atan2(-v.x, -v.z)
		desired = lerp_angle(heading, vel_yaw, 0.6)
	_yaw = lerp_angle(_yaw, desired, 1.0 - exp(-4.0 * delta))

	var speed_ratio := clampf(target.speed / target.top_speed, 0.0, 1.5)
	global_position = global_position.lerp(_desired_position(8.0 + speed_ratio * 2.0), 1.0 - exp(-10.0 * delta))
	var fwd := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	look_at(target.global_position + Vector3.UP * 1.0 + fwd * 4.0, Vector3.UP)

	var target_fov := 68.0 + speed_ratio * 12.0 + (8.0 if target.boosting else 0.0)
	fov = lerpf(fov, target_fov, 1.0 - exp(-3.0 * delta))

	_shake = maxf(_shake - delta * 2.5, 0.0)
	var s := _shake * _shake * 0.6
	h_offset = randf_range(-s, s)
	v_offset = randf_range(-s, s)


func _desired_position(distance: float) -> Vector3:
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	return target.global_position + back * distance + Vector3.UP * 3.6
