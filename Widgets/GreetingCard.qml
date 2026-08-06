import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

// Overview tab card: time-of-day greeting, clock, and date
Rectangle {
    id: greetingCard
    required property var dashboard
    Layout.fillWidth: true
    radius: Config.radius.xl
    color: Colors.card

    ColumnLayout {
        id: greetingLayout
        anchors.fill: parent
        anchors.margins: Config.gap.md
        spacing: Config.gap.xs

        Text {
            text: dashboard.greeting() + ", " + dashboard.userName + "!"
            color: Colors.border
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.xl
            font.bold: true
        }

        Text {
            text: dashboard.currentTime
            color: Colors.border
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.hero
            font.bold: true
        }

        Text {
            text: dashboard.currentDate
            color: Colors.subtext
            font.family: Config.bar.fontFamily
            font.pixelSize: Config.type.md
        }
    }
}
