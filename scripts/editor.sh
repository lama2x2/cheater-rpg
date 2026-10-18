#!/usr/bin/env bash
# Открыть проект в редакторе Godot.
set -euo pipefail
source "$(dirname "$0")/_godot.sh"
exec "$GODOT" -e --path . "$@"
