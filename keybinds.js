// Description format supplied by bindInfo() in hyprland.lua:
// qsbind|category|main modifier, or empty for literal modifiers|action

// Hyprland exposes modifiers as a bitmask. Keep their display order explicit so
// combinations read consistently, regardless of their order in the Lua config
const modifierNames = [
    [64, "SUPER", "Super"], [8, "ALT", "Alt"], [4, "CTRL", "Ctrl"],
    [1, "SHIFT", "Shift"], [2, "CAPS", "Caps"], [16, "MOD2", "Mod2"],
    [32, "MOD3", "Mod3"], [128, "MOD5", "Mod5"]
]
// Known groups come first; user-defined groups remain visible after these
const categoryOrder = ["Apps and shell", "Windows", "Layouts", "Gaps", "Workspaces",
    "Screenshots and tools", "Dictation", "Media and brightness", "Other"]
// Replace hardware key names with labels someone can recognize on a keyboard
const keyNames = {
    return: "Enter", space: "Space", mouse_down: "Scroll down", mouse_up: "Scroll up",
    "mouse:272": "Left mouse drag", "mouse:273": "Right mouse drag",
    XF86AudioRaiseVolume: "Volume up", XF86AudioLowerVolume: "Volume down",
    XF86AudioMute: "Mute", XF86AudioMicMute: "Mic mute",
    XF86MonBrightnessUp: "Brightness up", XF86MonBrightnessDown: "Brightness down",
    XF86AudioNext: "Media next", XF86AudioPrev: "Media previous",
    XF86AudioPlay: "Media play", XF86AudioPause: "Media pause"
}

// Also handles a main modifier made of several keys, such as CTRL + ALT
function modifierMask(mod) {
    return mod.toUpperCase().split(/[ +]+/).reduce((mask, name) => {
        const entry = modifierNames.find(m => m[1] === (name === "CONTROL" ? "CTRL" : name))
        return mask | (entry ? entry[0] : 0)
    }, 0)
}

// Only descriptions explicitly marked with a main modifier get the Mod alias.
// Literal Super shortcuts must stay literal even when mainMod is also Super.
function formatModifiers(mask, mod) {
    const primary = modifierMask(mod)
    const parts = []
    if (primary && (mask & primary) === primary) {
        parts.push("Mod")
        mask &= ~primary
    }
    for (const m of modifierNames) if (mask & m[0]) parts.push(m[2])
    return parts
}

// Ignore the cosmetic + separators when searching a shortcut. Every search
// word must match, but words may occur in different fields and in any order.
function searchWords(text) {
    return text.toLowerCase().replace(/\+/g, " ").trim().split(/\s+/).filter(Boolean)
}

// Return display rows plus a header based on the full, unfiltered config.
// Filtering individual bindings before range merging keeps searches such as
// "workspace 4" accurate even when the full list shows a single 1–8 row.
function buildModel(bindings, filter) {
    if (!Array.isArray(bindings)) throw new Error("Expected a list of bindings")
    const mods = []
    const allRows = bindings.map((bind, order) => {
        const description = bind.description || ""
        const fields = description.split("|")
        const annotated = fields.length >= 4 && fields[0] === "qsbind"
        const mod = annotated ? fields[2] : ""
        if (mod && !mods.includes(mod)) mods.push(mod)
        // Unknown descriptions still appear under Other. Callback IDs cannot
        // explain a Lua action, so show an honest fallback instead of the ID.
        const action = annotated ? fields.slice(3).join("|") : description ||
            (bind.dispatcher === "__lua" ? "Unlabelled Lua action" :
                [bind.dispatcher, bind.arg].filter(Boolean).join(" ")) || "Unlabelled action"
        const notes = []
        if (bind.release) notes.push("On release")
        if (bind.repeat) notes.push("Hold to repeat")
        if (bind.longPress) notes.push("Long press")
        if (bind.locked) notes.push("Works while locked")
        if (bind.submap) notes.push("Submap: " + bind.submap)
        const key = bind.key || (bind.keycode ? "Code " + bind.keycode : "Any key")
        const modifiers = formatModifiers(bind.modmask || 0, mod).join(" + ")
        const category = annotated ? fields[1] : "Other"
        const shortcut = (modifiers ? modifiers + " + " : "") +
            (keyNames[key] || (key.length === 1 ? key.toUpperCase() : key))
        return {
            category, action, order,
            modifiers, key, note: notes.join(" · "),
            shortcut,
            // Search both Mod and its physical keys, plus raw hardware names.
            searchText: searchWords([category, action, shortcut, key,
                formatModifiers(bind.modmask || 0, "").join(" "), notes.join(" ")].join(" ")).join(" ")
        }
    })
    const words = searchWords(filter || "")
    const rows = allRows.filter(row => words.every(word => row.searchText.includes(word)))

    // Only merge consecutive numeric workspace bindings whose action and key
    // agree. Missing or rebound workspace keys must remain visible as gaps
    const compact = []
    const consumed = new Set()
    for (let i = 0; i < rows.length; i++) {
        if (consumed.has(i)) continue
        const row = rows[i]
        const match = row.action.match(/^(Switch to workspace |Move window to workspace )(\d+)$/)
        if (row.category !== "Workspaces" || !match || row.key !== match[2]) {
            compact.push(row)
            continue
        }
        let last = Number(row.key)
        while (true) {
            const next = rows.findIndex((candidate, index) => index > i && !consumed.has(index) &&
                candidate.category === row.category && candidate.modifiers === row.modifiers &&
                candidate.note === row.note && candidate.key === String(last + 1) &&
                candidate.action === match[1] + (last + 1))
            if (next < 0) break
            consumed.add(next)
            last++
        }
        if (last > Number(row.key)) {
            const range = row.key + "–" + last
            compact.push(Object.assign({}, row, {
                shortcut: (row.modifiers ? row.modifiers + " + " : "") + range,
                action: match[1] + range
            }))
        } else compact.push(row)
    }
    const categories = categoryOrder.concat(compact.map(r => r.category).filter(c => !categoryOrder.includes(c)))
    // Qt's sort can reorder equal entries. The original position keeps related
    // shortcuts together, including press/release pairs in the same category.
    compact.sort((a, b) => categories.indexOf(a.category) - categories.indexOf(b.category) || a.order - b.order)
    return {
        rows: compact,
        modLabel: mods.length ? "Mod = " + mods.map(m => formatModifiers(modifierMask(m), "").join(" + ")).join(" / ") : "Mod not specified",
        bindingCount: bindings.length
    }
}
