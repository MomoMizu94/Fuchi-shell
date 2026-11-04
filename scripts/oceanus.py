"""Launch or focus Oceanus without tying its lifetime to Quickshell"""

import argparse
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import tempfile
import time
from uuid import uuid4


WINDOW_PREFIX = "fuchi-oceanus-"


def hyprctl(*arguments):
    result = subprocess.run(
        ["hyprctl", *arguments], capture_output=True, text=True, timeout=10,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not connect to Hyprland")
    return result.stdout.strip()


def require_ok(reply):
    if reply != "ok":
        raise RuntimeError("Hyprland rejected the request: " + reply)


def oceanus_windows():
    clients = json.loads(hyprctl("-j", "clients"))
    if not isinstance(clients, list):
        raise ValueError("Hyprland returned an invalid window list")
    windows = []
    for client in clients:
        app_id = client.get("initialClass") or client.get("class", "")
        address = client.get("address", "")
        if app_id.startswith(WINDOW_PREFIX) and re.fullmatch(r"0x[0-9a-fA-F]+", address):
            windows.append(client)
    return windows


def focus_existing():
    windows = oceanus_windows()
    if not windows:
        return False

    def focus_order(window):
        order = window.get("focusHistoryID", -1)
        return order if isinstance(order, int) and order >= 0 else float("inf")

    window = min(windows, key=focus_order)
    address = window["address"]
    require_ok(hyprctl("dispatch", f'hl.dsp.focus({{window="address:{address}"}})'))
    return True


def load_projects(path):
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return []
    if not isinstance(document, dict) or document.get("version") != 1:
        raise ValueError(f"Invalid Oceanus project history: {path}")
    projects = document.get("projects")
    if not isinstance(projects, list) or any(
        not isinstance(project, str) or not project.startswith("/") or "\x00" in project
        for project in projects
    ):
        raise ValueError(f"Invalid Oceanus project history: {path}")
    return projects[:12]


def remember_project(path, project, projects):
    recent = [str(project)]
    recent.extend(item for item in projects if item != str(project))
    document = {"version": 1, "projects": recent[:12]}
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=".oceanus-", delete=False) as temporary:
            temporary_path = Path(temporary.name)
            json.dump(document, temporary, ensure_ascii=False, indent=2)
            temporary.write("\n")
        temporary_path.replace(path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def launch(project, python):
    project = project.expanduser().resolve(strict=True)
    if not project.is_dir():
        raise ValueError(f"Project is not a folder: {project}")
    # Keep the venv executable path; resolving its symlink loses the venv
    python = python.expanduser().absolute()
    if not python.is_file() or not os.access(python, os.X_OK):
        raise ValueError(f"Oceanus Python was not found at {python}. Set oceanus.python in config.js.")
    if shutil.which("kitty") is None:
        raise RuntimeError("Kitty is required to open Oceanus")

    environment = dict(os.environ)
    environment.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
    # Reuse Oceanus's workspace rules before opening an unusable terminal
    check = subprocess.run(
        [str(python), "-P", "-c", "from pathlib import Path; "
         "from agent_core.shell_sandbox import validate_workspace_root; "
         "validate_workspace_root(Path.cwd()); "
         "from agent_core.tui import OceanusApp"],
        cwd=project, env=environment, capture_output=True, text=True, timeout=30,
    )
    if check.returncode:
        lines = check.stderr.strip().splitlines()
        reason = lines[-1] if lines else f"Python exited with status {check.returncode}"
        raise RuntimeError("Oceanus could not start in this project: " + reason)

    app_id = WINDOW_PREFIX + uuid4().hex
    command = ["kitty", "--class", app_id, "--title", "Oceanus", "--directory", str(project),
               "-o", "remember_window_size=no", "-o", "initial_window_width=1200",
               "-o", "initial_window_height=820", "env",
               "LITELLM_LOCAL_MODEL_COST_MAP=" + environment["LITELLM_LOCAL_MODEL_COST_MAP"],
               str(python), "-P", "-m", "agent_core.tui"]
    shell_command = "exec " + shlex.join(command)
    delimiter = "="
    while "]" + delimiter + "]" in shell_command:
        delimiter += "="
    lua_string = "[" + delimiter + "[" + shell_command + "]" + delimiter + "]"
    # Hyprland owns the process, so a shell reload cannot terminate the task
    require_ok(hyprctl("eval", "hl.exec_cmd(" + lua_string
                      + ', {float=true, center=true, size={"min(1200,monitor_w*0.9)",'
                      + '"min(820,monitor_h*0.9)"}})'))
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        for window in oceanus_windows():
            if (window.get("initialClass") or window.get("class")) == app_id:
                return project
        time.sleep(0.1)
    raise RuntimeError("Oceanus was launched, but its window has not appeared. "
                       "Check for an Oceanus window before trying again.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["open", "projects", "launch"])
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--project", type=Path)
    parser.add_argument("--python", type=Path)
    arguments = parser.parse_args()
    try:
        arguments.state.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock_path = arguments.state.with_suffix(".lock")
        with lock_path.open("a") as lock:
            # Serialize launch and focus across shell reloads
            fcntl.flock(lock, fcntl.LOCK_EX)
            if arguments.action == "open" and focus_existing():
                result = {"focused": True}
            else:
                projects = load_projects(arguments.state)
                result = {"focused": False, "projects": projects}
                if arguments.action == "launch":
                    if arguments.project is None or arguments.python is None:
                        raise ValueError("Launching requires a project and an Oceanus Python executable")
                    project = launch(arguments.project, arguments.python)
                    result = {"launched": True}
                    try:
                        remember_project(arguments.state, project, projects)
                    except OSError as error:
                        result["warning"] = f"Oceanus opened, but project history could not be saved: {error}"
        print(json.dumps({"ok": True, **result}))
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(json.dumps({"ok": False, "error": str(error)}))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
