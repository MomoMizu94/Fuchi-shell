function preferredDevice(devices, type) {
    let fallback = null
    for (const device of devices) {
        if (device.type !== type) continue
        if (device.connected) return device
        if (!fallback) fallback = device
    }
    return fallback
}
