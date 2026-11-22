import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

ColumnLayout {
    id: root
    required property var dashboard

    readonly property int cardColumns: width >= 1320 ? 3 : width >= 960 ? 2 : 1
    spacing: Config.gap.lg

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        columns: root.cardColumns
        rowSpacing: Config.gap.lg
        columnSpacing: Config.gap.lg

        GreetingCard {
            dashboard: root.dashboard
            Layout.preferredWidth: 400
            Layout.preferredHeight: quickToggles.implicitHeight
        }
        SystemInfoCard {
            dashboard: root.dashboard
            Layout.fillWidth: true
            Layout.preferredHeight: quickToggles.implicitHeight
        }
        QuickTogglesCard {
            id: quickToggles
            dashboard: root.dashboard
            Layout.preferredWidth: 560
        }
        MusicMiniCard {
            id: musicMini
            Layout.row: root.cardColumns === 2 ? 2 : -1
            Layout.column: root.cardColumns === 2 ? 0 : -1
            dashboard: root.dashboard
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
        HardwareCard {
            dashboard: root.dashboard
            // In two columns the hardware gauges fit beside the quick toggles
            Layout.row: root.cardColumns === 2 ? 1 : -1
            Layout.column: root.cardColumns === 2 ? 1 : -1
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: quickToggles.implicitHeight
        }
        WeatherCard {
            Layout.row: root.cardColumns === 2 ? 2 : -1
            Layout.column: root.cardColumns === 2 ? (expandedMap ? 0 : 1) : -1
            Layout.columnSpan: expandedMap ? 2 : 1
            expandedMap: !musicMini.player && root.cardColumns > 1
            dashboard: root.dashboard
            Layout.preferredWidth: 560
            Layout.fillHeight: true
            Layout.preferredHeight: musicMini.player ? Math.max(440, musicMini.implicitHeight) : 440
        }
    }

    NotificationHistoryCard { dashboard: root.dashboard; Layout.minimumHeight: 144 }
}
