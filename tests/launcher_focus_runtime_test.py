"""Run with QS_TEST_LIVE_LAUNCHER=1 on a Wayland desktop with layer-shell support."""
import os
import shutil
import unittest

import settings_runtime_test as settings_tests


@unittest.skipUnless(
    os.environ.get("QS_TEST_LIVE_LAUNCHER") == "1" and os.environ.get("WAYLAND_DISPLAY")
    and shutil.which("qs"), "requires an opt-in Wayland desktop",
)
class LauncherFocusTest(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def test_reopen_while_launched_app_is_starting(self):
        self.environment.update(
            QT_QPA_PLATFORM="wayland",
            WAYLAND_DISPLAY=os.environ["WAYLAND_DISPLAY"],
            XDG_RUNTIME_DIR=os.environ["XDG_RUNTIME_DIR"],
            XDG_DATA_HOME=str(self.directory / "data"),
            HOME=str(self.directory),
        )
        applications = self.directory / "data/applications"
        applications.mkdir(parents=True)
        (self.directory / "mapped").touch()
        app = self.directory / "focus-app.qml"
        app.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    FloatingWindow {
        id: app
        title: "Launcher focus test"
        implicitWidth: 300
        implicitHeight: 100
        visible: false
        Text { anchors.centerIn: parent; text: "Checking launcher focus" }
    }
    Timer { interval: 160; running: true; onTriggered: app.visible = true }
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!app.contentItem.Window.window?.visible) return
        mapped.setText("mapped")
        stop()
    } }
    FileView { id: mapped; path: Quickshell.env("HOME") + "/mapped" }
    Timer { interval: 1800; running: true; onTriggered: Qt.quit() }
}
''')
        entry = applications / "qs-launch-focus-probe.desktop"
        entry.write_text(
            "[Desktop Entry]\nType=Application\nName=QS Launch Focus Probe\n"
            f'Exec={shutil.which("qs")} -p "{app}"\n'
        )
        self.run_qml('''
    Shell.AppLauncher { id: launcher; onCloseRequested: open = false }
    TestCase { id: input; when: false; parent: launcher.contentItem }
    FileView { id: mapped; path: Quickshell.env("HOME") + "/mapped" }
    Timer { interval: 350; running: true; onTriggered: launcher.open = true }
    Timer { interval: 750; running: true; onTriggered: {
        launcher.query = "QS Launch Focus Probe"
        check(launcher.results[0]?.id === "qs-launch-focus-probe", "found the test desktop entry")
        input.keyClick(Qt.Key_Return)
        check(!launcher.open, "launching the test app closes the launcher")
        reopen.start()
    } }
    Timer { id: reopen; interval: 30; onTriggered: {
        check(launcher.closing, "reopen during the slide out")
        launcher.open = true
        check(launcher.query === "", "reopen clears the previous search")
        verify.start()
    } }
    Timer { id: verify; interval: 60; repeat: true; onTriggered: {
        mapped.reload()
        if (mapped.text() !== "mapped") return
        stop()
        input.wait(150)
        check(launcher.contentItem.Window.window?.active, "late app took keyboard focus from the reopened launcher")
        input.keyClick(Qt.Key_X)
        check(launcher.query === "x", "first keystroke reaches the search field")
        input.keyClick(Qt.Key_Escape)
        check(!launcher.open, "Escape dismisses the launcher")
        released.start()
    } }
    Timer { id: released; interval: 60; repeat: true; onTriggered: {
        if (launcher.visible) return
        check(!launcher.contentItem.Window.window?.active, "launcher released keyboard focus")
        stop()
        Shell.Settings.setValue("animationPopup", 0)
        launcher.open = true
        instant.start()
    } }
    Timer { id: instant; interval: 50; repeat: true; onTriggered: {
        if (!launcher.contentItem.Window.window?.active) return
        input.keyClick(Qt.Key_Slash)
        check(launcher.commandMode, "slash commands work after reopening a fully closed launcher")
        input.keyClick(Qt.Key_Escape)
        check(!launcher.visible, "zero-duration close releases the panel immediately")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports="import QtTest")


if __name__ == "__main__":
    unittest.main()
