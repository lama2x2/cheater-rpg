extends Node
## Срез здания (D-102, 17.3): пока герой внутри здания, его стены, обращённые к камере,
## срезаются до цоколя (cutaway_m) — видно всю планировку, проходы и пол; дальние стены — полной
## высоты. Коллизии не меняются (стены по-прежнему держат). Стены зданий — area.building_walls.

const CHECK_S := 0.1
const INSIDE_MARGIN := 0.2

var area: Node3D
var hero: Node3D
var _current := -1
var _left := 0.0
## Срезанные меши: {меш: [исходная позиция, исходный масштаб]}.
var _cut: Dictionary = {}


func _ready() -> void:
	add_to_group("building_cutaway")


func _exit_tree() -> void:
	_restore()


func current_building() -> int:
	return _current


func _process(delta: float) -> void:
	_left -= delta
	if _left > 0.0 or area == null or hero == null:
		return
	_left = CHECK_S
	var found := -1
	if hero.visible:
		var at := Vector2(hero.global_position.x, hero.global_position.z)
		for i in area.building_walls.size():
			var rect: Rect2 = area.building_walls[i]["rect"]
			if rect.grow(-INSIDE_MARGIN).has_point(at):
				found = i
				break
	if found == _current:
		return
	_restore()
	_current = found
	if found >= 0:
		_apply(area.building_walls[found])


func _apply(record: Dictionary) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var sides := VisionRules.camera_sides(-camera.global_transform.basis.z)
	var cut_to := float(Content.vision_rules().config()["cutaway_m"])
	for wall: Dictionary in record["walls"]:
		if not sides.has(String(wall["side"])):
			continue
		for child in (wall["body"] as Node).find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			if mesh == null:
				continue
			var box := mesh.mesh as BoxMesh
			if box == null:
				continue
			_cut[mesh] = [mesh.position, mesh.scale]
			var bottom := mesh.position.y - box.size.y / 2.0
			if bottom >= cut_to:
				mesh.visible = false  # перемычка над дверью — целиком
				continue
			var keep := cut_to - bottom
			mesh.scale.y = keep / box.size.y
			mesh.position.y = bottom + keep / 2.0


func _restore() -> void:
	for mesh: MeshInstance3D in _cut:
		if is_instance_valid(mesh):
			mesh.position = _cut[mesh][0]
			mesh.scale = _cut[mesh][1]
			mesh.visible = true
	_cut.clear()
	_current = -1
