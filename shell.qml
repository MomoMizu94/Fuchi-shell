//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Mpris
import Quickshell.Io
import QtQuick
import "config.js" as Config
import "settings.js" as Paths


Scope {
    id: root
    // Bar clicks and external IPC calls share the same menu handlers
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
    property bool layoutMenuOpen: false
    property real layoutMenuTargetY: 0
    property bool hostMenuOpen: false
    property real hostMenuTargetY: 0
    property bool updatesMenuOpen: false
    property real updatesMenuTargetY: 0
    // Current tiling layout as its dwm label ("tile", "bstack", ...). hyprland.lua pushes this
    // in on every change (see PublishLayout there). Both the bar indicator and
    // the layout menu read it
    property string currentLayout: ""

    // Let the newly opened menu receive keys as soon as the launcher starts closing
    onCenterOpenChanged: if (centerOpen) launcherOpen = false
    onPowerMenuOpenChanged: if (powerMenuOpen) launcherOpen = false
    onTrayMenuOpenChanged: if (trayMenuOpen) launcherOpen = false
    onBluetoothMenuOpenChanged: if (bluetoothMenuOpen) launcherOpen = false
    onLayoutMenuOpenChanged: if (layoutMenuOpen) launcherOpen = false
    onCalendarMenuOpenChanged: if (calendarMenuOpen) launcherOpen = false
    onNetworkMenuOpenChanged: if (networkMenuOpen) launcherOpen = false
    onHostMenuOpenChanged: if (hostMenuOpen) launcherOpen = false
    onUpdatesMenuOpenChanged: if (updatesMenuOpen) launcherOpen = false

    UpdateService { id: updateService }
    ColorPicker { id: colorPicker }
    readonly property bool otherMenuOpen: launcherOpen || centerOpen || powerMenuOpen || trayMenuOpen
        || bluetoothMenuOpen || calendarMenuOpen || networkMenuOpen || layoutMenuOpen || hostMenuOpen || updatesMenuOpen
    onOtherMenuOpenChanged: if (otherMenuOpen) clipboardMenu.open = false

    function showClipboard(y) {
        launcherOpen = false
        centerOpen = false
        powerMenuOpen = false
        trayMenuOpen = false
        bluetoothMenuOpen = false
        calendarMenuOpen = false
        networkMenuOpen = false
        layoutMenuOpen = false
        hostMenuOpen = false
        updatesMenuOpen = false
        clipboardMenu.targetY = y
        clipboardMenu.open = true
    }

    // Notification history
    ListModel { id: history }

    function trimHistory() {
        if (history.count > Settings.historyLimit)
            history.remove(Settings.historyLimit, history.count - Settings.historyLimit)
    }

    Connections {
        target: Settings
        function onHistoryLimitChanged() { root.trimHistory() }
    }

    function dismissKeyboardOverlays() {
        root.launcherOpen = false
        clipboardMenu.open = false
    }

    function showSettings() {
        dismissKeyboardOverlays()
        Qt.callLater(function() { settingsWindow.showSettings() })
    }

    function showLibrary() {
        dismissKeyboardOverlays()
        Qt.callLater(function() { libraryWindow.showLibrary() })
    }

    function showOceanus(action) {
        dismissKeyboardOverlays()
        if (oceanusLauncher.running) return
        oceanusLauncher.command = ["python3", Quickshell.shellDir + "/scripts/oceanus.py", action,
            "--state", Quickshell.statePath("oceanus.json"),
            "--python", Paths.absolutePath(Config.oceanus.python, Quickshell.env("HOME"))]
        oceanusLauncher.running = true
    }

    // Spotify's ('spotify' package in AUR) notification carries no image -> reuse the artwork exposed
    // by the same player over MPRIS
    readonly property var spotifyPlayer: {
        const players = Mpris.players.values
        for (let i = 0; i < players.length; i++) {
            const player = players[i]
            if (player && ((player.identity || "").toLowerCase() === "spotify"
                    || (player.desktopEntry || "").toLowerCase() === "spotify"))
                return players[i]
        }
        return null
    }

    function syncSpotifyHistoryArt() {
        // Callers defer this until the current metadata update has settled.
        const artUrl = root.spotifyPlayer ? (root.spotifyPlayer.trackArtUrl || "") : ""
        if (!artUrl)
            return

        for (let i = 0; i < history.count; i++) {
            const entry = history.get(i)
            if ((entry.appName || "").toLowerCase() === "spotify"
                    && entry.summary === root.spotifyPlayer.trackTitle) {
                if (entry.image === "")
                    history.setProperty(i, "image", artUrl)
                return
            }
        }
    }

    Connections {
        target: root.spotifyPlayer
        function onPostTrackChanged() { Qt.callLater(root.syncSpotifyHistoryArt) }
        function onMetadataChanged() { Qt.callLater(root.syncSpotifyHistoryArt) }
    }

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
        actionsSupported: false
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            // Support for transient notifications
            if (!dash.dndEnabled && !n.transient && root.playNotificationSound(n))
                soundPlayer.startDetached()

            if (!n.transient) {
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
                root.trimHistory()
                if ((n.appName || "").toLowerCase() === "spotify")
                    Qt.callLater(root.syncSpotifyHistoryArt)
            }
            n.tracked = true
        }
    }

    // IPC handlers
    IpcHandler {
        target: "colorpicker"
        function pick(): void { colorPicker.pick() }
    }
    IpcHandler {
        target: "clipboard"
        function toggle(): void {
            if (clipboardMenu.open) clipboardMenu.open = false
            else root.showClipboard((clipboardMenu.screen?.height ?? clipboardMenu.height) / 2)
        }
    }
    IpcHandler {
        target: "oceanus"
        function show(): void { root.showOceanus("open") }
        function newConversation(): void { root.showOceanus("new") }
    }

    IpcHandler {
        target: "library"
        function show(): void { root.showLibrary() }
        function hide(): void { libraryWindow.hideLibrary() }
        function setFolder(path: string): void { Settings.setPath("libraryFolder", path) }
        function toggle(): void {
            if (libraryWindow.visible || libraryWindow.openRequested) libraryWindow.hideLibrary()
            else root.showLibrary()
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
        target: "settings"
        function show(): void { root.showSettings() }
        function hide(): void { settingsWindow.hideSettings() }
        function toggle(): void {
            if (settingsWindow.visible || settingsWindow.openRequested) settingsWindow.hideSettings()
            else root.showSettings()
        }
    }

    IpcHandler {
        id: powerMenuIpc
        target: "powermenu"
        function toggle(): void { root.powerMenuOpen = !root.powerMenuOpen }
        function show(): void { root.powerMenuOpen = true }
        function hide(): void { root.powerMenuOpen = false }
    }

    IpcHandler {
        id: trayMenuIpc
        target: "traymenu"
        function open(id: string, y: string): void {
            root.trayMenuItemId = id
            root.trayMenuTargetY = Number(y)
            root.trayMenuOpen = true
        }
        function hide(): void { root.trayMenuOpen = false }
    }

    IpcHandler {
        id: bluetoothMenuIpc
        target: "bluetoothmenu"
        function toggle(y: string): void {
            root.bluetoothMenuTargetY = Number(y)
            root.bluetoothMenuOpen = !root.bluetoothMenuOpen
        }
        function hide(): void { root.bluetoothMenuOpen = false }
    }

    IpcHandler {
        id: calendarMenuIpc
        target: "calendarmenu"
        function toggle(y: string): void {
            root.calendarMenuTargetY = Number(y)
            root.calendarMenuOpen = !root.calendarMenuOpen
        }
        function hide(): void { root.calendarMenuOpen = false }
    }

    IpcHandler {
        id: networkMenuIpc
        target: "networkmenu"
        function toggle(y: string): void {
            root.networkMenuTargetY = Number(y)
            root.networkMenuOpen = !root.networkMenuOpen
        }
        function hide(): void { root.networkMenuOpen = false }
    }

    IpcHandler {
        id: layoutMenuIpc
        target: "layoutmenu"
        function toggle(y: string): void {
            root.layoutMenuTargetY = Number(y)
            root.layoutMenuOpen = !root.layoutMenuOpen
        }
        function hide(): void { root.layoutMenuOpen = false }
    }

    IpcHandler {
        id: hostMenuIpc
        target: "hostmenu"
        function toggle(y: string): void {
            root.hostMenuTargetY = Number(y)
            root.hostMenuOpen = !root.hostMenuOpen
        }
        function hide(): void { root.hostMenuOpen = false }
    }

    IpcHandler {
        id: updatesMenuIpc
        target: "updatesmenu"
        function toggle(y: string): void {
            root.updatesMenuTargetY = Number(y)
            root.updatesMenuOpen = !root.updatesMenuOpen
        }
        function hide(): void { root.updatesMenuOpen = false }
    }

    // Pushed in by hyprland.lua on every layout change
    IpcHandler {
        target: "layout"
        function set(name: string): void { root.currentLayout = name }
    }

    // Ask Lua for the current label at startup: the shell can be restarted
    // independently of the compositor, and nothing would push until the next
    // layout change otherwise. `hyprctl eval` runs in the config's own global Lua
    // state, which is how PublishLayout is reachable at all
    Process { id: layoutProbe; command: ["hyprctl", "eval", "PublishLayout()"] }
    Component.onCompleted: layoutProbe.startDetached()

    // Retries while the label is still empty, covering the shell coming up before
    // Hyprland can answer. The binding stops the timer as soon as one lands
    Timer {
        interval: 1500
        repeat: true
        running: root.currentLayout === ""
        onTriggered: layoutProbe.startDetached()
    }

    // On-screen popup for incoming notifications
    NotificationPopup {
        notifModel: server.trackedNotifications
        dndEnabled: dash.dndEnabled
        spotifyArtUrl: root.spotifyPlayer ? (root.spotifyPlayer.trackArtUrl || "") : ""
    }

    // Grace period between the top hover-zone and the panel's own hover
    // reaching the cursor as it slides into view
    Timer {
        id: dashboardCloseTimer
        // Comfortably longer than the slide-in animation so panelHovered has
        // a chance to pick up the cursor before this can fire
        interval: Settings.animationSlide + 200
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
        onSettingsRequested: root.showSettings()
        onLibraryRequested: root.showLibrary()
        onOceanusRequested: root.showOceanus("open")
    }

    SettingsWindow { id: settingsWindow }
    LibraryWindow { id: libraryWindow }
    Process {
        id: oceanusLauncher
        stderr: StdioCollector { id: oceanusError }
        onExited: (code, status) => {
            if (code === 0 && status === 0) return
            const message = oceanusError.text.trim() || "The Oceanus launcher stopped."
            console.warn(message)
            Quickshell.execDetached(["notify-send", "--", "Oceanus", message])
        }
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

    LayoutMenu {
        id: layoutMenu
        open: root.layoutMenuOpen
        targetY: root.layoutMenuTargetY
        current: root.currentLayout
        onCloseRequested: root.layoutMenuOpen = false
    }

    HostMenu {
        open: root.hostMenuOpen
        targetY: root.hostMenuTargetY
        onCloseRequested: root.hostMenuOpen = false
    }

    UpdateMenu {
        service: updateService
        open: root.updatesMenuOpen
        targetY: root.updatesMenuTargetY
        onCloseRequested: root.updatesMenuOpen = false
    }
    ClipboardMenu { id: clipboardMenu }

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
    Bar {
        pickedColor: colorPicker.lastColor
        currentLayout: root.currentLayout
        updates: updateService
        onClipboardRequested: y => root.showClipboard(y)
        onColorRequested: reuse => {
            if (reuse && colorPicker.lastColor) colorPicker.copyColor(colorPicker.lastColor)
            else colorPicker.pick()
        }
        onTrayMenuRequested: (itemId, y) => trayMenuIpc.open(itemId, String(y))
        onLayoutMenuRequested: y => layoutMenuIpc.toggle(String(y))
        onCalendarMenuRequested: y => calendarMenuIpc.toggle(String(y))
        onUpdatesMenuRequested: y => updatesMenuIpc.toggle(String(y))
        onBluetoothMenuRequested: y => bluetoothMenuIpc.toggle(String(y))
        onNetworkMenuRequested: y => networkMenuIpc.toggle(String(y))
        onHostMenuRequested: y => hostMenuIpc.toggle(String(y))
        onPowerMenuRequested: powerMenuIpc.toggle()
    }
}
