// SPDX-License-Identifier: GPL-3.0-or-later
//
// The charts are drawn with Canvas, which nothing can assert on, but every one
// of them computes its geometry first — and that geometry is what can silently
// go wrong on an idle machine, a single sample, or a value list full of junk.
// This checks those computations directly.

import QtQuick 2.15
import "../package"

Item {
    id: root

    Sparkline {
        id: sparkline
        width: 200
        height: 40
    }

    SegmentedBar {
        id: bar
        width: 300
        barHeight: 10
    }

    SwapBar {
        id: swapBar
    }

    readonly property var palette: ({
        dark: true,
        track: Qt.rgba(1, 1, 1, 0.14),
        swap: "#F08C6E",
        cpu: "#4F9DF7"
    })

    // A tiny helper so the assertions below read as assertions.
    QtObject {
        id: expect

        property var problems: []

        function that(condition, message) {
            if (!condition) {
                problems.push(message)
                console.error("FAILED: " + message)
            }
        }

        function finite(value, message) {
            that(isFinite(value), message + " (got " + value + ")")
        }
    }

    Component.onCompleted: {
        // ---------------------------------------------------------- sparkline
        const cases = [
            { name: "empty", values: [] },
            { name: "single", values: [42] },
            { name: "all zero", values: [0, 0, 0, 0] },
            { name: "equal", values: [7, 7, 7, 7, 7] },
            { name: "spike", values: [1, 1, 90, 1, 1] },
            { name: "junk", values: [NaN, -5, "x", null, undefined, 3] },
            { name: "over capacity", values: new Array(200).fill(0).map((_, i) => i) }
        ]

        for (const testCase of cases) {
            sparkline.values = testCase.values
            const points = sparkline.plotPoints(sparkline.width, sparkline.height)

            expect.that(points.xs.length === points.ys.length,
                        testCase.name + ": xs and ys disagree")
            expect.that(points.xs.length !== 1,
                        testCase.name + ": a lone point cannot be a line")

            for (let i = 0; i < points.xs.length; ++i) {
                expect.finite(points.xs[i], testCase.name + ": x not finite")
                expect.finite(points.ys[i], testCase.name + ": y not finite")
                expect.that(points.xs[i] >= 0 && points.xs[i] <= sparkline.width + 0.001,
                            testCase.name + ": x outside the chart")
                expect.that(points.ys[i] >= 0 && points.ys[i] <= sparkline.height + 0.001,
                            testCase.name + ": y outside the chart")
                if (i > 0)
                    expect.that(points.xs[i] > points.xs[i - 1],
                                testCase.name + ": x is not strictly increasing")
            }

            if (testCase.values.length > 1) {
                expect.that(points.xs[0] <= 0.001,
                            testCase.name + ": the oldest sample is not at the left edge")
                expect.that(Math.abs(points.xs[points.xs.length - 1] - sparkline.width) <= 0.001,
                            testCase.name + ": the newest sample is not at the right edge")
            }
        }

        // A spike must actually reach the top, or the chart hides what it is for.
        // A reading with a ceiling of its own is drawn against it: half of a
        // 0..100% chart is half the height, and a sample over the ceiling is
        // pinned to the top instead of drawn outside the chart.
        sparkline.scaleMax = 100
        sparkline.values = [50, 50]
        const half = sparkline.plotPoints(sparkline.width, sparkline.height)
        const middle = (sparkline.height - sparkline.lineWidth) / 2 + sparkline.lineWidth / 2
        expect.that(Math.abs(half.ys[0] - middle) <= 1,
                    "50% is not drawn halfway up a 0..100 chart: " + half.ys[0] + " vs " + middle)

        sparkline.values = [200, 200]
        const over = sparkline.plotPoints(sparkline.width, sparkline.height)
        expect.that(over.ys[0] >= 0 && over.ys[0] <= sparkline.lineWidth,
                    "a sample over the ceiling is not pinned to the top: " + over.ys[0])
        sparkline.scaleMax = 0

        sparkline.values = [1, 1, 90, 1, 1]
        const spike = sparkline.plotPoints(sparkline.width, sparkline.height)
        expect.that(Math.min(...spike.ys) < sparkline.height * 0.1,
                    "a spike does not reach the top of the chart")

        // ------------------------------------------------------ segmented bar
        bar.segments = []
        expect.that(bar.edgeAt(0) === 0, "an empty bar does not start at zero")

        bar.segments = [{ value: 0, color: "#fff" }, { value: 0, color: "#fff" }]
        expect.that(bar.edgeAt(1) === 0, "a zero total draws more than the track")

        bar.segments = [{ value: 3, color: "#a" }, { value: 1, color: "#b" }, { value: 0, color: "#c" }]
        let previous = -1
        for (let i = 0; i <= bar.segmentCount; ++i) {
            const edge = bar.edgeAt(i)
            expect.finite(edge, "edge not finite")
            expect.that(edge >= previous, "edges are not monotonic")
            previous = edge
        }
        expect.that(bar.edgeAt(bar.segmentCount) === Math.floor(bar.width),
                    "the last segment does not end on the bar's width")
        expect.that(bar.edgeAt(1) === Math.round(bar.width * 0.75), "a 3:1 split is not three quarters")

        // Nonsense values must be treated as nothing rather than drawing outside.
        bar.segments = [{ value: -4, color: "#a" }, { value: "x", color: "#b" }]
        expect.that(bar.edgeAt(bar.segmentCount) === 0, "junk values produced a filled bar")
        bar.segments = [{ value: 1 }, { value: 1, color: "#b" }] // the first has no colour
        expect.that(bar.total === 2, "a segment without a colour stopped counting")

        // ------------------------------------------------------ process table
        const table = tableComponent.createObject(root, { width: 380 })
        const rows = [
            { pid: 1, name: "busy", cpu: 40, memory: 1000 },
            { pid: 2, name: "quiet", cpu: 0, memory: 900000 },
            { pid: 3, name: "junk", cpu: NaN, memory: -5 }
        ]
        table.processes = rows
        for (let i = 0; i < rows.length; ++i) {
            const share = table.rowShare(rows[i])
            expect.finite(share, "row share not finite")
            expect.that(share >= 0 && share <= 1, "row share outside 0..1")
        }
        expect.that(table.rowShare(rows[0]) === 1, "the busiest row is not full")
        expect.that(table.rowShare(rows[1]) === 0, "an idle row has a bar")

        // Sorted by memory, the bars must follow that figure instead.
        table.sortMode = "memory"
        expect.that(table.rowShare(rows[1]) === 1, "the largest row is not full when sorted by memory")
        expect.that(table.rowShare(rows[0]) > 0, "a small row lost its bar entirely")

        table.processes = []
        expect.that(table.rowShare({ pid: 9, name: "x", cpu: 1, memory: 1 }) === 0,
                    "an empty table still draws a bar")

        // ----------------------------------------------------------- swap bar
        swapBar.theme = root.palette
        swapBar.usedKiB = 1 * 1024 * 1024
        swapBar.totalKiB = 4 * 1024 * 1024
        expect.that(swapBar.enabled, "a machine with swap has no bar")
        expect.that(Math.abs(swapBar.usedShare - 0.25) < 0.0001,
                    "a quarter full reads " + swapBar.usedShare)
        expect.that(swapBar.implicitHeight === swapBar.barHeight, "the bar takes no space")

        swapBar.usedKiB = 0
        expect.that(swapBar.usedShare === 0, "an empty swap is not empty")
        // A bar that overshot its total would draw outside its track.
        swapBar.usedKiB = 9 * 1024 * 1024
        expect.that(swapBar.usedShare === 1, "a swap fuller than its total reads " + swapBar.usedShare)
        swapBar.usedKiB = -5
        expect.that(swapBar.usedShare === 0, "a negative swap reading reads " + swapBar.usedShare)

        swapBar.totalKiB = 0
        expect.that(!swapBar.enabled, "a machine without swap still claims a bar")
        expect.that(swapBar.implicitHeight === 0, "a machine without swap still takes space")

        // Only claim success when nothing failed: the runtime would happily carry
        // on past a Qt.exit() and print this marker anyway.
        if (expect.problems.length === 0)
            console.error("chart checks passed")
        Qt.exit(expect.problems.length === 0 ? 0 : 1)
    }

    Component {
        id: tableComponent
        ProcessTable {}
    }

    // Never reached: the assertions above exit the process.
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.error("FAILED: the checks did not finish")
            Qt.exit(2)
        }
    }
}
