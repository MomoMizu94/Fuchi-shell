"""Check update parsing and process failures without contacting package servers."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("check_updates", REPO / "scripts/check-updates.py")
updates = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updates)


class UpdateCheckTests(unittest.TestCase):
    def result(self, source, code, output="", errors=""):
        with patch.object(updates, "run_command", return_value=(code, output, errors)):
            return updates.check(source, 90)

    def test_versions_epochs_age_labels_and_sorting(self):
        result = self.result("aur", 0, "z-git 1:r12-1 -> 1:r13-1 [2 days old]\na-bin 2-1 -> 3-1\n")
        self.assertTrue(result["ok"])
        self.assertEqual(result["packages"], [
            {"name": "a-bin", "installed": "2-1", "available": "3-1"},
            {"name": "z-git", "installed": "1:r12-1", "available": "1:r13-1"},
        ])

    def test_empty_exit_statuses_are_source_specific(self):
        for source, code in [("repositories", 2), ("aur", 1), ("aur", 0), ("repositories", 0)]:
            self.assertEqual(self.result(source, code), {"ok": True, "packages": []})
        for source, code in [("repositories", 1), ("aur", 2), ("aur", -11)]:
            self.assertFalse(self.result(source, code)["ok"])

    def test_errors_and_partial_failed_output_are_not_empty_successes(self):
        self.assertEqual(self.result("aur", 1, errors="AUR request failed")["error"], "AUR request failed")
        self.assertFalse(self.result("aur", 1, "foo 1 -> 2\n")["ok"])
        self.assertFalse(self.result("repositories", 2, "foo 1 -> 2\n")["ok"])
        self.assertFalse(self.result("repositories", 1, errors="Cannot fetch updates")["ok"])

    def test_malformed_or_duplicate_rows_fail_instead_of_hiding_updates(self):
        for output in ["unexpected output", "foo 1 ->", "foo 1 -> 2\nfoo 1 -> 2\n"]:
            self.assertFalse(self.result("aur", 0, output)["ok"])

    def test_large_aur_error_urls_do_not_hide_the_failure_reason(self):
        message = 'request failed: Get "https://aur.archlinux.org/rpc?' + "arg=example&" * 100 + '": network unreachable'
        result = self.result("aur", 1, errors=message)
        self.assertIn("https://aur.archlinux.org/rpc", result["error"])
        self.assertIn("network unreachable", result["error"])
        self.assertNotIn("arg=example", result["error"])

    def test_missing_command_has_actionable_message(self):
        with patch.object(updates, "run_command", side_effect=FileNotFoundError):
            self.assertIn("pacman-contrib", updates.check("repositories", 90)["error"])
            self.assertIn("Install yay", updates.check("aur", 90)["error"])

    def test_commands_cannot_install_and_repository_database_is_private(self):
        calls = []
        def run(command, environment, timeout):
            calls.append((command, environment.copy()))
            if command[0] == "checkupdates":
                database = Path(environment["CHECKUPDATES_DB"])
                self.assertTrue(database.is_dir())
                self.assertNotEqual(str(database), "/var/lib/pacman")
            return 0, "", ""
        with patch.object(updates, "run_command", side_effect=run):
            updates.check("repositories", 90)
            updates.check("aur", 90)
        self.assertEqual(calls[0][0], ["checkupdates", "--nocolor"])
        self.assertEqual(calls[1][0], ["yay", "-Qua", "--color", "never", "--devel=false"])
        self.assertEqual(calls[0][1]["LC_ALL"], "C")
        self.assertFalse(Path(calls[0][1]["CHECKUPDATES_DB"]).exists())

    def test_timeout_kills_child_processes(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = str(Path(directory) / "child.pid")
            code = """import subprocess, sys, time
child = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(60)'])
open(sys.argv[1], 'w').write(str(child.pid))
time.sleep(60)
"""
            with self.assertRaises(subprocess.TimeoutExpired):
                updates.run_command([sys.executable, "-c", code, marker], os.environ.copy(), 0.3)
            pid = Path(marker).read_text()
            status = Path("/proc") / pid / "stat"
            if status.exists():
                self.assertEqual(status.read_text().split()[2], "Z", "child must be stopped")

    def test_timeout_becomes_a_retryable_failure(self):
        with patch.object(updates, "run_command", side_effect=subprocess.TimeoutExpired("yay", 2)):
            result = updates.check("aur", 2)
            self.assertFalse(result["ok"])
            self.assertIn("timed out after 2 seconds", result["error"])


if __name__ == "__main__":
    unittest.main()
