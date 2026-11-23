"""Exercise the sidebar hover interactions in isolated Quickshell windows."""
import shutil
import unittest

import settings_runtime_test as settings_tests


@unittest.skipUnless(shutil.which("qs"), "Quickshell is required")
class SidebarHoverTest(unittest.TestCase):
    setUp = settings_tests.SettingsRuntimeTest.setUp
    tearDown = settings_tests.SettingsRuntimeTest.tearDown
    run_qml = settings_tests.SettingsRuntimeTest.run_qml

    def bar_source(self, name):
        source = (settings_tests.REPO / "Bar" / (name + ".qml")).read_text()
        return source.replace('"../', '"source/')

    def floating_menu(self, name):
        source = self.bar_source(name).replace("PanelWindow {", "FloatingWindow {", 1)
        return "\n".join(line for line in source.splitlines() if not line.startswith(
            ("    anchors {", "    exclusionMode:", "    WlrLayershell.keyboardFocus:")))

    def test_adapter_selection_and_scrollable_device_menu(self):
        source = self.floating_menu("BluetoothMenu")
        source = source.replace("Bluetooth.defaultAdapter", "harness.adapter")
        source = source.replace("Bluetooth.devices", "harness.devices")
        (self.directory / "BluetoothPreview.qml").write_text(source)
        self.run_qml('''
    property var adapter: null
    property var devices: Array.from({length: 24}, (_, i) => ({
        name: "Device " + i, deviceName: "Device " + i, paired: true, connected: false,
        batteryAvailable: false, pairing: false, state: 0
    }))
    property bool bluetoothOpen: false
    BluetoothPreview {
        id: menu
        implicitWidth: 640; implicitHeight: 360
        open: harness.bluetoothOpen
        onCloseRequested: harness.bluetoothOpen = false
    }
    TestCase { id: input; when: false }
    function viewport(item) {
        if (item.reveal && item.contentItem) return item
        for (const child of item.children) {
            const found = viewport(child)
            if (found) return found
        }
        return null
    }
    Timer { interval: 100; running: true; onTriggered: {
        const first = {type: 1, connected: false}
        const second = {type: 1, connected: true}
        const other = {type: 2, connected: true}
        check(Network.preferredDevice([first, other, second], 1) === second, "prefer connected device")
        second.connected = false
        check(Network.preferredDevice([first, other, second], 1) === first, "use first disconnected device")
        check(Network.preferredDevice([], 1) === null, "no device of requested type")
        bluetoothOpen = true
        input.wait(20)
        check(!menu.open && !menu.visible, "opening without an adapter releases the overlay")
        adapter = {enabled: true, discovering: false}
        bluetoothOpen = true
        input.wait(350)
        const view = viewport(menu.contentItem)
        check(menu.visible && view.height < menu.height && view.contentHeight > view.height,
              "long device list fits the screen and can scroll")
        view.contentY = view.contentHeight - view.height
        check(view.atYEnd && view.contentY > 0, "the end of the list is reachable")
        adapter = null
        input.wait(20)
        check(!menu.open && !menu.visible, "losing the adapter unmaps the overlay")
        console.log("TEST_PASSED"); Qt.quit()
    } }
''', 'import QtTest\nimport "source/Bar/network.js" as Network')

    def test_switching_interface_and_scrolling_to_wifi_password(self):
        source = self.floating_menu("NetworkMenu").replace('"network.js"', '"source/Bar/network.js"')
        source = source.replace("Networking.devices.values", "harness.adapters")
        source = source.replace("Networking.wifiEnabled", "harness.wifiOn")
        source = source.replace("Networking.connectivity", "NetworkConnectivity.None")
        (self.directory / "NetworkPreview.qml").write_text(source)
        commands = self.directory / "bin"
        commands.mkdir()
        (commands / "qs").symlink_to(shutil.which("qs"))
        bash = commands / "bash"
        bash.write_text('#!/bin/sh\ncase "$1" in *network-details.sh) /usr/bin/sleep 0.2; echo "$2-address";; esac\n')
        bash.chmod(0o755)
        self.environment["PATH"] = str(commands)
        self.run_qml('''
    property bool wifiOn: true
    QtObject {
        id: network
        property string name: "Example"
        property bool connected: false
        property bool known: false
        property bool stateChanging: false
        property int security: WifiSecurityType.WpaPsk
        property real signalStrength: 1
        signal connectionFailed(string reason)
    }
    QtObject {
        id: wifi
        property int type: DeviceType.Wifi
        property bool connected: true
        property string name: "wlan0"
        property bool scannerEnabled: false
        property var networks: ({values: Array(20).fill(network)})
    }
    QtObject {
        id: wired
        property int type: DeviceType.Wired
        property bool connected: false
        property string name: "eth1"
        property var network: null
        property int linkSpeed: 1000
        property bool hasLink: true
    }
    property var adapters: [wifi, wired]
    NetworkPreview { id: menu; implicitWidth: 640; implicitHeight: 400; targetY: 200 }
    TestCase { id: input; when: false }
    function find(item, predicate) {
        if (predicate(item)) return item
        for (const child of item.children) {
            const found = find(child, predicate)
            if (found) return found
        }
        return null
    }
    Timer { interval: 100; running: true; onTriggered: {
        menu.open = true
        input.wait(50)
        wired.connected = true
        input.wait(650)
        check(menu.ipAddr === "eth1-address", "an in-flight Wi-Fi probe yields to the wired interface")
        const view = find(menu.contentItem, item => item.reveal !== undefined)
        const label = find(view.contentItem, item => item.text === network.name)
        view.reveal(label)
        input.mouseClick(label)
        input.wait(100)
        const password = find(view.contentItem, item => item.echoMode === TextInput.Password)
        const bottom = password.mapToItem(view, 0, password.height).y
        check(menu.pskTarget === network && password.visible && bottom <= view.height + 1,
              "choosing a secured network reveals the password field below the list")
        console.log("TEST_PASSED"); Qt.quit()
    } }
''', 'import Quickshell.Networking\nimport QtTest')

    def test_nested_tray_mouse_navigation(self):
        source = self.bar_source("TrayMenu").replace("PanelWindow {", "FloatingWindow {", 1)
        start = source.index("    anchors {")
        end = source.index("    MouseArea {", start)
        source = source[:start] + "    property var activeItem\n" + source[end:]
        source = source.replace("QsMenuOpener {", "QtObject {").replace(
            "menu: panel.parent.menuHandle", "property var menu: panel.parent.menuHandle"
        ).replace("model: opener.children", "model: opener.menu ? opener.menu.entries : null")
        (self.directory / "TestTray.qml").write_text(source)
        self.run_qml('''
    property int calls: 0
    function entry(text, children = [], enabled = true) {
        return {text, entries: children, enabled, hasChildren: children.length > 0,
                isSeparator: false, icon: "", buttonType: 0, checkState: Qt.Unchecked,
                triggered: () => { harness.calls++ }}
    }
    TestTray {
        id: menu
        implicitWidth: 800; implicitHeight: 360
        open: true
        targetY: 338
        activeItem: ({menu: {entries: [
            entry("Profiles", [entry("Saved", [entry("Evening")])]),
            entry("Quick Colors", [entry("Red"), entry("Green"), entry("Blue"), entry("Orange")]),
            entry("Unavailable", [], false), entry("Exit")
        ]}})
        onCloseRequested: open = false
    }
    TestCase { id: input; when: false; parent: menu.contentItem }
    function label(item, text) {
        if (!item.visible) return null
        if (item.text === text) return item
        for (const child of item.children) {
            const found = label(child, text)
            if (found) return found
        }
        return null
    }
    function row(text) {
        const item = label(menu.contentItem, text)
        check(!!item, text + " is visible")
        return item
    }
    function hover(text) {
        input.mouseMove(row(text))
        input.wait(30)
    }
    Timer { interval: 800; running: true; onTriggered: {
        hover("Profiles")
        hover("Saved")
        hover("Evening")
        check(menu.open && calls === 0, "crossing both branches keeps the menu open")
        hover("Quick Colors")
        check(!label(menu.contentItem, "Evening"), "changing branch closes old descendants")
        input.mouseClick(row("Quick Colors"))
        check(menu.open && calls === 0, "clicking a parent opens its branch")
        hover("Unavailable")
        check(!label(menu.contentItem, "Green"), "disabled sibling clears the open branch")
        input.mouseClick(row("Unavailable"))
        check(menu.open && calls === 0, "disabled row ignores clicks")
        hover("Quick Colors")
        const bottom = row("Orange").mapToItem(menu.contentItem, 0, row("Orange").height)
        check(bottom.y <= menu.height, "submenu near the bottom stays on screen")
        input.mouseClick(row("Green"))
        check(!menu.open && calls === 1, "clicking a leaf runs one action and dismisses")
        menu.open = true
        input.wait(700)
        check(!label(menu.contentItem, "Green"), "reopening starts with the root menu")
        input.mouseClick(menu.contentItem, 760, 12)
        check(!menu.open && calls === 1, "clicking outside dismisses without running an action")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', 'import QtTest')

    def test_workspace_hover_and_dismissal(self):
        source = self.bar_source("Workspaces").replace("model: Hyprland.workspaces",
                                                       "model: harness.workspaces")
        (self.directory / "TestWorkspaces.qml").write_text(source)
        scripts = self.directory / "scripts"
        scripts.mkdir()
        (scripts / "workspace-preview.py").write_text('''
import base64
svg = b'<svg xmlns="http://www.w3.org/2000/svg" width="80" height="45"/>'
print("data:image/svg+xml;base64," + base64.b64encode(svg).decode())
''')
        self.run_qml('''
    QtObject {
        id: visited
        property int id: 2
        property string name: "2"
        property bool active: true
        property bool urgent: false
        property var monitor: ({name: "test-output"})
    }
    property var workspaces: [{name: "1", id: 1, active: false}, visited, {name: "3", id: 3, active: false}]
    FloatingWindow {
        id: bar
        visible: true; implicitWidth: 300; implicitHeight: 300
        TestWorkspaces { id: rail; y: 8 }
    }
    TestCase { id: input; when: false; parent: bar.contentItem }
    function chip(id) { return rail.children.find(c => c.modelData?.id === id) }
    function preview() { return rail.data.find(c => c.grabFocus !== undefined) }
    function hasText(item, text) {
        if (!item.visible) return false
        if (item.text === text) return true
        return item.children.some(c => hasText(c, text))
    }
    Timer { interval: 60; running: true; onTriggered: input.mouseMove(bar.contentItem, 230, 230) }
    Timer { interval: 1100; running: true; onTriggered: {
        const popup = preview()
        check(chip(2).snapshot.startsWith("data:image/"), "visible workspace captured")
        const dot = findItem(chip(2), "workspaceUrgencyDot")
        check(dot && !dot.visible, "workspace starts without an urgency dot")
        visited.urgent = true
        check(!dot.visible, "active workspace suppresses urgency")
        visited.active = false
        check(dot.visible, "inactive urgent workspace shows the dot")
        visited.urgent = false
        check(!dot.visible, "clearing urgency removes the dot")
        input.mouseMove(chip(1))
        input.wait(70)
        input.mouseMove(chip(2))
        input.wait(100)
        check(!popup.visible, "passing over an icon skips its preview")
        input.wait(450)
        check(popup.visible && popup.chip === chip(2) && !popup.grabFocus, "hover previews the inactive workspace")
        const iconRight = chip(2).mapToGlobal(chip(2).width, 0).x
        const previewLeft = popup.contentItem.mapToGlobal(0, 0).x
        check(previewLeft > iconRight, "preview clears the workspace icon's hover area")
        const barTop = bar.contentItem.mapToGlobal(0, 0).y
        check(popup.contentItem.mapToGlobal(0, 0).y - barTop === 16, "upper preview clears the top of the bar")
        function hasSnapshot(item) {
            if (item.source?.toString() === chip(2).snapshot && item.status === Image.Ready) return true
            return item.children.some(child => hasSnapshot(child))
        }
        check(hasSnapshot(popup.contentItem), "hover shows the desktop image retained after leaving")
        check(popup.height === 188, "16:9 thumbnail preserves the captured desktop proportions")
        input.mouseMove(chip(3))
        input.wait(500)
        check(hasText(popup.contentItem, "Visit this workspace to preview it"), "unvisited workspace has no other desktop image")
        const previewCenterY = popup.contentItem.mapToGlobal(0, popup.height / 2).y
        const iconCenterY = chip(3).mapToGlobal(0, chip(3).height / 2).y
        check(Math.abs(previewCenterY - iconCenterY) <= 1, "lower preview stays centered on its icon")
        input.mouseMove(bar.contentItem, 240, 240)
        input.wait(260)
        check(!popup.visible, "leaving dismisses preview")
        console.log("TEST_PASSED")
        Qt.quit()
    } }
''', 'import QtTest')
