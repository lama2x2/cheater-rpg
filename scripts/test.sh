#!/usr/bin/env bash
# Юнит-тесты + дымовой прогон главной сцены (300 кадров без окна).
set -euo pipefail
source "$(dirname "$0")/_godot.sh"

echo "== Юнит-тесты"
unit_log="$(mktemp)"
status=0
"$GODOT" --headless --path . -s res://tests/run_tests.gd >"$unit_log" 2>&1 || status=$?
grep -E "^  (ok|FAIL)|^        |Тестов" "$unit_log"
if [ "$status" -ne 0 ] || grep -qE "SCRIPT ERROR|Parse Error" "$unit_log"; then
  grep -A4 -E "SCRIPT ERROR|Parse Error" "$unit_log" >&2 || true
  echo "Юнит-тесты: провал (лог: $unit_log)" >&2
  exit 1
fi

echo "== Дымовой прогон сцены"
log="$(mktemp)"
"$GODOT" --headless --path . --quit-after 300 >"$log" 2>&1 || true
if grep -E "SCRIPT ERROR|ERROR:|Parse Error" "$log"; then
  echo "Дымовой прогон: есть ошибки (лог: $log)" >&2
  exit 1
fi
echo "Дымовой прогон: ок"
