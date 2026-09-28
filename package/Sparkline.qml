// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 2.15

/**
 * The history of one metric: the last samples drawn as a line with the area
 * under it filled, the newest sample always at the right edge.
 *
 * Deliberately free of dde-shell imports so it can be rendered standalone.
 */
Item {
    id: root

    /// Oldest first. Empty, all-zero and single-sample lists are all valid.
    property var values: []
    /// The panel's colour roles; one the palette does not carry falls back to
    /// a literal, so the chart draws something either way.
    property var theme: null
    property color lineColor: role("cpu", "#4A90D9")
    property real lineWidth: 2
    /// How many samples the chart keeps; older ones fall off the left edge.
    property int capacity: 60
    /// The top of the scale never drops below this, or an idle machine would
    /// have its noise stretched over the whole height.
    property real scaleFloor: 1
    /// The top of the scale, for a reading that has a ceiling of its own — a
    /// usage chart is 0..100%, a fan chart is 0..its chip's ceiling. 0 fits the
    /// scale to whatever the window holds, which is what a transfer rate needs,
    /// having no ceiling at all.
    property real scaleMax: 0

    implicitWidth: 200
    implicitHeight: 40

    /// Bigger than this and a chart only 12px tall reads as a lozenge.
    property int plateRadius: 4

    function role(name, fallback) {
        const palette = root.theme || {}
        const value = palette[name]
        return value === undefined || value === null ? fallback : value
    }

    readonly property bool dark: role("dark", false) === true
    readonly property color plateColor: role("track", dark ? "#1AFFFFFF" : "#12000000")

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

    /// A sample is a real; a gap in the list, a NaN or a negative reading
    /// counts as zero rather than taking the chart down.
    function sample(samples, index) {
        const value = Number(samples[index])
        return isFinite(value) && value > 0 ? value : 0
    }

    function busiest(samples, from) {
        let busiest = 0
        for (let i = from; i < samples.length; ++i)
            busiest = Math.max(busiest, sample(samples, i))
        return busiest
    }

    /// The x and y of every sample that fits in capacity, the newest at the
    /// right edge. A single sample has no history to draw a line from, so it is
    /// drawn flat across the width instead of as one dot in the corner.
    function plotPoints(w, h) {
        const samples = root.values || []
        const count = Math.min(samples.length, root.capacity)
        if (count < 1)
            return { xs: [], ys: [] }

        const first = samples.length - count
        const top = root.scaleMax > 0 ? root.scaleMax
                                      : Math.max(root.scaleFloor, busiest(samples, first), 1e-9)
        const bottom = h - root.lineWidth / 2
        const span = Math.max(1, h - root.lineWidth)
        // Spread what there is over the whole width: a chart that only fills its
        // right corner for the first two minutes reads as an empty box, and this
        // panel is opened right after a boot as often as not.
        const step = w / Math.max(1, count - 1)

        if (count === 1) {
            const flat = bottom - Math.min(1, Math.max(0, sample(samples, first) / top)) * span
            return { xs: [0, w], ys: [flat, flat] }
        }

        const xs = []
        const ys = []
        for (let i = 0; i < count; ++i) {
            const value = sample(samples, first + i)
            xs.push(w - (count - 1 - i) * step)
            ys.push(bottom - Math.min(1, Math.max(0, value / top)) * span)
        }
        return { xs: xs, ys: ys }
    }

    /// Canvas does not track what onPaint reads, so the inputs are listed here
    /// and any change to one of them repaints the chart.
    readonly property var paintInputs: [values, capacity, scaleFloor, scaleMax, lineWidth,
                                        lineColor, plateColor, width, height]

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

            // The plate is also the clip: the filled area keeps the rounded
            // corners and nothing can be drawn outside the item.
            root.roundedPath(ctx, 0, 0, w, h, root.plateRadius)
            ctx.fillStyle = root.rgba(root.plateColor, root.plateColor.a)
            ctx.fill()
            ctx.save()
            root.roundedPath(ctx, 0, 0, w, h, root.plateRadius)
            ctx.clip()

            const points = root.plotPoints(w, h)
            if (points.xs.length > 1) {
                const baseline = h - root.lineWidth / 2
                const fill = ctx.createLinearGradient(0, 0, 0, baseline)
                fill.addColorStop(0, root.rgba(root.lineColor, 0.40))
                fill.addColorStop(1, root.rgba(root.lineColor, 0.03))

                ctx.beginPath()
                ctx.moveTo(points.xs[0], baseline)
                for (let i = 0; i < points.xs.length; ++i)
                    ctx.lineTo(points.xs[i], points.ys[i])
                ctx.lineTo(points.xs[points.xs.length - 1], baseline)
                ctx.closePath()
                ctx.fillStyle = fill
                ctx.fill()

                ctx.beginPath()
                ctx.moveTo(points.xs[0], points.ys[0])
                for (let i = 1; i < points.xs.length; ++i)
                    ctx.lineTo(points.xs[i], points.ys[i])
                ctx.strokeStyle = root.rgba(root.lineColor, root.lineColor.a)
                ctx.lineWidth = root.lineWidth
                ctx.lineJoin = "round"
                ctx.lineCap = "round"
                ctx.stroke()
            }
            ctx.restore()
        }
    }
}
