# Общий кусок для скриптов: находит Godot и переходит в корень проекта.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
if [ ! -x "$GODOT" ]; then
  echo "Godot не найден. Установите: brew install --cask godot" >&2
  exit 1
fi
# Импорт ресурсов и кэш классов (папка .godot/): при первом запуске и если после pull появились
# скрипты новее кэша `class_name` (иначе новые классы «не найдены»).
cache=.godot/global_script_class_cache.cfg
if [ ! -f "$cache" ] || [ -n "$(find src tests -name '*.gd' -newer "$cache" -print -quit 2>/dev/null)" ]; then
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  touch "$cache" 2>/dev/null || true
fi
