pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "config.js" as Config
import "settings.js" as Logic

Singleton {
    id: settings

    // config.js remains the source of defaults. Only user overrides go to disk.
    readonly property var defaults: ({
        fontFamily: Config.bar.fontFamily,
        profilePic: Config.systemInfo.profilePic,
        wallpaperFolder: Config.launcher.wallpaperFolder,
        animationSlide: Config.anim.slide,
        animationPopup: Config.anim.popup,
        animationTabSlide: Config.anim.tabSlide,
        notificationTimeout: Config.notifications.timeout,
        historyLimit: Config.notifications.historyLimit,
        launcherRows: Config.launcher.maxVisibleRows,
        volumeLimit: Math.round(Config.volumeMenu.maxVolume * 100),
        layoutIcons: Config.sidebar.useNerdLayoutGlyphs
    })
    property var overrides: ({})
    readonly property var fontFamilies: Qt.fontFamilies().sort()
    readonly property string fontFamily: fontFamilies.includes(value("fontFamily"))
        ? value("fontFamily") : Config.bar.fontFamily
    readonly property string profilePic: value("profilePic")
    readonly property string wallpaperFolder: value("wallpaperFolder")
    readonly property int animationSlide: value("animationSlide")
    readonly property int animationPopup: value("animationPopup")
    readonly property int animationTabSlide: value("animationTabSlide")
    readonly property int notificationTimeout: value("notificationTimeout")
    readonly property int historyLimit: value("historyLimit")
    readonly property int launcherRows: value("launcherRows")
    readonly property real maxVolume: value("volumeLimit") / 100
    readonly property bool layoutIcons: value("layoutIcons")
    readonly property string path: settingsFile.path
    property bool ready: false
    property bool dirty: false
    property bool saving: false
    property bool reloadPending: false
    property string errorText: ""

    function value(key) {
        return Object.prototype.hasOwnProperty.call(overrides, key) ? overrides[key] : defaults[key]
    }

    function isOverridden(key) {
        return Object.prototype.hasOwnProperty.call(overrides, key)
    }

    function setValue(key, newValue) {
        if (!ready) return false
        try {
            if (key === "fontFamily" && !fontFamilies.includes(newValue))
                throw new Error("Choose an installed font")
            const next = Logic.updated(overrides, defaults, key, newValue)
            if (JSON.stringify(next) === JSON.stringify(overrides)) {
                if (!dirty && !saving) errorText = ""
                return true
            }
            // Replacing the object emits a change signal. Mutating a JS field does not.
            overrides = next
            dirty = true
            saveDelay.restart()
            return true
        } catch (error) {
            errorText = error.message
            return false
        }
    }

    function reset(key) {
        if (!ready || !isOverridden(key)) return
        const next = Object.assign({}, overrides)
        delete next[key]
        overrides = next
        dirty = true
        saveDelay.restart()
    }

    function setPath(key, input) {
        try {
            return setValue(key, Logic.storedPath(input, Quickshell.env("HOME")))
        } catch (error) {
            errorText = error.message
            return false
        }
    }

    function fileUrl(path) {
        return Logic.fileUrl(path, Quickshell.env("HOME"))
    }

    function save() {
        saveDelay.stop()
        if (!ready || saving || !dirty) return
        dirty = false
        saving = true
        settingsFile.setText(Logic.encode(overrides))
    }

    function requestReload() {
        if (reloadPending) return
        reloadPending = true
        if (dirty) save()
        else if (!saving) Quickshell.reload(false)
    }

    Timer {
        id: saveDelay
        interval: 150
        onTriggered: settings.save()
    }

    FileView {
        id: settingsFile
        path: Quickshell.statePath("settings.json")
        atomicWrites: true
        // Load before the first frame so saved fonts and dimensions do not flash.
        blockLoading: true
        onLoaded: {
            try {
                settings.overrides = Logic.decode(text())
                settings.ready = true
            } catch (error) {
                settings.errorText = "Could not read saved settings: " + error.message
            }
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) settings.ready = true
            else settings.errorText = "Could not read saved settings. Check " + path
        }
        // Let FileView finish its completion handler before starting another job.
        onSaved: Qt.callLater(function() {
            settings.saving = false
            settings.errorText = ""
            // A change during an in-flight write needs its own write afterwards.
            if (settings.dirty) settings.save()
            else if (settings.reloadPending) Quickshell.reload(false)
        })
        onSaveFailed: error => {
            settings.saving = false
            settings.dirty = true
            settings.reloadPending = false
            settings.errorText = "Could not save settings. Check permissions for " + path + ", then retry."
        }
    }

    Connections {
        target: Quickshell
        function onReloadFailed(errorString) {
            settings.reloadPending = false
            settings.errorText = "Could not reload the shell: " + errorString
        }
    }

    Component.onCompleted: settingsFile.text()
}
