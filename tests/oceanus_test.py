import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import oceanus


class ProjectPickerTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.state = self.root / "projects.json"
        self.project = self.root / "Ocean's project "
        self.project.mkdir()
        self.sandbox = Mock()
        self.sandbox.validate_workspace_root.side_effect = Path.resolve
        self.enterContext(patch.dict(sys.modules, {"agent_core.shell_sandbox": self.sandbox}))
        self.run = self.enterContext(patch.object(oceanus.subprocess, "run"))
        self.hyprctl = self.enterContext(patch.object(oceanus, "hyprctl", return_value="ok"))
        self.enterContext(patch.dict(os.environ))
        self.addCleanup(os.chdir, Path.cwd())

    def choose_project(self, command, *, check):
        self.assertTrue(check)
        if command[0] != "yazi":
            self.assertEqual(command, [sys.executable, "-P", "-m", "agent_core.tui"])
            return
        self.assertEqual(command[:2], ["yazi", "--cwd-file"])
        self.assertEqual(command[3:], ["--", str(self.start)])
        Path(command[2]).write_bytes(os.fsencode(self.project))

    def test_launch_in_selected_folder_and_skip_missing_recent_folder(self):
        self.start = self.root
        recent = [str(self.root / "removed"), str(self.start)]
        self.state.write_text(json.dumps({"version": 1, "projects": recent}))
        self.run.side_effect = self.choose_project
        oceanus.pick_and_run(self.state)
        self.assertEqual(Path.cwd(), self.project)
        self.sandbox.validate_workspace_root.assert_called_once_with(self.project)
        self.hyprctl.assert_called_once_with(
            "dispatch", f'hl.dsp.window.float({{action="unset",window="pid:{os.getppid()}"}})'
        )
        self.assertEqual(self.run.call_count, 2)
        self.assertEqual(oceanus.load_projects(self.state), [str(self.project), *recent])

    def test_cancel_first_launch(self):
        oceanus.pick_and_run(self.state)
        self.run.assert_called_once()
        self.assertEqual(self.run.call_args.args[0][-1], str(Path.home()))
        self.hyprctl.assert_not_called()
        self.assertFalse(self.state.exists())

    def test_rejected_workspace_keeps_history(self):
        self.start = self.root
        oceanus.remember_project(self.state, self.start, [])
        self.run.side_effect = self.choose_project
        self.sandbox.validate_workspace_root.side_effect = PermissionError("protected workspace")
        with self.assertRaises(PermissionError):
            oceanus.pick_and_run(self.state)
        self.run.assert_called_once()
        self.hyprctl.assert_not_called()
        self.assertEqual(oceanus.load_projects(self.state), [str(self.start)])


class InterpreterHandoffTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        root = Path(directory.name)
        self.project = root / "project"
        self.project.mkdir()
        self.python = sys._base_executable
        self.env = dict(os.environ, HOME=str(root), PYTHONUSERBASE=str(root / "user"),
                        PATH=str(root) + os.pathsep + os.environ["PATH"])
        self.env["PYTHONPATH"] = "."
        for name in ("PYTHONNOUSERSITE", "PYTHONHOME"):
            self.env.pop(name, None)
        site = subprocess.check_output([self.python, "-m", "site", "--user-site"],
                                       env=self.env, text=True).strip()
        package = Path(site) / "agent_core"
        package.mkdir(parents=True)
        (package / "__init__.py").touch()
        (package / "shell_sandbox.py").write_text("def validate_workspace_root(path): return path\n")
        self.tui = package / "tui.py"
        for executable, body in {
            "yazi": 'printf %s "$HOME/project" > "$2"',
            "hyprctl": "echo ok",
        }.items():
            path = root / executable
            path.write_text("#!/bin/sh\n" + body + "\n")
            path.chmod(0o700)
        # Run the child command that the launcher actually passes to Kitty
        token = uuid4()
        window = {"initialClass": oceanus.WINDOW_PREFIX + token.hex}
        with (
            patch.object(oceanus, "uuid4", return_value=token),
            patch.object(oceanus, "hyprctl", return_value="ok"),
            patch.object(oceanus, "oceanus_windows", return_value=[window]),
            patch.object(oceanus.shutil, "which", return_value="/usr/bin/test-tool"),
            patch.object(oceanus.shlex, "join", wraps=oceanus.shlex.join) as join,
        ):
            oceanus.launch(root / "state.json", Path(self.python))
        kitty_command = join.call_args.args[0]
        child_start = kitty_command.index("--directory") + 2
        self.command = kitty_command[child_start:]

    def test_user_site_runs_without_importing_from_selected_project(self):
        (self.project / "agent_core.py").write_text("raise AssertionError('imported from project')\n")
        self.tui.write_text("from pathlib import Path\nprint(Path.cwd())\n")
        result = subprocess.run(self.command, env=self.env, cwd=self.project, capture_output=True,
                                text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(self.project))

    def test_missing_dependency_shows_error_and_waits_for_enter(self):
        self.tui.write_text("import missing_oceanus_test_dependency\n")
        master, terminal = os.openpty()
        self.addCleanup(os.close, master)
        self.addCleanup(os.close, terminal)
        with subprocess.Popen(self.command, env=self.env, stdin=terminal,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE) as picker:
            try:
                readable, _, _ = select.select([picker.stdout], [], [], 10)
                self.assertTrue(readable, "Timed out waiting for the picker prompt")
                self.assertIn(b"Press Enter to close", os.read(picker.stdout.fileno(), 256))
                self.assertIsNone(picker.poll())
                os.write(master, b"\n")
                _, errors = picker.communicate(timeout=5)
                self.assertNotEqual(picker.returncode, 0)
                self.assertIn(b"No module named 'missing_oceanus_test_dependency'", errors)
            finally:
                if picker.poll() is None:
                    picker.kill()


if __name__ == "__main__":
    unittest.main()
