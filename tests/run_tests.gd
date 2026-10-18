extends SceneTree
## Мини-раннер тестов без сторонних плагинов.
## Запуск: scripts/test.sh  (или godot --headless --path . -s res://tests/run_tests.gd)
## Находит tests/test_*.gd и вызывает каждый метод test_* на новом экземпляре.

const TESTS_DIR := "res://tests"


func _init() -> void:
	var passed := 0
	var failed := 0
	for file in DirAccess.get_files_at(TESTS_DIR):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		var script: GDScript = load(TESTS_DIR.path_join(file))
		for method in script.get_script_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			var instance: Object = script.new()
			instance.call(method_name)
			var failures: PackedStringArray = instance.get("failures")
			if failures.is_empty():
				passed += 1
				print("  ok    %s::%s" % [file, method_name])
			else:
				failed += 1
				print("  FAIL  %s::%s" % [file, method_name])
				for failure in failures:
					print("        " + failure)
	print("\nТестов пройдено: %d, упало: %d" % [passed, failed])
	quit(1 if failed > 0 else 0)
