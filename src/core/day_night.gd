class_name DayNight
extends RefCounted
## День и ночь (задача 19): освещение по игровому часу — плавно между ключевыми точками.
## Чистые правила; применение к солнцу и окружению — src/world/day_night_light.gd.
## Данные — data/daynight.json.

var _keys: Array = []


func _init(config: Dictionary) -> void:
	_keys = config["keys"]


## Освещение в час hour (0..24, дробный): {"sun", "sun_color", "pitch", "ambient", "ambient_color", "bg"}.
func at(hour: float) -> Dictionary:
	var h := fposmod(hour, 24.0)
	for i in range(_keys.size() - 1):
		var a: Dictionary = _keys[i]
		var b: Dictionary = _keys[i + 1]
		if h >= float(a["h"]) and h <= float(b["h"]):
			var t := (h - float(a["h"])) / maxf(float(b["h"]) - float(a["h"]), 0.0001)
			return {
				"sun": lerpf(float(a["sun"]), float(b["sun"]), t),
				"sun_color": _c(a["sun_color"]).lerp(_c(b["sun_color"]), t),
				"pitch": lerpf(float(a["pitch"]), float(b["pitch"]), t),
				"ambient": lerpf(float(a["ambient"]), float(b["ambient"]), t),
				"ambient_color": _c(a["ambient_color"]).lerp(_c(b["ambient_color"]), t),
				"bg": _c(a["bg"]).lerp(_c(b["bg"]), t),
			}
	return at(0.0)


static func _c(v: Array) -> Color:
	return Color(float(v[0]), float(v[1]), float(v[2]))
