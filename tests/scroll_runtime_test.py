"""Real wheel events in temporary offscreen windows, without desktop changes."""
import shutil
import unittest

import settings_runtime_test as settings_tests


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class ScrollRuntimeTests(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def test_wheel_distance_direction_bounds_and_horizontal_gallery(self):
        self.run_qml('''
    FloatingWindow {
        id: preview
        visible: true
        implicitWidth: 400
        implicitHeight: 300
        Flickable {
            id: view
            anchors.fill: parent
            contentWidth: Math.max(2000, Config.scrolling.wheelStep * 8)
            contentHeight: Math.max(2000, Config.scrolling.wheelStep * 8)
            Shell.ScrollWheel { id: wheel; view: view }
            Rectangle { width: view.contentWidth; height: view.contentHeight; color: "gray" }
        }
    }
    TestCase { id: input; when: false }
    Timer { interval: 100; running: true; onTriggered: {
        const step = Config.scrolling.wheelStep
        input.mouseWheel(view, 100, 100, 0, -120)
        check(view.contentY === step, "one notch uses scrolling.wheelStep")
        input.mouseWheel(view, 100, 100, 0, -240)
        check(view.contentY === 3 * step, "two notches move twice as far")
        input.mouseWheel(view, 100, 100, 0, 60)
        check(view.contentY === 2.5 * step, "partial notch moves proportionally in reverse")
        wheel.step = 200
        input.mouseWheel(view, 100, 100, 0, -120)
        check(view.contentY === 2.5 * step + 200, "configured distance takes effect")
        input.mouseWheel(view, 100, 100, 0, 12000)
        check(view.contentY === 0, "movement clamps to the top")
        input.mouseWheel(view, 100, 100, 0, -12000)
        check(view.contentY === view.contentHeight - view.height, "movement clamps to the bottom")
        input.mouseWheel(view, 100, 100, 0, -120)
        input.wait(80)
        check(view.contentY === view.contentHeight - view.height, "wheel does not overshoot at the bottom")
        wheel.horizontal = true
        input.mouseWheel(view, 100, 100, 0, -120)
        check(view.contentX === 200, "vertical wheel scrolls horizontal gallery")
        input.mouseWheel(view, 100, 100, 120, 0)
        check(view.contentX === 0, "horizontal wheel also works")
        // High-resolution deltas are pixels, not multiples of the wheel step.
        check(wheel.scroll({pixelDelta: Qt.point(-13, 0), angleDelta: Qt.point(0, 0), modifiers: 0}), "pixel scroll handled")
        check(view.contentX === 13, "pixel scrolling is not accelerated")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports='import QtTest\nimport "source/config.js" as Config')

    def test_settings_scrollview_handles_wheel_over_its_content(self):
        self.run_qml('''
    Shell.SettingsWindow { id: preview; implicitWidth: 700; implicitHeight: 500 }
    TestCase { id: input; when: false }
    property int stage: 0
    Timer { interval: 100; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (stage === 0) { preview.showSettings(); stage = 1; return }
        const scroll = findItem(preview.contentItem, "settingsScroll")
        const flick = scroll.contentItem
        check(flick.contentHeight > flick.height, "settings content is scrollable")
        input.mouseWheel(flick, 25, 50, 0, -120)
        check(flick.contentY === Math.min(Config.scrolling.wheelStep, flick.contentHeight - flick.height), "ScrollView uses the shared wheel distance, got " + flick.contentY)
        input.mouseWheel(flick, 25, 50, 0, 120)
        check(flick.contentY === 0, "ScrollView scrolls back without a second native movement")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports='import QtTest\nimport "source/config.js" as Config')


if __name__ == "__main__":
    unittest.main()
