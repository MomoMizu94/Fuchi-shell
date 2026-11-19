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
import sys
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
            json.dump(document, temporary, indent=2)
            temporary.write("\n")
        temporary_path.replace(path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def pick_and_run(state):
    from agent_core.shell_sandbox import validate_workspace_root

    projects = load_projects(state)
    start = Path.home()
    for folder in projects:
        if Path(folder).is_dir():
            start = Path(folder)
            break

    # Yazi writes its current folder on quit and skips the file when cancelled
    with tempfile.TemporaryDirectory(prefix="oceanus-yazi-") as directory:
        cwd_file = Path(directory) / "cwd"
        subprocess.run(["yazi", "--cwd-file", str(cwd_file), "--", str(start)], check=True)
        if not cwd_file.exists():
            return
        selected = os.fsdecode(cwd_file.read_bytes())
        if not selected:
            return
        if not os.path.isabs(selected):
            raise ValueError("Choose a local project folder in Yazi")
        project = validate_workspace_root(Path(selected))

    # Kitty starts this helper directly, so the parent PID identifies this picker
    require_ok(hyprctl("dispatch", f'hl.dsp.window.float({{action="unset",window="pid:{os.getppid()}"}})'))
    os.chdir(project)
    try:
        with state.with_suffix(".lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            remember_project(state, project, load_projects(state))
    except OSError as error:
        print(f"Could not save Oceanus project history: {error}", file=sys.stderr, flush=True)
    os.environ.setdefault("LITELLM_LOCAL_MODEL_COST_MAP", "True")
    # Keep the picker alive so Kitty can show errors if the TUI exits early
    subprocess.run([sys.executable, "-P", "-m", "agent_core.tui"], check=True)


def launch(state, python):
    # Resolving the Python symlink would bypass the virtual environment
    python = python.expanduser().absolute()
    if not python.is_file() or not os.access(python, os.X_OK):
        raise ValueError(f"Oceanus Python was not found at {python}. Set oceanus.python in config.js.")
    for executable in ("kitty", "yazi"):
        if shutil.which(executable) is None:
            raise RuntimeError(f"Install {executable} to open Oceanus")

    app_id = WINDOW_PREFIX + uuid4().hex
    # A relative PYTHONPATH would follow Yazi into the selected project
    command = [
        "kitty", "--class", app_id, "--title", "Oceanus", "--directory", str(Path.home()),
        "env", "-u", "PYTHONPATH", str(python), "-P", str(Path(__file__).resolve()),
        "pick", "--state", str(state),
    ]
    shell_command = "exec " + shlex.join(command)
    delimiter = "="
    while "]" + delimiter + "]" in shell_command:
        delimiter += "="
    lua_string = "[" + delimiter + "[" + shell_command + "]" + delimiter + "]"
    # Hyprland owns the process, so a shell reload cannot terminate the task
    picker_rules = '{float=true,center=true,size={"monitor_w*0.7","monitor_h*0.7"}}'
    require_ok(hyprctl("eval", f"hl.exec_cmd({lua_string}, {picker_rules})"))
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        for window in oceanus_windows():
            if (window.get("initialClass") or window.get("class")) == app_id:
                return
        time.sleep(0.1)
    raise RuntimeError("Oceanus was launched, but its window has not appeared. "
                       "Check for an Oceanus window before trying again.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["open", "new", "pick"])
    parser.add_argument("--state", type=Path, required=True)
    parser.add_argument("--python", type=Path)
    arguments = parser.parse_args()
    state = arguments.state.absolute()
    try:
        state.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        if arguments.action == "pick":
            pick_and_run(state)
        else:
            with state.with_suffix(".lock").open("a") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                if arguments.action == "open" and focus_existing():
                    return 0
                if arguments.python is None:
                    parser.error("Opening a window requires --python")
                launch(state, arguments.python)
    except (OSError, ValueError, RuntimeError, ImportError, subprocess.SubprocessError) as error:
        print(f"Could not open Oceanus: {error}", file=sys.stderr, flush=True)
        if arguments.action == "pick" and sys.stdin.isatty():
            input("Press Enter to close. ")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
