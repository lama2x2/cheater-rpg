#!/usr/bin/env bash
# Юнит-тесты + дымовой прогон главной сцены (300 кадров без окна).
set -euo pipefail
source "$(dirname "$0")/_godot.sh"

echo "== Юнит-тесты"
"$GODOT" --headless --path . -s res://tests/run_tests.gd

echo "== Дымовой прогон сцены"
log="$(mktemp)"
"$GODOT" --headless --path . --quit-after 300 >"$log" 2>&1 || true
if grep -E "SCRIPT ERROR|ERROR:|Parse Error" "$log"; then
  echo "Дымовой прогон: есть ошибки (лог: $log)" >&2
  exit 1
fi
echo "Дымовой прогон: ок"
