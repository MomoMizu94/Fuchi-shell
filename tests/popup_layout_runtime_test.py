"""Render notification and mixer states in isolated offscreen windows."""
import shutil
import unittest

import settings_runtime_test as settings_tests


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class PopupLayoutTest(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def floating_panel(self, name):
        source = (settings_tests.REPO / (name + ".qml")).read_text()
        source = source.replace('import "config.js"', 'import "source"\nimport "source/config.js"')
        source = source.replace("PanelWindow {", "FloatingWindow {", 1)
        return "\n".join(line for line in source.splitlines() if not line.startswith(
            ("    anchors {", "    margins {", "    exclusionMode:")))

    def test_notification_timeouts_and_close_reason(self):
        (self.directory / "Popup.qml").write_text(self.floating_panel("NotificationPopup"))
        self.run_qml('''
    property var expired: []
    function notification(name, timeout, urgency) {
        return {summary: name, body: "", appName: "Test", appIcon: "", image: "",
                expireTimeout: timeout, urgency,
                expire: () => { expired = expired.concat(name) },
                dismiss: () => check(false, "timer must report expiration")}
    }
    Popup { notifModel: [
        notification("persistent", 0, NotificationUrgency.Normal),
        notification("short", 120, NotificationUrgency.Normal),
        notification("default", -1, NotificationUrgency.Normal),
        notification("critical", -1, NotificationUrgency.Critical)
    ] }
    Component.onCompleted: Shell.Settings.setValue("notificationTimeout", 1000)
    Timer { interval: 400; running: true; onTriggered:
        check(expired.join(",") === "short", "sender controls positive and zero timeouts") }
    Timer { interval: 1500; running: true; onTriggered: {
        check(expired.join(",") === "short,default", "only normal default uses shell duration")
        console.log("TEST_PASSED"); Qt.quit()
    } }
''', 'import Quickshell.Services.Notifications')

    def test_notification_text_icon_and_artwork_sizes(self):
        (self.directory / "Popup.qml").write_text(self.floating_panel("NotificationPopup"))
        self.run_qml('''
    Popup { id: popup; notifModel: variants }
    property string message: "A message that wraps to several lines. ".repeat(28)
    property string headline: "An unusually long notification title ".repeat(25)
    property var variants: ["Text only", "Small icon", "Preview", "Missing image", "Spotify", "Long text", headline, "Long image"].map(
        (summary, i) => ({summary, body: i === 5 || i === 7 ? message : "", urgency: 2, appName: i === 4 ? "Spotify" : "Test",
                         appIcon: i === 1 ? Qt.resolvedUrl("source/assets/record.gif").toString() : "",
                         image: i === 2 || i === 7 ? Qt.resolvedUrl("source/assets/record.gif")
                              : i === 3 ? Qt.resolvedUrl("absent.png") : ""}))
    function label(item, text) {
        if (item.text === text) return item
        for (const child of item.children) {
            const found = label(child, text)
            if (found) return found
        }
        return null
    }
    Timer { interval: 200; running: true; onTriggered: {
        const labels = variants.map(n => label(popup.contentItem, n.summary))
        const boxes = labels.map(t => t.parent.parent.parent)
        check(boxes[0].height === 104, "one-line text notification is compact")
        check(boxes[1].height === 160, "icon notification uses the full card height")
        check(boxes[2].height === 160, "artwork has its large preview")
        check(boxes[3].height === boxes[0].height, "failed image releases its space")
        check(labels[0].width > labels[1].width && labels[1].width === labels[2].width,
              "unused image width returns to the text")
        check(boxes[4].height === boxes[0].height, "Spotify without artwork starts compact")
        check(boxes[5].height === boxes[0].height && boxes[7].height === boxes[2].height,
              "message length does not change either card height")
        for (const index of [5, 7]) {
            const body = label(boxes[index], message)
            check(body.lineCount === 2 && body.truncated, "long body ends on its second line")
        }
        check(labels[6].lineCount === 2 && labels[6].truncated && boxes[6].height === boxes[0].height,
              "summary-only message also truncates after two lines")
        popup.spotifyArtUrl = Qt.resolvedUrl("source/assets/record.gif")
        verifyArt.start()
    } }
    Timer { id: verifyArt; interval: 100; onTriggered: {
        check(label(popup.contentItem, "Spotify").parent.parent.parent.height === 160,
              "late album art gets a preview")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''')

    def test_history_expansion_and_hardware_hover(self):
        self.run_qml('''
    QtObject {
        id: readings
        property real cpuValue: 15
        property real gpuValue: 40
        property real ramValue: 50
        property real diskValue: 75
        property real cpuTemp: 61
        property real gpuTemp: 0
        property real ramUsedGb: 7.5
        property real ramTotalGb: 15
        property real diskUsedGb: 375
        property real diskTotalGb: 500
        property ListModel historyModel: ListModel {}
    }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 500; implicitHeight: 690
        ColumnLayout {
            anchors.fill: parent
            Shell.HardwareCard { id: hardware; dashboard: readings; Layout.fillWidth: true; Layout.preferredHeight: 210 }
            Shell.NotificationHistoryCard { id: history; dashboard: readings }
        }
    }
    TestCase { id: input; when: false; parent: window.contentItem }
    function label(item, text) {
        if (item.text === text) return item
        for (const child of item.children) {
            const found = label(child, text)
            if (found) return found
        }
        return null
    }
    function add(title, body) {
        readings.historyModel.append({summary: title, body, time: "12:34", image: "", appIcon: ""})
    }
    Timer { interval: 120; running: true; onTriggered: {
        const message = "long message ".repeat(25)
        add("Long body", message)
        add("Short", "One line.")
        input.wait(60)
        const body = label(history, message)
        const entry = body.parent.parent.parent
        const small = label(history, "Short").parent.parent.parent
        check(body.truncated && body.lineCount === 2 && entry.canExpand, "body collapses to two lines")
        check(!small.canExpand, "short messages have no disclosure")
        input.mouseClick(body)
        input.wait(50)
        check(entry.expanded && body.lineCount > 2 && !body.truncated, "row click reveals full body")
        input.mouseClick(body)
        input.wait(50)
        check(!entry.expanded && body.truncated && body.lineCount === 2, "second click collapses")
        input.mouseClick(label(entry, ""))
        input.wait(40)
        check(readings.historyModel.count === 1 && !small.expanded, "dismiss only removes the clicked entry")

        for (const [glyph, detail] of [["", "CPU · 61 °C"], ["󰾲", "GPU · Temperature unavailable"],
                                       ["󰘚", "RAM · 7.5 / 15.0 GiB"], ["", "Disk · 375 / 500 GiB"]]) {
            const icon = label(hardware, glyph)
            const metric = icon.parent
            const tip = metric.data.find(c => c.opened !== undefined)
            input.mouseMove(metric, 5, 5)
            input.wait(420)
            check(tip.opened && tip.text === detail, "hover opens the correct reading for " + glyph)
            for (const point of [Qt.point(5, 5), Qt.point(metric.width - 5, metric.height - 5)]) {
                input.mouseMove(metric, point.x, point.y)
                input.wait(30)
                const cursor = metric.mapToItem(window.contentItem, point.x, point.y)
                const corner = tip.contentItem.mapToItem(window.contentItem, -tip.leftPadding, -tip.topPadding)
                check(tip.opened && Math.abs(corner.y - cursor.y - 12) <= 1,
                      "tooltip follows the pointer vertically on " + glyph)
                const expectedX = Math.min(cursor.x + 12, window.width - tip.width - tip.margins)
                check(Math.abs(corner.x - expectedX) <= 1, "tooltip x for " + glyph + " expected " + expectedX + ", got " + corner.x)
            }
            if (glyph === "") {
                readings.cpuTemp = 63
                check(tip.text === "CPU · 63 °C", "visible tooltip follows sensor updates")
            }
            input.mouseMove(history, 8, 8)
            input.wait(160)
            check(!tip.visible, "leaving hides the tooltip")
        }
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', 'import QtTest\nimport QtQuick.Layouts')

    def test_mixer_sections_and_stream_controls(self):
        data = self.directory / "data"
        apps = data / "applications"
        apps.mkdir(parents=True)
        icon = settings_tests.REPO / "assets/record.gif"
        (apps / "org.example.MixerPlayer.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Music player\nExec=mixer-player\n"
            f"Icon={icon}\nStartupWMClass=mixer-player\n")
        self.environment.update(XDG_DATA_HOME=str(data), MIXER_TEST_ICON=str(icon))
        source = self.floating_panel("VolumeMenu")
        source = source.replace("    id: volumeMenu", "    id: volumeMenu\n    required property var backend", 1)
        source = source.replace("Pipewire.", "volumeMenu.backend.")
        start = source.index("    PwObjectTracker {")
        end = source.index("\n    }", start) + len("\n    }")
        (self.directory / "Mixer.qml").write_text(source[:start] + source[end:])
        self.run_qml('''
    QtObject {
        id: audio
        property real volume: 0.65
        property bool muted: false
    }
    QtObject {
        id: radioAudio
        property real volume: 0.8
        property bool muted: false
    }
    QtObject {
        id: pipe
        property var nodes: ({values: [
            ...Array.from({length: 9}, (_, id) => ({id, isStream: false, isSink: true, audio,
                description: "USB Audio Interface Output " + id})),
            {id: 10, isSink: false, isStream: false, audio, name: "Microphone"},
            {id: 11, isStream: true, type: PwNodeType.AudioOutStream, audio, description: "Playback",
                properties: {"application.process.binary": "mixer-player", "application.name": "Music player"}}
        ]})
        property var defaultAudioSink: nodes.values[0]
        property var defaultAudioSource: nodes.values[9]
        property var preferredDefaultAudioSink
        property var preferredDefaultAudioSource
    }
    Mixer { id: mixer; backend: pipe; open: true; implicitWidth: 800; implicitHeight: 720 }
    TestCase { id: input; when: false; parent: mixer.contentItem }
    function find(item, predicate) {
        if (predicate(item)) return item
        for (const child of item.children) {
            const found = find(child, predicate)
            if (found) return found
        }
        return null
    }
    function textItem(text) { return find(mixer.contentItem, i => i.text === text && i.visible) }
    Timer { interval: 650; running: true; onTriggered: {
        Shell.Settings.setValue("animationPopup", 0)
        const track = find(mixer.contentItem, i => i.fillFraction !== undefined)
        const original = track.mapToItem(mixer.contentItem, 0, 0)
        const panel = find(mixer.contentItem, i => i.railWidth !== undefined)
        check(panel.width === 160, "collapsed mixer is narrow")
        input.mouseClick(textItem("USB Audio Interface Output 0"))
        input.wait(40)
        check(panel.width === 520 && panel.x + panel.width === mixer.width, "panel expands to the left")
        const list = find(mixer.contentItem, i => i.count === 9 && i.contentY !== undefined)
        const name = find(list.contentItem, i => i.text === "USB Audio Interface Output 1")
        check(name && !name.truncated, "long device name fits")
        check(name.mapToItem(mixer.contentItem, name.width, 0).x < original.x, "list is left of master")
        input.mouseWheel(list, 10, 10, 0, -120)
        check(list.contentY > 0, "long device lists scroll")
        list.positionViewAtEnd()
        input.wait(20)
        input.mouseClick(find(list.contentItem, i => i.text === "USB Audio Interface Output 8"))
        input.wait(40)
        check(pipe.preferredDefaultAudioSink.id === 8 && panel.width === 160, "select output and collapse")
        input.mouseClick(textItem("Microphone"))
        input.wait(30)
        input.mouseClick(textItem("Microphone"))
        check(pipe.preferredDefaultAudioSource.id === 10, "select input")
        input.mouseClick(textItem("Apps"))
        input.wait(30)
        const row = textItem("Music player").parent.parent.parent
        const drawer = find(panel, i => i.trigger !== undefined && i.trigger !== null)
        check(drawer && drawer.height < panel.height / 2, "one stream opens a compact drawer")
        const triggerY = drawer.trigger.mapToItem(drawer, 0, drawer.trigger.height / 2).y
        check(triggerY >= 0 && triggerY <= drawer.height, "pointer can cross from the category into its drawer")
        const icon = find(row, i => i.backer !== undefined)
        input.tryVerify(() => icon.visible && icon.status === Image.Ready, 1000)
        check(icon.source.toString().endsWith("/record.gif"), "playback resolves the desktop entry icon")
        input.mouseClick(find(row, i => i.text === "󰕾"))
        check(audio.muted, "per-app mute toggles")
        const streamTrack = find(row, i => i.radius === 5 && i.height === 10)
        input.mouseClick(streamTrack, streamTrack.width * 0.25, 5)
        check(Math.abs(audio.volume - 0.25) < 0.01, "per-app volume changes")
        pipe.nodes = {values: pipe.nodes.values.concat([{
            id: 14, isStream: true, type: PwNodeType.AudioOutStream,
            audio: radioAudio, description: "Music player",
            properties: {"application.name": "Music player", "media.name": "Radio"}
        }])}
        input.wait(60)
        const radio = textItem("Radio").parent.parent
        check(textItem("Playback") && find(radio, i => i.text === "Music player"),
              "two streams from one app show their individual labels")
        input.mouseClick(find(radio, i => i.text === "󰕾"))
        check(radioAudio.muted && audio.muted, "each stream controls its own mute")
        input.mouseClick(textItem("Recording"))
        input.wait(30)
        check(textItem("No recording streams") !== null, "empty recording list explains its state")
        pipe.nodes = {values: pipe.nodes.values.concat([
            {id: 12, isStream: true, type: PwNodeType.AudioInStream, audio, name: "Recorder",
                properties: {"application.icon-name": Quickshell.env("MIXER_TEST_ICON")}},
            {id: 13, isStream: true, type: PwNodeType.AudioInStream, audio, name: "Unknown recorder"}
        ])}
        input.wait(60)
        const recorder = textItem("Recorder").parent.parent.parent
        const recorderIcon = find(recorder, i => i.backer !== undefined)
        check(recorderIcon.visible && recorderIcon.status === Image.Ready, "recording displays its advertised icon")
        const unknown = textItem("Unknown recorder").parent.parent.parent
        check(find(unknown, i => i.visible && i.text === "󰑊"), "unidentified recording stream has a fallback")
        const now = track.mapToItem(mixer.contentItem, 0, 0)
        check(now.x === original.x && now.y === original.y, "master slider stays pinned")
        mixer.implicitWidth = 380
        mixer.implicitHeight = 480
        input.wait(60)
        check(panel.width <= mixer.width && panel.height <= mixer.height, "expanded panel fits a small display")
        const button = textItem("Recording").parent.parent
        const corner = button.mapToItem(mixer.contentItem, button.width, button.height)
        check(corner.y <= mixer.height, "last section stays on screen")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', imports='import QtTest\nimport Quickshell.Services.Pipewire')


if __name__ == "__main__":
    unittest.main()
