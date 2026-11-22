"""Check the dashboard layout and palette in isolated offscreen windows."""
import os
import shutil
import unittest

import settings_runtime_test as settings_tests


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class DashboardRuntimeTest(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def test_dashboard_sizes_input_and_palette(self):
        repo = settings_tests.REPO
        preview = self.directory / "preview"
        preview.mkdir()
        for source in [*repo.glob("*.qml"), *repo.glob("*.js"), repo / "qmldir"]:
            if source.name != "secrets.js":
                shutil.copy(source, preview)
        for folder in ("Bar", "Tabs", "Widgets"):
            shutil.copytree(repo / folder, preview / folder)
        shutil.copy(repo / "secrets.js.example", preview / "secrets.js")

        # Offscreen Qt can render the dashboard in a floating window
        source = (preview / "Dashboard.qml").read_text()
        source = source.replace("PanelWindow {", "FloatingWindow {", 1)
        source = source.replace("    anchors { left: true; right: true; top: true; bottom: true }", "")
        source = source.replace("    exclusionMode: ExclusionMode.Normal", "")
        source = source.replace("    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand", "")
        (preview / "Dashboard.qml").write_text(source)

        # Keep weather, system and finance queries out of the layout test
        commands = self.directory / "bin"
        commands.mkdir()
        (commands / "bash").symlink_to(shutil.which("true"))
        self.environment.update(
            HOME=str(self.directory), PATH=str(commands) + os.pathsep + os.environ["PATH"],
            DBUS_SESSION_BUS_ADDRESS=f"unix:path={self.directory}/run/test-bus",
            http_proxy="http://127.0.0.1:9", https_proxy="http://127.0.0.1:9",
        )
        checks = '''
    function findText(item, value) {
        if (item.text === value) return item
        for (const child of item.children || []) {
            const match = findText(child, value)
            if (match) return match
        }
        return null
    }

    QtObject {
        id: player
        property bool isPlaying: false
        property string trackTitle: "Test track"
        property string trackArtist: "Test artist"
        property string trackAlbum: ""
        property string trackArtUrl: ""
        property bool canGoPrevious: true
        property bool canGoNext: true
        property bool lengthSupported: false
    }
    TestCase { id: input; when: false }

    function checkOverview(overview) {
        preview.cpuValue = 0
        preview.gpuValue = 100
        preview.ramValue = 42.6
        preview.diskValue = 71.2
        const hardware = findText(overview, "HARDWARE").parent
        for (const [glyph, reading] of [["", "0%"], ["󰾲", "100%"], ["󰘚", "43%"], ["", "71%"]]) {
            const icon = findText(hardware, glyph)
            check(icon && icon.visible, "hardware icon is visible: " + glyph)
            const percent = findText(icon.parent, reading)
            check(percent && percent.y + percent.height <= icon.y, reading + " appears above its icon")
        }

        const music = findItem(overview, "dashboardMusicCard")
        const map = findItem(overview, "weatherRadarMap")
        const idleWidth = map.width
        check(!music.visible, "empty player leaves the grid")
        if (expectedColumns === 3) {
            const greeting = findText(overview, preview.currentTime).parent.parent
            const gauges = hardware.parent
            check(gauges.y === greeting.y + greeting.height + Config.gap.lg,
                "hardware sits directly below the greeting")
        }
        if (expectedColumns > 1) {
            const lastDay = findText(overview, "MON")
            const dayCorner = lastDay.mapToItem(map, lastDay.width, lastDay.height)
            check(dayCorner.x <= 0 && dayCorner.y <= map.height, "forecast sits beside the radar")
        }
        music.player = player
        input.wait(80)
        check(music.visible && music.height > 250, "paused player has room for album art and controls")
        if (expectedColumns > 1) check(map.width < idleWidth, "idle layout gives more width to the map")
        music.player = null
        input.wait(80)
        check(!music.visible && map.width === idleWidth, "removing the player restores the idle layout")
        const forecast = preview.weatherForecast
        preview.weatherForecast = []
        preview.weatherLat = 0
        input.wait(40)
        const heading = findText(overview, expectedColumns > 1 ? "Forecast" : "WEATHER FORECAST")
        check(!heading.visible && !map.visible, "missing forecast and radar leave only current conditions")
        preview.weatherForecast = forecast
        preview.weatherLat = 60
        input.wait(40)

        const shortTitle = "Screenshot copied"
        const longTitle = "A notification with a long summary. ".repeat(24)
        for (const summary of [shortTitle, longTitle]) {
            preview.historyModel.append({summary, body: "", time: "12:58", image: "", appIcon: ""})
        }
        input.wait(80)
        const shortText = findText(overview, shortTitle)
        const longText = findText(overview, longTitle)
        check(shortText.lineCount === 1 && !shortText.truncated, "short title stays on one line")
        check(longText.lineCount === 2 && longText.truncated, "long title uses two lines then elides")
        const row = longText.parent.parent
        const timestamp = findText(row, "12:58")
        check(longText.mapToItem(row, longText.width, 0).x <= timestamp.mapToItem(row, 0, 0).x,
            "wrapped text leaves room for the timestamp")
        preview.historyModel.clear()
    }

    Timer { interval: 800; running: true; onTriggered: {
        const panel = findItem(preview.contentItem, "dashboardPanel")
        const viewport = findItem(panel, "dashboardTabViewport")
        const overview = viewport.contentItem.children[0]
        check(panel.width === Math.min(1500, preview.width - 2 * Config.radius.fillet), "panel fits width")
        check(panel.height === Math.min(1200, preview.height - Config.frame.thin), "panel fits height")
        check(overview.cardColumns === expectedColumns, "overview wraps at this width")
        checkOverview(overview)

        const palette = Preview.Colors
        const clock = findText(overview, preview.currentTime)
        const temperature = findText(overview, "23°")
        const dnd = findText(overview, "DND")
        const tile = dnd.parent.parent
        const emptyState = findText(overview, "No notifications")
        check(Qt.colorEqual(clock.color, palette.text), "clock uses foreground")
        check(Qt.colorEqual(temperature.color, palette.text), "temperature uses foreground")
        check(Qt.colorEqual(emptyState.color, palette.subtext), "empty history is muted")
        check(Qt.colorEqual(tile.color, palette.inset), "idle toggle uses inset")
        preview.dndEnabled = true
        check(Qt.colorEqual(dnd.color, palette.text), "enabled label uses foreground")
        check(Qt.colorEqual(tile.color, Qt.alpha(palette.accent, 0.18)), "on state uses the current accent")
        const lightSlots = {}
        for (let slot = 0; slot < 16; slot++) lightSlots["color" + slot] = "#405368"
        lightSlots.color3 = "#175f9c"
        palette.wal = {special: {background: "#eef3f8", foreground: "#172532"}, colors: lightSlots}
        check(palette.isLight && Qt.colorEqual(clock.color, "#172532"), "clock follows the light palette")
        check(Qt.colorEqual(tile.color, Qt.alpha("#175f9c", 0.18)), "enabled tile follows the light palette")

        if (expectedColumns < 3) {
            check(viewport.contentHeight > viewport.height, "short window has overflow")
            input.mouseWheel(viewport, 25, 35, 0, -120)
            check(viewport.contentY > 0, "wheel scrolls overview")
        }
        const position = viewport.contentY
        const tabs = ["Calendar", "Finance", "Performance", "Dashboard"]
        for (let index = 0; index < tabs.length; index++) {
            const label = findText(panel, tabs[index])
            check(label && label.visible, tabs[index] + " label is visible")
            input.mouseClick(label)
            const tabIndex = (index + 1) % 4
            check(preview.activeTab === tabIndex, "label selects " + tabs[index])
            if (expectedColumns === 1 && tabIndex !== 0) {
                input.wait(650)
                const page = viewport.parent.children[tabIndex]
                check(page.contentHeight > page.height, tabs[index] + " can scroll on a short screen")
                input.mouseWheel(page, 10, 10, 0, -120)
                check(page.contentY > 0, "wheel scrolls " + tabs[index])
            }
        }
        check(viewport.contentY === position, "tab switch retains scroll position")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
'''
        for width, height, columns in [(1920, 1440, 3), (1280, 720, 2), (720, 480, 1)]:
            with self.subTest(width=width, height=height):
                window = f"""
    readonly property int expectedColumns: {columns}
    Preview.Dashboard {{
        id: preview
        implicitWidth: {width}
        implicitHeight: {height}
        open: true
        weatherTemp: "23"
        weatherLat: 60
        weatherForecast: ["SAT", "SUN", "MON"].map(day => ({{day, high: 2, low: -2, desc: "clouds"}}))
        historyModel: ListModel {{}}
    }}
"""
                output = self.run_qml(window + checks, imports=(
                    'import "preview" as Preview\nimport "preview/config.js" as Config\nimport QtTest'
                ))
                self.assertNotIn("already taken", output)


if __name__ == "__main__":
    unittest.main()
