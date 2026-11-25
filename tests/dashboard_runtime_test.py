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

    def prepare_dashboard(self):
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
        return commands

    def test_finance_selection_and_offline_location_retry(self):
        commands = self.prepare_dashboard()
        (commands / "bash").unlink()
        bash = commands / "bash"
        bash.write_text('''#!/usr/bin/python3
import json, os, sys, time
from pathlib import Path
if sys.argv[1].endswith("fetch-quotes.sh"):
    time.sleep(0.25)
    (Path(os.environ["HOME"]) / "online").touch()
    quote = dict(ok=True, price=10, prev=9, cur="USD", range=sys.argv[2], t=[], c=[], o=[], h=[], l=[])
    print(json.dumps({"series": [dict(quote, sym=s, name=s) for s in sys.argv[4:]]}))
elif sys.argv[1].endswith("fetch-weather.sh"):
    print(json.dumps({"cur":{"main":{"temp":10,"humidity":70},"name":"Resolved",
        "weather":[{"description":"clear"}],"wind":{"speed":0,"deg":0}}, "fc":{"list":[]}}))
''')
        bash.chmod(0o755)
        curl = commands / "curl"
        curl.write_text('''#!/usr/bin/python3
import os
from pathlib import Path
if (Path(os.environ["HOME"]) / "online").exists():
    print('{"status":"success","lat":0,"lon":22}')
''')
        curl.chmod(0o755)
        self.run_qml('''
    Preview.Dashboard {
        id: dash
        implicitWidth: 800; implicitHeight: 600
        historyModel: ListModel {}
        onFinanceSeriesChanged: {
            for (const entry of financeSeries)
                check(entry.range === "1d", "old candles must never be published")
        }
    }
    TestCase { id: input; when: false }
    Timer { interval: 80; running: true; onTriggered: {
        dash.open = true
        dash.activeTab = 2
        input.wait(100)
        check(dash.financeLoading && !dash.hasWeatherLocation, "first requests are outstanding or offline")
        dash.setFinanceRange(1)
        dash.setFinanceRange(0)
        dash.removeFinanceSymbol(0)
        input.tryVerify(() => !dash.financeLoading && dash.financeSeries.length > 0, 3000)
        check(dash.financeSeries.length === dash.financeSymbols.length, "new watchlist is fetched")
        check(dash.financeUpdated !== "", "fresh results receive an update time")
        dash.open = false
        input.tryVerify(() => !dash.visible, 2000)
        dash.open = true
        input.tryVerify(() => dash.weatherLocation === "Resolved", 2000)
        check(dash.hasWeatherLocation && dash.weatherLat === 0, "equatorial lookup refreshes weather")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports='import "preview" as Preview\nimport QtTest')

    def test_finance_candle_tints_follow_palette(self):
        self.prepare_dashboard()
        self.run_qml('''
    FloatingWindow {
        visible: true
        implicitWidth: 200
        implicitHeight: 100
        Preview.PriceChart {
            id: chart
            anchors.fill: parent
            mode: "candle"
            series: ({ok: true, t: [1, 2], o: [10, 20], c: [20, 10], h: [21, 21], l: [9, 9]})
        }
    }
    TestCase { id: input; when: false }
    Timer { interval: 100; running: true; onTriggered: {
        for (const [up, down] of [["#60a075", "#c77573"], ["#d09f45", "#cd843a"],
                                  ["#ed4040", "#40c060"], ["#888888", "#888888"]]) {
            const slots = {}
            for (let i = 0; i < 16; i++) slots["color" + i] = "#888888"
            slots.color1 = down
            slots.color2 = up
            Preview.Colors.wal = {special: {background: "#181818", foreground: "#eeeeee"}, colors: slots}
            input.wait(60)
            const image = input.grabImage(chart)
            const rise = image.pixel(50, 50)
            const fall = image.pixel(150, 50)
            check(rise.g > Math.max(rise.r, rise.b) + 0.05, "rising candle reads green with " + up)
            check(fall.r > Math.max(fall.g, fall.b) + 0.05, "falling candle reads red with " + down)
            check(fall.hslHue < 20 / 360 || fall.hslHue > 335 / 360, "warm palettes produce a red-toned candle")
            if (up === "#60a075") {
                for (const [painted, base] of [[rise, Preview.Colors.ok], [fall, Preview.Colors.error]]) {
                    for (const channel of ["r", "g", "b"])
                        check(Math.abs(painted[channel] - base[channel]) < 0.05, "matching colors keep a light tint")
                }
            }
        }
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports='import "preview" as Preview\nimport QtTest')

    def test_storage_refreshes_on_open(self):
        commands = self.prepare_dashboard()
        df = commands / "df"
        df.write_text("""#!/bin/sh
if [ -e "$HOME/detached" ]; then exit 1; fi
if [ -e "$HOME/attached" ]; then touch "$HOME/detached"; exit 0; fi
touch "$HOME/attached"
echo '/dev/sdb1 ext4 1024 256 75% /mnt/usb'
""")
        df.chmod(0o755)
        self.run_qml('''
    FloatingWindow {
        visible: true
        Preview.StorageCard { id: card; active: false }
    }
    TestCase { id: input; when: false }
    Timer { interval: 80; running: true; onTriggered: {
        check(card.status === "Reading disks…", "inactive card has not queried disk usage")
        card.active = true
        input.tryVerify(() => card.volumes.length === 1, 1000)
        check(card.volumes[0].mount === "/mnt/usb", "mounted drive is visible")
        card.active = false
        card.active = true
        input.tryVerify(() => card.status === "No mounted local disks", 1000)
        check(card.volumes.length === 0, "detached drive is removed")
        card.active = false
        card.active = true
        input.tryVerify(() => card.status === "Disk usage unavailable", 1000)
        check(card.status === "Disk usage unavailable", "failed read has an error state")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports='import "preview" as Preview\nimport QtTest')

    def test_dashboard_sizes_input_and_palette(self):
        commands = self.prepare_dashboard()
        df = commands / "df"
        df.write_text("""#!/bin/sh
cat <<'DISKS'
Filesystem Type 1B-blocks Avail Use% Mounted on
/dev/sda1 ext4 2147483648 536870912 75% /
tmpfs tmpfs 1073741824 1073741824 0% /run
/dev/mapper/Media Disk fuseblk 1099511627776 0 100% /mnt/Media Disk
/dev/sda2 ext4 2147483648 536870912 75% /home
/dev/sdb1 vfat 2147483648 536870912 75% /boot
tank/archive zfs 2147483648 536870912 75% /mnt/archive-with-a-very-long-mount-name
DISKS
""")
        df.chmod(0o755)
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

    function checkRadarDrag(viewport, map) {
        const middle = map.mapToItem(viewport.contentItem, map.width / 2, map.height / 2)
        viewport.contentY = Math.min(viewport.contentHeight - viewport.height,
            Math.max(0, middle.y - viewport.height / 2))
        const before = viewport.contentY
        const x = map.width / 2
        const y = map.height / 2
        input.mousePress(map, x, y)
        let latitude = map.centerLat
        for (const distance of [15, 30, 45, 60]) {
            input.mouseMove(map, x, y - distance, 10, Qt.LeftButton)
            check(map.centerLat < latitude, "each drag move pans the radar")
            latitude = map.centerLat
        }
        input.mouseRelease(map, x, y - 60)
        check(viewport.contentY === before, "radar pan keeps the page in place")
        viewport.contentY = 0
    }

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

    function checkHistory(overview, page) {
        const shortTitle = "Screenshot copied"
        const longTitle = "A notification with a long summary. ".repeat(24)
        page.contentY = Math.max(0, page.contentHeight - page.height)
        const paragraphs = Array.from({length: 16}, (_, i) => "Line " + (i + 1)).join("\\n")
        for (const [summary, body] of [[longTitle, ""], [shortTitle, paragraphs]]) {
            preview.historyModel.insert(0, {summary, body, time: "12:59", image: "", appIcon: ""})
            input.wait(50)
            const text = findText(overview, body || summary)
            const entry = text.parent.parent.parent
            const arrow = findText(entry, "▾")
            check(arrow.visible && text.truncated, "truncated history entry offers expansion")
            const initialHeight = entry.height
            input.mouseClick(arrow)
            input.wait(50)
            check(entry.expanded && !text.truncated && entry.height > initialHeight,
                "clicking the history arrow reveals the full message")
            input.mouseClick(text, 4, 4)
            input.wait(50)
            check(!entry.expanded && text.truncated && entry.height === initialHeight,
                "clicking the first line collapses the message")
            preview.historyModel.clear()
        }
        const senderPreview = "This is a shortened terminal notification. ".repeat(5).slice(0, 197) + "..."
        preview.historyModel.append({summary: senderPreview, body: "", time: "12:59", image: "", appIcon: ""})
        input.wait(50)
        const saved = findText(overview, senderPreview)
        const disclosure = findText(saved.parent.parent.parent, "▾")
        check(saved.truncated === disclosure.visible, "only text clipped by the dashboard has a disclosure")
        if (expectedColumns === 3)
            check(!disclosure.visible && saved.lineCount === 2, "the complete 200-character sender preview fits")
        preview.historyModel.clear()
        for (let i = 0; i < 18; i++)
            preview.historyModel.append({summary: "Earlier " + i, body: "", time: "12:58", image: "", appIcon: ""})
        preview.historyModel.append({summary: shortTitle, body: paragraphs, time: "12:59", image: "", appIcon: ""})
        input.wait(50)
        const lastBody = findText(overview, paragraphs)
        const entry = lastBody.parent.parent.parent
        let list = entry.parent
        while (list.contentY === undefined) list = list.parent
        list.contentY = list.contentHeight - list.height
        input.mouseClick(findText(entry, "▾"))
        input.wait(80)
        const top = entry.mapToItem(list, 0, 0).y
        const shown = Math.min(list.height, top + entry.height) - Math.max(0, top)
        check(entry.expanded && shown >= Math.min(entry.height, list.height) - 1,
            "expanding bottom row reveals the text inside the clipped history list: " + shown + "/" + list.height)
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
        const radar = findItem(overview, "weatherRadarMap")
        check(radar.basemapUrl.endsWith("/dark_all/"), "dark theme uses labelled dark tiles")
        if (expectedColumns === 3) {
            preview.radarFrames = [{time: 1700000000, url: "file:///unused"}]
            input.wait(30)
            const pause = findText(radar, "")
            check(pause && pause.visible, "radar shows the pause action")
            input.mouseClick(pause)
            check(!radar.radarPlaying && pause.text === "", "timestamp pauses the radar")
            input.mouseClick(pause)
            check(radar.radarPlaying, "radar can resume")
            preview.radarFrames = []
        }
        const lightSlots = {}
        for (let slot = 0; slot < 16; slot++) lightSlots["color" + slot] = "#405368"
        lightSlots.color3 = "#175f9c"
        lightSlots.color4 = "#71369c"
        lightSlots.color5 = "#975237"
        lightSlots.color6 = "#328477"
        palette.wal = {special: {background: "#eef3f8", foreground: "#172532"}, colors: lightSlots}
        check(palette.isLight && Qt.colorEqual(clock.color, "#172532"), "clock follows the light palette")
        check(Qt.colorEqual(tile.color, Qt.alpha("#175f9c", 0.18)), "enabled tile follows the light palette")

        check(radar.basemapUrl.endsWith("/rastertiles/voyager/"), "light theme restores Voyager")
        const performance = viewport.parent.children[3].contentItem
        for (const [name, icon, role] of [["CPU","",palette.cpu], ["RAM","󰘚",palette.ram],
                                         ["GPU","󰾲",palette.gpu], ["VRAM","󰾲",palette.gpu]]) {
            const label = findText(performance, name)
            const gaugeIcon = label.parent.children[0]
            check(Qt.colorEqual(gaugeIcon.color, role), name + " uses its resource color")
            check(Qt.colorEqual(findText(overview, icon).color, role), name + " matches overview")
        }

        if (expectedColumns < 3) {
            check(viewport.contentHeight > viewport.height, "short window has overflow")
            checkRadarDrag(viewport, findItem(overview, "weatherRadarMap"))
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
            if (tabs[index] === "Performance") {
                input.tryVerify(() => findText(performance, "/Media Disk") !== null, 1000)
                const name = findText(performance, "/Media Disk")
                check(findText(name.parent, "100%"), "full disk shows its percentage")
                check(findText(name.parent.parent, "0 B free of 1.0 TiB"), "disk capacity uses binary units")
                check(!findText(performance, "/run"), "memory filesystems are filtered out")
                const first = findText(performance, "/")
                const last = findText(performance, "/archive-with-a-very-long-mount-name")
                check(name.mapToItem(performance, 0, 0).y > first.mapToItem(performance, 0, 0).y
                      || last.mapToItem(performance, 0, 0).y > first.mapToItem(performance, 0, 0).y,
                      "extra disks wrap to another row")
                const page = viewport.parent.children[tabIndex]
                const card = findText(performance, "DISK USAGE").parent.parent.parent
                for (const label of [name, last]) {
                    const percent = label.parent.children[1]
                    check(percent.mapToItem(performance, percent.width, 0).x <= page.contentWidth,
                          "disk usage fits the scrollable page")
                    const detail = label.parent.parent.children[1]
                    check(detail.mapToItem(card, 0, detail.height).y <= card.height,
                          "capacity reading fits inside the storage card")
                }
            }
            if (expectedColumns === 1 && tabIndex !== 0) {
                input.wait(650)
                const page = viewport.parent.children[tabIndex]
                check(page.contentHeight > page.height, tabs[index] + " can scroll on a short screen")
                if (tabs[index] === "Performance") {
                    preview.netDownMbs = 1234.5
                    input.wait(30)
                    const reading = findText(page.contentItem, "1234.5 MB/s")
                    const right = reading.mapToItem(page.contentItem, reading.implicitWidth, 0).x
                    check(right <= page.contentWidth, "the entire network reading fits the scrollable page")
                }
                input.mouseWheel(page, 10, 10, 0, -120)
                check(page.contentY > 0, "wheel scrolls " + tabs[index])
            }
        }
        check(viewport.contentY === position, "tab switch retains scroll position")
        input.wait(650)
        checkHistory(overview, viewport)
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
        weatherLon: 22
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
