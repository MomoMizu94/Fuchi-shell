#!/usr/bin/env python3
"""Query one update source and emit one JSON result. Never install packages."""

import argparse
import json
import os
import re
import signal
import subprocess
import tempfile


def parse_packages(output):
    packages = []
    seen = set()
    for line in output.splitlines():
        if not line.strip():
            continue
        fields = line.split()
        if (len(fields) < 4 or fields[2] != "->"
                or not re.fullmatch(r"[A-Za-z0-9@._+\-]+", fields[0])):
            raise ValueError("Unrecognized package output: " + line[:160])
        name, installed, _, available = fields[:4]
        # Yay 13 can append an age label after the available version.
        if name in seen:
            raise ValueError("Duplicate package in update output: " + name)
        seen.add(name)
        packages.append({"name": name, "installed": installed, "available": available})
    return sorted(packages, key=lambda package: package["name"])


def run_command(command, environment, timeout):
    with subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          stdin=subprocess.DEVNULL, text=True, errors="replace",
                          env=environment, start_new_session=True) as process:
        try:
            output, errors = process.communicate(timeout=timeout)
        finally:
            # Also stop children such as pacman/fakeroot on timeout or shell reload.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()
        return process.returncode, output, errors


def check(source, timeout):
    environment = dict(os.environ, LC_ALL="C", NO_COLOR="1", TERM="dumb")
    command = (["checkupdates", "--nocolor"] if source == "repositories" else
               ["yay", "-Qua", "--color", "never", "--devel=false"])
    try:
        # A private database avoids changing pacman's sync database and avoids
        # collisions with a terminal's checkupdates process or another shell.
        with tempfile.TemporaryDirectory(prefix="quickshell-updates-") as directory:
            if source == "repositories":
                environment["CHECKUPDATES_DB"] = directory
            code, output, errors = run_command(command, environment, timeout)

        no_updates = not output.strip() and (
            (source == "repositories" and code == 2)
            or (source == "aur" and code == 1 and not errors.strip()))
        if code != 0 and not no_updates:
            detail = errors.strip() or output.strip() or f"{command[0]} exited with code {code}"
            # AUR failures can include a URL containing every installed package.
            # Keep the endpoint and actual failure reason readable in the popup.
            detail = re.sub(r'https?://[^\s"]+', lambda match: match[0].split("?", 1)[0], detail)
            return {"ok": False, "error": detail[:600]}
        return {"ok": True, "packages": parse_packages(output)}
    except FileNotFoundError:
        package = "pacman-contrib" if source == "repositories" else "yay"
        return {"ok": False, "error": f"{command[0]} was not found. Install {package} to check this source."}
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": f"Check timed out after {timeout:g} seconds. Try Check now when connected."}
    except (OSError, ValueError) as error:
        return {"ok": False, "error": str(error)[:600]}


def interrupted(signum, frame):
    raise InterruptedError("Update check was interrupted")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", choices=("repositories", "aur"))
    parser.add_argument("--timeout", type=float, default=90)
    args = parser.parse_args()
    if not 0 < args.timeout <= 3600:
        parser.error("--timeout must be greater than zero and at most 3600 seconds")
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    print(json.dumps(check(args.source, args.timeout)), flush=True)


if __name__ == "__main__":
    main()
