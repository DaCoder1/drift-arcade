class_name SkidMarks
extends MultiMeshInstance3D
## Tire marks drawn as a ring buffer of flat quads in a single MultiMesh.

const MAX_MARKS := 4000
const MIN_SEGMENT := 0.25

var _next := 0
var _last := {}


func _ready() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2(0.3, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.02, 0.02, 0.02, 0.6)
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = 0
	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Extends the trail identified by `key` to `pos`.
func add_point(key: Object, pos: Vector3) -> void:
	pos.y = 0.0
	if not _last.has(key):
		_last[key] = pos
		return
	var from: Vector3 = _last[key]
	var d := pos - from
	var length := d.length()
	if length < MIN_SEGMENT:
		return
	_last[key] = pos
	if length > 4.0:
		return
	var basis := Basis.looking_at(d / length, Vector3.UP) * Basis.from_scale(Vector3(1.0, 1.0, length))
	var mid := (from + pos) * 0.5
	mid.y = 0.02
	multimesh.set_instance_transform(_next, Transform3D(basis, mid))
	_next = (_next + 1) % MAX_MARKS
	multimesh.visible_instance_count = mini(multimesh.visible_instance_count + 1, MAX_MARKS)


func break_trail(key: Object) -> void:
	_last.erase(key)


func clear_marks() -> void:
	_last.clear()
	_next = 0
	multimesh.visible_instance_count = 0
