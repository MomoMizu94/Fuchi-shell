"""Exercise confirmation buttons without running desktop power commands."""
import shutil
import unittest

import settings_runtime_test as settings_tests


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class PowerMenuTest(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def test_accessible_confirmation_and_cancellation(self):
        commands = self.directory / "bin"
        commands.mkdir()
        (commands / "qs").symlink_to(shutil.which("qs"))
        log = self.directory / "power.log"
        log.touch()
        recorder = commands / "systemctl"
        recorder.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$QS_POWER_LOG"\n')
        recorder.chmod(0o755)
        self.environment.update(PATH=str(commands), QS_POWER_LOG=str(log))

        source = (settings_tests.REPO / "PowerMenu.qml").read_text()
        source = source.replace('import "config.js"', 'import "source"\nimport "source/config.js"')
        source = source.replace("PanelWindow {", "FloatingWindow {", 1)
        source = source.replace("    anchors { left: true; right: true; top: true; bottom: true }", "")
        source = source.replace("    exclusionMode: ExclusionMode.Normal", "")
        source = source.replace("    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand", "")
        (self.directory / "PowerPreview.qml").write_text(source)
        self.run_qml('''
    PowerPreview {
        id: menu
        implicitWidth: 600
        implicitHeight: 800
        onCloseRequested: open = false
    }
    function button(item, name) {
        if (item.visible && item.Accessible.role === Accessible.Button && item.Accessible.name === name)
            return item
        for (const child of item.children) {
            const found = button(child, name)
            if (found) return found
        }
        return null
    }
    FileView { id: actionLog; path: Quickshell.env("QS_POWER_LOG") }
    Timer { interval: 100; running: true; onTriggered: menu.open = true }
    Timer { interval: 250; running: true; onTriggered: {
        menu.activateSelection({isAutoRepeat: false})
        menu.activateSelection({isAutoRepeat: true})
        check(menu.open && menu.pendingAction?.id === "logout", "holding Enter keeps confirmation open")
        button(menu.contentItem, "Cancel log out").Accessible.pressAction()
        button(menu.contentItem, "Shut down").Accessible.pressAction()
        button(menu.contentItem, "Cancel shut down").Accessible.pressAction()
        check(menu.open && !menu.pendingAction, "cancel returns to the action list")

        button(menu.contentItem, "Restart").Accessible.pressAction()
        button(menu.contentItem, "Confirm restart").Accessible.pressAction()
        check(!menu.open && !menu.pendingAction, "confirm executes and dismisses the menu")
        waitForCommand.start()
    } }
    Timer { id: waitForCommand; interval: 40; repeat: true; onTriggered: {
        actionLog.reload()
        if (!actionLog.text().trim()) return
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''')
        self.assertEqual(log.read_text().splitlines(), ["reboot"])


if __name__ == "__main__":
    unittest.main()
