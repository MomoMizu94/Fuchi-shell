#!/bin/sh
# Use the optional local environment, or distro-installed Python/Bleak.
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ -x "$root/.venv-hue/bin/python" ]; then
    exec "$root/.venv-hue/bin/python" -u "$root/scripts/hue.py" "$@"
fi
exec python3 -u "$root/scripts/hue.py" "$@"
