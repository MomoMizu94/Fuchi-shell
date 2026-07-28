#!/usr/bin/env bash
# Set wallpaper via awww (with a transition) and regenerate the pywal palette.
# Quickshell picks up the new colors live (Colors.qml watches ~/.cache/wal/colors.json).
# Reloads hyprlctl for new accent colors.
set -eu

img="$(realpath "$1")"

awww img "$img" --transition-type any
wal -n --saturate 0.6 -i "$img"
hyprctl reload
