import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic as Controls

import "config.js" as Config

// Right-docked, hover-only volume mixer: master output slider, output/input
// device pickers, and per-app playback/recording volume via PipeWire
PanelWindow {
    id: volumeMenu

    property bool open: false
    property bool closing: false
    property bool panelHovered: false
    visible: open || closing
    onOpenChanged: {
        closing = !open && Settings.animationPopup > 0
        if (open) activeSection = null
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal

    // Only the panel's own on-screen rect is input-active — without this a
    // PanelWindow captures full-screen input regardless of visible content
    // (see FrameShape.qml's identical technique/comment)
    mask: Region {
        x: panel.x - 2
        y: panel.y
        width: panel.width + 2
        height: panel.height
    }

    // A node's `.audio` volume/mute is only populated and writable while the
    // node is bound by a tracker — tracking just the defaults left every
    // stream row reading 0% and silently dropping writes (verified live:
    // wpctl reported spotify-player at 1.00 while our rows showed 0), so the
    // per-app lists must be tracked too, not only the master sink/source
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
            .concat(volumeMenu.playbackList)
            .concat(volumeMenu.recordingList)
    }

    readonly property var sections: [
        { key: "output", label: "Output", icon: "󰋋", emptyText: "No output devices" },
        { key: "input", label: "Input", icon: "󰍬", emptyText: "No input devices" },
        { key: "apps", label: "Apps", icon: "󰀻", emptyText: "No playback streams" },
        { key: "recording", label: "Recording", icon: "󰑊", emptyText: "No recording streams" }
    ]
    property var activeSection: null
    readonly property string sectionKey: activeSection ? activeSection.key : ""
    readonly property bool showingDevices: sectionKey === "output" || sectionKey === "input"
    readonly property var sectionNodes: {
        switch (sectionKey) {
            case "output": return outputList
            case "input": return inputList
            case "apps": return playbackList
            case "recording": return recordingList
            default: return []
        }
    }

    function isEasyEffects(n) {
        return ((n.description || n.name || "") + "").toLowerCase().includes("easy effects")
    }
    // These fields are available without tracking. Reading properties here
    // would exclude devices that are not tracked, including non-default outputs.
    function computeOutputList() {
        return Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink && !isEasyEffects(n))
    }
    function computeInputList() {
        return Pipewire.nodes.values.filter(n => n.audio && !n.isStream && !n.isSink && !isEasyEffects(n))
    }
    // Stream types are composite values with shared bits. Exact equality
    // distinguishes playback from recording.
    function computePlaybackList() {
        return Pipewire.nodes.values.filter(n => n.isStream && n.type === PwNodeType.AudioOutStream)
    }
    function computeRecordingList() {
        return Pipewire.nodes.values.filter(n => n.isStream && n.type === PwNodeType.AudioInStream)
    }
    function sectionLabel(section) {
        if (section.key === sectionKey) return section.label
        let node = null
        if (section.key === "output") node = Pipewire.defaultAudioSink
        if (section.key === "input") node = Pipewire.defaultAudioSource
        return node ? (node.description || node.name || section.label) : section.label
    }

    // Bindings keep the lists current as nodes and their classification change.
    readonly property var outputList: computeOutputList()
    readonly property var inputList: computeInputList()
    readonly property var playbackList: computePlaybackList()
    readonly property var recordingList: computeRecordingList()

    function selectOutput(node) {
        Pipewire.preferredDefaultAudioSink = node
        activeSection = null
    }
    function selectInput(node) {
        Pipewire.preferredDefaultAudioSource = node
        activeSection = null
    }

    function volumeIcon() {
        const sink = Pipewire.defaultAudioSink
        if (!sink || !sink.audio || sink.audio.muted || sink.audio.volume <= 0) return "󰝟"
        if (sink.audio.volume < 0.34) return "󰕿"
        if (sink.audio.volume < 0.67) return "󰖀"
        return "󰕾"
    }

    // Maps a drag/click Y position to a volume in [0, maxVolume], snapping to
    // exactly 1.0 within a small band so casually crossing 100% takes a
    // deliberate push rather than an accidental brush
    function setVolumeFromY(y) {
        const sink = Pipewire.defaultAudioSink
        if (!sink || !sink.audio) return
        const raw = Math.max(0, Math.min(Settings.maxVolume, (1 - y / track.height) * Settings.maxVolume))
        sink.audio.volume = Math.abs(raw - 1.0) < Config.volumeMenu.snapBand ? 1.0 : raw
    }

    readonly property int percentRowHeight: 22
    readonly property int masterLabelHeight: 18

    Item {
        id: panel
        readonly property real railWidth: Math.min(volumeMenu.width, Config.volumeMenu.width)
        width: Math.min(volumeMenu.width, railWidth + (volumeMenu.activeSection ? Config.volumeMenu.detailWidth : 0))
        Behavior on width { NumberAnimation { duration: Settings.animationPopup; easing.type: Easing.OutCubic } }
        height: Math.min(volumeMenu.height, Config.volumeMenu.padding * 2 + Config.volumeMenu.gap * 7
            + volumeMenu.masterLabelHeight + volumeMenu.percentRowHeight + Config.volumeMenu.sliderHeight
            + Config.volumeMenu.deviceButtonSize * (1 + volumeMenu.sections.length))

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: volumeMenu.open ? 0 : -width
        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: Settings.animationPopup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !volumeMenu.open) volumeMenu.closing = false
            }
        }

        HoverHandler {
            onHoveredChanged: volumeMenu.panelHovered = hovered
        }

        // Curves the panel's right corners inward so they blend into the
        // frame's inner edge instead of meeting it at a hard right angle
        CornerFillet {
            anchors.right: parent.right
            anchors.rightMargin: Config.frame.thin
            anchors.bottom: parent.top
            solidCorner: "bottomRight"
        }
        CornerFillet {
            anchors.right: parent.right
            anchors.rightMargin: Config.frame.thin
            anchors.top: parent.bottom
            solidCorner: "topRight"
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: Config.radius.hero
            bottomLeftRadius: Config.radius.hero
            topRightRadius: 0
            bottomRightRadius: 0
            color: Colors.surface
            clip: true

            ColumnLayout {
                id: rail
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom; margins: Config.volumeMenu.padding }
                width: panel.railWidth - Config.volumeMenu.padding * 2
                spacing: Config.volumeMenu.gap

                Text {
                    Layout.preferredHeight: volumeMenu.masterLabelHeight
                    Layout.alignment: Qt.AlignHCenter
                    text: "MASTER"
                    color: Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.micro
                    font.bold: true
                    font.letterSpacing: 1
                }

                Rectangle {
                    Layout.preferredWidth: Config.volumeMenu.deviceButtonSize
                    Layout.preferredHeight: Config.volumeMenu.deviceButtonSize
                    Layout.alignment: Qt.AlignHCenter
                    radius: Config.radius.xl
                    color: muteHover.hovered ? Colors.card : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: volumeMenu.volumeIcon()
                        color: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
                            ? Colors.error : Colors.text
                        font.family: Settings.fontFamily
                        font.pixelSize: Config.type.display
                    }

                    HoverHandler { id: muteHover }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const sink = Pipewire.defaultAudioSink
                            if (sink && sink.audio) sink.audio.muted = !sink.audio.muted
                        }
                    }
                }

                Item {
                    Layout.preferredWidth: Config.volumeMenu.sliderTrackWidth
                    Layout.preferredHeight: Config.volumeMenu.sliderHeight
                    Layout.alignment: Qt.AlignHCenter

                    Rectangle {
                        id: track
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.inset
                        border.width: 1
                        border.color: Colors.border
                        clip: true

                        readonly property real volume: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) ? Pipewire.defaultAudioSink.audio.volume : 0
                        readonly property real fillFraction: Math.max(0, Math.min(1, volume / Settings.maxVolume))
                        readonly property real unityFraction: Math.min(1, 1 / Settings.maxVolume)
                        // warn and accent resolve to the same pywal slot on some
                        // palettes, so the hot end of the gradient can't rely on a different
                        // Colors role being visually distinct — lighten accent
                        // instead, which guarantees contrast regardless of theme
                        readonly property color mutedColor: Qt.darker(Colors.accent, 1.5)
                        readonly property color hotColor: Qt.lighter(Colors.accent, 1.7)

                        // One continuous pill, clipped to the current fill
                        // height rather than built from stacked rectangles —
                        // stacking a separately-colored "boost" rectangle on
                        // top previously left a visible seam at the 100% mark
                        // (only one of the two had rounded corners). The inner
                        // Rectangle is always the track's full height so the
                        // gradient's colors stay pinned to absolute volume
                        // positions; only the reveal window grows with volume
                        Item {
                            id: fillMask
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: track.height * track.fillFraction
                            clip: true

                            Rectangle {
                                width: parent.width
                                height: track.height
                                anchors.bottom: parent.bottom
                                radius: width / 2
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: track.hotColor }
                                    GradientStop { position: 1 - track.unityFraction; color: Colors.accent }
                                    GradientStop { position: 1.0; color: track.mutedColor }
                                }
                            }
                        }
                        // 100% mark — small notches just outside the track's
                        // edges rather than a bright bar crossing the fill, so
                        // it reads as a reference mark without interrupting
                        // the gradient
                        Rectangle {
                            x: -5; width: 3; height: 2; radius: 1
                            y: track.height * (1 - track.unityFraction) - 1
                            color: Colors.subtext
                            opacity: 0.8
                        }
                        Rectangle {
                            x: track.width + 2; width: 3; height: 2; radius: 1
                            y: track.height * (1 - track.unityFraction) - 1
                            color: Colors.subtext
                            opacity: 0.8
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: mouse => volumeMenu.setVolumeFromY(mouse.y)
                            onPositionChanged: mouse => { if (pressed) volumeMenu.setVolumeFromY(mouse.y) }
                        }
                    }

                    // Drag handle — sits outside `track` (which clips) so it
                    // can protrude past the track's width like a normal
                    // slider knob instead of being cut off
                    Rectangle {
                        id: handle
                        readonly property real size: Config.volumeMenu.sliderTrackWidth + 10
                        width: size
                        height: size
                        radius: size / 2
                        x: (track.width - size) / 2
                        y: track.height * (1 - track.fillFraction) - size / 2
                        color: Colors.surface
                        border.width: 3
                        border.color: Colors.accent

                        MouseArea {
                            anchors.fill: parent
                            onPressed: mouse => volumeMenu.setVolumeFromY(mouse.y + handle.y)
                            onPositionChanged: mouse => { if (pressed) volumeMenu.setVolumeFromY(mouse.y + handle.y) }
                        }
                    }
                }

                Text {
                    Layout.preferredHeight: volumeMenu.percentRowHeight
                    Layout.alignment: Qt.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                        ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) + "%" : "--"
                    color: Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                }

                Repeater {
                    model: volumeMenu.sections
                    delegate: Rectangle {
                        id: sectionButton
                        required property var modelData
                        readonly property bool selected: volumeMenu.sectionKey === modelData.key
                        Layout.fillWidth: true
                        Layout.preferredHeight: Config.volumeMenu.deviceButtonSize
                        radius: Config.radius.xl
                        color: selected ? Qt.alpha(Colors.accent, 0.18) : sectionHover.hovered ? Colors.card : "transparent"

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - Config.gap.xs
                            spacing: 2

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: sectionButton.modelData.icon
                                color: sectionButton.selected ? Colors.accent : Colors.text
                                font.family: Settings.fontFamily
                                font.pixelSize: Config.type.lg
                            }
                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: volumeMenu.sectionLabel(sectionButton.modelData)
                                elide: Text.ElideRight
                                color: Colors.subtext
                                font.family: Settings.fontFamily
                                font.pixelSize: Config.type.micro
                            }
                        }

                        HoverHandler { id: sectionHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: volumeMenu.activeSection = sectionButton.selected ? null : sectionButton.modelData
                        }
                    }
                }
            }

            ColumnLayout {
                id: details
                anchors.left: parent.left
                anchors.leftMargin: Config.volumeMenu.padding
                width: Math.max(0, panel.width - panel.railWidth - Config.volumeMenu.padding)
                anchors.verticalCenter: parent.verticalCenter
                visible: volumeMenu.activeSection !== null && width > 0
                spacing: Config.gap.md

                Text {
                    Layout.fillWidth: true
                    text: volumeMenu.activeSection?.label ?? ""
                    color: Colors.textStrong
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.md
                    font.bold: true
                }
                Text {
                    Layout.fillWidth: true
                    visible: nodes.count === 0
                    text: volumeMenu.activeSection?.emptyText ?? ""
                    color: Colors.subtext
                    font.family: Settings.fontFamily
                    font.pixelSize: Config.type.sm
                }
                ListView {
                    id: nodes
                    readonly property int rowHeight: volumeMenu.showingDevices ? Config.volumeMenu.deviceRowHeight : Config.volumeMenu.appRowHeight
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(count, Config.volumeMenu.maxVisibleAppRows) * rowHeight
                    visible: count > 0
                    clip: true
                    model: volumeMenu.sectionNodes
                    onModelChanged: positionViewAtBeginning()
                    ScrollWheel { view: nodes }
                    Controls.ScrollBar.vertical: Controls.ScrollBar {
                        id: scrollBar
                        visible: nodes.contentHeight > nodes.height
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property var audio: modelData.audio
                        readonly property var defaultDevice: volumeMenu.sectionKey === "output"
                            ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
                        width: ListView.view.width - (scrollBar.visible ? scrollBar.width + Config.gap.xs : 0)
                        height: nodes.rowHeight
                        radius: Config.radius.md
                        color: deviceMouse.containsMouse ? Colors.card : "transparent"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Config.gap.xs
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Config.gap.sm
                                Text {
                                    visible: volumeMenu.showingDevices
                                    text: row.defaultDevice?.id === row.modelData.id ? "●" : "○"
                                    color: Colors.accent
                                    font.family: Settings.fontFamily
                                    font.pixelSize: Config.type.sm
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.description || row.modelData.name
                                    elide: Text.ElideRight
                                    color: Colors.text
                                    font.family: Settings.fontFamily
                                    font.pixelSize: Config.type.sm
                                }
                                Text {
                                    visible: !volumeMenu.showingDevices
                                    text: row.audio?.muted ? "󰝟" : "󰕾"
                                    color: row.audio?.muted ? Colors.error : Colors.subtext
                                    font.family: Settings.fontFamily
                                    font.pixelSize: Config.type.sm
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (row.audio) row.audio.muted = !row.audio.muted
                                    }
                                }
                            }

                            Rectangle {
                                id: streamTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 10
                                visible: !volumeMenu.showingDevices
                                radius: 5
                                color: Colors.inset
                                border.width: 1
                                border.color: Colors.border

                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width * Math.max(0, Math.min(1, row.audio?.volume ?? 0))
                                    radius: parent.radius
                                    color: Colors.accent
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    preventStealing: true
                                    function setVolume(x) {
                                        if (row.audio) row.audio.volume = Math.max(0, Math.min(1, x / width))
                                    }
                                    onPressed: mouse => setVolume(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) setVolume(mouse.x) }
                                }
                            }
                        }

                        MouseArea {
                            id: deviceMouse
                            anchors.fill: parent
                            enabled: volumeMenu.showingDevices
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (volumeMenu.sectionKey === "output") volumeMenu.selectOutput(row.modelData)
                                else volumeMenu.selectInput(row.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
