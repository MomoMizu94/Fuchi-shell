import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts

import "config.js" as Config

PanelWindow {
    id: volumeMenu

    property bool open: false
    property bool closing: false
    property bool panelHovered: false
    visible: open || closing
    onOpenChanged: {
        closing = !open
        if (open) expandedList = ""
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Normal

    // Only the panel's own on-screen rect is input-active — without this a
    // PanelWindow captures full-screen input regardless of visible content
    // (see FrameShape.qml's identical technique/comment). A couple of px of
    // slop on the left keeps the input region continuous with FrameShape's
    // fixed right-edge hover strip as the panel slides across it.
    mask: Region {
        x: panel.x - 2
        y: panel.y
        width: panel.width + 2
        height: panel.height
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    property string expandedList: ""   // "" | "output" | "input"
    property var outputList: []
    property var inputList: []

    function isEasyEffects(n) {
        return ((n.description || n.name || "") + "").toLowerCase().includes("easy effects")
    }
    // PipeWire's own media.class property ("Audio/Sink" / "Audio/Source") is a
    // stable, documented way to tell real devices from streams/filters — far
    // more reliable than guessing at Quickshell's internal PwNodeType bitflags
    // (an earlier attempt at that crashed default-source switching outright).
    function computeOutputList() {
        return Pipewire.nodes.values.filter(n => n.properties["media.class"] === "Audio/Sink" && !isEasyEffects(n))
    }
    function computeInputList() {
        return Pipewire.nodes.values.filter(n => n.properties["media.class"] === "Audio/Source" && !isEasyEffects(n))
    }
    function refreshLists() {
        outputList = computeOutputList()
        inputList = computeInputList()
    }
    Component.onCompleted: refreshLists()
    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { volumeMenu.refreshLists() }
    }

    function selectOutput(node) {
        Pipewire.preferredDefaultAudioSink = node
        expandedList = ""
    }
    function selectInput(node) {
        Pipewire.preferredDefaultAudioSource = node
        expandedList = ""
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
    // deliberate push rather than an accidental brush.
    function setVolumeFromY(y) {
        const sink = Pipewire.defaultAudioSink
        if (!sink || !sink.audio) return
        const raw = Math.max(0, Math.min(Config.volumeMenu.maxVolume, (1 - y / track.height) * Config.volumeMenu.maxVolume))
        sink.audio.volume = Math.abs(raw - 1.0) < Config.volumeMenu.snapBand ? 1.0 : raw
    }

    readonly property int percentRowHeight: 22
    readonly property int outputBlockHeight: expandedList === "output"
        ? Config.volumeMenu.deviceButtonSize + outputList.length * Config.volumeMenu.deviceRowHeight
        : Config.volumeMenu.deviceButtonSize
    readonly property int inputBlockHeight: expandedList === "input"
        ? Config.volumeMenu.deviceButtonSize + inputList.length * Config.volumeMenu.deviceRowHeight
        : Config.volumeMenu.deviceButtonSize

    Item {
        id: panel
        width: Config.volumeMenu.width
        height: Config.volumeMenu.padding * 2
            + Config.volumeMenu.deviceButtonSize
            + Config.volumeMenu.gap
            + Config.volumeMenu.sliderHeight
            + Config.volumeMenu.gap
            + volumeMenu.percentRowHeight
            + Config.volumeMenu.gap
            + volumeMenu.outputBlockHeight
            + Config.volumeMenu.gap
            + volumeMenu.inputBlockHeight
        Behavior on height { NumberAnimation { duration: Config.anim.popup; easing.type: Easing.OutCubic } }

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: volumeMenu.open ? 0 : -width
        Behavior on anchors.rightMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !volumeMenu.open) volumeMenu.closing = false
            }
        }

        HoverHandler {
            onHoveredChanged: volumeMenu.panelHovered = hovered
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
                anchors.fill: parent
                anchors.margins: Config.volumeMenu.padding
                spacing: Config.volumeMenu.gap

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
                        font.family: Config.bar.fontFamily
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
                        readonly property real fillFraction: Math.max(0, Math.min(1, volume / Config.volumeMenu.maxVolume))
                        readonly property real unityFraction: Math.min(1, 1 / Config.volumeMenu.maxVolume)
                        // warn and accent resolve to the same pywal slot on some
                        // palettes (verified: both map to color3 here), so the
                        // hot end of the gradient can't rely on a different
                        // Colors role being visually distinct — lighten accent
                        // instead, which guarantees contrast regardless of theme.
                        readonly property color mutedColor: Qt.darker(Colors.accent, 1.5)
                        readonly property color hotColor: Qt.lighter(Colors.accent, 1.7)

                        // One continuous pill, clipped to the current fill
                        // height rather than built from stacked rectangles —
                        // stacking a separately-colored "boost" rectangle on
                        // top previously left a visible seam at the 100% mark
                        // (only one of the two had rounded corners). The inner
                        // Rectangle is always the track's full height so the
                        // gradient's colors stay pinned to absolute volume
                        // positions; only the reveal window grows with volume.
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
                        // the gradient.
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
                    // slider knob instead of being cut off.
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
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: volumeMenu.outputBlockHeight
                    radius: Config.radius.xl
                    color: "transparent"
                    clip: true

                    Column {
                        anchors.fill: parent

                        Rectangle {
                            width: parent.width
                            height: Config.volumeMenu.deviceButtonSize
                            radius: Config.radius.xl
                            color: outHeaderHover.hovered ? Colors.card : "transparent"

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                width: parent.width - Config.gap.xs

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "󰋋"
                                    color: Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.lg
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: volumeMenu.expandedList === "output"
                                        ? "Output"
                                        : (Pipewire.defaultAudioSink ? (Pipewire.defaultAudioSink.description || Pipewire.defaultAudioSink.name) : "")
                                    elide: Text.ElideRight
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.micro
                                }
                            }

                            HoverHandler { id: outHeaderHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: volumeMenu.expandedList = volumeMenu.expandedList === "output" ? "" : "output"
                            }
                        }

                        Repeater {
                            model: volumeMenu.expandedList === "output" ? volumeMenu.outputList : []
                            delegate: Rectangle {
                                id: outRow
                                required property var modelData
                                width: parent ? parent.width : 0
                                height: Config.volumeMenu.deviceRowHeight
                                color: outRowHover.hovered ? Colors.card : "transparent"
                                radius: Config.radius.md

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Config.gap.xs
                                    spacing: Config.gap.xs

                                    Text {
                                        text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === outRow.modelData.id) ? "●" : "○"
                                        color: Colors.accent
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.type.micro
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: outRow.modelData.description || outRow.modelData.name
                                        color: Colors.text
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.type.micro
                                    }
                                }

                                HoverHandler { id: outRowHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: volumeMenu.selectOutput(outRow.modelData)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: volumeMenu.inputBlockHeight
                    radius: Config.radius.xl
                    color: "transparent"
                    clip: true

                    Column {
                        anchors.fill: parent

                        Rectangle {
                            width: parent.width
                            height: Config.volumeMenu.deviceButtonSize
                            radius: Config.radius.xl
                            color: inHeaderHover.hovered ? Colors.card : "transparent"

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 2
                                width: parent.width - Config.gap.xs

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "󰍬"
                                    color: Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.lg
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: volumeMenu.expandedList === "input"
                                        ? "Input"
                                        : (Pipewire.defaultAudioSource ? (Pipewire.defaultAudioSource.description || Pipewire.defaultAudioSource.name) : "")
                                    elide: Text.ElideRight
                                    color: Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.micro
                                }
                            }

                            HoverHandler { id: inHeaderHover }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: volumeMenu.expandedList = volumeMenu.expandedList === "input" ? "" : "input"
                            }
                        }

                        Repeater {
                            model: volumeMenu.expandedList === "input" ? volumeMenu.inputList : []
                            delegate: Rectangle {
                                id: inRow
                                required property var modelData
                                width: parent ? parent.width : 0
                                height: Config.volumeMenu.deviceRowHeight
                                color: inRowHover.hovered ? Colors.card : "transparent"
                                radius: Config.radius.md

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Config.gap.xs
                                    spacing: Config.gap.xs

                                    Text {
                                        text: (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.id === inRow.modelData.id) ? "●" : "○"
                                        color: Colors.accent
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.type.micro
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: inRow.modelData.description || inRow.modelData.name
                                        color: Colors.text
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.type.micro
                                    }
                                }

                                HoverHandler { id: inRowHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: volumeMenu.selectInput(inRow.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
