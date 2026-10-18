#!/usr/bin/env bash
# Сборка build/CheaterRPG.app (пресет «macOS» из export_presets.cfg, ad-hoc подпись).
# Нужны export templates той же версии, что и Godot (см. docs/spec/13_tech.md, 13.8).
set -euo pipefail
source "$(dirname "$0")/_godot.sh"

mkdir -p build
rm -rf build/CheaterRPG.app
"$GODOT" --headless --path . --export-release "macOS" build/CheaterRPG.app
echo "Готово: build/CheaterRPG.app"
echo "Запуск: open build/CheaterRPG.app (если macOS ругается — правый клик → «Открыть»)"
