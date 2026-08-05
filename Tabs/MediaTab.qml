import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../"
import "../config.js" as Config

// Full-size MPRIS player view. Currently a spare tab — not wired into
// Dashboard.qml's tab bar. Playback controls stay available on the Overview tab via
// Widgets/MusicMiniCard.qml if this spare tab is switched with another tab
ColumnLayout {
    id: root
    required property var dashboard

    spacing: 12

    Text {
        visible: Mpris.players.values.length === 0
        Layout.fillWidth: true
        Layout.fillHeight: true
        text: "No media playing"
        color: Colors.border
        font.family: Config.bar.fontFamily
        font.pixelSize: Config.bar.fontSize - 2
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    Repeater {
        model: Mpris.players.values
        delegate: Rectangle {
            id: mediaCard
            required property var modelData
            required property int index
            property var player: modelData

            // Optimistic play/pause: flips instantly on click, reconciles with the
            // real MPRIS state once the player confirms
            property bool optimisticPlaying: player ? player.isPlaying : false
            onPlayerChanged: optimisticPlaying = player ? player.isPlaying : false
            Connections {
                target: mediaCard.player
                function onIsPlayingChanged() { mediaCard.optimisticPlaying = mediaCard.player.isPlaying }
            }

            property real mediaProgress: 0
            property string mediaCurrentTime: "0:00"

            function fmtTime(secs) {
                var s = Math.floor(secs || 0)
                return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
            }

            Timer {
                interval: Config.timer.interval
                running: mediaCard.player && mediaCard.player.isPlaying
                repeat: true
                triggeredOnStart: true
                onTriggered: {
                    var p = mediaCard.player
                    if (p && p.lengthSupported && p.length > 0)
                        mediaCard.mediaProgress = Math.min(1, p.position / p.length)
                    mediaCard.mediaCurrentTime = mediaCard.fmtTime(p ? p.position : 0)
                }
            }

            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Config.radius.xxl
            color: Colors.inset
            clip: true

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // -- Left: album art + rotating radial rays --
                Item {
                    id: artArea
                    Layout.preferredWidth: Math.round(mediaCard.width * 0.32)
                    Layout.fillHeight: true
                    property real artSize: Math.min(width, height) * 0.5

                    Canvas {
                        id: raysCanvas
                        property real breathePhase: 0
                        anchors.fill: parent
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            var cx = width / 2, cy = height / 2
                            var halfDiag = (artArea.artSize / 2) * Math.SQRT2
                            var innerR = halfDiag + 4
                            var outerR = innerR + artArea.artSize * 0.12
                            var longDelta = artArea.artSize * 0.04
                            var breathe = 0.5 + 0.5 * Math.sin(raysCanvas.breathePhase)
                            var growth = artArea.artSize * 0.05 * breathe
                            var numRays = 36
                            ctx.strokeStyle = "" + Colors.accent
                            ctx.lineWidth = Math.max(3, artArea.artSize * 0.032)
                            ctx.globalAlpha = 0.6
                            ctx.lineCap = "round"
                            for (var i = 0; i < numRays; i++) {
                                var angle = (i / numRays) * Math.PI * 2 - Math.PI / 2
                                var iR = (i % 3 === 0) ? innerR - longDelta : innerR
                                var oR = ((i % 3 === 0) ? outerR + longDelta : outerR) + growth
                                ctx.beginPath()
                                ctx.moveTo(cx + iR * Math.cos(angle), cy + iR * Math.sin(angle))
                                ctx.lineTo(cx + oR * Math.cos(angle), cy + oR * Math.sin(angle))
                                ctx.stroke()
                            }
                        }

                        // One revolution every 30s + ~2.4s breathe cycle while playing; freezes in place on pause
                        FrameAnimation {
                            running: mediaCard.player && mediaCard.optimisticPlaying
                            onTriggered: {
                                raysCanvas.rotation = (raysCanvas.rotation + frameTime * 12) % 360
                                raysCanvas.breathePhase = (raysCanvas.breathePhase + frameTime * 2.6) % (Math.PI * 2)
                                raysCanvas.requestPaint()
                            }
                        }
                    }

                    Rectangle {
                        width: artArea.artSize; height: artArea.artSize
                        anchors.centerIn: parent
                        radius: artArea.artSize * 0.1
                        clip: true
                        color: Colors.accent

                        Image {
                            anchors.fill: parent
                            source: mediaCard.player ? (mediaCard.player.trackArtUrl || "") : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: source.toString() !== ""
                        }

                        Text {
                            visible: !mediaCard.player || !mediaCard.player.trackArtUrl
                            anchors.centerIn: parent
                            text: "󰝚"
                            color: Colors.onAccent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: artArea.artSize * 0.4
                        }
                    }
                }

                // -- Center: info + controls + progress --
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 24
                    Layout.rightMargin: 24
                    spacing: 10

                    Item { Layout.fillHeight: true }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: mediaCard.player ? (mediaCard.player.trackTitle || "—") : "—"
                        color: Colors.text
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.bar.fontSize + 8
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: mediaCard.player ? (mediaCard.player.trackArtist || "—") : "—"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.bar.fontSize - 4
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        visible: mediaCard.player && mediaCard.player.trackAlbum !== ""
                        text: mediaCard.player ? (mediaCard.player.trackAlbum || "") : ""
                        color: Colors.accent
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.bar.fontSize - 4
                        elide: Text.ElideRight
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 28

                        Text {
                            text: ""
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize + 8
                            opacity: mediaCard.player && mediaCard.player.canGoPrevious ? 1.0 : 0.3
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (mediaCard.player && mediaCard.player.canGoPrevious) mediaCard.player.previous()
                            }
                        }

                        Rectangle {
                            width: 56; height: 56; radius: 28
                            color: Colors.accent
                            Text {
                                anchors.centerIn: parent
                                text: mediaCard.player && mediaCard.optimisticPlaying ? "" : ""
                                color: Colors.onAccent
                                font.family: Config.bar.fontFamily
                                font.pixelSize: Config.bar.fontSize + 10
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (mediaCard.player) { mediaCard.optimisticPlaying = !mediaCard.optimisticPlaying; mediaCard.player.togglePlaying() }
                            }
                        }

                        Text {
                            text: ""
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize + 8
                            opacity: mediaCard.player && mediaCard.player.canGoNext ? 1.0 : 0.3
                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (mediaCard.player && mediaCard.player.canGoNext) mediaCard.player.next()
                            }
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        height: 6
                        visible: mediaCard.player && mediaCard.player.lengthSupported && mediaCard.player.length > 0
                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.xs
                            color: Qt.rgba(1, 1, 1, 0.10)
                        }
                        Rectangle {
                            width: parent.width * mediaCard.mediaProgress
                            height: parent.height
                            radius: Config.radius.xs
                            color: Colors.accent
                            Behavior on width { NumberAnimation { duration: 900; easing.type: Easing.Linear } }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: mediaCard.player && mediaCard.player.lengthSupported && mediaCard.player.length > 0
                        Text {
                            text: mediaCard.mediaCurrentTime
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 6
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: mediaCard.fmtTime(mediaCard.player ? mediaCard.player.length : 0)
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 6
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // -- Right: GIF --
                Item {
                    Layout.preferredWidth: Math.round(mediaCard.width * 0.16)
                    Layout.fillHeight: true

                    AnimatedImage {
                        anchors.centerIn: parent
                        width: Math.min(parent.width * 0.8, 160); height: width
                        source: "file://" + Quickshell.env("HOME") + "/.config/quickshell/assets/record.gif"
                        playing: mediaCard.player && mediaCard.optimisticPlaying
                        fillMode: Image.PreserveAspectFit
                    }
                }
            }
        }
    }
}
