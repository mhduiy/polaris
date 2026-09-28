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
        dockSize: 48
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
        dockSize: 48
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

            if (problems.length === 0)
                console.error("no jitter checks passed")
            Qt.exit(problems.length === 0 ? 0 : 1)
        }
    }

}
