import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: picker
    property string lastColor: ""
    property bool busy: false

    function pick() {
        if (busy) return
        busy = true
        sample.hex = ""
        sample.running = true
    }

    function copyColor(value) {
        if (busy || !/^#[0-9a-f]{6}$/i.test(value)) return
        busy = true
        copy.value = value.toUpperCase()
        copy.running = true
    }

    function notify(message, hex = "") {
        const command = ["notify-send", "-a", "Color picker"]
        if (hex) {
            // A single RGBA pixel scales to the notification's image slot
            const bytes = hex.slice(1).match(/../g).map(pair => "0x" + pair)
            command.push("--hint", "variant:image-data:(1, 1, 4, true, 8, 4, [byte "
                + bytes.join(", ") + ", 0xff])")
        }
        Quickshell.execDetached(command.concat(["--", "Color picker", message]))
    }

    Process {
        id: sample
        property string hex: ""
        command: ["env", "hyprpicker", "--no-fancy", "--format=hex"]
        stdout: SplitParser { onRead: data => sample.hex = data.trim() }
        onExited: (code) => {
            picker.busy = false
            if (code === 127) picker.notify("Install hyprpicker to pick a screen color.")
            else if (code === 0) picker.copyColor(hex)
        }
    }
    Process {
        id: copy
        property string value: ""
        command: ["env", "wl-copy", "--type", "text/plain;charset=utf-8", "--", value]
        onExited: (code) => {
            picker.busy = false
            if (code === 0) {
                picker.lastColor = value
                picker.notify("Copied " + value, value)
            } else {
                picker.notify("Could not copy the color.")
            }
        }
    }
}
