import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../"
import "../config.js" as Config

// Calendar panel opened from Clock: month grid navigation, day selection,
// and simple text-based events (backed by the Events singleton)
PanelWindow {
    id: calMenu
    signal closeRequested()

    property bool open: false
    property bool closing: false
    property real targetY: 0
    visible: open || closing
    onOpenChanged: {
        closing = !open
        if (open) {
            // Fresh view every time: current month, today selected
            const now = new Date()
            calYear = now.getFullYear()
            calMonth = now.getMonth() + 1
            selectedDate = Events.isoToday()
            eventInput.text = ""
            eventInput.forceActiveFocus()
        }
    }

    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    // Ignore (not Normal): with Normal this full-screen surface gets inset by
    // FrameReserve's exclusive zones, shifting our coordinate origin off the
    // output's corner — the panel would land frame.thick too far right and the
    // icon-y handed over from Bar (whose window ignores zones, so it spans the
    // real output) would be misaligned by the top frame strip as well
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    property int calYear: new Date().getFullYear()
    property int calMonth: new Date().getMonth() + 1
    property string selectedDate: Events.isoToday()

    function selectedHeading() {
        return Events.headingFor(selectedDate)
    }

    MouseArea {
        anchors.fill: parent
        onClicked: calMenu.closeRequested()
    }

    Item {
        id: panel
        width: Config.calendarMenu.width
        // Height and vertical position snap instantly
        height: column.implicitHeight + Config.calendarMenu.padding * 2

        anchors.left: parent.left
        anchors.top: parent.top
        // Center on the clock's y, clamped so the panel — plus its corner
        // fillets — never runs off the top/bottom of the frame
        anchors.topMargin: Math.max(
            Config.frame.thin + Config.radius.fillet,
            Math.min(calMenu.targetY - height / 2, parent.height - height - Config.frame.thin - Config.radius.fillet)
        )
        // Open: docked flush against the sidebar's inner edge; closed: fully
        // off-screen left
        anchors.leftMargin: calMenu.open ? Config.frame.thick : -width
        Behavior on anchors.leftMargin {
            NumberAnimation {
                duration: Config.anim.popup
                easing.type: Easing.OutCubic
                onRunningChanged: if (!running && !calMenu.open) calMenu.closing = false
            }
        }

        MouseArea { anchors.fill: parent }

        // Concave fillets melting the panel's left corners into the sidebar
        CornerFillet {
            anchors.left: parent.left
            anchors.bottom: parent.top
            solidCorner: "bottomLeft"
        }
        CornerFillet {
            anchors.left: parent.left
            anchors.top: parent.bottom
            solidCorner: "topLeft"
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius: 0
            bottomLeftRadius: 0
            topRightRadius: Config.radius.hero
            bottomRightRadius: Config.radius.hero
            color: Colors.surface
            clip: true

            ColumnLayout {
                id: column
                anchors.fill: parent
                anchors.margins: Config.calendarMenu.padding
                spacing: Config.calendarMenu.gap

                // -- Month navigation --
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    Layout.rightMargin: Config.gap.sm

                    Text {
                        text: "‹"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.xl
                        font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Config.gap.xs
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (calMenu.calMonth === 1) { calMenu.calMonth = 12; calMenu.calYear-- }
                                else calMenu.calMonth--
                            }
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: Events.monthNames[calMenu.calMonth - 1] + "  " + calMenu.calYear
                        color: Colors.textStrong
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.md
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Text {
                        text: "›"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.xl
                        font.bold: true
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Config.gap.xs
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (calMenu.calMonth === 12) { calMenu.calMonth = 1; calMenu.calYear++ }
                                else calMenu.calMonth++
                            }
                        }
                    }
                }

                // -- Compact month grid --
                CalendarGrid {
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    Layout.rightMargin: Config.gap.sm
                    year: calMenu.calYear
                    month: calMenu.calMonth
                    cellHeight: Config.calendarMenu.cellSize
                    todaySize: Config.calendarMenu.cellSize
                    cellSpacing: Config.gap.xs
                    dowFontSize: Config.type.micro
                    weekFontSize: Config.type.micro
                    dayFontSize: Config.type.sm
                    showSelection: true
                    selectedDate: calMenu.selectedDate
                    eventDates: Events.eventDates
                    onDayClicked: iso => calMenu.selectedDate = iso
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: Config.gap.xs * 2 + 1
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 1
                        color: Colors.border
                    }
                }

                // -- Selected day: heading + events --
                Text {
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    text: calMenu.selectedHeading()
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.micro
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                Repeater {
                    // Rebuilt via Events.revision: eventsFor() results carry
                    // no change notifications of their own
                    model: Events.revision >= 0 ? Events.eventsFor(calMenu.selectedDate) : []

                    delegate: Item {
                        id: eventRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: Config.calendarMenu.rowHeight

                        Rectangle {
                            anchors.fill: parent
                            radius: Config.radius.md
                            color: rowHover.hovered ? Colors.card : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Config.gap.sm
                                anchors.rightMargin: Config.gap.sm
                                spacing: Config.gap.sm

                                Text {
                                    visible: eventRow.modelData.time !== ""
                                    text: eventRow.modelData.time
                                    color: Colors.accent
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    font.bold: true
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: eventRow.modelData.title
                                    color: Colors.text
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: rowHover.hovered
                                    text: "󰅖"
                                    color: deleteHover.hovered ? Colors.error : Colors.subtext
                                    font.family: Config.bar.fontFamily
                                    font.pixelSize: Config.type.sm

                                    HoverHandler { id: deleteHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -Config.gap.xs
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Events.removeAt(calMenu.selectedDate, eventRow.index)
                                    }
                                }
                            }

                            HoverHandler { id: rowHover }
                        }
                    }
                }

                Text {
                    visible: Events.revision >= 0 && Events.eventsFor(calMenu.selectedDate).length === 0
                    Layout.fillWidth: true
                    Layout.leftMargin: Config.gap.sm
                    text: "No events"
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.type.sm
                }

                // -- Add event --
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: Config.gap.xs
                    implicitHeight: Config.calendarMenu.rowHeight
                    radius: Config.radius.md
                    color: Colors.inset

                    TextInput {
                        id: eventInput
                        anchors.fill: parent
                        anchors.leftMargin: Config.gap.sm
                        anchors.rightMargin: Config.gap.sm
                        color: Colors.text
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.type.sm
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true

                        Text {
                            visible: eventInput.text === ""
                            anchors.fill: parent
                            text: "14:00 Dentist  (time optional)"
                            color: Colors.subtext
                            font: eventInput.font
                            verticalAlignment: Text.AlignVCenter
                        }

                        Keys.onReturnPressed: {
                            let title = text.trim()
                            if (title === "") return
                            let time = ""
                            const m = title.match(/^(\d{1,2}:\d{2})\s+(.*)$/)
                            if (m) { time = m[1].padStart(5, "0"); title = m[2] }
                            Events.add(calMenu.selectedDate, time, title)
                            text = ""
                        }
                        Keys.onEscapePressed: calMenu.closeRequested()
                    }
                }
            }
        }
    }
}
