"""Exercise real QML bindings and FileView writes without touching the desktop."""
import os
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class SettingsRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qs-test-")
        self.directory = Path(self.temporary.name)
        (self.directory / "run").mkdir(mode=0o700)
        (self.directory / "source").symlink_to(REPO, target_is_directory=True)
        self.environment = dict(
            os.environ,
            QT_QPA_PLATFORM="offscreen",
            QT_QUICK_BACKEND="software",
            XDG_RUNTIME_DIR=str(self.directory / "run"),
            XDG_STATE_HOME=str(self.directory / "state"),
            XDG_CACHE_HOME=str(self.directory / "cache"),
            NO_COLOR="1",
            QS_NO_RELOAD_POPUP="1",
        )
        self.environment.pop("WAYLAND_DISPLAY", None)

    def tearDown(self):
        self.temporary.cleanup()

    def run_qml(self, content, imports=""):
        harness = imports + '\n' + '''import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Dialogs
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
    function findItem(item, name) {
        if (item.objectName === name) return item
        for (const child of item.children || []) {
            const found = findItem(child, name)
            if (found) return found
        }
        return null
    }
    Timer { interval: 6000; running: true; onTriggered: {
        console.error("ASSERTION_FAILED", "Test timed out")
        Qt.exit(1)
    } }
''' + content + "\n}\n"
        source = self.directory / "shell.qml"
        source.write_text(harness)
        result = subprocess.run(
            ["qs", "-p", str(source)], env=self.environment,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, timeout=15,
        )
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("ASSERTION_FAILED", result.stdout)
        self.assertIsNone(re.search(r"TypeError|ReferenceError|Unable to assign|Binding loop", result.stdout), result.stdout)
        self.assertIn("TEST_PASSED", result.stdout)
        return result.stdout

    def seed_settings(self):
        self.run_qml('''
    property bool changed: false
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (!changed) {
            changed = true
            Shell.Settings.setValue("launcherRows", 12)
            Shell.Settings.save()
        } else if (!Shell.Settings.saving && !Shell.Settings.dirty) {
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''')
        return next((self.directory / "state").rglob("settings.json"))

    def stub_hyprctl(self, fail=False):
        tools = self.directory / "bin"
        tools.mkdir()
        command = tools / "hyprctl"
        command.write_text('''#!/usr/bin/env python3
import json
import os
import sys
import time
with open(os.environ["QS_TEST_RULE_LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
time.sleep(0.15)
if os.environ.get("QS_TEST_RULE_FAIL"):
    print("Could not connect to Hyprland", file=sys.stderr)
    sys.exit(1)
print("ok")
''')
        command.chmod(0o755)
        self.environment["PATH"] = str(tools) + os.pathsep + self.environment["PATH"]
        self.environment["WAYLAND_DISPLAY"] = "test-display"
        self.environment["QS_TEST_RULE_LOG"] = str(self.directory / "rules.jsonl")
        if fail:
            self.environment["QS_TEST_RULE_FAIL"] = "1"

    def test_floating_rule_is_installed_before_each_open(self):
        self.stub_hyprctl()
        self.run_qml('''
    Shell.SettingsWindow { id: preview }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (stage === 0) {
            preview.showSettings()
            preview.showSettings()
            check(!preview.visible, "waits for the compositor rule before showing")
            stage = 1
        } else if (stage === 1 && preview.visible) {
            preview.hideSettings()
            preview.showSettings()
            check(!preview.visible, "reopening also installs the rule first")
            stage = 2
        } else if (stage === 2 && preview.visible) {
            check(preview.placementError === "", "placement succeeded")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''')
        calls = [json.loads(line) for line in (self.directory / "rules.jsonl").read_text().splitlines()]
        self.assertEqual(len(calls), 2, "duplicate show requests should share a single operation")
        for arguments in calls:
            self.assertEqual(arguments[0], "eval")
            self.assertIn('initial_title="^Fuchi-shell settings$"', arguments[1])
            self.assertIn("float=true,center=true", arguments[1])
            self.assertIn('name="fuchi-shell-settings"', arguments[1])
            self.assertIn('size={"min(1435,monitor_w*0.9)","min(1505,monitor_h*0.9)"}', arguments[1])

    def test_hide_cancels_a_pending_open(self):
        self.stub_hyprctl()
        self.run_qml('''
    Shell.SettingsWindow { id: preview }
    Component.onCompleted: {
        preview.showSettings()
        preview.hideSettings()
    }
    Timer { interval: 500; running: true; onTriggered: {
        check(!preview.visible && !preview.openRequested, "a completed placement must not undo hide")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''')

    def test_native_close_can_reopen_repeatedly(self):
        self.stub_hyprctl()
        self.run_qml('''
    Shell.SettingsWindow { id: preview }
    property int closes: 0
    property bool reopening: false
    Component.onCompleted: preview.showSettings()
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!preview.visible) return
        const nativeWindow = preview.contentItem.Window.window
        check(nativeWindow !== null && nativeWindow.visible, "native window is mapped")
        if (reopening) {
            reopening = false
            if (closes === 3) {
                console.log("TEST_PASSED")
                Qt.quit()
                return
            }
        }
        nativeWindow.close()
        check(!preview.visible && !preview.openRequested, "native close clears open state")
        closes++
        reopening = true
        preview.showSettings()
    } }
''')

    def test_placement_failure_is_shown(self):
        self.stub_hyprctl(fail=True)
        self.run_qml('''
    Shell.SettingsWindow { id: preview }
    Component.onCompleted: preview.showSettings()
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!preview.visible) return
        check(preview.placementError.includes("window placement"), "placement failure is visible")
        check(preview.placementError.includes("Could not connect"), "original failure is included")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''')

    def test_live_bindings_resets_queued_writes_and_normal_reload(self):
        self.run_qml('''
    PersistentProperties {
        id: memory
        reloadableId: "settings-test-memory"
        property int generations: 0
        onLoaded: generations++
    }
    Shell.SettingsWindow { id: preview; visible: true }
    Text { id: sample; font.family: Shell.Settings.fontFamily }
    property bool started: false
    Timer { interval: 100; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready || started) return
        started = true
        if (memory.generations === 1) {
            check(Shell.Settings.launcherRows === 8, "config.js defaults are active")
            const alternative = Shell.Settings.fontFamilies.find(name =>
                name.includes("Nerd Font") && !name.startsWith("Symbols") && name !== Shell.Settings.fontFamily)
            if (alternative) {
                check(Shell.Settings.setValue("fontFamily", alternative), "installed font accepted")
                check(sample.font.family === alternative, "font binding updates immediately")
                Shell.Settings.reset("fontFamily")
                check(sample.font.family === Shell.Settings.defaults.fontFamily, "reset restores default font")
                check(!Shell.Settings.isOverridden("fontFamily"), "reset removes override")
            }
            check(!Shell.Settings.setValue("fontFamily", "not-an-installed-font"), "missing font rejected")
            Shell.Settings.setValue("historyLimit", 0)
            check(Shell.Settings.historyLimit === 0, "zero history is not treated as a missing value")
            Shell.Settings.setValue("launcherRows", 11)
            Shell.Settings.save()
            Shell.Settings.setValue("launcherRows", 12)
            Shell.Settings.setValue("animationSlide", 0)
            Shell.Settings.setValue("animationPopup", 0)
            Shell.Settings.setValue("animationTabSlide", 0)
            Shell.Settings.requestReload()
        } else {
            check(memory.generations === 2, "normal reload happens once")
            check(Shell.Settings.launcherRows === 12, "latest write survives reload")
            check(Shell.Settings.historyLimit === 0, "zero value survives reload")
            check(Shell.Settings.animationSlide === 0 && Shell.Settings.animationPopup === 0
                && Shell.Settings.animationTabSlide === 0, "disabled animations survive reload")
            const rows = findItem(preview.contentItem, "launcherRowsControl")
            check(rows !== null && rows.value === 12, "real settings control follows store")
            Shell.Settings.reset("launcherRows")
            check(rows.value === 8, "real control follows reset")
            preview.visible = false
            preview.showSettings()
            check(preview.visible, "same window can be reopened")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''')

    def test_corrupt_file_is_reported_and_left_untouched(self):
        saved = self.seed_settings()
        damaged = '{"version":1,"overrides":{"launcherRows":'
        saved.write_text(damaged)
        self.run_qml('''
    Timer { interval: 150; running: true; onTriggered: {
        check(!Shell.Settings.ready, "editing disabled for corrupt file")
        check(Shell.Settings.errorText.includes("Could not read"), "load error shown")
        check(!Shell.Settings.setValue("launcherRows", 6), "cannot overwrite unreadable settings")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''')
        self.assertEqual(saved.read_text(), damaged)

    def test_narrow_layout_and_file_picker_callbacks(self):
        self.run_qml('''
    Shell.SettingsWindow { id: preview; visible: true; implicitWidth: 520; implicitHeight: 420 }
    property var imageDialogToAccept: null
    Timer {
        id: acceptImage
        interval: 200
        onTriggered: {
            const dialog = harness.imageDialogToAccept
            dialog.selectedFile = Qt.resolvedUrl("source/assets/record.gif")
            // Simulate the native helper reporting its accepted selection.
            // accept() reads the offscreen helper's empty user selection instead.
            dialog.accepted()
            check(Shell.Settings.profilePic.endsWith("/source/assets/record.gif"), "image acceptance changes setting")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    }
    Timer { interval: 250; running: true; onTriggered: {
        check(Shell.Settings.ready, "settings loaded")
        const scroll = findItem(preview.contentItem, "settingsScroll")
        check(scroll.width > 0 && scroll.width < 520, "form fits narrow window")
        check(scroll.contentItem.contentWidth <= scroll.width, "no horizontal overflow")
        check(scroll.contentItem.contentHeight > scroll.height, "form can scroll vertically")
        let folderDialog = null
        let imageDialog = null
        for (const object of preview.data) {
            if (object.objectName === "wallpaperFolderDialog") folderDialog = object
            if (object.objectName === "profilePictureDialog") imageDialog = object
        }
        check(folderDialog && imageDialog, "both file pickers exist")
        const nativeWindow = preview.contentItem.Window.window
        check(folderDialog.parentWindow === nativeWindow && imageDialog.parentWindow === nativeWindow,
            "file pickers belong to the settings window")
        folderDialog.options = FolderDialog.DontUseNativeDialog
        folderDialog.open()
        folderDialog.selectedFolder = "file:///tmp"
        folderDialog.accept()
        check(Shell.Settings.wallpaperFolder === "/tmp", "folder acceptance changes setting")
        imageDialog.options = FileDialog.DontUseNativeDialog
        imageDialog.currentFolder = Qt.resolvedUrl("source/assets")
        imageDialog.open()
        harness.imageDialogToAccept = imageDialog
        acceptImage.start()
    } }
''')

    def test_failed_write_retains_changes_and_blocks_reload(self):
        saved = self.seed_settings()
        saved.unlink()
        # Make the target a directory after the store has loaded its defaults.
        self.run_qml('''
    property bool started: false
    Process {
        id: blocker
        command: ["mkdir", Shell.Settings.path]
        onExited: code => {
            check(code === 0, "test directory created")
            Shell.Settings.setValue("launcherRows", 14)
            Shell.Settings.requestReload()
        }
    }
    Timer { interval: 100; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (!started) {
            started = true
            blocker.running = true
        } else if (Shell.Settings.errorText.includes("Could not save")) {
            check(Shell.Settings.launcherRows === 14, "live change retained after failed write")
            check(Shell.Settings.dirty, "unsaved change can be retried")
            check(!Shell.Settings.reloadPending, "failed save cancels requested reload")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''')
        self.assertTrue(saved.is_dir())


if __name__ == "__main__":
    unittest.main()
