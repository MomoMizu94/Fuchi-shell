"""Write a small JPEG data URL if the workspace stays visible throughout capture."""
import base64
import json
import subprocess
import sys


def output_scale(output, workspace_id, width):
    monitors = subprocess.check_output(["hyprctl", "-j", "monitors"], timeout=2)
    for monitor in json.loads(monitors):
        if monitor["name"] != output or monitor["activeWorkspace"]["id"] != workspace_id:
            continue
        special = monitor.get("specialWorkspace") or {}
        if special.get("name") or special.get("id") or monitor.get("disabled"):
            return None
        pixels = monitor["height"] if monitor["transform"] % 2 else monitor["width"]
        return min(1, width * monitor["scale"] / pixels)
    return None


def capture(output, workspace_id, width):
    scale = output_scale(output, workspace_id, width)
    if scale is None:
        return
    frame = subprocess.check_output(
        ["grim", "-o", output, "-s", str(scale), "-t", "jpeg", "-"], timeout=3
    )
    if output_scale(output, workspace_id, width) == scale:
        print("data:image/jpeg;base64," + base64.b64encode(frame).decode("ascii"))


if __name__ == "__main__":
    try:
        capture(sys.argv[1], int(sys.argv[2]), int(sys.argv[3]))
    except FileNotFoundError:
        sys.exit(2)
    except (subprocess.SubprocessError, ValueError, KeyError, OSError):
        sys.exit(1)
