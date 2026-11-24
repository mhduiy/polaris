// SPDX-License-Identifier: GPL-3.0-or-later
//
// The dock item must keep its size while its numbers change, otherwise the
// taskbar jitters once per second. Every value is drawn in a cell sized for the
// widest text it can ever show; this exits non-zero when that stops holding.
//
// Run through ctest, or directly:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml tests/test_no_jitter.qml

import QtQuick 2.15
import "../package"

Item {
    /// Qt.exit() neither stops this script nor sets the process status, so a check
    /// only records its verdict; the marker ctest looks for is printed at the end
    /// and only when nothing failed.
    property var problems: []

    function check(condition, message) {
        if (!condition) {
            problems.push(message)
            console.error("FAILED: " + message)
        }
    }

    /// The Grid that holds the metrics, so the stacked columns can be measured.
    function gridOf(item) {
        for (let i = 0; i < item.children.length; ++i) {
            if (item.children[i].columns !== undefined)
                return item.children[i]
        }
        return null
    }

    /// The visible cells of a stacked item, in the order the Grid fills them.
    function cellsOf(item) {
        const grid = gridOf(item)
        const cells = []
        if (!grid)
            return cells
        for (let i = 0; i < grid.children.length; ++i) {
            if (grid.children[i].visible)
                cells.push(grid.children[i])
        }
        return cells
    }

    /// Both cells share label and value widths; only the top draws a column rule.
    function checkStackedColumns(item, name) {
        const cells = cellsOf(item)
        for (let i = 0; i < cells.length; i += 2) {
            const top = cells[i]
            check(top.stackColumnStart === (i > 0),
                  name + ": the column rule is on the wrong cell at " + i)
            if (i + 1 === cells.length)
                continue
            const bottom = cells[i + 1]
            check(top.labelWidth > 0 && top.labelWidth === bottom.labelWidth,
                  name + ": a stacked column is ragged at " + i + ": "
                  + top.labelWidth + " / " + bottom.labelWidth)
            check(top.valueWidth === bottom.valueWidth && top.x === bottom.x && top.width === bottom.width,
                  name + ": the numbers have different right edges at " + i + ": "
                  + top.width + " / " + bottom.width)
            check(top.y < bottom.y, name + ": a stacked pair is not laid out top to bottom")
            check(!bottom.stackColumnStart, name + ": the bottom cell draws a column rule at " + i)
        }
    }

    MonitorItem {
        id: smallest
        dockSize: 48
        cpuUsage: 0.0
        cpuTemperature: 0
        memoryUsage: 0.0
        swapUsage: 0.0
        netDownloadRate: 0
        netUploadRate: 0
    }

    MonitorItem {
        id: largest
        dockSize: 48
        cpuUsage: 1.0
        cpuTemperature: 100
        memoryUsage: 1.0
        swapUsage: 1.0
        netDownloadRate: 999.9 * 1000 * 1000
        netUploadRate: 999.9 * 1000 * 1000
    }

    // A missing sensor renders "--" instead of a number.
    MonitorItem {
        id: noSensor
        dockSize: 48
        cpuUsage: 0.5
        cpuTemperature: -1
        memoryUsage: 0.5
        swapUsage: 0.5
    }

    MonitorItem {
        id: verticalSmallest
        dockSize: 28
        vertical: true
        cpuUsage: 0.0
        cpuTemperature: 0
        memoryUsage: 0.0
        swapUsage: 0.0
        netDownloadRate: 0
        netUploadRate: 0
    }

    MonitorItem {
        id: verticalLargest
        dockSize: 28
        vertical: true
        cpuUsage: 1.0
        cpuTemperature: 100
        memoryUsage: 1.0
        swapUsage: 1.0
        netDownloadRate: 999.9 * 1000 * 1000
        netUploadRate: 999.9 * 1000 * 1000
    }

    // Switching a metric off changes the width on purpose; what must never
    // happen is the numbers changing it.
    MonitorItem {
        id: hiddenSmallest
        dockSize: 48
        showCpu: false
        showTemperature: false
        cpuUsage: 0.0
        cpuTemperature: 0
        memoryUsage: 0.0
        swapUsage: 0.0
        netDownloadRate: 0
        netUploadRate: 0
    }

    MonitorItem {
        id: hiddenLargest
        dockSize: 48
        showCpu: false
        showTemperature: false
        cpuUsage: 1.0
        cpuTemperature: 100
        memoryUsage: 1.0
        swapUsage: 1.0
        netDownloadRate: 999.9 * 1000 * 1000
        netUploadRate: 999.9 * 1000 * 1000
    }

    // The charts are the other way the item could resize: a chart sized from its
    // samples would make the item jitter once per second.
    MonitorItem {
        id: chartSmallest
        dockSize: 48
        chartMode: "both"
        cpuUsage: 0.0
        cpuHistory: []
        memoryUsage: 0.0
        memoryHistory: []
    }

    MonitorItem {
        id: chartLargest
        dockSize: 48
        chartMode: "both"
        cpuUsage: 1.0
        cpuHistory: [1, 90, 3, 100, 2]
        memoryUsage: 1.0
        memoryHistory: new Array(200).fill(100)
    }

    MonitorItem {
        id: lineSmallest
        dockSize: 48
        chartMode: "line"
        cpuUsage: 0.0
        cpuHistory: []
        downloadHistory: []
    }

    MonitorItem {
        id: lineLargest
        dockSize: 48
        chartMode: "line"
        cpuUsage: 1.0
        cpuHistory: [12, 88, 40]
        downloadHistory: [0, 1e9, 5e8]
    }

    MonitorItem {
        id: verticalCharts
        dockSize: 48
        vertical: true
        chartMode: "both"
        cpuHistory: []
        memoryHistory: [1, 2, 3]
    }

    MonitorItem {
        id: verticalChartsFull
        dockSize: 48
        vertical: true
        chartMode: "both"
        cpuHistory: [50, 60, 70, 80]
        memoryHistory: [90, 91, 92]
    }

    // The item must draw itself from the size the dock hands it, so the taskbar's
    // own height setting reaches it.
    MonitorItem {
        id: smallDock
        dockSize: 38
        chartMode: "both"
    }

    MonitorItem {
        id: largeDock
        dockSize: 56
        chartMode: "both"
    }

    MonitorItem {
        id: balanceLoading
        dockSize: 38
        chartMode: "line"
        showBalance: true
        balance: ({name: "AIHub", compact: "--"})
    }

    MonitorItem {
        id: balanceLoaded
        dockSize: 38
        chartMode: "line"
        showBalance: true
        balance: ({name: "AIHub", compact: "$3.97", balance: "3.96948748 USD"})
    }

    MonitorItem {
        id: verticalBalanceLoading
        dockSize: 38
        vertical: true
        chartMode: "line"
        showBalance: true
        balance: balanceLoading.balance
    }

    MonitorItem {
        id: verticalBalanceLoaded
        dockSize: 38
        vertical: true
        chartMode: "line"
        showBalance: true
        balance: balanceLoaded.balance
    }

    // The stacked layout wraps the same metrics onto two rows; it must be as
    // steady as the single line, and it must stay inside the taskbar it is given.
    MonitorItem {
        id: stackedSmallest
        dockSize: 48
        style: "stacked"
        cpuUsage: 0.0
        cpuTemperature: 0
        memoryUsage: 0.0
        swapUsage: 0.0
        netDownloadRate: 0
        netUploadRate: 0
    }

    MonitorItem {
        id: stackedLargest
        dockSize: 48
        style: "stacked"
        cpuUsage: 1.0
        cpuTemperature: 100
        memoryUsage: 1.0
        swapUsage: 1.0
        netDownloadRate: 999.9 * 1000 * 1000
        netUploadRate: 999.9 * 1000 * 1000
    }

    MonitorItem {
        id: singleLine
        dockSize: 48
        style: "label"
    }

    // Measure the largest single-line font: one line fits the fallback layout,
    // while two leave enough height for stacked text, regardless of font family.
    TextMetrics {
        id: dockLineMetrics
        font.pixelSize: largeDock.fontSize
        text: "100%"
    }

    MonitorItem {
        id: stackedFits
        dockSize: 2 * Math.ceil(dockLineMetrics.boundingRect.height)
        style: "stacked"
    }

    MonitorItem {
        id: stackedTooThin
        dockSize: Math.ceil(dockLineMetrics.boundingRect.height)
        style: "stacked"
    }

    // A stacked line has no room for charts, but the numbers still have to be
    // drawn: asking for the chart-only line must not leave the item empty.
    MonitorItem {
        id: stackedChartOnly
        dockSize: 48
        style: "stacked"
        chartMode: "line"
    }

    // Switching metrics off re-pairs the columns (here power ends up above the
    // balance), and a re-paired column has to line up as well as a declared one.
    MonitorItem {
        id: stackedRepaired
        dockSize: 48
        style: "stacked"
        showMemory: false
        showSwap: false
        showNetwork: false
        showPower: true
        showBalance: true
        balance: balanceLoaded.balance
    }

    // Hiding one metric pairs swap with download, and leaves upload on its own.
    MonitorItem {
        id: stackedMixed
        dockSize: 48
        style: "stacked"
        showCpu: false
    }

    // Nothing may leave the process alive: ctest would wait for it forever.
    Timer {
        interval: 10000
        running: true
        onTriggered: {
            console.error("FAILED: the checks did not finish")
            Qt.exit(1)
        }
    }

    Timer {
        interval: 100
        running: true

        onTriggered: {
            check(smallest.implicitWidth === largest.implicitWidth
                    && largest.implicitWidth === noSensor.implicitWidth,
                    "horizontal width follows the values: " + smallest.implicitWidth + " / "
                    + largest.implicitWidth + " / " + noSensor.implicitWidth)
            check(verticalSmallest.implicitWidth === verticalLargest.implicitWidth
                    && verticalSmallest.implicitHeight === verticalLargest.implicitHeight,
                    "vertical size follows the values")
            check(hiddenSmallest.implicitWidth === hiddenLargest.implicitWidth,
                    "hidden metrics still follow the values: " + hiddenSmallest.implicitWidth + " / "
                    + hiddenLargest.implicitWidth)
            check(hiddenSmallest.implicitWidth < smallest.implicitWidth,
                    "hiding a metric did not shrink the item: " + hiddenSmallest.implicitWidth + " / "
                    + smallest.implicitWidth)
            // With the leading metrics hidden, the first one left must not draw a
            // dangling separator in front of itself.
            check(!hiddenSmallest.needsSeparator(2) && hiddenSmallest.needsSeparator(3),
                    "separators do not follow the visible metrics")
            check(!smallest.needsSeparator(0) && smallest.needsSeparator(1),
                    "the first visible metric draws a separator")
            check(balanceLoading.implicitWidth === balanceLoaded.implicitWidth,
                  "the taskbar widens when a balance replaces the placeholder")
            check(verticalBalanceLoading.implicitHeight === verticalBalanceLoaded.implicitHeight
                  && verticalBalanceLoaded.childrenRect.width <= verticalBalanceLoaded.implicitWidth,
                  "the balance changes the vertical layout or overflows it")

            // Charts must be sized from their cells, never from their samples.
            check(chartSmallest.implicitWidth === chartLargest.implicitWidth,
                  "the item widens when the charts have more to draw: "
                  + chartSmallest.implicitWidth + " / " + chartLargest.implicitWidth)
            check(chartSmallest.implicitHeight === 48 && chartLargest.implicitHeight === 48,
                  "drawing charts changed the item's height: "
                  + chartSmallest.implicitHeight + " / " + chartLargest.implicitHeight)
            check(lineSmallest.implicitWidth === lineLargest.implicitWidth,
                  "the chart-only line widens with its samples: "
                  + lineSmallest.implicitWidth + " / " + lineLargest.implicitWidth)
            check(verticalCharts.implicitWidth === verticalChartsFull.implicitWidth
                  && verticalCharts.implicitHeight === verticalChartsFull.implicitHeight,
                  "a vertical item resizes when its charts fill up: "
                  + verticalCharts.implicitWidth + "x" + verticalCharts.implicitHeight + " / "
                  + verticalChartsFull.implicitWidth + "x" + verticalChartsFull.implicitHeight)

            check(smallDock.implicitHeight === 38 && largeDock.implicitHeight === 56,
                  "the item ignores the dock size it is given: "
                  + smallDock.implicitHeight + " / " + largeDock.implicitHeight)
            check(largeDock.fontSize > smallDock.fontSize,
                  "the text does not follow the dock size")
            check(largeDock.chartWidth > smallDock.chartWidth
                  && largeDock.chartHeight > smallDock.chartHeight,
                  "the charts do not follow the dock size: "
                  + smallDock.chartWidth + "x" + smallDock.chartHeight + " / "
                  + largeDock.chartWidth + "x" + largeDock.chartHeight)

            // Nothing may be drawn outside the item: a chart wider than a vertical
            // dock is clipped by the dock, and one taller than the taskbar is
            // clipped by the item.
            const items = [["smallest", smallest], ["largest", largest],
                           ["chartSmallest", chartSmallest], ["chartLargest", chartLargest],
                           ["verticalLargest", verticalLargest],
                           ["lineLargest", lineLargest], ["verticalChartsFull", verticalChartsFull],
                           ["smallDock", smallDock], ["largeDock", largeDock]]
            for (const entry of items) {
                const name = entry[0]
                const item = entry[1]
                check(item.childrenRect.width <= item.implicitWidth,
                      name + " draws wider than it is: " + Math.ceil(item.childrenRect.width)
                      + " > " + item.implicitWidth)
                check(item.childrenRect.height <= item.implicitHeight,
                      name + " draws taller than it is: " + Math.ceil(item.childrenRect.height)
                      + " > " + item.implicitHeight)
            }

            // The stacked layout stays steady and leaves more taskbar width free.
            check(stackedSmallest.implicitWidth === stackedLargest.implicitWidth,
                  "the stacked line follows its values: " + stackedSmallest.implicitWidth + " / "
                  + stackedLargest.implicitWidth)
            check(stackedSmallest.stacked && !singleLine.stacked,
                  "the style setting does not reach the layout")
            check(stackedSmallest.implicitWidth < singleLine.implicitWidth,
                  "the stacked line is not narrower than the labelled one: "
                  + stackedSmallest.implicitWidth + " / " + singleLine.implicitWidth)
            check(stackedFits.stacked && stackedFits.childrenRect.height <= stackedFits.implicitHeight,
                  "the stacked line overflows its measured taskbar height")
            check(!stackedTooThin.stacked
                  && stackedTooThin.childrenRect.height <= stackedTooThin.implicitHeight,
                  "a taskbar too thin for two rows does not fall back to one")
            check(stackedChartOnly.showValues && !stackedChartOnly.showCharts,
                  "a stacked line in chart-only mode draws nothing: values="
                  + stackedChartOnly.showValues + " charts=" + stackedChartOnly.showCharts)

            // Two rows filled column by column, including mixed and odd pairs.
            check(cellsOf(stackedSmallest).length === 6, "the stacked line does not hold six cells")
            check(cellsOf(stackedMixed).length === 5, "hiding one metric does not leave five cells")
            checkStackedColumns(stackedSmallest, "declared columns")
            checkStackedColumns(stackedRepaired, "re-paired columns")
            checkStackedColumns(stackedMixed, "mixed columns")

            if (problems.length === 0)
                console.error("no jitter checks passed")
            Qt.exit(problems.length === 0 ? 0 : 1)
        }
    }

}
