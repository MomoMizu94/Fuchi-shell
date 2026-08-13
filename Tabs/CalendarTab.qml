import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

// Calendar tab: full-size month grid + per-day events and a to-do
// list. Compact-popup counterpart is Bar/CalendarMenu.qml — the two
// share date logic via the Events singleton but are separate layouts
ColumnLayout {
    id: root
    required property var dashboard

    spacing: 6

    property string selectedDate: Events.isoToday()

    function selectedHeading() {
        return Events.headingFor(root.selectedDate)
    }

    // Fresh view every time the dashboard opens: current month, today selected
    Connections {
        target: root.dashboard
        function onOpenChanged() {
            if (root.dashboard.open) {
                const now = new Date()
                root.dashboard.calYear = now.getFullYear()
                root.dashboard.calMonth = now.getMonth() + 1
                root.selectedDate = Events.isoToday()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 20
        Text {
            text: "‹"
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.bar.fontSize + 20
            font.bold: true
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (dashboard.calMonth === 1) { dashboard.calMonth = 12; dashboard.calYear-- }
                    else dashboard.calMonth--
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: Events.monthNames[dashboard.calMonth - 1] + "  " + dashboard.calYear
            color: Colors.text
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.bar.fontSize + 20
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            text: "›"
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.bar.fontSize + 10
            font.bold: true
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (dashboard.calMonth === 12) { dashboard.calMonth = 1; dashboard.calYear++ }
                    else dashboard.calMonth++
                }
            }
        }
    }

    // Shared month grid
    CalendarGrid {
        Layout.fillWidth: true
        Layout.bottomMargin: 100
        year: dashboard.calYear
        month: dashboard.calMonth
        eventDates: Events.eventDates
        showSelection: true
        selectedDate: root.selectedDate
        onDayClicked: iso => root.selectedDate = iso
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 14

        // -- Events for the selected day --
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // 40/60 split with the to-do card
            Layout.preferredWidth: 4
            radius: Config.radius.xl
            color: Colors.card

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 14
                spacing: 10

                Text {
                    text: "EVENTS — " + root.selectedHeading()
                    color: Colors.subtext
                    font.family: Config.bar.fontFamily
                    font.pixelSize: Config.bar.fontSize - 8
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: Config.radius.lg
                        color: Colors.border

                        TextInput {
                            id: eventInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 4
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            function submit() {
                                let title = text.trim()
                                if (title === "") return
                                let time = ""
                                const m = title.match(/^(\d{1,2}:\d{2})\s+(.*)$/)
                                if (m) { time = m[1].padStart(5, "0"); title = m[2] }
                                Events.add(root.selectedDate, time, title)
                                text = ""
                            }

                            Text {
                                visible: eventInput.text === ""
                                anchors.fill: parent
                                text: "14:00 Dentist  (time optional)"
                                color: Colors.subtext
                                font: eventInput.font
                                verticalAlignment: Text.AlignVCenter
                            }

                            Keys.onReturnPressed: submit()
                        }
                    }

                    Rectangle {
                        width: 34; height: 34
                        radius: Config.radius.lg
                        color: Colors.accent

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: Colors.onAccent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize + 4
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: eventInput.submit()
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: eventItemsCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: eventItemsCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            // Rebuilt via Events.revision: eventsFor() results
                            // carry no change notifications of their own
                            model: Events.revision >= 0 ? Events.eventsFor(root.selectedDate) : []
                            delegate: Rectangle {
                                id: eventRow
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                height: 38
                                radius: Config.radius.lg
                                color: Qt.rgba(1,1,1,0.07)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Text {
                                        visible: eventRow.modelData.time !== ""
                                        text: eventRow.modelData.time
                                        color: Colors.accent
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.bar.fontSize - 4
                                        font.bold: true
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: eventRow.modelData.title
                                        color: Colors.text
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.bar.fontSize - 4
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: "󰅖"
                                        color: Colors.subtext
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.bar.fontSize - 4

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: Events.removeAt(root.selectedDate, eventRow.index)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: Events.revision >= 0 && Events.eventsFor(root.selectedDate).length === 0
                        text: "No events"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.bar.fontSize - 4
                    }
                }
            }
        }

        // -- To-do list --
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            // 40/60 split with the events card
            Layout.preferredWidth: 6
            radius: Config.radius.xl
            color: Colors.card

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "TO-DO"
                        color: Colors.subtext
                        font.family: Config.bar.fontFamily
                        font.pixelSize: Config.bar.fontSize - 8
                        font.bold: true
                        font.letterSpacing: 1.5
                    }

                    Item { Layout.fillWidth: true }

                    // Bulk-remove for checked tasks; same tile as the add button
                    // below, faded out and inert while nothing is checked off
                    Rectangle {
                        readonly property bool armed: dashboard.todoDoneCount > 0

                        width: 34; height: 34
                        radius: Config.radius.lg
                        color: Colors.error
                        opacity: armed ? 1 : 0.35

                        Text {
                            id: clearIcon
                            anchors.centerIn: parent
                            // The trash-can glyph's ink is wider than the advance
                            // cell the Text item is sized to, and overhangs to the
                            // right, so plain centering leaves it visibly off
                            anchors.horizontalCenterOffset:
                                clearIcon.width / 2 - (clearIconMetrics.tightBoundingRect.x
                                                       + clearIconMetrics.tightBoundingRect.width / 2)
                            text: "󰩹"
                            color: Colors.onAccent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize + 2
                            font.bold: true

                            TextMetrics {
                                id: clearIconMetrics
                                font: clearIcon.font
                                text: clearIcon.text
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.armed
                            onClicked: dashboard.clearDoneTodos()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.fillWidth: true
                        height: 34
                        radius: Config.radius.lg
                        color: Colors.border

                        TextInput {
                            id: todoInput
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            color: Colors.text
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize - 4
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true

                            Text {
                                visible: todoInput.text === ""
                                anchors.fill: parent
                                text: "Add new task…"
                                color: Colors.subtext
                                font: todoInput.font
                                verticalAlignment: Text.AlignVCenter
                            }

                            Keys.onReturnPressed: {
                                if (text.trim() !== "") {
                                    dashboard.todoList.append({ taskText: text.trim(), done: false })
                                    text = ""
                                    dashboard.saveTodos()
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 34; height: 34
                        radius: Config.radius.lg
                        color: Colors.accent

                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: Colors.onAccent
                            font.family: Config.bar.fontFamily
                            font.pixelSize: Config.bar.fontSize + 4
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (todoInput.text.trim() !== "") {
                                    dashboard.todoList.append({ taskText: todoInput.text.trim(), done: false })
                                    todoInput.text = ""
                                    dashboard.saveTodos()
                                }
                            }
                        }
                    }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: todoItemsCol.implicitHeight
                    clip: true

                    ColumnLayout {
                        id: todoItemsCol
                        width: parent.width
                        spacing: 4

                        Repeater {
                            model: dashboard.todoList
                            delegate: Rectangle {
                                required property int index
                                required property string taskText
                                required property bool done

                                Layout.fillWidth: true
                                // Grows with wrapped task text
                                Layout.preferredHeight: Math.max(38, taskRow.implicitHeight + 12)
                                radius: Config.radius.lg
                                color: done ? Qt.rgba(1,1,1,0.03) : Qt.rgba(1,1,1,0.07)

                                RowLayout {
                                    id: taskRow
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10

                                    Rectangle {
                                        width: 18; height: 18; radius: Config.radius.sm
                                        color: done ? Colors.accent : "transparent"
                                        border.width: 2
                                        border.color: done ? Colors.accent : Colors.subtext

                                        Text {
                                            visible: done
                                            anchors.centerIn: parent
                                            text: "✓"
                                            color: Colors.onAccent
                                            font.pixelSize: 11
                                            font.bold: true
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                dashboard.todoList.setProperty(index, "done", !done)
                                                dashboard.saveTodos()
                                            }
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: taskText
                                        color: done ? Colors.subtext : Colors.text
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.bar.fontSize - 4
                                        font.strikeout: done
                                        wrapMode: Text.WordWrap
                                    }

                                    Text {
                                        text: "󰅖"
                                        color: Colors.subtext
                                        font.family: Config.bar.fontFamily
                                        font.pixelSize: Config.bar.fontSize - 4

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                const dash = dashboard
                                                dash.todoList.remove(index, 1)
                                                dash.saveTodos()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

    }
}
