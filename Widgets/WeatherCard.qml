import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import "../"
import "../config.js" as Config

// Overview tab card: current conditions, 3-day forecast, and an interactive
// RainViewer precipitation radar map (pan/zoom/play-pause)
Rectangle {
    required property var dashboard
    Layout.fillWidth: true
    radius: Config.radius.xl
    color: Colors.card
    clip: true

    ColumnLayout {
        id: weatherContent
        anchors.fill: parent
        anchors.margins: Config.gap.md
        spacing: Config.gap.sm
        Text {
            text: "WEATHER"
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.label
            font.bold: true
            font.letterSpacing: 1.5
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Config.gap.md

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Config.gap.sm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Config.gap.xl
                    Text {
                        text: dashboard.weatherTemp + "°"
                        color: Colors.border
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.hero
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: dashboard.weatherIcon(dashboard.weatherDesc)
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.hero
                        color: Colors.border
                        font.bold: true
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: dashboard.weatherLocation !== ""
                    text: dashboard.weatherLocation
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: dashboard.weatherDesc !== "" ? dashboard.weatherDesc : "Loading…"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                    elide: Text.ElideRight
                }

                Text {
                    text: "H: " + dashboard.weatherHigh + "°  L: " + dashboard.weatherLow
                        + "°"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }

                Text {
                    text: dashboard.weatherHumidity + "% humidity"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }

                Text {
                    text: "Wind: " + dashboard.weatherWindSpeed + " km/h " + dashboard.weatherWindDir
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }

                Item { Layout.fillHeight: true }
            }

            // -- Interactive radar map (drag to pan, wheel to zoom, double-click home) --
            ClippingRectangle {
                id: precipMap
                Layout.fillHeight: true
                Layout.preferredWidth: height
                radius: Config.radius.lg
                color: Colors.border
                visible: dashboard.weatherLat !== 0

                property real centerLat: dashboard.weatherLat
                property real centerLon: dashboard.weatherLon
                property real xf: dashboard.lonToTileX(centerLon, dashboard.mapZoom)
                property real yf: dashboard.latToTileY(centerLat, dashboard.mapZoom)
                property bool radarPlaying: true
                property var radarFrame: dashboard.radarFrames[dashboard.radarIdx] || null
                property bool viewSettled: false
                property int prefetchStage: 0

                function unsettle() {
                    viewSettled = false
                    prefetchStage = 0
                    settleTimer.restart()
                }

                Timer {
                    id: settleTimer
                    interval: Config.timer.mapSettle
                    onTriggered: precipMap.viewSettled = true
                }
                Component.onCompleted: settleTimer.start()

                Connections {
                    target: dashboard
                    function onRadarFramesChanged() { precipMap.unsettle() }
                }

                Timer {
                    interval: dashboard.radarIdx === dashboard.radarFrames.length - 1 ? Config.timer.radarFrameDwell : Config.timer.radarFrameAdvance
                    repeat: true
                    running: dashboard.visible && dashboard.activeTab === 0
                             && precipMap.radarPlaying && precipMap.viewSettled
                             && dashboard.radarFrames.length > 0
                             && precipMap.prefetchStage >= dashboard.radarFrames.length - 1
                    onTriggered: dashboard.radarIdx = (dashboard.radarIdx + 1) % dashboard.radarFrames.length
                }

                // Staggered prefetch: warm one radar frame (9 center tiles) at a
                // time — gentle enough to stay under RainViewer's rate limit.
                // The animation holds on the current frame until all are warm
                Timer {
                    interval: Config.timer.mapPrefetchStagger
                    repeat: true
                    running: precipMap.viewSettled
                             && precipMap.prefetchStage < dashboard.radarFrames.length - 1
                    onTriggered: precipMap.prefetchStage++
                }

                Repeater {
                    model: precipMap.viewSettled ? dashboard.radarFrames.length * 9 : 0
                    delegate: Image {
                        required property int index
                        visible: false
                        asynchronous: true
                        cache: true
                        source: {
                            if (Math.floor(index / 9) > precipMap.prefetchStage) return ""
                            const f = dashboard.radarFrames[Math.floor(index / 9)]
                            if (!f) return ""
                            const cell = index % 9
                            const cdx = (cell % 3) - 1
                            const cdy = Math.floor(cell / 3) - 1
                            const z = dashboard.mapZoom
                            const n = Math.pow(2, z)
                            const tx = (((Math.floor(precipMap.xf) + cdx) % n) + n) % n
                            const ty = Math.floor(precipMap.yf) + cdy
                            if (ty < 0 || ty >= n) return ""
                            return f.url + "/256/" + z + "/" + tx + "/" + ty + "/2/1_1.png"
                        }
                    }
                }

                Item {
                    // 5×5 tile grid centered on the fractional position
                    anchors.centerIn: parent
                    width: 1280; height: 1280
                    anchors.horizontalCenterOffset: -((precipMap.xf % 1) - 0.5) * 256
                    anchors.verticalCenterOffset: -((precipMap.yf % 1) - 0.5) * 256

                    Repeater {
                        model: 25
                        delegate: Item {
                            required property int index
                            property int dx: (index % 5) - 2
                            property int dy: Math.floor(index / 5) - 2

                            // Atomic URL build: range check and URL always agree
                            function tileUrl(prefix, suffix) {
                                const z = dashboard.mapZoom
                                const n = Math.pow(2, z)
                                const tx = (((Math.floor(precipMap.xf) + dx) % n) + n) % n
                                const ty = Math.floor(precipMap.yf) + dy
                                if (ty < 0 || ty >= n) return ""
                                return prefix + z + "/" + tx + "/" + ty + suffix
                            }

                            x: (dx + 2) * 256
                            y: (dy + 2) * 256
                            width: 256; height: 256

                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                source: parent.tileUrl("https://basemaps.cartocdn.com/rastertiles/voyager/", ".png")
                                opacity: 0.85
                            }
                            Image {
                                anchors.fill: parent
                                asynchronous: true
                                cache: true
                                visible: precipMap.viewSettled && precipMap.radarFrame !== null
                                source: precipMap.viewSettled && precipMap.radarFrame
                                    ? parent.tileUrl(precipMap.radarFrame.url + "/256/", "/2/1_1.png")
                                    : ""
                                opacity: 0.8
                            }
                        }
                    }
                }

                // Home marker — pinned to the real location
                Rectangle {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: (dashboard.lonToTileX(dashboard.weatherLon, dashboard.mapZoom) - precipMap.xf) * 256
                    anchors.verticalCenterOffset: (dashboard.latToTileY(dashboard.weatherLat, dashboard.mapZoom) - precipMap.yf) * 256
                    width: 12; height: 12; radius: 6
                    color: Colors.accent
                    border.width: 2
                    border.color: Colors.text
                }

                MouseArea {
                    anchors.fill: parent
                    property real pressXf: 0
                    property real pressYf: 0
                    property real pressX: 0
                    property real pressY: 0

                    onPressed: mouse => {
                        pressXf = precipMap.xf; pressYf = precipMap.yf
                        pressX = mouse.x; pressY = mouse.y
                    }
                    onPositionChanged: mouse => {
                        if (!pressed) return
                        const z = dashboard.mapZoom
                        const newXf = pressXf - (mouse.x - pressX) / 256
                        const newYf = pressYf - (mouse.y - pressY) / 256
                        precipMap.centerLon = dashboard.tileXToLon(newXf, z)
                        precipMap.centerLat = Math.max(-85, Math.min(85, dashboard.tileYToLat(newYf, z)))
                        precipMap.unsettle()
                    }
                    onWheel: wheel => {
                        const step = wheel.angleDelta.y > 0 ? 1 : -1
                        dashboard.mapZoom = Math.max(3, Math.min(12, dashboard.mapZoom + step))
                        precipMap.unsettle()
                    }
                    onDoubleClicked: {
                        precipMap.centerLat = Qt.binding(() => dashboard.weatherLat)
                        precipMap.centerLon = Qt.binding(() => dashboard.weatherLon)
                        dashboard.mapZoom = 7
                        precipMap.unsettle()
                    }
                }

                // Radar time HUD — click to play/pause
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: Config.gap.sm
                    radius: Config.radius.md
                    color: Qt.rgba(0, 0, 0, 0.45)
                    width: hudRow.implicitWidth + 16
                    height: hudRow.implicitHeight + 8
                    visible: precipMap.radarFrame !== null

                    RowLayout {
                        id: hudRow
                        anchors.centerIn: parent
                        spacing: Config.gap.sm
                        Text {
                            text: precipMap.radarPlaying ? "" : ""
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.label
                        }
                        Text {
                            text: precipMap.radarFrame
                                ? Qt.formatTime(new Date(precipMap.radarFrame.time * 1000), "HH:mm")
                                  + (precipMap.radarFrame.future ? " ⟶ NOWCAST" : "")
                                : ""
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.label
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: precipMap.radarPlaying = !precipMap.radarPlaying
                    }
                }

                Text {
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: Config.gap.xs
                    text: "© OSM © CARTO · RainViewer"
                    color: Colors.border
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.micro
                }
            }
        }

        // 3-day forecast strip
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Config.gap.lg
            Text {
                text: "WEATHER FORECAST"
                color: Colors.subtext
                font.family: Config.bar.fontFamily
                font.pixelSize: Config.type.lg                                        
                font.bold: true
                font.letterSpacing: 1.5
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: Config.gap.lg
            Layout.alignment: Qt.AlignHCenter
            spacing: Config.gap.lg

            Repeater {
                model: 3
                delegate: ColumnLayout {
                    required property int index
                    property var fc: dashboard.weatherForecast[index] || null
                    Layout.fillWidth: true
                    spacing: Config.gap.xs
                    visible: fc !== null

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: fc ? fc.day : ""
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.base
                        font.bold: true
                        font.letterSpacing: 1
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: fc ? dashboard.weatherIcon(fc.desc) : ""
                        color: Colors.border
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.display
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: fc ? fc.high + "° / " + fc.low + "°" : ""
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.base
                    }
                }
            }
        }
    }
}
