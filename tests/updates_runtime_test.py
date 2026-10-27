"""Run the real update service and popup with fake package commands, offscreen."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class UpdatesRuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qs-updates-test-")
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        (self.directory / "source").symlink_to(REPO, target_is_directory=True)
        (self.directory / "run").mkdir(mode=0o700)
        (self.directory / "bin").mkdir()
        self.fixture = self.directory / "results.json"
        self.log = self.directory / "calls.jsonl"
        self.fixture.write_text(json.dumps({
            "checkupdates": {"code": 0, "out": "linux 6.1-1 -> 6.2-1\n"},
            "yay": {"code": 0, "out": "example-bin 1-1 -> 2-1\n"},
        }))
        mock = f"#!{sys.executable}\n" + '''import json, os, pathlib, sys, time
name = pathlib.Path(sys.argv[0]).name
with open(os.environ["UPDATE_TEST_LOG"], "a") as log:
    log.write(json.dumps([name] + sys.argv[1:]) + "\\n")
result = json.loads(pathlib.Path(os.environ["UPDATE_TEST_RESULTS"]).read_text())[name]
time.sleep(result.get("delay", 0.08))
print(result.get("out", ""), end="", flush=True)
print(result.get("err", ""), end="", file=sys.stderr, flush=True)
sys.exit(result.get("code", 0))
'''
        for name in ["checkupdates", "yay"]:
            path = self.directory / "bin" / name
            path.write_text(mock)
            path.chmod(0o755)
        self.environment = dict(os.environ,
            QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
            XDG_RUNTIME_DIR=str(self.directory / "run"),
            XDG_STATE_HOME=str(self.directory / "state"),
            XDG_CACHE_HOME=str(self.directory / "cache"),
            UPDATE_TEST_RESULTS=str(self.fixture), UPDATE_TEST_LOG=str(self.log),
            PATH=str(self.directory / "bin") + os.pathsep + os.environ["PATH"],
            QS_NO_RELOAD_POPUP="1", NO_COLOR="1")
        self.environment.pop("WAYLAND_DISPLAY", None)

    def run_qml(self, body, service_properties="automatic: false"):
        source = '''import QtQuick
import Quickshell
import Quickshell.Io
import "source" as Shell
Scope {
    id: harness
    function check(condition, message) {
        if (!condition) {
            console.error("ASSERTION_FAILED", message)
            Qt.exit(1)
            throw new Error(message)
        }
    }
    function pass() { console.log("TEST_PASSED"); Qt.quit() }
    function findItem(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = findItem(child, name)
            if (found) return found
        }
        return null
    }
    Shell.UpdateService {
        id: updates
        helperCommand: %s
        %s
    }
    FileView { id: fixture; path: %s }
    Timer { interval: 8000; running: true; onTriggered: {
        console.error("ASSERTION_FAILED", "Test timed out")
        Qt.exit(1)
    } }
''' % (json.dumps([sys.executable, str(REPO / "scripts/check-updates.py")]),
       service_properties, json.dumps(str(self.fixture))) + body + "\n}\n"
        path = self.directory / "shell.qml"
        path.write_text(source)
        result = subprocess.run(["qs", "-p", str(path)], env=self.environment,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("TEST_PASSED", result.stdout)
        self.assertIsNone(re.search(r"ASSERTION_FAILED|TypeError|ReferenceError|Unable to assign|Binding loop|Cannot assign|Error loading", result.stdout), result.stdout)
        return result.stdout

    def test_startup_checks_both_sources_and_duplicate_refresh_is_ignored(self):
        self.run_qml('''
    Timer { interval: 20; running: true; onTriggered: {
        check(updates.busy, "startup starts checking")
        updates.refresh()
        updates.refresh()
    } }
    Timer { interval: 30; repeat: true; running: true; onTriggered: {
        if (updates.busy) return
        check(updates.complete && !updates.hasError, "both sources completed")
        check(updates.count === 2, "two available packages")
        check(updates.repositories.packages[0].available === "6.2-1", "version reached QML")
        check(updates.summary === "2 updates available", "summary follows results")
        pass()
    } }
''', "automatic: true")
        calls = [json.loads(line)[0] for line in self.log.read_text().splitlines()]
        self.assertCountEqual(calls, ["checkupdates", "yay"])

    def test_failure_retains_only_its_sources_last_success_and_recovers(self):
        self.run_qml('''
    property int stage: 0
    property double firstSuccess: 0
    Component.onCompleted: {
        check(updates.summary === "Not checked yet", "initial state is unknown")
        updates.refresh()
    }
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (updates.busy) return
        if (stage === 0) {
            firstSuccess = updates.aur.lastSuccess
            fixture.setText(JSON.stringify({checkupdates: {code: 2}, yay: {code: 1, err: "Offline"}}))
            stage = 1
            updates.refresh()
        } else if (stage === 1) {
            check(updates.hasError, "failure is visible")
            check(updates.repositories.packages.length === 0, "repository success cleared old updates")
            check(updates.aur.packages.length === 1, "AUR failure retained its packages")
            check(updates.aur.lastSuccess === firstSuccess, "failure did not change success time")
            check(updates.aur.error === "Offline", "failure reason retained")
            fixture.setText(JSON.stringify({checkupdates: {code: 2}, yay: {code: 1}}))
            stage = 2
            updates.refresh()
        } else {
            check(updates.summary === "Up to date", "successful empty check clears stale state")
            check(updates.count === 0 && !updates.hasError, "warning cleared on recovery")
            pass()
        }
    } }
''')

    def test_initial_partial_failure_is_never_up_to_date(self):
        self.fixture.write_text(json.dumps({"checkupdates": {"code": 2}, "yay": {"code": 1, "err": "Cannot connect"}}))
        self.run_qml('''
    Component.onCompleted: updates.refresh()
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (updates.busy) return
        check(!updates.complete && updates.hasError, "partial success is incomplete")
        check(updates.aur.lastSuccess === 0, "failed first check has no timestamp")
        check(updates.summary !== "Up to date", "unknown source is not current")
        pass()
    } }
''')

    def test_scheduled_check_runs_again(self):
        self.run_qml('''
    property double firstSuccess: 0
    Timer { interval: 20; repeat: true; running: true; onTriggered: {
        if (updates.busy || !updates.complete) return
        if (!firstSuccess) firstSuccess = updates.repositories.lastSuccess
        else if (updates.repositories.lastSuccess > firstSuccess) pass()
    } }
''', "automatic: true; intervalMs: 300")

    def test_helper_timeout_is_reported_and_releases_busy(self):
        self.fixture.write_text(json.dumps({"checkupdates": {"delay": 2}, "yay": {"code": 1}}))
        self.run_qml('''
    Component.onCompleted: updates.refresh()
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (updates.busy) return
        check(updates.repositories.error.includes("timed out"), "timeout reaches the UI")
        check(updates.aur.lastSuccess > 0, "other source can finish")
        pass()
    } }
''', "automatic: false; timeoutSeconds: 0.3")

    def test_invalid_helper_response_preserves_previous_list(self):
        self.run_qml('''
    Component.onCompleted: {
        updates.repositories.packages = [{name: "example", installed: "1", available: "2"}]
        updates.repositories.lastSuccess = 123
        updates.helperCommand = ["python3", "-c", "print('not json')"]
        updates.refresh()
    }
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (updates.busy) return
        check(updates.hasError, "invalid response is visible")
        check(updates.repositories.packages.length === 1, "old list survives malformed response")
        check(updates.repositories.lastSuccess === 123, "old timestamp survives malformed response")
        pass()
    } }
''')

    def test_missing_python_releases_busy_with_a_useful_error(self):
        self.run_qml('''
    Component.onCompleted: {
        updates.helperCommand = ["/nonexistent-update-test-python"]
        updates.refresh()
    }
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (updates.busy) return
        check(updates.hasError && !updates.complete, "failed startup is not up to date")
        check(updates.repositories.error.includes("Python 3"), "missing dependency explained")
        pass()
    } }
''')

    def test_popup_models_large_lists_long_versions_and_stale_results(self):
        # Offscreen Qt has no layer-shell backend. Compile the unchanged popup
        # body in a floating window; compositor anchoring still needs a live check.
        preview = (REPO / "Bar/UpdateMenu.qml").read_text()
        preview = preview.replace('import "../"', 'import "source"')
        preview = preview.replace('import "../config.js"', 'import "source/config.js"')
        preview = preview.replace("PanelWindow {", "FloatingWindow {", 1)
        preview = preview.replace("    anchors { left: true; right: true; top: true; bottom: true }",
                                  "    implicitWidth: 800; implicitHeight: 900")
        preview = preview.replace("    exclusionMode: ExclusionMode.Ignore\n", "")
        preview = preview.replace("    WlrLayershell.keyboardFocus: open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None\n", "")
        (self.directory / "PopupPreview.qml").write_text(preview)
        self.run_qml('''
    PopupPreview { id: popup; service: updates; open: true; targetY: 500 }
    FloatingWindow {
        visible: true
        implicitWidth: 64; implicitHeight: 64
        Shell.UpdateIndicator { service: updates; anchors.fill: parent }
    }
    Component.onCompleted: {
        const packages = []
        for (let i = 0; i < 1000; i++) packages.push({name: "example-" + i,
            installed: "1:" + "very-long-version".repeat(8), available: "2-1"})
        updates.repositories.packages = packages
        updates.repositories.lastSuccess = Date.now()
        updates.repositories.error = "Offline"
    }
    Timer { interval: 800; running: true; onTriggered: {
        check(popup.rows.length === 1002, "all packages plus two source headings")
        check(popup.sourceDetail(popup.rows[0].state).includes("Last known updates"), "stale list labeled")
        check(popup.sourceDetail(popup.rows[1001].state) === "Not checked yet", "unqueried source labeled")
        const panel = findItem(popup.contentItem, "updatesPanel")
        const list = findItem(popup.contentItem, "updatePackages")
        check(panel.height <= popup.height, "popup fits screen height")
        check(list.contentHeight > list.height, "large list scrolls")
        check(list.contentItem.children.length < 100, "large list only instantiates visible rows")
        const originalRows = popup.rows
        list.contentY = 120
        updates.now += 60000
        check(popup.rows === originalRows, "relative time update does not rebuild the package list")
        check(list.contentY === 120, "relative time update preserves scrolling")
        list.positionViewAtBeginning()
        panel.grabToImage(result => {
            check(result.saveToFile(%s), "popup rendered to an image")
            popup.open = false
            pass()
        })
    } }
''' % json.dumps(str(Path(os.environ.get("UPDATE_PREVIEW_DIR", self.directory)) / "updates-popup.png")))


if __name__ == "__main__":
    unittest.main()
