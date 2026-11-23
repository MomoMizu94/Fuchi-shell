"""Check which monitor frames can be assigned to a workspace."""
import contextlib
import io
import json
import runpy
import unittest
from pathlib import Path
from unittest.mock import patch


capture = runpy.run_path(str(Path(__file__).resolve().parents[1] / "scripts/workspace-preview.py"))["capture"]


def monitor(workspace, special=None, transform=0):
    return json.dumps([{
        "name": "DP-1", "activeWorkspace": {"id": workspace},
        "specialWorkspace": special or {}, "scale": 1.5, "transform": transform,
        "width": 1920, "height": 1080,
    }]).encode()


class WorkspacePreviewTest(unittest.TestCase):
    def run_capture(self, responses):
        with patch("subprocess.check_output", side_effect=responses) as command:
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                capture("DP-1", 2, 320)
            return output.getvalue(), command.call_args_list

    def test_rotated_scaled_output(self):
        state = monitor(2, transform=1)
        image, calls = self.run_capture([state, b"frame", state])
        self.assertTrue(image.startswith("data:image/jpeg;base64,"))
        args = calls[1].args[0]
        self.assertEqual(args[args.index("-o") + 1], "DP-1")
        self.assertAlmostEqual(float(args[args.index("-s") + 1]), 320 * 1.5 / 1080)

    def test_skip_inactive_or_special_workspace(self):
        for state in (monitor(3), monitor(2, {"name": "special:magic"})):
            with self.subTest(state=state):
                image, calls = self.run_capture([state])
                self.assertEqual(image, "")
                self.assertEqual(len(calls), 1)

    def test_switch_during_capture_discards_frame(self):
        for changed in (monitor(1), monitor(2, {"id": -99}), b"[]"):
            with self.subTest(changed=changed):
                image, _ = self.run_capture([monitor(2), b"frame", changed])
                self.assertEqual(image, "")
