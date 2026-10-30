"""Exercise wheel events with both pixel and angle deltas, as on Wayland."""
import os
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

try:
    from PySide6.QtCore import QPoint, QPointF, QUrl, Qt
    from PySide6.QtGui import QGuiApplication, QWheelEvent
    from PySide6.QtQuick import QQuickView
    from PySide6.QtTest import QTest
except ImportError:
    QGuiApplication = None

REPO = Path(__file__).resolve().parents[1]


@unittest.skipIf(QGuiApplication is None, "PySide6 is required for native wheel-event tests")
class WheelInputTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="qs-wheel-test-")
        cls.directory = Path(cls.temporary.name)
        (cls.directory / "run").mkdir(mode=0o700)
        cls.environment = patch.dict(os.environ, {
            "QT_QPA_PLATFORM": "offscreen", "QT_QUICK_BACKEND": "software",
            "XDG_RUNTIME_DIR": str(cls.directory / "run"),
            "XDG_CACHE_HOME": str(cls.directory / "cache"),
        })
        cls.environment.start()
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        # Copy the actual component unchanged, without importing the shell's
        # singleton module, which requires the Quickshell executable.
        for name in ("ScrollWheel.qml", "config.js"):
            shutil.copyfile(REPO / name, cls.directory / name)
        (cls.directory / "Wheel.qml").write_text('''import QtQuick
Item {
    id: scene
    width: 400; height: 300
    property bool readerMode: false
    property int fallbackEvents: 0
    property int boundaryEvents: 0
    property alias wheelStep: wheel.step
    Flickable {
        id: viewport
        objectName: "viewport"
        anchors.fill: parent
        contentWidth: width; contentHeight: 100000
        ScrollWheel {
            id: wheel
            view: viewport
            parent: scene.readerMode ? readerPointer : viewport
            onUnhandledWheel: event => {
                if (scene.readerMode) {
                    scene.boundaryEvents++
                    event.accepted = true
                }
            }
        }
        Rectangle { width: viewport.width; height: 100000; color: "gray" }
    }
    MouseArea {
        id: readerPointer
        anchors.fill: parent
        enabled: scene.readerMode
        onWheel: event => {
            scene.fallbackEvents++
            wheel.scroll(event, true)
        }
    }
}''')

    @classmethod
    def tearDownClass(cls):
        cls.environment.stop()
        cls.temporary.cleanup()

    def setUp(self):
        self.window = QQuickView()
        self.window.setSource(QUrl.fromLocalFile(str(self.directory / "Wheel.qml")))
        self.window.show()
        QTest.qWait(100)
        self.assertEqual(self.window.status(), QQuickView.Ready,
                         [error.toString() for error in self.window.errors()])
        self.root = self.window.rootObject()
        self.viewport = self.root.findChild(type(self.root), "viewport")

    def tearDown(self):
        self.window.close()
        self.window.deleteLater()
        self.app.processEvents()

    def send_wheel(self, pixels, angle, source=Qt.MouseEventNotSynthesized):
        event = QWheelEvent(QPointF(100, 100), QPointF(100, 100),
                            QPoint(0, pixels), QPoint(0, angle), Qt.NoButton,
                            Qt.NoModifier, Qt.NoScrollPhase, False, source)
        self.app.sendEvent(self.window, event)
        QTest.qWait(30)

    def test_mouse_pixel_delta_does_not_bypass_configured_step(self):
        for reader in (False, True):
            for step in (120, 640):
                with self.subTest(reader=reader, step=step):
                    self.root.setProperty("readerMode", reader)
                    self.root.setProperty("wheelStep", step)
                    self.viewport.setProperty("contentY", 0)
                    self.send_wheel(-15, -120)
                    self.assertEqual(self.viewport.property("contentY"), step)
                    self.send_wheel(-30, -240)
                    self.assertEqual(self.viewport.property("contentY"), 3 * step)
                    self.assertEqual(self.root.property("fallbackEvents"), 0,
                                     "mouse input must not fall through to the reader's touchpad path")

    def test_synthesized_mouse_wheel_uses_configured_step(self):
        for reader in (False, True):
            for source in (Qt.MouseEventSynthesizedBySystem, Qt.MouseEventSynthesizedByQt):
                for step in (120, 640, 2000):
                    with self.subTest(reader=reader, source=source, step=step):
                        self.root.setProperty("readerMode", reader)
                        self.root.setProperty("wheelStep", step)
                        self.viewport.setProperty("contentY", 0)
                        self.send_wheel(-15, -120, source)
                        self.assertEqual(self.viewport.property("contentY"), step)
                        self.assertEqual(self.root.property("fallbackEvents"), 0)

    def test_pixel_only_input_keeps_pixel_distance(self):
        for reader in (False, True):
            with self.subTest(reader=reader):
                self.root.setProperty("readerMode", reader)
                self.root.setProperty("wheelStep", 2000)
                self.viewport.setProperty("contentY", 0)
                self.send_wheel(-15, 0, Qt.MouseEventSynthesizedBySystem)
                self.assertEqual(self.viewport.property("contentY"), 15)

    def test_reader_mouse_at_page_end_requests_one_page_turn(self):
        self.root.setProperty("readerMode", True)
        self.viewport.setProperty("contentY", 99700)
        self.send_wheel(-15, -120)
        self.assertEqual(self.root.property("boundaryEvents"), 1)
        self.assertEqual(self.root.property("fallbackEvents"), 0)


if __name__ == "__main__":
    unittest.main()
