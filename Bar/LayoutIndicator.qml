import QtQuick
import "../"
import "../config.js" as Config

SidebarButton {
    id: root
    property string layout: ""
    Accessible.name: "Tiling layout " + layout
    glyphSize: Settings.layoutIcons ? Config.sidebar.iconSize : Config.sidebar.layoutGlyphSize
    glyph: {
        for (const layout of Config.layouts)
            if (layout.label === root.layout)
                return Settings.layoutIcons ? layout.nerd : layout.ascii
        return ""
    }
}
