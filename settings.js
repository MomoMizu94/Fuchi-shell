// Validation shared by the QML settings store and the Node tests.
const rules = {
    fontFamily: { type: "string", maxLength: 200 },
    profilePic: { type: "string", maxLength: 4096, allowEmpty: true },
    wallpaperFolder: { type: "string", maxLength: 4096 },
    animationSlide: { type: "number", min: 0, max: 2000 },
    animationPopup: { type: "number", min: 0, max: 2000 },
    animationTabSlide: { type: "number", min: 0, max: 2000 },
    notificationTimeout: { type: "number", min: 1000, max: 60000 },
    historyLimit: { type: "number", min: 0, max: 2000 },
    launcherRows: { type: "number", min: 1, max: 20 },
    volumeLimit: { type: "number", min: 100, max: 200 },
    layoutIcons: { type: "boolean" }
}

function validate(key, value) {
    if (!Object.prototype.hasOwnProperty.call(rules, key))
        throw new Error("Unknown preference: " + key)
    const rule = rules[key]
    if (typeof value !== rule.type)
        throw new Error("Invalid value for " + key)
    if (rule.type === "number" && (!Number.isInteger(value) || value < rule.min || value > rule.max))
        throw new Error(key + " must be between " + rule.min + " and " + rule.max)
    if (rule.type === "string" && (value !== value.trim() || /[\x00-\x1f]/.test(value)
            || value.length > rule.maxLength || (!rule.allowEmpty && value.length === 0)))
        throw new Error("Invalid text for " + key)
    return value
}

function decode(text) {
    const document = JSON.parse(text)
    if (!document || document.version !== 1 || !document.overrides
            || typeof document.overrides !== "object" || Array.isArray(document.overrides))
        throw new Error("Expected a version 1 settings file with an overrides object")
    const overrides = {}
    for (const key of Object.keys(document.overrides))
        overrides[key] = validate(key, document.overrides[key])
    return overrides
}

function encode(overrides) {
    return JSON.stringify({ version: 1, overrides: overrides }, null, 2) + "\n"
}

function updated(overrides, defaults, key, value) {
    validate(key, value)
    const next = Object.assign({}, overrides)
    if (value === defaults[key])
        delete next[key]
    else
        next[key] = value
    return next
}

function absolutePath(path, home) {
    if (path === "") return ""
    if (path === "~") return home
    if (path.startsWith("~/")) return home + path.slice(1)
    return path.startsWith("/") ? path : home + "/" + path
}

function storedPath(input, home) {
    let path = input.toString()
    if (path.startsWith("file://")) {
        if (path.startsWith("file://localhost/")) path = path.slice(16)
        else path = path.slice(7)
        if (!path.startsWith("/")) throw new Error("Choose a local file or folder")
        path = decodeURIComponent(path)
    } else if (/^[a-z][a-z0-9+.-]*:/i.test(path)) {
        throw new Error("Choose a local file or folder")
    }
    path = absolutePath(path, home)
    return path.startsWith(home + "/") ? path.slice(home.length + 1) : path
}

function fileUrl(path, home) {
    const absolute = absolutePath(path, home)
    if (!absolute) return ""
    return "file://" + absolute.split("/").map(encodeURIComponent).join("/")
}
