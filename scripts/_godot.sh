# Общий кусок для скриптов: находит Godot и переходит в корень проекта.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
if [ ! -x "$GODOT" ]; then
  echo "Godot не найден. Установите: brew install --cask godot" >&2
  exit 1
fi
# Первый запуск: импорт ресурсов и кэш классов (папка .godot/).
if [ ! -d .godot ]; then
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
