"""Exercise both sidebar tools without sampling the desktop or its clipboard."""
import io
import json
import os
import shutil
import subprocess
import time
import unittest

import settings_runtime_test as settings_tests

REPO = settings_tests.REPO


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class SidebarToolsTest(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def stub(self, name, script):
        path = self.directory / name
        path.write_text("#!/bin/sh\n" + script)
        path.chmod(0o755)

    def prepare_commands(self):
        for key in list(self.environment):
            if key.startswith("CLIPHIST_"):
                del self.environment[key]
        self.environment.update(
            XDG_CONFIG_HOME=str(self.directory / "config"),
            CLIPHIST_CONFIG_PATH=str(self.directory / "cliphist.conf"),
            CLIPHIST_DB_PATH=str(self.directory / "history.db"),
        )
        self.environment["PATH"] = str(self.directory) + os.pathsep + self.environment["PATH"]
        self.environment["RESULT"] = str(self.directory / "result")
        self.stub("notify-send", "exit 0\n")

    def prepare_clipboard_panel(self):
        source = (REPO / "Bar/ClipboardMenu.qml").read_text().replace('"../', '"source/')
        source = source.replace("PanelWindow {", "FloatingWindow {", 1)
        source = "\n".join(line for line in source.splitlines() if not line.startswith(
            ("    anchors {", "    exclusionMode:", "    WlrLayershell.keyboardFocus:")))
        (self.directory / "ClipboardPreview.qml").write_text(source)

    def test_pick_and_cancel(self):
        self.prepare_commands()
        self.stub("notify-send", 'printf "%s\\n" "$@" >> "$RESULT-notifications"\n')
        self.stub("hyprpicker", 'if [ -e "$RESULT" ]; then exit 0; fi\necho "#40a0ff"\n')
        self.stub("wl-copy", 'printf "%s" "$4" >> "$RESULT"\n')
        self.run_qml("""
    Shell.ColorPicker { id: picker }
    TestCase { id: input; when: false }
    Timer { interval: 60; running: true; onTriggered: {
        picker.pick()
        picker.pick()
        input.tryVerify(() => picker.lastColor === "#40A0FF", 1500)
        check(picker.lastColor === "#40A0FF", "sample copied")
        picker.pick()
        input.tryVerify(() => !picker.busy, 1500)
        check(picker.lastColor === "#40A0FF", "cancel keeps last color")
        picker.copyColor(picker.lastColor)
        input.tryVerify(() => !picker.busy, 1500)
        console.log("TEST_PASSED")
        Qt.quit()
    } }
""", imports="import QtTest")
        self.assertEqual((self.directory / "result").read_text(), "#40A0FF#40A0FF")
        # The detached notification process can finish after the QML window closes
        log = self.directory / "result-notifications"
        hint = "variant:image-data:(1, 1, 4, true, 8, 4, [byte 0x40, 0xA0, 0xFF, 0xff])"
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            if log.exists() and log.read_text().splitlines().count(hint) >= 2:
                break
            time.sleep(0.01)
        self.assertEqual(log.read_text().splitlines().count(hint), 2)

    @unittest.skipUnless(shutil.which("cliphist"), "cliphist is required")
    def test_empty_and_expired_entries(self):
        self.prepare_commands()
        self.stub("wl-copy", 'touch "$RESULT"\n')
        helper = ["python3", str(REPO / "scripts/clipboard-history.py")]
        empty = subprocess.run(helper + ["list"], env=self.environment, capture_output=True, check=True)
        self.assertEqual(json.loads(empty.stdout), [])
        subprocess.run(["cliphist", "store"], input=b"example", env=self.environment, check=True)
        missing = subprocess.run(helper + ["copy-text", "9999"], env=self.environment, capture_output=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertFalse((self.directory / "result").exists())

    @unittest.skipUnless(shutil.which("cliphist"), "cliphist is required")
    def test_webp_preview_and_restore(self):
        from PIL import Image

        self.prepare_commands()
        self.stub("wl-copy", 'printf "%s" "$2" > "$RESULT-mime"\ncat > "$RESULT"\n')
        image = io.BytesIO()
        Image.new("RGB", (32, 16), "blue").save(image, "WEBP")
        helper = ["python3", str(REPO / "scripts/clipboard-history.py")]
        for data in [b"RIFF header for WEBP", image.getvalue()]:
            subprocess.run(["cliphist", "store"], input=data, env=self.environment, check=True)
        webp, text = json.loads(subprocess.check_output(helper + ["list"], env=self.environment))
        self.assertFalse(text["binary"])
        self.assertTrue(webp["binary"])
        preview = subprocess.check_output(helper + ["thumbnail", webp["key"]], env=self.environment)
        self.assertTrue(preview.startswith(b"data:image/png;base64,"))
        subprocess.run(helper + ["copy-binary", webp["key"]], env=self.environment, check=True, capture_output=True)
        self.assertEqual((self.directory / "result-mime").read_text(), "image/webp")
        self.assertEqual((self.directory / "result").read_bytes(), image.getvalue())

    def test_refresh_preserves_visible_entry_and_selection(self):
        self.prepare_commands()
        self.prepare_clipboard_panel()
        (self.directory / "fixture.py").write_text("""
import json
import os
import sys
from pathlib import Path

if sys.argv[1] == "list":
    marker = Path(os.environ["RESULT"])
    count = 100 if marker.exists() else 99
    marker.touch()
    print(json.dumps([{"key": str(i), "label": str(i), "binary": i % 4 == 0}
                      for i in reversed(range(count))]))
""")
        self.run_qml("""
    ClipboardPreview { id: menu; open: true; implicitWidth: 560; implicitHeight: 650
        helper: Quickshell.shellDir + "/fixture.py"
    }
    TestCase { id: input; when: false }
    Timer { interval: 50; running: true; onTriggered: {
        const list = findItem(menu.contentItem, "clipboardEntries")
        input.tryVerify(() => list.count === 99, 1000)
        list.currentIndex = 2
        list.positionViewAtIndex(47, ListView.Beginning)
        list.contentY += 17
        const first = list.itemAt(1, list.contentY)
        const key = first.modelData.key
        const offset = list.contentY - first.y
        const selected = menu.matches[list.currentIndex].key
        input.tryVerify(() => list.count === 100, 4000)
        input.wait(50)
        const after = list.itemAt(1, list.contentY)
        check(list.count === 100 && after.modelData.key === key, "refresh retains the visible entry")
        check(list.contentY - after.y === offset, "partially visible row stays in place")
        check(menu.matches[list.currentIndex].key === selected, "keyboard selection is independent of scrolling")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
""", imports="import QtTest")

    @unittest.skipUnless(shutil.which("cliphist"), "cliphist is required")
    def test_clear_saved_history(self):
        self.prepare_commands()
        self.prepare_clipboard_panel()
        self.environment["CLIP_TEST_BINARY"] = shutil.which("cliphist")
        self.stub("cliphist", '''
if [ "$1" = wipe ] && [ ! -e "$RESULT" ]; then
    touch "$RESULT"
    exit 1
fi
exec "$CLIP_TEST_BINARY" "$@"
''')
        for data in [b"apple", b"orange"]:
            subprocess.run(["cliphist", "store"], input=data, env=self.environment, check=True)
        self.run_qml("""
    ClipboardPreview {
        id: menu; open: true; implicitWidth: 560; implicitHeight: 480
        helper: Quickshell.shellDir + "/source/scripts/clipboard-history.py"
    }
    TestCase { id: input; when: false }
    Timer { interval: 80; running: true; onTriggered: {
        const clear = findItem(menu.contentItem, "clearClipboard")
        const confirm = findItem(menu.contentItem, "confirmClearClipboard")
        input.tryVerify(() => menu.entries.length === 2, 1500)
        input.keyClick(Qt.Key_G)
        check(menu.matches.length === 1, "history is filtered")
        input.mouseClick(clear)
        input.mouseClick(clear)
        check(!confirm.visible && menu.entries.length === 2, "cancel keeps both entries")
        input.mouseClick(clear)
        input.mouseClick(confirm)
        input.tryVerify(() => menu.error !== "", 1500)
        check(menu.entries.length === 2, "failed wipe keeps the list")
        input.mouseClick(clear)
        input.mouseClick(confirm)
        input.tryVerify(() => menu.entries.length === 0, 1500)
        check(menu.open && !clear.enabled && !confirm.visible && !menu.error, "cleared panel is empty")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
""", imports="import QtTest")
        remaining = subprocess.check_output(["cliphist", "list"], env=self.environment)
        self.assertEqual(remaining, b"")

    @unittest.skipUnless(shutil.which("cliphist"), "cliphist is required")
    def test_clipboard_image_and_text(self):
        from PIL import Image

        self.prepare_commands()
        self.stub("wl-copy", 'cat > "$RESULT"\n')
        self.prepare_clipboard_panel()
        payload = io.BytesIO()
        Image.new("RGB", (320, 160), "teal").save(payload, "PNG")
        message = b"<b>Notes</b>\n  with tabs\tand spaces\n"
        for data in [str(index).encode() for index in range(16)] + [message, payload.getvalue()]:
            subprocess.run(["cliphist", "store"], input=data, env=self.environment, check=True)

        self.run_qml("""
    ClipboardPreview {
        id: menu; open: true; implicitWidth: 560; implicitHeight: 700
        helper: Quickshell.shellDir + "/source/scripts/clipboard-history.py"
    }
    TestCase { id: input; when: false }
    function hasImage(item) {
        if (item.source && String(item.source).startsWith("data:image/png") && item.status === Image.Ready)
            return item.sourceSize.width <= 240
        for (const child of item.children || []) if (hasImage(child)) return true
        return false
    }
    Timer { interval: 100; running: true; onTriggered: {
        const list = findItem(menu.contentItem, "clipboardEntries")
        input.tryVerify(() => list.count === 18 && hasImage(list.contentItem), 2000)
        check(list.count === 18 && hasImage(list.contentItem), "real cliphist image has a thumbnail")
        check(list.height === 420 && list.contentHeight > list.height, "long history has a capped viewport")
        input.mouseWheel(list, 20, 20, 0, -120)
        check(list.contentY > list.originY, "wheel reveals older entries")
        list.positionViewAtBeginning()
        input.keyClick(Qt.Key_Return)
        input.tryVerify(() => !menu.open, 1500)
        check(!menu.open, "keyboard restores selected image")
        menu.open = true
        input.tryVerify(() => list.count === 18, 1500)
        input.keyClick(Qt.Key_T)
        check(list.count === 1 && !menu.matches[0].binary, "typing filters clipboard previews")
        input.mouseClick(list.itemAtIndex(0))
        input.tryVerify(() => !menu.open, 1500)
        check(!menu.open, "click restores text")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
""", imports="import QtTest")
        self.assertEqual((self.directory / "result").read_bytes(), message)
        subprocess.run(["python3", str(REPO / "scripts/clipboard-history.py"), "copy-binary", "18"],
                       env=self.environment, check=True, capture_output=True)
        self.assertEqual((self.directory / "result").read_bytes(), payload.getvalue())
