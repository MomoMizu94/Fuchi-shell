//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Io
import QtQuick
import "config.js" as Config


Scope {
    id: root

    property bool centerOpen: false
    property bool launcherOpen: false
    property bool powerMenuOpen: false
    property bool volumeMenuOpen: frame.volumeHovered || volumeMenu.panelHovered
    property bool trayMenuOpen: false
    property string trayMenuItemId: ""
    property real trayMenuTargetY: 0

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

    Process {
        id: soundPlayer
        command: ["paplay", "/usr/share/sounds/freedesktop/stereo/message.oga"]
    }

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
            console.log("Stored image:", history.get(0).image)
            console.log("Stored appIcon:", history.get(0).appIcon)
            n.tracked = true
        }
    }

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

    NotificationPopup {
        notifModel: server.trackedNotifications
        dndEnabled: dash.dndEnabled
    }

    // Grace period between the top hover-zone (blocked from receiving further
    // hover events the instant Dashboard's own full-screen surface maps, since
    // that surface — unlike VolumeMenu's — has no input mask, so it captures
    // the whole screen for click-away-to-close) and the panel's own hover
    // reaching the cursor as it slides into view. Without this, "hovered
    // nothing" would be briefly true right as Dashboard opens and it would
    // close itself before ever becoming visible.
    Timer {
        id: dashboardCloseTimer
        // Comfortably longer than the slide-in animation so panelHovered has
        // a chance to pick up the cursor before this can fire — otherwise a
        // hover-in that starts the timer immediately (see onDashboardHoveredChanged
        // below) could close Dashboard mid-slide, before it's even reached
        // the cursor's position.
        interval: Config.anim.slide + 200
        onTriggered: if (!frame.dashboardHovered && !dash.panelHovered) root.centerOpen = false
    }

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
