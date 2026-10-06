#!/usr/bin/env bash
# Set a wallpaper, or use --theme dark|light to recolor the current wallpaper.
# Quickshell picks up the new colors live (Colors.qml watches ~/.cache/wal/colors.json).
# Reloads Hyprland for new accent colors.
set -eu

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
mkdir -p "$state_dir"
# Wallpaper and theme requests share pywal's cache and must run in order.
exec 9>"$state_dir/theme.lock"
flock 9

mode=dark
if [[ -f "$state_dir/theme-mode" ]]; then
    mode=$(cat "$state_dir/theme-mode")
fi
if [[ "${1:-}" == --theme ]]; then
    mode="${2:-}"
    img=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["wallpaper"])' "$HOME/.cache/wal/colors.json")
else
    img="${1:?Usage: set-wallpaper.sh IMAGE | --theme dark|light}"
fi
case "$mode" in
    dark|light) ;;
    *) echo "Invalid theme: $mode. Use dark or light." >&2; exit 1 ;;
esac
img=$(realpath -e -- "$img")

if [[ "$1" != --theme ]]; then
    awww img "$img" --transition-type any
fi
python3 "$(dirname "${BASH_SOURCE[0]}")/palette.py" "$img" "$mode" > "$state_dir/palette.json"
wal -n -f "$state_dir/palette.json"
printf '%s\n' "$mode" > "$state_dir/theme-mode"
# Reload included Kitty colors too; pywal's OSC updates only cover basic colors.
if pgrep -u "$UID" -x kitty >/dev/null; then
    pkill -USR1 -u "$UID" -x kitty
fi
hyprctl reload
