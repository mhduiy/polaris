// SPDX-License-Identifier: GPL-3.0-or-later

// The one place that decides how a number is spelled on screen, shared by the
// dock line and the detail panel so the two can never drift apart.
.pragma library

/// Transfer rate as the dock line shows it: "0B/s", "340K/s", "12.4M/s".
function rateText(bytesPerSecond) {
    if (bytesPerSecond < 1000)
        return Math.round(bytesPerSecond) + "B/s"
    if (bytesPerSecond < 1000 * 1000)
        return Math.round(bytesPerSecond / 1000) + "K/s"
    if (bytesPerSecond < 1000 * 1000 * 1000)
        return (bytesPerSecond / (1000 * 1000)).toFixed(1) + "M/s"
    return (bytesPerSecond / (1000 * 1000 * 1000)).toFixed(1) + "G/s"
}

/// The same rate spelled out for the tooltip, where there is room for it.
function rateDetail(bytesPerSecond) {
    if (bytesPerSecond < 1000)
        return Math.round(bytesPerSecond) + " B/s"
    if (bytesPerSecond < 1000 * 1000)
        return (bytesPerSecond / 1000).toFixed(1) + " KB/s"
    if (bytesPerSecond < 1000 * 1000 * 1000)
        return (bytesPerSecond / (1000 * 1000)).toFixed(1) + " MB/s"
    return (bytesPerSecond / (1000 * 1000 * 1000)).toFixed(1) + " GB/s"
}

/// A vertical dock is only dockSize wide, which "12.4M/s" does not fit in: there
/// the unit is dropped and the rate rounded to whole units.
function rateCompact(bytesPerSecond) {
    if (bytesPerSecond < 1000)
        return Math.round(bytesPerSecond) + "B"
    if (bytesPerSecond < 1000 * 1000)
        return Math.round(bytesPerSecond / 1000) + "K"
    if (bytesPerSecond < 1000 * 1000 * 1000)
        return Math.round(bytesPerSecond / (1000 * 1000)) + "M"
    return Math.round(bytesPerSecond / (1000 * 1000 * 1000)) + "G"
}

/// A byte count: "512B", "340K", "1.2G".
function bytes(count) {
    if (count < 1000)
        return Math.round(count) + "B"
    if (count < 1000 * 1000)
        return Math.round(count / 1000) + "K"
    if (count < 1000 * 1000 * 1000)
        return (count / (1000 * 1000)).toFixed(1) + "M"
    return (count / (1000 * 1000 * 1000)).toFixed(1) + "G"
}

/// KiB as the kernel reports memory, in GiB with one decimal.
function kibToGiB(kib) {
    return (kib / (1024 * 1024)).toFixed(1)
}
