#!/usr/bin/env bash
# Запуск игры.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
exec "$GODOT" --path . "$@"
