//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick
import "config.js" as Config


Scope {
    id: root
    // Open-state for every popup/menu — each flag is toggled via its
    // matching IpcHandler and drives the matching component further down
    property bool centerOpen: false
    property bool launcherOpen: false
    property bool powerMenuOpen: false
    property bool volumeMenuOpen: frame.volumeHovered || volumeMenu.panelHovered
    property bool trayMenuOpen: false
    property string trayMenuItemId: ""
    property real trayMenuTargetY: 0
    property bool bluetoothMenuOpen: false
    property real bluetoothMenuTargetY: 0
    property bool calendarMenuOpen: false
    property real calendarMenuTargetY: 0
    property bool networkMenuOpen: false
    property real networkMenuTargetY: 0

    // Notification history
    ListModel { id: history }

    // Silence music apps from notification sounds
    function playNotificationSound(n) {
        const app = (n.appName || "").toLowerCase();

        const silentApps = [
            "spotify",
            "spotify_player",
            "spotify-player"
        ];

        return !silentApps.includes(app);
    }

    // Plays the notification sound; triggered by onNotification
    Process {
        id: soundPlayer
        command: ["paplay", "/usr/share/sounds/freedesktop/stereo/message.oga"]
    }

    // Listens for system notifications: feeds the popup via trackedNotifications
    // and appends each one to the history
    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            if (!dash.dndEnabled && root.playNotificationSound(n))
                soundPlayer.startDetached()
            history.insert(0, {
                summary: n.summary,
                body: n.body,
                appName: n.appName,
                urgency: n.urgency,
                time: Qt.formatDateTime(new Date(), "HH:mm"),
                image: n.image ? n.image.toString() : (
                    n.appIcon.startsWith("/") ? n.appIcon : ""
                ),
                appIcon: n.appIcon.startsWith("/") ? "" : (n.appIcon || "")
            })
            // History cap
            if (history.count > Config.notifications.historyLimit)
                history.remove(Config.notifications.historyLimit, history.count - Config.notifications.historyLimit)
            n.tracked = true
        }
    }

    // IPC handlers
    IpcHandler {
        target: "notifications"
        function toggle(): void { root.centerOpen = !root.centerOpen }
        function show(): void { root.centerOpen = true }
        function hide(): void { root.centerOpen = false }
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void { root.launcherOpen = !root.launcherOpen }
        function show(): void { root.launcherOpen = true }
        function hide(): void { root.launcherOpen = false }
    }

    IpcHandler {
        target: "powermenu"
        function toggle(): void { root.powerMenuOpen = !root.powerMenuOpen }
        function show(): void { root.powerMenuOpen = true }
        function hide(): void { root.powerMenuOpen = false }
    }

    IpcHandler {
        target: "traymenu"
        function open(id: string, y: string): void {
            root.trayMenuItemId = id
            root.trayMenuTargetY = Number(y)
            root.trayMenuOpen = true
        }
        function hide(): void { root.trayMenuOpen = false }
    }

    IpcHandler {
        target: "bluetoothmenu"
        function toggle(y: string): void {
            root.bluetoothMenuTargetY = Number(y)
            root.bluetoothMenuOpen = !root.bluetoothMenuOpen
        }
        function hide(): void { root.bluetoothMenuOpen = false }
    }

    IpcHandler {
        target: "calendarmenu"
        function toggle(y: string): void {
            root.calendarMenuTargetY = Number(y)
            root.calendarMenuOpen = !root.calendarMenuOpen
        }
        function hide(): void { root.calendarMenuOpen = false }
    }

    IpcHandler {
        target: "networkmenu"
        function toggle(y: string): void {
            root.networkMenuTargetY = Number(y)
            root.networkMenuOpen = !root.networkMenuOpen
        }
        function hide(): void { root.networkMenuOpen = false }
    }

    // On-screen popup for incoming notifications
    NotificationPopup {
        notifModel: server.trackedNotifications
        dndEnabled: dash.dndEnabled
    }

    // Grace period between the top hover-zone and the panel's own hover
    // reaching the cursor as it slides into view
    Timer {
        id: dashboardCloseTimer
        // Comfortably longer than the slide-in animation so panelHovered has
        // a chance to pick up the cursor before this can fire
        interval: Config.anim.slide + 200
        onTriggered: if (!frame.dashboardHovered && !dash.panelHovered) root.centerOpen = false
    }

    // Every popup/menu wired to its open-flag
    Dashboard {
        id: dash
        open: root.centerOpen
        historyModel: history
        onCloseRequested: root.centerOpen = false
        onPanelHoveredChanged: {
            if (panelHovered) dashboardCloseTimer.stop()
            else if (root.centerOpen) dashboardCloseTimer.restart()
        }
    }

    AppLauncher {
        id: launcher
        open: root.launcherOpen
        onCloseRequested: root.launcherOpen = false
    }

    PowerMenu {
        id: powerMenu
        open: root.powerMenuOpen
        onCloseRequested: root.powerMenuOpen = false
    }

    VolumeMenu {
        id: volumeMenu
        open: root.volumeMenuOpen
    }

    TrayMenu {
        id: trayMenu
        open: root.trayMenuOpen
        itemId: root.trayMenuItemId
        targetY: root.trayMenuTargetY
        onCloseRequested: root.trayMenuOpen = false
    }

    BluetoothMenu {
        id: bluetoothMenu
        open: root.bluetoothMenuOpen
        targetY: root.bluetoothMenuTargetY
        onCloseRequested: root.bluetoothMenuOpen = false
    }

    CalendarMenu {
        id: calendarMenu
        open: root.calendarMenuOpen
        targetY: root.calendarMenuTargetY
        onCloseRequested: root.calendarMenuOpen = false
    }

    NetworkMenu {
        id: networkMenu
        open: root.networkMenuOpen
        targetY: root.networkMenuTargetY
        onCloseRequested: root.networkMenuOpen = false
    }

    // Reserved screen-edge space, the hover-sensitive frame,
    // and the bar itself
    FrameReserve {}
    FrameShape {
        id: frame
        onHoverOpenRequested: root.centerOpen = true
        onLauncherHoverRequested: root.launcherOpen = true
        onDashboardHoveredChanged: {
            if (dashboardHovered) dashboardCloseTimer.stop()
            else if (root.centerOpen) dashboardCloseTimer.restart()
        }
    }
    Bar {}
}
