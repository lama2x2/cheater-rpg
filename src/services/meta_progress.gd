class_name MetaProgress
extends RefCounted
## Знание между играми (11.4a, 16.1): пройденные кампании — карточки отмечаются «пройдено».
## user://meta.json, не в сейве партии.

const PATH := "user://meta.json"


static func _load() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return data if data is Dictionary else {}


static func completed(campaign: String) -> bool:
	return (_load().get("completed_campaigns", []) as Array).has(campaign)


static func complete(campaign: String) -> void:
	var data := _load()
	var list: Array = data.get("completed_campaigns", [])
	if list.has(campaign):
		return
	list.append(campaign)
	data["completed_campaigns"] = list
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
