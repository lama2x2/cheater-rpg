extends Camera3D
## Изометрическая ортографическая камера, следует за целью. Колесо мыши — зум.

const ISO_PITCH := -35.264
const ISO_YAW := 45.0
const DISTANCE := 40.0
const ZOOM_MIN := 10.0
const ZOOM_MAX := 40.0
const ZOOM_STEP := 2.0

var target: Node3D
var follow_speed: float = 8.0


func _ready() -> void:
	projection = PROJECTION_ORTHOGONAL
	size = 22.0
	near = 0.1
	far = 200.0
	rotation_degrees = Vector3(ISO_PITCH, ISO_YAW, 0.0)
	current = true
	if target:
		global_position = _desired_position()


func _process(delta: float) -> void:
	if target == null:
		return
	global_position = global_position.lerp(_desired_position(), clampf(follow_speed * delta, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	var wheel := event as InputEventMouseButton
	if wheel == null or not wheel.pressed:
		return
	if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
		size = clampf(size - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		size = clampf(size + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)


func _desired_position() -> Vector3:
	return target.global_position + global_transform.basis.z * DISTANCE
