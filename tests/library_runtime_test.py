"""Exercise the real Library window and helper with temporary, synthetic books."""
import json
import io
import shutil
import textwrap
import unittest
import zipfile

from PIL import Image

import settings_runtime_test as settings_tests
from library_test import archive


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class LibraryRuntimeTests(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def fault_helper(self, before_ready="", before_request=""):
        helper = self.directory / "helper.py"
        helper.write_text('''import argparse, json, sys, time
from pathlib import Path
sys.path.insert(0, %r)
from library import Library
parser = argparse.ArgumentParser()
for option in ("root", "state", "cache"):
    parser.add_argument("--" + option, required=True)
parser.add_argument("mode")
args = parser.parse_args()
backend = Library(args.root, args.state, args.cache)
%s
print(json.dumps({"ready": True}), flush=True)
for line in sys.stdin:
    request = json.loads(line)
    with Path(%r).open("a") as log:
        log.write(json.dumps(dict(root=args.root, **request)) + "\\n")
%s
    result = dict(backend.dispatch(request), ok=True, reply=request["id"], op=request["op"])
    print(json.dumps(result), flush=True)
''' % (str(settings_tests.REPO / "scripts"), before_ready,
       str(self.directory / "helper-requests.jsonl"), textwrap.indent(before_request, "    ")))
        return helper

    def test_folder_change_during_startup_uses_the_latest_folder(self):
        first, second = self.directory / "first", self.directory / "second"
        middle = self.directory / "middle"
        archive(middle / "Skipped book.cbz")
        chapter = first / "Old book.cbz"
        archive(chapter)
        archive(second / "New book.cbz")
        helper = self.fault_helper(before_ready="time.sleep(0.35)")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            controller.request({op: "mark", files: [%s], done: true})
            stage = 1
        } else if (stage === 1) {
            check(controller.starting && !controller.ready, "change occurs before handshake")
            Shell.Settings.setPath("libraryFolder", %s)
            Shell.Settings.setPath("libraryFolder", %s)
            stage = 2
        } else if (stage === 2 && controller.ready && !controller.busy && controller.books.length) {
            check(controller.configuredFolder === controller.folder, "helper uses the selected folder")
            check(controller.books[0].name === "New book", "new folder is indexed")
            check(!controller.restartWanted && controller.error === "", "restart finishes cleanly")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % tuple(json.dumps(str(path)) for path in (helper, first, chapter, middle, second)))
        requests = [json.loads(line) for line in (self.directory / "helper-requests.jsonl").read_text().splitlines()]
        self.assertTrue(all(request["root"] == str(second) for request in requests))
        self.assertFalse(any(request["op"] == "mark" for request in requests))

    def test_helper_exit_during_open_clears_loading_and_allows_q_and_retry(self):
        self.check_open_interruption("open")

    def test_helper_exit_fails_an_open_queued_behind_another_request(self):
        self.check_open_interruption("queued")

    def test_invalid_open_response_clears_loading_and_allows_retry(self):
        self.check_open_interruption("malformed")

    def check_open_interruption(self, mode):
        books = self.directory / "books"
        archive(books / "Series" / "001.cbz")
        archive(books / "Series" / "002.cbz")
        marker = self.directory / "failed-once"
        operation = "setting" if mode == "queued" else "open"
        action = 'print("not JSON", flush=True)\ncontinue' if mode == "malformed" else "sys.exit(3)"
        fault = ('if request["op"] == %r and not Path(%r).exists():\n'
                 '    Path(%r).touch()\n' % (operation, str(marker), str(marker)))
        helper = self.fault_helper(before_request=fault + textwrap.indent(action, "    "))
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    property var input: null
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            input = Qt.createQmlObject('import QtQuick; import QtTest; Item { property alias events: events; TestEvent { id: events } }',
                findItem(preview.contentItem, "libraryContent"), "failureInputTest")
            stage = 1
        } else if (stage === 1 && controller.ready && !controller.busy && controller.books.length) {
            preview.openBook(controller.books[0])
            %s
            preview.openChapter(0)
            stage = 2
        } else if (stage === 2 && !controller.busy && controller.error) {
            check(!preview.opening, "interrupted open clears loading")
            check(findItem(preview.contentItem, "libraryBack").enabled, "Back is enabled")
            check(input.events.keyClick(Qt.Key_Q, Qt.NoModifier, 0), "Q delivered after failure")
            check(preview.view === "chapters" && preview.visible, "Q leaves the failed reader")
            stage = 3
        } else if (stage === 3 && controller.ready && !controller.busy) {
            preview.openChapter(0)
            stage = 4
        } else if (stage === 4 && !controller.busy && !preview.opening && preview.pages.length === 3) {
            check(controller.error === "", "retry reconnects and reads successfully")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(helper)), json.dumps(str(books)),
       'controller.request({op: "setting", key: "rtl", value: true})' if mode == "queued" else ""))

    def test_folder_change_discards_stale_scan_results_and_queued_operations(self):
        first, second = self.directory / "first", self.directory / "second"
        chapter = first / "Old book.cbz"
        archive(chapter)
        archive(second / "New book.cbz")
        helper = self.fault_helper(before_request='''if request["op"] == "scan" and args.root == %r:
    time.sleep(0.35)''' % str(first))
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    property bool switched: false
    property string newFolder: %s
    Connections {
        target: preview.controller
        function onBooksChanged() {
            if (harness.switched)
                check(preview.controller.books.every(book => book.id.startsWith(harness.newFolder + "/")),
                    "late results from the old folder are ignored")
        }
    }
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.inFlight && controller.inFlight.op === "scan") {
            controller.request({op: "mark", files: [%s], done: true})
            switched = true
            Shell.Settings.setPath("libraryFolder", newFolder)
            stage = 2
        } else if (stage === 2 && controller.ready && !controller.busy && controller.books.length) {
            check(controller.books[0].name === "New book", "new folder replaces the old scan")
            check(controller.error === "", "folder switch finishes without an old error")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % tuple(json.dumps(str(path)) for path in (second, helper, first, chapter)))
        requests = [json.loads(line) for line in (self.directory / "helper-requests.jsonl").read_text().splitlines()]
        self.assertFalse(any(request["op"] == "mark" for request in requests))

    def test_failed_or_silent_startup_clears_requests_and_refresh_reconnects(self):
        books = self.directory / "books"
        chapter = books / "Example book.cbz"
        archive(chapter)
        other = self.directory / "other"
        archive(other / "Example book.cbz")
        for mode in ("missing", "silent", "missing-switch"):
            with self.subTest(mode=mode):
                helper = self.fault_helper(before_ready="time.sleep(2)") if mode == "silent" else (
                    self.directory / "missing-helper")
                self.run_qml('''
    Shell.LibraryService {
        id: controller
        onFailed: (operation, message) => {
            if (operation === "open") harness.openFailures++
        }
    }
    property int stage: 0
    property int openFailures: 0
    property var normalCommand: []
    property bool switchAfterFailure: %s
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (stage === 0) {
            normalCommand = controller.helperCommand
            controller.helperCommand = %s
            controller.startupTimeoutMs = 150
            Shell.Settings.setPath("libraryFolder", %s)
            controller.active = true
            controller.request({op: "open", file: %s})
            stage = 1
        } else if (stage === 1 && switchAfterFailure && controller.starting) {
            switchAfterFailure = false
            Shell.Settings.setPath("libraryFolder", %s)
        } else if (stage === 1 && !controller.busy && controller.error) {
            check(!controller.ready && !controller.starting && !controller.stopping, "startup failure is idle")
            check(controller.error.includes("did not start"), "startup failure has a useful error")
            check(openFailures === 1, "queued open receives one failure notification")
            controller.helperCommand = normalCommand
            controller.startupTimeoutMs = 5000
            controller.refresh()
            stage = 2
        } else if (stage === 2 && controller.ready && !controller.busy && controller.books.length) {
            check(controller.books[0].name === "Example book", "Refresh starts the normal helper")
            check(controller.error === "", "successful retry clears the error")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(mode == "missing-switch"),
       json.dumps(["python3", str(helper)] if mode == "silent" else [str(helper)]),
       json.dumps(str(books)), json.dumps(str(chapter)), json.dumps(str(other))))

    def test_same_window_resume_completion_marks_and_folder_switch(self):
        books = self.directory / "books"
        archive(books / "Example series" / "c002.cbz", dict(tags=["quiet"], language="English"))
        archive(books / "Example series" / "c010.cbz")
        archive(books / "Standalone.cbz")
        other = self.directory / "other books"
        archive(other / "Other book.cbz")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.books.length === 2 && !controller.busy) {
            check(preview.rtl && preview.fit === "page", "reader defaults")
            const series = controller.books.find(book => book.chapters.length === 2)
            preview.openBook(series)
            check(preview.view === "chapters", "opens chapters in the same window")
            preview.openChapter(0)
            stage = 2
        } else if (stage === 2 && !preview.opening && preview.pages.length === 3) {
            preview.goTo(2)
            controller.refresh()
            stage = 3
        } else if (stage === 3 && !controller.busy) {
            check(!preview.currentBook.chapters[0].done, "visiting last page does not mark read")
            preview.nextPage()
            stage = 4
        } else if (stage === 4 && preview.chapterIndex === 1 && !preview.opening && !controller.busy) {
            controller.refresh()
            stage = 5
        } else if (stage === 5 && !controller.busy) {
            check(preview.currentBook.chapters[0].done, "advancing past final page marks read")
            check(preview.view === "reader" && preview.visible, "next chapter stays in same window")
            const before = controller.books
            const inserted = Object.assign({}, preview.currentBook.chapters[0], {file: "synthetic inserted chapter"})
            const changed = Object.assign({}, preview.currentBook,
                {chapters: [inserted].concat(preview.currentBook.chapters)})
            controller.books = before.map(book => book.id === changed.id ? changed : book)
            check(preview.chapterIndex === 2, "imports preserve the open chapter by file identity")
            controller.books = before
            check(preview.chapterIndex === 1, "chapter index follows the refreshed model")
            preview.goTo(2)
            preview.nextPage()
            stage = 6
        } else if (stage === 6 && !controller.busy) {
            check(preview.view === "chapters", "last chapter returns to chapter list")
            check(preview.currentBook.done === 2, "whole series completed")
            preview.mark([preview.currentBook.chapters[0].file], false)
            stage = 7
        } else if (stage === 7 && !controller.busy) {
            check(!preview.currentBook.chapters[0].done, "manual unread works")
            Shell.Settings.setPath("libraryFolder", %s)
            stage = 8
        } else if (stage === 8 && !controller.busy && controller.books.length === 1) {
            check(preview.view === "library", "folder change returns to library")
            check(controller.books[0].name === "Other book", "new folder is indexed")
            preview.hideLibrary()
            preview.showLibrary()
            stage = 9
        } else if (stage === 9 && preview.visible && !controller.busy && controller.ready) {
            check(controller.error === "", "reopening works")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(books)), json.dumps(str(other))))

    def test_filtering_and_settings_folder_control(self):
        books = self.directory / "books"
        archive(books / "Quiet book.cbz", dict(tags=["quiet"], language="English"))
        archive(books / "Action book.cbz", dict(tags=["action"]))
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    Shell.SettingsWindow { id: preferences }
    property bool started: false
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (!started) {
            started = true
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
        } else if (preview.controller.books.length === 2 && !preview.controller.busy) {
            check(findItem(preferences.contentItem, "libraryFolderControl") !== null, "existing settings has library field")
            preview.filters = ({"tags:quiet": 1})
            check(preview.shownBooks.length === 1, "include tag")
            preview.filters = ({"tags:quiet": -1})
            check(preview.shownBooks[0].name === "Action book", "exclude tag")
            preview.filters = ({})
            findItem(preview.contentItem, "librarySearch").text = "Quiet"
            check(preview.shownBooks.length === 1, "title search")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)))

    def test_grid_scroll_survives_reading_refresh_and_reopening(self):
        books = self.directory / "books"
        for index in range(40):
            archive(books / f"Book {index:02d}.cbz")
        archive(books / "Series 40" / "001.cbz")
        archive(books / "Series 40" / "002.cbz")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    property real savedY: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        const grid = findItem(preview.contentItem, "libraryGrid")
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.ready && !controller.busy && grid.count === 41) {
            grid.currentIndex = grid.count - 2
            grid.positionViewAtIndex(grid.currentIndex, GridView.End)
            grid.contentY = Math.max(0, grid.contentHeight - grid.height - 37)
            savedY = grid.contentY
            check(savedY > grid.cellHeight, "fixture scrolls well below the first row")
            preview.openBook(grid.model[grid.currentIndex])
            stage = 2
        } else if (stage === 2 && !preview.opening && preview.pages.length === 3) {
            preview.back()
            stage = 3
        } else if (stage === 3 && preview.view === "library" && !controller.busy) {
            check(Math.abs(grid.contentY - savedY) < 1, "standalone return preserves grid offset after progress refresh")
            const series = controller.books.find(book => book.chapters.length === 2)
            grid.currentIndex = grid.model.findIndex(book => book.id === series.id)
            grid.positionViewAtIndex(grid.currentIndex, GridView.End)
            savedY = grid.contentY
            preview.openBook(series)
            preview.openChapter(0)
            stage = 4
        } else if (stage === 4 && !preview.opening && preview.pages.length === 3) {
            preview.back()
            stage = 5
        } else if (stage === 5 && preview.view === "chapters" && !controller.busy) {
            preview.back()
            stage = 6
        } else if (stage === 6 && preview.view === "library" && !controller.busy) {
            check(Math.abs(grid.contentY - savedY) < 1, "chapter-list return preserves the same grid offset: "
                + grid.contentY + " expected " + savedY + " remembered " + grid.savedY)
            preview.hideLibrary()
            preview.showLibrary()
            stage = 7
        } else if (stage === 7 && controller.ready && !controller.busy) {
            check(Math.abs(grid.contentY - savedY) < 1, "reopening Library preserves the grid offset")
            findItem(preview.contentItem, "librarySearch").text = "Book 01"
            stage = 8
        } else if (stage === 8 && grid.count === 1) {
            check(Math.abs(grid.contentY - grid.originY) < 1, "a new search starts at the top")
            findItem(preview.contentItem, "librarySearch").text = ""
            stage = 9
        } else if (stage === 9 && grid.count === 41) {
            check(grid.currentIndex === 0, "clearing search selects the first result")
            grid.positionViewAtIndex(grid.count - 1, GridView.End)
            preview.filters = ({"tags:no-match": 1})
            stage = 10
        } else if (stage === 10 && grid.count === 0) {
            check(Math.abs(grid.contentY - grid.originY) < 1, "an empty filter resets the scroll")
            preview.filters = ({})
            stage = 11
        } else if (stage === 11 && grid.count === 41) {
            check(grid.currentIndex === 0, "clearing filters restores keyboard selection")
            grid.positionViewAtIndex(grid.count - 1, GridView.End)
            preview.sort = "name"
            stage = 12
        } else if (stage === 12) {
            check(Math.abs(grid.contentY - grid.originY) < 1, "a new sort order starts at the top")
            grid.positionViewAtIndex(grid.count - 1, GridView.End)
            controller.books = controller.books.slice(0, 1)
            stage = 13
        } else if (stage === 13 && grid.count === 1) {
            check(Math.abs(grid.contentY - grid.originY) < 1, "a shorter list clamps the remembered offset")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)))

    def test_chapter_click_selection_direction_toggle_and_q_exit(self):
        books = self.directory / "books"
        archive(books / "Example series" / "c001.cbz")
        archive(books / "Example series" / "c002.cbz")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    property var input: null
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            const content = findItem(preview.contentItem, "libraryContent")
            input = Qt.createQmlObject('import QtQuick; import QtTest; Item { property alias events: events; TestEvent { id: events } }',
                content, "libraryInputTest")
            stage = 1
        } else if (stage === 1 && controller.books.length === 1 && !controller.busy) {
            preview.openBook(controller.books[0])
            stage = 2
        } else if (stage === 2) {
            const row = findItem(preview.contentItem, "libraryChapterRow1")
            if (!row) return
            check(input.events.mouseClick(row, 50, 30, Qt.LeftButton, Qt.NoModifier, 0), "chapter click delivered")
            check(findItem(preview.contentItem, "libraryChapters").currentIndex === 1, "click selects the second chapter")
            check(row.selected && row.border.width === 2, "clicked chapter is highlighted")
            findItem(preview.contentItem, "libraryDownloads").forceActiveFocus()
            check(row.selected && row.border.width === 2, "selection remains visible without list focus")
            findItem(preview.contentItem, "libraryChapters").forceActiveFocus()
            check(input.events.keyClick(Qt.Key_Return, Qt.NoModifier, 0), "Enter delivered")
            stage = 3
        } else if (stage === 3 && !preview.opening && preview.pages.length === 3 && !controller.busy) {
            check(preview.chapterIndex === 1, "Enter opens the clicked chapter")
            check(input.events.keyClick(Qt.Key_D, Qt.NoModifier, 0), "direction key delivered")
            check(!preview.rtl, "D switches to left-to-right")
            check(input.events.keyClick(Qt.Key_Right, Qt.NoModifier, 0), "Right Arrow delivered")
            check(preview.page === 1, "Right Arrow advances in left-to-right mode")
            check(input.events.keyClick(Qt.Key_Q, Qt.NoModifier, 0), "Q delivered")
            check(preview.view === "chapters" && preview.visible, "Q leaves the reader without closing Library")
            stage = 4
        } else if (stage === 4 && !controller.busy) {
            check(preview.currentBook.chapters[1].page === 1, "Q saves reading position")
            check(!preview.rtl, "direction preference is retained")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)))

    def test_progress_saves_are_combined_and_flushed_on_completion_and_close(self):
        books = self.directory / "books"
        first, second = books / "Series" / "001.cbz", books / "Series" / "002.cbz"
        archive(first)
        archive(second)
        helper = self.fault_helper()
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.books.length && !controller.busy) {
            preview.openBook(controller.books[0])
            preview.openChapter(0)
            stage = 2
        } else if (stage === 2 && !preview.opening && preview.pages.length) {
            for (let index = 0; index < 100; ++index) preview.goTo(index %% 3)
            preview.goTo(2)
            preview.nextPage()
            stage = 3
        } else if (stage === 3 && !preview.opening && preview.chapterIndex === 1 && preview.pages.length) {
            for (let index = 0; index < 100; ++index) preview.goTo(index %% 2)
            preview.goTo(1)
            stage = 4
        } else if (stage === 4 && !controller.busy) {
            preview.goTo(2)
            preview.hideLibrary()
            stage = 5
        } else if (stage === 5 && !controller.busy && !preview.visible) {
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(helper)), json.dumps(str(books))))
        requests = [json.loads(line) for line in (self.directory / "helper-requests.jsonl").read_text().splitlines()]
        progress = [request for request in requests if request["op"] == "progress"]
        self.assertEqual(len(progress), 3, progress)
        first_saves = [request for request in progress if request["file"] == str(first)]
        second_saves = [request for request in progress if request["file"] == str(second)]
        self.assertEqual([(item["page"], item["done"]) for item in first_saves], [(2, True)])
        self.assertEqual([item["page"] for item in second_saves], [1, 2])
        state = json.loads(next((self.directory / "state").rglob("reading.json")).read_text())
        self.assertTrue(state["progress"][str(first)]["done"])
        self.assertEqual(state["progress"][str(second)]["page"], 2)

    def test_reader_images_and_preloader_decode_to_display_size(self):
        books = self.directory / "books"
        books.mkdir()
        stream = io.BytesIO()
        Image.new("RGB", (1600, 2400), "#61737d").save(stream, "JPEG")
        with zipfile.ZipFile(books / "Large pages.cbz", "w") as output:
            output.writestr("001.jpg", stream.getvalue())
            output.writestr("002.jpg", stream.getvalue())
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        const image = findItem(preview.contentItem, "libraryPageImage")
        const preload = findItem(preview.contentItem, "libraryPagePreloader")
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.books.length && !controller.busy) {
            const grid = findItem(preview.contentItem, "libraryGrid")
            check(grid.cellWidth >= 332 && grid.cellHeight === 504, "grid has larger covers")
            preview.openBook(controller.books[0])
            stage = 2
        } else if (stage === 2 && image.status === Image.Ready && preload.status === Image.Ready) {
            check(image.implicitWidth < 1600 && image.implicitHeight < 2400, "page uses a smaller decoded image")
            check(preload.implicitWidth < 1600 && preload.implicitHeight < 2400, "preloader uses a smaller decoded image")
            check(!image.mipmap, "page does not allocate unused mipmaps")
            preview.setFit("width")
            stage = 3
        } else if (stage === 3 && image.status === Image.Ready
                && image.height > findItem(preview.contentItem, "libraryPageViewport").height) {
            check(Math.abs(image.height / image.width - 1.5) < 0.01, "fit-width preserves page proportions")
            check(image.implicitWidth < 1600, "fit-width still bounds the decoded width")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)))

    def test_mouse_wheel_scrolls_grid_and_reader_then_turns_at_page_end(self):
        books = self.directory / "books"
        for index in range(18):
            archive(books / f"Book {index:02d}.cbz")
        tall = books / "Tall.cbz"
        pixels = io.BytesIO()
        Image.new("RGB", (800, 2400), "#8aafbd").save(pixels, "PNG")
        with zipfile.ZipFile(tall, "w") as output:
            output.writestr("001.png", pixels.getvalue())
            output.writestr("002.png", pixels.getvalue())
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    TestCase { id: input; when: false }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        const grid = findItem(preview.contentItem, "libraryGrid")
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.books.length === 19 && !controller.busy) {
            input.mouseWheel(grid, 100, 100, 0, -120)
            check(grid.contentY === Math.min(Config.scrolling.wheelStep, grid.contentHeight - grid.height), "grid wheel scrolls over a cover")
            input.mouseWheel(grid, 100, 100, 0, -240)
            check(grid.contentY === Math.min(3 * Config.scrolling.wheelStep, grid.contentHeight - grid.height), "grid handler stays in the viewport after scrolling")
            preview.setFit("width")
            preview.openBook(controller.books.find(book => book.name === "Tall"))
            stage = 2
        } else if (stage === 2 && !preview.opening
                && findItem(preview.contentItem, "libraryPageImage").status === Image.Ready) {
            const flick = findItem(preview.contentItem, "libraryPageViewport")
            input.mouseWheel(flick, 100, 100, 0, -120)
            check(flick.contentY === Math.min(Config.scrolling.wheelStep, flick.contentHeight - flick.height) && preview.page === 0, "reader scrolls before turning pages")
            input.mouseWheel(flick, 100, 100, 0, -240)
            check(flick.contentY === Math.min(3 * Config.scrolling.wheelStep, flick.contentHeight - flick.height), "reader respects wheel delta and clamps to the page end")
            flick.contentY = flick.contentHeight - flick.height
            input.mouseWheel(flick, 100, 100, 0, -120)
            check(preview.page === 1, "wheel turns the page at its bottom")
            preview.setFit("page")
            input.mouseWheel(flick, 100, 100, 0, 120)
            check(preview.page === 0, "fit-page wheel still turns pages")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)), imports='import QtTest\nimport "source/config.js" as Config')

    def test_auto_turn_timing_manual_reset_stop_and_saved_delay(self):
        books = self.directory / "books"
        archive(books / "Book.cbz")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    TestCase { id: input; when: false }
    property int stage: 0
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && preview.controller.books.length && !preview.controller.busy) {
            preview.openBook(preview.controller.books[0])
            stage = 2
        } else if (stage === 2 && !preview.opening
                && findItem(preview.contentItem, "libraryPageImage").status === Image.Ready) {
            running = false
            const button = findItem(preview.contentItem, "libraryAutoTurn")
            const delay = findItem(preview.contentItem, "libraryAutoTurnSeconds")
            check(!preview.autoTurning && delay.value === 10, "auto-turn starts off with a ten-second default")
            delay.value = 1
            delay.valueModified()
            input.mouseClick(button)
            check(preview.autoTurning && !delay.activeFocus, "start control enables auto-turn and focuses reader")
            input.wait(550)
            check(preview.page === 0, "first page receives its full delay")
            preview.nextPage()
            input.wait(650)
            check(preview.page === 1, "manual turn resets the countdown")
            input.wait(450)
            check(preview.page === 2, "timer advances after a full new interval")
            input.mouseClick(button)
            input.wait(1100)
            check(preview.page === 2 && preview.view === "reader" && !preview.autoTurning, "stop cancels the timer")
            input.mouseClick(button)
            preview.back()
            check(!preview.autoTurning, "leaving the reader switches auto-turn off")
            input.wait(150)
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)), imports="import QtTest")
        state = next((self.directory / "state").rglob("reading.json"))
        self.assertEqual(json.loads(state.read_text())["settings"]["autoTurnSeconds"], 1)
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    Component.onCompleted: preview.showLibrary()
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!preview.controller.ready || preview.controller.busy) return
        check(preview.autoTurnSeconds === 1, "delay survives a fresh shell instance")
        check(!preview.autoTurning, "enabled state is never restored")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''')

    def test_auto_turn_waits_during_loading_and_editing_and_stops_on_error(self):
        books = self.directory / "books"
        archive(books / "Book.cbz")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    TestCase { id: input; when: false }
    property int stage: 0
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && preview.controller.books.length && !preview.controller.busy) {
            preview.openBook(preview.controller.books[0])
            stage = 2
        } else if (stage === 2 && !preview.opening
                && findItem(preview.contentItem, "libraryPageImage").status === Image.Ready) {
            running = false
            preview.setAutoTurnSeconds(1)
            preview.autoTurning = true
            preview.opening = true
            input.wait(1100)
            check(preview.page === 0, "loading time does not advance pages")
            preview.opening = false
            const delay = findItem(preview.contentItem, "libraryAutoTurnSeconds")
            delay.forceActiveFocus()
            input.wait(1100)
            check(preview.page === 0, "editing the delay pauses auto-turn")
            const button = findItem(preview.contentItem, "libraryAutoTurn")
            input.mouseClick(button)
            input.mouseClick(button)
            check(!delay.activeFocus, "auto-turn control returns focus to the page")
            preview.minimized = true
            input.wait(1100)
            check(preview.page === 0, "minimizing pauses auto-turn")
            preview.minimized = false
            input.wait(1100)
            check(preview.page === 1, "ready page advances after leaving the editor")
            preview.imageError = "Synthetic image failure"
            check(!preview.autoTurning, "image failure stops auto-turn")
            preview.imageError = ""
            preview.autoTurning = true
            preview.hideLibrary()
            check(!preview.autoTurning, "closing Library stops auto-turn")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)), imports="import QtTest")

    def test_auto_turn_continues_to_next_chapter_and_finishes_series(self):
        books = self.directory / "books"
        for name in ("001.cbz", "002.cbz"):
            path = books / "Series" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            pixels = io.BytesIO()
            Image.new("RGB", (100, 160), "#8aafbd").save(pixels, "PNG")
            with zipfile.ZipFile(path, "w") as output:
                output.writestr("page.png", pixels.getvalue())
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    TestCase { id: input; when: false }
    property int stage: 0
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && preview.controller.books.length && !preview.controller.busy) {
            preview.openBook(preview.controller.books[0])
            preview.openChapter(0)
            stage = 2
        } else if (stage === 2 && !preview.opening
                && findItem(preview.contentItem, "libraryPageImage").status === Image.Ready) {
            preview.setAutoTurnSeconds(1)
            preview.autoTurning = true
            stage = 3
        } else if (stage === 3 && preview.chapterIndex === 1 && !preview.opening) {
            check(preview.autoTurning && preview.page === 0, "auto-turn continues into the next chapter")
            stage = 4
        } else if (stage === 4 && preview.view === "chapters" && !preview.controller.busy) {
            check(!preview.autoTurning, "finishing the series stops auto-turn")
            check(preview.currentBook.done === 2, "both chapters are marked read")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)), imports="import QtTest")

    def test_fullscreen_hides_panels_and_f_and_f11_restore_them(self):
        books = self.directory / "books"
        archive(books / "Book.cbz")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    TestCase { id: input; when: false }
    property int stage: 0
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        if (stage === 0) {
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && preview.controller.books.length && !preview.controller.busy) {
            preview.openBook(preview.controller.books[0])
            stage = 2
        } else if (stage === 2 && !preview.opening
                && findItem(preview.contentItem, "libraryPageImage").status === Image.Ready) {
            running = false
            preview.downloadsVisible = true
            const content = findItem(preview.contentItem, "libraryContent")
            const page = findItem(preview.contentItem, "libraryPageViewport")
            const header = findItem(preview.contentItem, "libraryHeader")
            const controls = findItem(preview.contentItem, "libraryPageControls")
            const automatic = findItem(preview.contentItem, "libraryAutoTurnControls")
            const downloads = findItem(preview.contentItem, "libraryDownloadsPanel")
            input.keyClick(Qt.Key_F)
            input.wait(150)
            check(preview.fullscreen && preview.pageOnly, "F enters fullscreen reading")
            check(!header.visible && !controls.visible && !automatic.visible && !downloads.visible,
                  "fullscreen hides every button panel, including open downloads")
            check(content.padding === 0, "fullscreen removes outer padding")
            check(page.width === content.width && page.height === content.height, "page viewport fills the window")
            input.keyClick(Qt.Key_Left)
            check(preview.page === 1, "page navigation works with hidden controls")
            input.keyClick(Qt.Key_F)
            input.wait(100)
            check(!preview.fullscreen && header.visible && controls.visible && automatic.visible && downloads.visible,
                  "F restores panels and the previous downloads visibility")
            check(content.padding > 0, "windowed padding returns")
            input.keyClick(Qt.Key_F11)
            input.wait(100)
            check(preview.pageOnly && !header.visible, "F11 uses the same page-only mode")
            input.keyClick(Qt.Key_F11)
            input.wait(100)
            check(!preview.fullscreen && controls.visible, "F11 also restores the controls")
            input.keyClick(Qt.Key_F)
            input.wait(100)
            input.keyClick(Qt.Key_Q)
            input.wait(100)
            check(preview.view === "library" && header.visible && !preview.pageOnly,
                  "leaving the reader restores browsing controls even in a fullscreen window")
            const search = findItem(preview.contentItem, "librarySearch")
            search.forceActiveFocus()
            input.keyClick(Qt.Key_F)
            check(search.text === "f" && preview.fullscreen, "F remains ordinary text in the library search")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % json.dumps(str(books)), imports="import QtTest")

    def test_status_poll_does_not_change_refresh_button(self):
        books = self.directory / "books"
        books.mkdir()
        helper = self.fault_helper(before_request="if request['op'] == 'status': time.sleep(0.3)")
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    property real buttonWidth: 0
    property real buttonX: 0
    Timer { interval: 40; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        const button = findItem(preview.contentItem, "libraryRefresh")
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.ready && !controller.busy) {
            buttonWidth = button.width
            buttonX = button.x
            controller.status()
            stage = 2
        } else if (stage === 2) {
            check(controller.inFlight && controller.inFlight.op === "status", "poll is in flight")
            check(button.text === "Refresh" && button.enabled, "background polling does not look like loading")
            check(button.width === buttonWidth && button.x === buttonX, "poll leaves button geometry stable")
            controller.refresh()
            check(button.text === "Loading…" && !button.enabled, "explicit refresh still indicates loading")
            stage = 3
        } else if (stage === 3 && !controller.busy) {
            check(button.width === buttonWidth && button.x === buttonX, "refresh leaves button geometry stable")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(helper)), json.dumps(str(books))))

    def test_folder_switch_flushes_pending_progress_before_restarting_the_helper(self):
        first, second = self.directory / "first", self.directory / "second"
        chapter = first / "Old book.cbz"
        archive(chapter)
        archive(second / "New book.cbz")
        helper = self.fault_helper(before_request='if request["op"] == "setting": time.sleep(0.2)')
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.books.length && !controller.busy) {
            preview.openBook(controller.books[0])
            stage = 2
        } else if (stage === 2 && !preview.opening && preview.pages.length) {
            preview.goTo(2)
            preview.setDirection(false)
            preview.goTo(1)
            Shell.Settings.setPath("libraryFolder", %s)
            stage = 3
        } else if (stage === 3 && controller.ready && !controller.busy
                && controller.books.length && controller.books[0].name === "New book") {
            check(controller.error === "", "folder switch finishes cleanly")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(helper)), json.dumps(str(first)), json.dumps(str(second))))
        state = json.loads(next((self.directory / "state").rglob("reading.json")).read_text())
        self.assertEqual(state["progress"][str(chapter)]["page"], 1)

    def test_discard_working_files_requires_dialog_confirmation(self):
        books = self.directory / "books"
        chapter = books / "Saved book.cbz"
        archive(chapter)
        stage = books / ".library-downloads" / "synthetic"
        stage.mkdir(parents=True)
        (stage / "page.part").write_text("unfinished")
        job = dict(id="synthetic", root=str(books), url="https://reader.example.test/gallery", status="failed",
                   outputs=[], error="Test failure", files=0)
        helper = self.fault_helper(before_ready='from library import atomic_json\n'
                                  'atomic_json(backend.queue_path, %r)' % dict(jobs=[job]))
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    function findPopup(item, name) {
        if (item.objectName === name) return item
        for (const child of item.data || []) {
            const found = findPopup(child, name)
            if (found) return found
        }
        return null
    }
    property int stage: 0
    Timer { interval: 80; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        const dialog = findPopup(preview.contentItem, "libraryDiscardDialog")
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.downloadsVisible = true
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.jobs.length && !controller.busy) {
            const button = findItem(preview.contentItem, "libraryDiscardFiles_synthetic")
            if (!button) return
            check(!!dialog, "discard dialog exists")
            button.clicked()
            check(dialog.visible, "discard opens a confirmation dialog")
            dialog.reject()
            check(!controller.jobs[0].discarded, "cancel keeps the working files")
            button.clicked()
            dialog.accept()
            stage = 2
        } else if (stage === 2 && !controller.busy && controller.jobs[0].discarded) {
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(helper)), json.dumps(str(books))))
        self.assertFalse(stage.exists())
        self.assertTrue(chapter.exists())

    def test_reading_and_cover_updates_remain_responsive_during_indexing(self):
        books = self.directory / "books"
        for index in range(4):
            archive(books / f"Book {index}.cbz")
        helper = self.directory / "slow-covers.py"
        helper.write_text('''import sys, time
sys.path.insert(0, %r)
import library
original = library.Library.cover
def slow_cover(self, *args, **kwargs):
    if kwargs.get("generate", True): time.sleep(0.3)
    return original(self, *args, **kwargs)
library.Library.cover = slow_cover
library.main()
''' % str(settings_tests.REPO / "scripts"))
        self.run_qml('''
    Shell.LibraryWindow { id: preview }
    property int stage: 0
    property string readingFile: ""
    Timer { interval: 60; repeat: true; running: true; onTriggered: {
        if (!Shell.Settings.ready) return
        const controller = preview.controller
        if (stage === 0) {
            controller.helperCommand = ["python3", %s]
            Shell.Settings.setPath("libraryFolder", %s)
            preview.showLibrary()
            stage = 1
        } else if (stage === 1 && controller.scanning && controller.books.some(book => !!book.cover)
                && controller.books.some(book => !book.cover)) {
            preview.openBook(controller.books[0])
            readingFile = preview.currentFile
            stage = 2
        } else if (stage === 2 && !preview.opening && preview.pages.length) {
            check(controller.scanning, "reader opens before cover generation finishes")
            preview.goTo(1)
            preview.back()
            stage = 3
        } else if (stage === 3 && !controller.busy && controller.books.every(book => !!book.cover)) {
            const book = controller.books.find(item => item.chapters.some(chapter => chapter.file === readingFile))
            const chapter = book.chapters.find(item => item.file === readingFile)
            check(chapter.page === 1, "refresh during indexing includes the latest progress")
            check(controller.error === "", "streamed covers and refresh finish cleanly")
            console.log("TEST_PASSED")
            Qt.quit()
        }
    } }
''' % (json.dumps(str(helper)), json.dumps(str(books))))


if __name__ == "__main__":
    unittest.main()
