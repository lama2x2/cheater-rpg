extends RefCounted
## Базовый класс тестов: проверки копят ошибки, а не роняют прогон.

var failures: PackedStringArray = []


func assert_eq(actual: Variant, expected: Variant, message: String = "") -> void:
	if actual != expected:
		failures.append("%s: ожидалось %s, получено %s" % [message, str(expected), str(actual)])


func assert_true(condition: bool, message: String = "") -> void:
	if not condition:
		failures.append("%s: условие ложно" % message)


func assert_almost(actual: float, expected: float, message: String = "", epsilon: float = 0.0001) -> void:
	if absf(actual - expected) > epsilon:
		failures.append("%s: ожидалось %f, получено %f" % [message, expected, actual])
