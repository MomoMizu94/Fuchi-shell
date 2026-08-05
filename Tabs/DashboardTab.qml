import QtQuick
import QtQuick.Layouts
import "../"
import "../config.js" as Config

// Overview tab: greeting/system-info/quick-toggles row, music/hardware/weather
// row, then notification history — just composes the Widgets/* cards
ColumnLayout {
    id: root
    required property var dashboard

    spacing: Config.gap.lg

    RowLayout {
        Layout.fillWidth: true
        spacing: Config.gap.lg

        // QuickToggles is the height reference for this row.
        // Greeting/SystemInfo are forced to match it exactly, not just fillHeight,
        // so their own content can never stretch the row taller than intended
        GreetingCard { dashboard: root.dashboard; Layout.preferredHeight: quickToggles.implicitHeight }
        SystemInfoCard { dashboard: root.dashboard; Layout.preferredHeight: quickToggles.implicitHeight }
        QuickTogglesCard { id: quickToggles; dashboard: root.dashboard }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Config.gap.lg

        // MusicMini is the height reference for this row. 
        // Hardware/Weather are forced to match it exactly
        MusicMiniCard { id: musicMini; dashboard: root.dashboard }
        HardwareCard { dashboard: root.dashboard; Layout.preferredHeight: musicMini.implicitHeight }
        WeatherCard { dashboard: root.dashboard; Layout.preferredHeight: musicMini.implicitHeight }
    }

    NotificationHistoryCard { dashboard: root.dashboard }
}
