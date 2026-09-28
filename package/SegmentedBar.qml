// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 2.15

/**
 * A proportional bar: one track carrying the segments, each sized by its share
 * of the total, so a full bar always means everything is accounted for.
 *
 * Deliberately free of dde-shell imports so it can be rendered standalone.
 */
Item {
    id: root

    /// [{ value, color }], drawn from the left in order. Values are reals >= 0;
    /// anything else counts as zero. A zero total leaves just the track.
    property var segments: []
    /// The panel's colour roles; one the palette does not carry falls back to
    /// a literal, so the bar draws something either way.
    property var theme: null
    property real barHeight: 10
    property real radius: 5

    implicitHeight: barHeight

    function role(name, fallback) {
        const palette = root.theme || {}
        const value = palette[name]
        return value === undefined || value === null ? fallback : value
    }

    readonly property bool dark: role("dark", false) === true
    readonly property color trackColor: role("track", dark ? "#1AFFFFFF" : "#12000000")

    /// Canvas is handed colour strings, so a role that carries an alpha keeps
    /// it instead of being read as opaque.
    function rgba(color, alpha) {
        return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255)
                + "," + Math.round(color.b * 255) + "," + alpha + ")"
    }

    function roundedPath(ctx, x, y, w, h, radius) {
        const r = Math.max(0, Math.min(radius, w / 2, h / 2))
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.quadraticCurveTo(x + w, y, x + w, y + r)
        ctx.lineTo(x + w, y + h - r)
        ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h)
        ctx.lineTo(x + r, y + h)
        ctx.quadraticCurveTo(x, y + h, x, y + h - r)
        ctx.lineTo(x, y + r)
        ctx.quadraticCurveTo(x, y, x + r, y)
        ctx.closePath()
    }

    /// A value is a real >= 0; anything else counts as zero.
    function valueAt(index) {
        const segment = root.segments ? root.segments[index] : null
        const value = segment ? Number(segment.value) : 0
        return isFinite(value) && value > 0 ? value : 0
    }

    readonly property int segmentCount: root.segments ? root.segments.length : 0

    readonly property real total: {
        let total = 0
        for (let i = 0; i < root.segmentCount; ++i)
            total += valueAt(i)
        return total
    }

    /// Where segment `index` starts, in whole pixels. The boundaries are
    /// snapped so two neighbouring segments share one edge instead of leaving a
    /// hairline of track between them, and the last one sits on the width
    /// itself, so rounding can never overshoot it.
    function edgeAt(index) {
        const total = root.total
        if (total <= 0 || index <= 0)
            return 0
        const width = Math.floor(root.width)
        if (index >= root.segmentCount)
            return width
        let covered = 0
        for (let i = 0; i < index; ++i)
            covered += valueAt(i)
        return covered >= total ? width : Math.round(width * covered / total)
    }

    /// Canvas does not track what onPaint reads, so the inputs are listed here
    /// and any change to one of them repaints the bar.
    readonly property var paintInputs: [segments, radius, trackColor, width, height]

    onPaintInputsChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            const w = canvas.width
            const h = canvas.height
            ctx.clearRect(0, 0, w, h)
            if (w < 1 || h < 1)
                return

            root.roundedPath(ctx, 0, 0, w, h, root.radius)
            ctx.fillStyle = root.rgba(root.trackColor, root.trackColor.a)
            ctx.fill()

            // Nothing but the track until something has a value.
            if (root.total <= 0)
                return

            // Clipped to the track, so the segments keep its rounded ends and a
            // boundary can never overshoot the width.
            ctx.save()
            root.roundedPath(ctx, 0, 0, w, h, root.radius)
            ctx.clip()

            for (let i = 0; i < root.segmentCount; ++i) {
                const left = root.edgeAt(i)
                const right = root.edgeAt(i + 1)
                const segment = root.segments[i]
                if (right > left && segment && segment.color) {
                    ctx.fillStyle = segment.color
                    ctx.fillRect(left, 0, right - left, h)
                }
            }
            ctx.restore()
        }
    }
}
