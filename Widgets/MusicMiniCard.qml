import QtQuick
import QtQuick.Layouts
import Quickshell
import QtQuick.Effects
import Quickshell.Services.Mpris
import "../"
import "../config.js" as Config

Rectangle {
    id: musicCard
    required property var dashboard
    //Layout.fillWidth: true
    Layout.preferredWidth: 400
    implicitHeight: musicContent.implicitHeight + 32
    radius: Config.radius.xl
    color: Colors.card

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    // Optimistic play/pause: flips instantly on click, reconciles with the
    // real MPRIS state once the player confirms (spotify_player's Spotify
    // Connect round trip can take ~1s)
    property bool optimisticPlaying: player ? player.isPlaying : false
    onPlayerChanged: optimisticPlaying = player ? player.isPlaying : false
    Connections {
        target: musicCard.player
        function onIsPlayingChanged() { musicCard.optimisticPlaying = musicCard.player.isPlaying }
    }

    function fmtTime(secs) {
        var s = Math.floor(secs || 0)
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    Timer {
        interval: Config.timer.interval
        running: !!musicCard.player && musicCard.optimisticPlaying
        repeat: true
        onTriggered: progressRing.requestPaint()
    }

    Text {
        visible: !musicCard.player
        anchors.centerIn: parent
        text: "No media playing"
        color: Colors.subtext
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.type.base
    }

    ColumnLayout {
        id: musicContent
        visible: !!musicCard.player
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Config.gap.lg
        spacing: Config.gap.sm

        // ── Album art with circular progress ring ──
        Item {
            Layout.alignment: Qt.AlignHCenter
            width: 250; height: 250

            Canvas {
                id: progressRing
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    var cx = width / 2, cy = height / 2
                    var r = cx - 6
                    var lw = 8

                    // Read position directly — bypasses QML property cache
                    var progress = 0
                    var p = musicCard.player
                    if (p && p.lengthSupported && p.length > 0)
                        progress = Math.min(1, p.position / p.length)

                    ctx.beginPath()
                    ctx.arc(cx, cy, r, 0, Math.PI * 2)
                    ctx.strokeStyle = "rgba(0,0,0,0.12)"
                    ctx.lineWidth = lw
                    ctx.lineCap = "round"
                    ctx.stroke()
                    if (progress > 0) {
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + progress * Math.PI * 2)
                        ctx.strokeStyle = "" + Colors.accent
                        ctx.lineWidth = lw
                        ctx.lineCap = "round"
                        ctx.stroke()
                    }
                }
            }

            Item {
                width: 220; height: 220
                anchors.centerIn: parent

                Image {
                    id: miniAlbumImg
                    anchors.fill: parent
                    source: musicCard.player ? (musicCard.player.trackArtUrl || "") : ""
                    fillMode: Image.PreserveAspectCrop
                    layer.enabled: true
                    visible: false
                }
                Rectangle {
                    id: miniAlbumMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                    layer.enabled: true
                }
                MultiEffect {
                    source: miniAlbumImg
                    anchors.fill: miniAlbumImg
                    maskEnabled: true
                    maskSource: miniAlbumMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.border
                    visible: !musicCard.player || !musicCard.player.trackArtUrl
                    Text {
                        anchors.centerIn: parent
                        text: "󰝚"
                        color: Colors.card
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.display
                    }
                }
            }
        }

        // ── Track info ──
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: musicCard.player ? (musicCard.player.trackTitle || "—") : "—"
            color: Colors.border
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.md
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: musicCard.player ? (musicCard.player.trackArtist || "—") : "—"
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.sm
            elide: Text.ElideRight
        }
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: musicCard.player ? (musicCard.player.trackAlbum || "") : ""
            color: Colors.accent
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.label
            elide: Text.ElideRight
            visible: musicCard.player && musicCard.player.trackAlbum !== ""
        }

        // ── Playback controls ──
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 28

            Text {
                text: ""
                color: musicCard.player && musicCard.player.canGoPrevious ? Colors.border : Colors.subtext
                font.family: Config.bar.fontFamily
                font.pixelSize: Config.type.xl
                opacity: musicCard.player && musicCard.player.canGoPrevious ? 1.0 : 0.4
                MouseArea { anchors.fill: parent; onClicked: if (musicCard.player && musicCard.player.canGoPrevious) musicCard.player.previous() }
            }
            Text {
                text: musicCard.player && musicCard.optimisticPlaying ? "" : ""
                color: Colors.accent
                font.family: Config.bar.fontFamily
                font.pixelSize: Config.type.display
                MouseArea { anchors.fill: parent; onClicked: if (musicCard.player) { musicCard.optimisticPlaying = !musicCard.optimisticPlaying; musicCard.player.togglePlaying() } }
            }
            Text {
                text: ""
                color: musicCard.player && musicCard.player.canGoNext ? Colors.border : Colors.subtext
                font.family: Config.bar.fontFamily
                font.pixelSize: Config.type.xl
                opacity: musicCard.player && musicCard.player.canGoNext ? 1.0 : 0.4
                MouseArea { anchors.fill: parent; onClicked: if (musicCard.player && musicCard.player.canGoNext) musicCard.player.next() }
            }
        }

        // ── GIF visualizer ──
        AnimatedImage {
            Layout.alignment: Qt.AlignHCenter
            source: "file://" + Quickshell.env("HOME") + "/.config/quickshell/assets/record.gif"
            playing: musicCard.player && musicCard.optimisticPlaying
            Layout.preferredWidth: 160
            Layout.preferredHeight: 160
            fillMode: Image.PreserveAspectFit
        }
    }
}
