import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import QtQuick.Effects
import QtQuick.Shapes

import "config.js" as Config
import "secrets.js" as Secrets


PanelWindow {
    id: dashboard
    signal closeRequested()
    property var historyModel
    property int activeTab: 0

    property bool open: false
    property bool closing: false
    property bool panelHovered: false
    visible: open || closing
    onOpenChanged: closing = !open

    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth() + 1

    property real cpuValue: 0
    property real ramValue: 0
    property real diskValue: 0
    property real gpuValue: 0

    // Performance tab details
    property real cpuFreqGhz: 0
    property real cpuTemp: 0
    property real gpuTemp: 0
    property string gpuName: ""
    property var coreLoads: []
    property real ramUsedGb: 0
    property real ramTotalGb: 0
    property real netUpMbs: 0
    property real netDownMbs: 0
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property int processCount: 0

    // For clock
    property string currentTime: Qt.formatTime(new Date(), "h:mm AP")
    property string currentDate: Qt.formatDate(new Date(), "dddd, d MMMM yyyy")

    property string userName: Quickshell.env("USER")

    property string weatherTemp: "--"
    property string weatherDesc: ""
    property string weatherLocation: ""
    property string weatherHigh: "--"
    property string weatherLow: "--"
    property string weatherHumidity: "--"
    property string weatherWindSpeed: "--"
    property string weatherWindDir: ""
    property var weatherForecast: []
    property real weatherLat: Secrets.lat
    property real weatherLon: Secrets.lon
    property int mapZoom: 7
    property var radarFrames: []
    property int radarIdx: 0

    property string sysOs: ""
    property string sysKernel: ""
    property string sysWm: Quickshell.env("XDG_CURRENT_DESKTOP")
    property string sysUptime: ""

    readonly property bool wifiEnabled: Networking.wifiEnabled
    readonly property bool bluetoothEnabled: Bluetooth.defaultAdapter !== null && Bluetooth.defaultAdapter.enabled
    property bool dndEnabled: false
    property bool nightEnabled: false

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ]

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // ── System stats processes ──
    Process {
        id: cpuProc
        command: ["bash", "-c", "top -bn1 | grep '^%Cpu' | awk '{printf \"%d\", $2+$4}'"]
        stdout: StdioCollector { id: cpuOut }
        onExited: { var v = parseFloat(cpuOut.text.trim()); if (!isNaN(v)) dashboard.cpuValue = v }
    }

    Process {
        id: ramProc
        command: ["bash", "-c", "free -m | awk 'NR==2{printf \"%d\", $3*100/$2}'"]
        stdout: StdioCollector { id: ramOut }
        onExited: { var v = parseFloat(ramOut.text.trim()); if (!isNaN(v)) dashboard.ramValue = v }
    }

    Process {
        id: diskProc
        command: ["bash", "-c", "df / | awk 'NR==2{print $5}' | tr -d '%'"]
        stdout: StdioCollector { id: diskOut }
        onExited: { var v = parseFloat(diskOut.text.trim()); if (!isNaN(v)) dashboard.diskValue = v }
    }

    Process {
        id: gpuProc
        command: ["bash", "-c", "nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits"]
        stdout: StdioCollector { id: gpuOut }
        onExited: { var v = parseFloat(gpuOut.text.trim()); if (!isNaN(v)) dashboard.gpuValue = v }
    }

    Process {
        id: perfProc
        command: ["bash", Quickshell.env("HOME") + "/.config/quickshell/scripts/perf.sh"]
        stdout: StdioCollector { id: perfOut }
        onExited: {
            try {
                const d = JSON.parse(perfOut.text)
                dashboard.cpuValue = d.cpu
                dashboard.coreLoads = d.cores
                dashboard.cpuFreqGhz = d.freq
                dashboard.cpuTemp = d.ctemp
                dashboard.gpuValue = d.gpu
                dashboard.gpuTemp = d.gtemp
                dashboard.gpuName = d.gname
                dashboard.ramValue = d.ramT > 0 ? 100 * d.ramU / d.ramT : 0
                dashboard.ramUsedGb = d.ramU
                dashboard.ramTotalGb = d.ramT
                dashboard.netUpMbs = d.up
                dashboard.netDownMbs = d.down
                dashboard.diskUsedGb = d.diskU
                dashboard.diskTotalGb = d.diskT
                dashboard.processCount = d.procs
            } catch (e) {}
        }
    }

    Timer {
        interval: Config.timer.interval
        running: dashboard.visible
        repeat: true
        triggeredOnStart: true

        onTriggered: {
            // Clock
            dashboard.currentTime = Qt.formatTime(new Date(), "h:mm AP")
            dashboard.currentDate = Qt.formatDate(new Date(), "dddd, d MMMM yyyy")

            // Only update stats when on correct tab
            if (dashboard.activeTab === 3) {
                if (!perfProc.running) perfProc.running = true
            }
        }
    }

    // ── System info ──
    Process {
        id: osProc
        command: ["bash", "-c", "grep PRETTY_NAME /etc/os-release | cut -d'\"' -f2"]
        stdout: StdioCollector { id: osOut }
        onExited: dashboard.sysOs = osOut.text.trim()
    }
    Process {
        id: kernelProc
        command: ["uname", "-r"]
        stdout: StdioCollector { id: kernelOut }
        onExited: dashboard.sysKernel = kernelOut.text.trim()
    }
    Process {
        id: uptimeProc
        command: ["bash", "-c", "awk '{h=int($1/3600);m=int(($1%3600)/60);print h\"h \"m\"m\"}' /proc/uptime"]
        stdout: StdioCollector { id: uptimeOut }
        onExited: dashboard.sysUptime = uptimeOut.text.trim()
    }
    Process {
        id: nightCheckProc
        command: ["bash", "-c", "pgrep -x wlsunset > /dev/null && echo yes || echo no"]
        stdout: StdioCollector { id: nightCheckOut }
        onExited: dashboard.nightEnabled = nightCheckOut.text.trim() === "yes"
    }
    Process { id: actionProc; command: ["echo"] }

    Component.onCompleted: {
        osProc.running = true
        kernelProc.running = true
        uptimeProc.running = true
        nightCheckProc.running = true
        if (dashboard.weatherLat === 0 || dashboard.weatherLon === 0)
            locProc.running = true
    }

    // ── Weather ──
    // Resolve location by IP unless secrets.js pins a fixed lat/lon
    Process {
        id: locProc
        command: ["bash", "-c", "curl -sf 'http://ip-api.com/json'"]
        stdout: StdioCollector { id: locOut }
        onExited: {
            try {
                const d = JSON.parse(locOut.text)
                if (d.status === "success") {
                    dashboard.weatherLat = d.lat
                    dashboard.weatherLon = d.lon
                }
            } catch(e) {}
        }
    }

    Process {
        id: weatherProc
        command: ["bash", "-c",
            "echo \"{\\\"cur\\\":$(curl -sf 'https://api.openweathermap.org/data/2.5/weather?lat="
            + dashboard.weatherLat + "&lon=" + dashboard.weatherLon
            + "&units=metric&appid=" + Secrets.owmApiKey
            + "'),\\\"fc\\\":$(curl -sf 'https://api.openweathermap.org/data/2.5/forecast?lat="
            + dashboard.weatherLat + "&lon=" + dashboard.weatherLon
            + "&units=metric&appid=" + Secrets.owmApiKey + "')}\""]
        stdout: StdioCollector { id: weatherOut }
        onExited: {
            try {
                const d = JSON.parse(weatherOut.text)
                const cur = d.cur
                dashboard.weatherTemp = "" + Math.round(cur.main.temp)
                dashboard.weatherDesc = cur.weather[0].description
                dashboard.weatherLocation = cur.name
                dashboard.weatherHumidity = "" + cur.main.humidity
                dashboard.weatherWindSpeed = cur.wind.speed.toFixed(1)
                dashboard.weatherWindDir = dashboard.windDir16(cur.wind.deg)

                // Group the 3-hour forecast entries by date
                const days = []
                const byDate = {}
                for (const item of d.fc.list) {
                    const date = item.dt_txt.split(" ")[0]
                    if (!byDate[date]) { byDate[date] = []; days.push(date) }
                    byDate[date].push(item)
                }
                const daily = days.map(date => {
                    const items = byDate[date]
                    // Condition from the entry closest to midday
                    let mid = items[0]
                    for (const it of items) {
                        const h = parseInt(it.dt_txt.split(" ")[1])
                        if (Math.abs(h - 12) < Math.abs(parseInt(mid.dt_txt.split(" ")[1]) - 12))
                            mid = it
                    }
                    return {
                        day: Qt.formatDate(new Date(date), "ddd").toUpperCase(),
                        desc: mid.weather[0].main,
                        high: Math.round(Math.max(...items.map(i => i.main.temp_max))),
                        low: Math.round(Math.min(...items.map(i => i.main.temp_min)))
                    }
                })
                if (daily.length > 0) {
                    dashboard.weatherHigh = "" + daily[0].high
                    dashboard.weatherLow = "" + daily[0].low
                }
                dashboard.weatherForecast = daily.slice(0, 3)
            } catch(e) {}
        }
    }

    // RainViewer radar frame index (past 2h + nowcast when available)
    Process {
        id: radarProc
        command: ["bash", "-c", "curl -sf 'https://api.rainviewer.com/public/weather-maps.json'"]
        stdout: StdioCollector { id: radarOut }
        onExited: {
            try {
                const d = JSON.parse(radarOut.text)
                const frames = []
                for (const f of d.radar.past)
                    frames.push({ time: f.time, url: d.host + f.path, future: false })
                for (const f of (d.radar.nowcast || []))
                    frames.push({ time: f.time, url: d.host + f.path, future: true })
                dashboard.radarFrames = frames
                // Rest on the newest past frame ("now") until the loop warms up
                dashboard.radarIdx = Math.max(0, d.radar.past.length - 1)
            } catch(e) {}
        }
    }

    Timer {
        interval: Config.timer.weatherRefresh
        running: dashboard.visible && dashboard.weatherLat !== 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!weatherProc.running) weatherProc.running = true
            if (!radarProc.running) radarProc.running = true
        }
    }

    Timer {
        interval: Config.timer.hardwareRefresh
        running: dashboard.visible && dashboard.activeTab === 0
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (!cpuProc.running)  cpuProc.running  = true
            if (!ramProc.running)  ramProc.running  = true
            if (!diskProc.running) diskProc.running = true
            if (!gpuProc.running)  gpuProc.running  = true
        }
    }

    ListModel { id: todoListModel }
    property alias todoList: todoListModel

    // Persistent to-do storage: ~/.local/state/quickshell/todos.json
    FileView {
        id: todoFile
        path: Quickshell.statePath("todos.json")
        watchChanges: false
        JsonAdapter {
            id: todoData
            property var todos: []
        }
        onLoaded: {
            todoListModel.clear()
            for (const t of todoData.todos)
                todoListModel.append({ taskText: t.taskText, done: t.done })
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) writeAdapter()
        }
    }

    function saveTodos() {
        const arr = []
        for (let i = 0; i < todoListModel.count; i++) {
            const t = todoListModel.get(i)
            arr.push({ taskText: t.taskText, done: t.done })
        }
        todoData.todos = arr
        todoFile.writeAdapter()
    }

    function greeting() {
        const hour = new Date().getHours();

        if (hour < 5)
            return "Good night";
        if (hour < 12)
            return "Good morning";
        if (hour < 18)
            return "Good afternoon";

        return "Good evening";
    }

    function toggleWifi() {
        Networking.wifiEnabled = !Networking.wifiEnabled
    }
    function toggleBluetooth() {
        if (Bluetooth.defaultAdapter)
            Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
    }
    function toggleNight() {
        actionProc.command = nightEnabled
            ? ["pkill", "wlsunset"]
            : ["wlsunset", "-T", "5000"]
        actionProc.startDetached()
        nightEnabled = !nightEnabled
    }

    function windDir16(deg) {
        const dirs = ["N","NNE","NE","ENE","E","ESE","SE","SSE","S","SSW","SW","WSW","W","WNW","NW","NNW"]
        return dirs[Math.round(((deg % 360) / 22.5)) % 16]
    }

    // Slippy-map tile coordinate conversions
    function lonToTileX(lon, z) { return (lon + 180) / 360 * Math.pow(2, z) }
    function latToTileY(lat, z) {
        const rad = lat * Math.PI / 180
        return (1 - Math.asinh(Math.tan(rad)) / Math.PI) / 2 * Math.pow(2, z)
    }
    function tileXToLon(x, z) { return x / Math.pow(2, z) * 360 - 180 }
    function tileYToLat(y, z) {
        return Math.atan(Math.sinh(Math.PI * (1 - 2 * y / Math.pow(2, z)))) * 180 / Math.PI
    }

    function weatherIcon(desc) {
        const d = (desc || "").toLowerCase()
        if (d.includes("thunder") || d.includes("storm")) return "󰙾"
        if (d.includes("snow") || d.includes("sleet") || d.includes("blizzard")) return "󰼶"
        if (d.includes("rain") || d.includes("drizzle") || d.includes("shower")) return "󰖗"
        if (d.includes("fog") || d.includes("mist") || d.includes("haze")) return "󰖑"
        if (d.includes("overcast")) return "󰅣"
        if (d.includes("cloud")) return ""
        if (d.includes("clear") || d.includes("sunny") || d.includes("sun")) return "󰖨"
        return ""
    }

    MouseArea {
        anchors.fill: parent
        onClicked: dashboard.closeRequested()
    }

    Item {
        id: hero
        anchors.horizontalCenter: parent.horizontalCenter
        width: 1500
        height: 1200
        y: dashboard.open ? 0 : -height

        Behavior on y {
            NumberAnimation {
                duration: Config.anim.slide
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !dashboard.open) dashboard.closing = false
            }
        }

        MouseArea { anchors.fill: parent }
        HoverHandler {
            onHoveredChanged: dashboard.panelHovered = hovered
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: Config.radius.hero
            bottomRightRadius: Config.radius.hero
            color: Colors.surface
        //border.width: 8
        //border.color: Colors.border
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Config.gap.xl
            spacing: 8

            // ══ Tab bar ══
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Repeater {
                    model: [
                        { icon: "󰕮", label: "Dashboard"     },
                        { icon: "󰃭", label: "Calendar"      },
                        { icon: "󰝚", label: "Media"         },
                        { icon: "󰓅", label: "Performance"   }
                    ]
                    delegate: Item {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        height: 50

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: dashboard.activeTab === index
                                ? Qt.rgba(0.29, 0.33, 0.42, 0.12)
                                : "transparent"
                        }

                        Text {
                            anchors.centerIn: parent
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.icon
                            color: dashboard.activeTab === index
                                ? Colors.textStrong : Colors.border
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.display
                        }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: parent.width * 0.5
                            height: 4
                            radius: Config.radius.sm
                            color: Colors.subtext
                            visible: dashboard.activeTab === index
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: dashboard.activeTab = index
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 4
                color: Colors.border
                opacity: 0.75
            }

            // ══ Content area ══
            Item {
                id: contentArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                DashboardTab {
                    y: 0
                    width: contentArea.width
                    height: contentArea.height
                    x: (0 - dashboard.activeTab) * contentArea.width
                    dashboard: dashboard
                    Behavior on x {
                        NumberAnimation { duration: Config.anim.tabSlide; easing.type: Easing.OutCubic }
                    }
                }

                CalendarTab {
                    y: 0
                    width: contentArea.width
                    height: contentArea.height
                    x: (1 - dashboard.activeTab) * contentArea.width
                    dashboard: dashboard
                    Behavior on x {
                        NumberAnimation { duration: Config.anim.tabSlide; easing.type: Easing.OutCubic }
                    }
                }

                MediaTab {
                    y: 0
                    width: contentArea.width
                    height: contentArea.height
                    x: (2 - dashboard.activeTab) * contentArea.width
                    dashboard: dashboard
                    Behavior on x {
                        NumberAnimation { duration: Config.anim.tabSlide; easing.type: Easing.OutCubic }
                    }
                }

                PerformanceTab {
                    y: 0
                    width: contentArea.width
                    height: contentArea.height
                    x: (3 - dashboard.activeTab) * contentArea.width
                    dashboard: dashboard
                    Behavior on x {
                        NumberAnimation { duration: Config.anim.tabSlide; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
        }
    }
}
