import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

ColumnLayout {
    id: root
    required property var dashboard

    spacing: Config.gap.lg

    readonly property string focusedSym: dashboard.financeSymbols[dashboard.financeFocused] || ""
    readonly property var focusedSeries: dashboard.financeSeriesFor(focusedSym)

    // Change over the *displayed range*: Yahoo's chartPreviousClose is the
    // baseline at the start of the requested range, so this reads as "1Y change"
    // on the 1Y preset and collapses to the familiar daily change on 1D.
    function pctChange(s) {
        if (!s || !s.ok || !s.prev) return 0
        return (s.price - s.prev) / s.prev * 100
    }
    function fmtPrice(v, cur) {
        const a = Math.abs(v)
        const n = a >= 1000 ? v.toFixed(2) : a >= 1 ? v.toFixed(2) : v.toFixed(4)
        // Thousands separators for readability on things like BTC and indices.
        const parts = n.split(".")
        parts[0] = parts[0].replace(/\B(?=(\d{3})+(?!\d))/g, " ")
        return parts.join(".")
    }
    // The arrow is not decoration: Colors.ok and Colors.error both come from
    // pywal and can land on near-identical hues, so direction must survive
    // colour alone.
    function arrow(p) { return p > 0 ? "▲" : p < 0 ? "▼" : "─" }
    function changeColor(p) { return p > 0 ? Colors.ok : p < 0 ? Colors.error : Colors.subtext }
    function fmtPct(p) { return (p > 0 ? "+" : "") + p.toFixed(2) + "%" }

    // ══ Focused asset ══
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Config.radius.xl
        color: Colors.card

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Config.gap.lg
            spacing: Config.gap.md

            // ── header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.gap.lg

                ColumnLayout {
                    spacing: 0

                    Text {
                        text: root.focusedSym
                        color: Colors.textStrong
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.md
                        font.bold: true
                    }

                    Text {
                        text: root.focusedSeries && root.focusedSeries.ok
                            ? root.focusedSeries.name : "—"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.sm
                        elide: Text.ElideRight
                        Layout.maximumWidth: 320
                    }
                }

                Item { Layout.fillWidth: true }

                // price + change
                ColumnLayout {
                    spacing: 0
                    visible: root.focusedSeries && root.focusedSeries.ok

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: Config.gap.sm

                        Text {
                            text: root.focusedSeries
                                ? root.fmtPrice(root.focusedSeries.price, root.focusedSeries.cur) : ""
                            color: Colors.textStrong
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.display
                            font.bold: true
                        }

                        Text {
                            text: root.focusedSeries ? root.focusedSeries.cur : ""
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                            Layout.alignment: Qt.AlignBottom
                            bottomPadding: 4
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignRight
                        readonly property real pct: root.pctChange(root.focusedSeries)
                        text: root.arrow(pct) + " " + root.fmtPct(pct)
                            + "  ·  " + Config.finance.ranges[root.dashboard.financeRangeIdx].label
                        color: root.changeColor(pct)
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.base
                        font.bold: true
                    }
                }
            }

            // ── range presets ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Config.gap.sm

                Repeater {
                    model: Config.finance.ranges
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property bool active: index === root.dashboard.financeRangeIdx
                        width: 56
                        height: 30
                        radius: Config.radius.md
                        color: active ? Colors.accent : Colors.inset

                        Text {
                            anchors.centerIn: parent
                            text: chip.modelData.label
                            color: chip.active ? Colors.onAccent : Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            font.bold: chip.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.dashboard.setFinanceRange(chip.index)
                                bigChart.resetView()
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    visible: root.dashboard.financeUpdated !== ""
                    text: root.dashboard.financeLoading
                        ? "Updating…"
                        : "Updated " + root.dashboard.financeUpdated
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }

                Text {
                    visible: bigChart.zoomed
                    text: "󰀽 right-click to reset"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }
            }

            // ── the chart ──
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                PriceChart {
                    id: bigChart
                    anchors.fill: parent
                    series: root.focusedSeries
                    mode: "candle"
                    interactive: true
                    showAxis: true
                    visible: root.focusedSeries !== null && root.focusedSeries.ok
                }

                Text {
                    anchors.centerIn: parent
                    visible: !bigChart.visible
                    text: root.dashboard.financeSeries.length === 0
                        ? "Loading…"
                        : "No data for " + root.focusedSym
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.base
                }
            }
        }
    }

    // ══ Watchlist strip ══
    // fillHeight must be explicitly false: a layout nested inside another
    // layout defaults it to true, which lets the strip swallow the whole
    // content area and collapse the focused chart above it.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: Config.finance.stripHeight
        Layout.minimumHeight: Config.finance.stripHeight
        Layout.maximumHeight: Config.finance.stripHeight
        spacing: Config.gap.lg

        Repeater {
            model: root.dashboard.financeSymbols

            delegate: Rectangle {
                id: card
                required property var modelData
                required property int index
                readonly property var s: root.dashboard.financeSeriesFor(modelData)
                readonly property bool isFocused: index === root.dashboard.financeFocused
                readonly property real pct: root.pctChange(s)

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Config.radius.xl
                color: Colors.card
                border.width: isFocused ? 2 : 0
                border.color: Colors.accent

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Config.gap.md
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.gap.sm

                        Text {
                            text: card.modelData
                            color: Colors.textStrong
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            font.bold: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Remove — hidden at one symbol, since the tab needs at
                        // least one asset to show.
                        Text {
                            visible: removeArea.containsMouse || cardHover.hovered
                            text: "󰅖"
                            color: removeArea.containsMouse ? Colors.error : Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            enabled: root.dashboard.financeSymbols.length > 1

                            MouseArea {
                                id: removeArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: root.dashboard.financeSymbols.length > 1
                                onClicked: root.dashboard.removeFinanceSymbol(card.index)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Config.gap.sm

                        Text {
                            text: card.s && card.s.ok ? root.fmtPrice(card.s.price, card.s.cur) : "—"
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.base
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            visible: card.s && card.s.ok
                            text: root.arrow(card.pct) + " " + root.fmtPct(card.pct)
                            color: root.changeColor(card.pct)
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                            font.bold: true
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        PriceChart {
                            anchors.fill: parent
                            series: card.s
                            mode: "line"
                            interactive: false
                            visible: card.s !== null && card.s.ok
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: card.s !== null && !card.s.ok
                            text: "Unavailable"
                            color: Colors.subtext
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.type.sm
                        }
                    }
                }

                HoverHandler { id: cardHover }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.dashboard.setFinanceFocus(card.index)
                }
            }
        }

        // ── add-symbol slot, only while there's room ──
        Rectangle {
            visible: root.dashboard.financeSymbols.length < Config.finance.maxSymbols
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Config.radius.xl
            color: Colors.inset

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - Config.gap.lg * 2
                spacing: Config.gap.sm

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "ADD ASSET"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.label
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 34
                    radius: Config.radius.lg
                    color: Colors.border

                    TextInput {
                        id: symInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        color: Colors.text
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.sm
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        onTextChanged: addError = ""

                        property string addError: ""

                        function commit() {
                            const r = root.dashboard.addFinanceSymbol(text)
                            if (r === "ok") { text = ""; addError = "" }
                            else if (r === "duplicate") addError = "Already watching"
                            else if (r === "invalid") addError = "Invalid symbol"
                            else if (r === "full") addError = "List is full"
                        }

                        Text {
                            visible: symInput.text === ""
                            anchors.fill: parent
                            text: "e.g. TSLA"
                            color: Colors.subtext
                            font: symInput.font
                            verticalAlignment: Text.AlignVCenter
                        }

                        Keys.onReturnPressed: symInput.commit()
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    visible: symInput.addError !== ""
                    text: symInput.addError
                    color: Colors.error
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.micro
                    horizontalAlignment: Text.AlignHCenter
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: symInput.addError === ""
                    text: "stocks · crypto · FX · indices"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.micro
                }
            }
        }
    }
}
