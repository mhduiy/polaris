// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 2.15

import "format.js" as Format

/**
 * Pure visual for the polaris dock item: the CPU / temperature / memory / swap
 * values, each coloured by its own load level, on one line or wrapped onto two
 * rows, and — when the settings ask for it — the history of each reading drawn
 * under its number, so the taskbar shows where a reading is going and not only
 * where it is.
 *
 * A metric's chart is sized from its own cells, never from its samples, so
 * adding the charts cannot make the item jitter.
 *
 * Deliberately free of dde-shell imports so it can be rendered standalone.
 */
Item {
    id: root

    property real cpuUsage: 0        // 0..1
    property real cpuTemperature: -1 // degrees Celsius, negative = unknown
    property real memoryUsage: 0     // 0..1
    property real swapUsage: 0       // 0..1
    property real netDownloadRate: 0 // bytes per second
    property real netUploadRate: 0   // bytes per second
    property real powerWatts: -1     // watts, negative = no source could be read
    property string powerSource: ""  // "battery", "rapl" or a hwmon chip name
    property int fanMaximum: 0       // highest fan speed in RPM

    property string memoryDetail: ""
    property string swapDetail: ""

    // Which metrics the control centre settings leave switched on.
    property bool showCpu: true
    property bool showTemperature: true
    property bool showMemory: true
    property bool showSwap: true
    property bool showNetwork: true
    property bool showPower: false
    property bool showFan: false
    property bool showBalance: false
    property var balance: ({})

    /// How every metric is drawn: "off" (the number alone), "both" (the number
    /// with its history under it) or "line" (the history with its label, no
    /// number). One setting for the line rather than one per metric: what is
    /// being watched is already chosen per metric, and a taskbar whose figures
    /// are half numbers and half charts reads as neither.
    property string chartMode: "off"

    /// The last samples of each reading, oldest first, exactly as the applet
    /// sampled them. Only drawn when chartMode asks for it.
    property var cpuHistory: []
    property var temperatureHistory: []
    property var memoryHistory: []
    property var swapHistory: []
    property var downloadHistory: []
    property var uploadHistory: []
    property var powerHistory: []
    property var fanHistory: []
    /// The chip's own ceiling for the fans, so a fan chart is scaled the way
    /// its gauge in the panel is; 0 fits the scale to the samples.
    property int fanCeiling: 0

    /// "label" keeps metrics on one line with labels; "stacked" pairs visible
    /// metrics into two rows to save width. Vertical docks keep their existing
    /// layout; thin horizontal docks fall back to one row.
    property string style: "label"

    property bool darkTheme: false
    property bool vertical: false
    property int dockSize: 48

    /// The size a stacked line draws at: two rows of it have to fit into the one
    /// height the taskbar gives. Deliberately computed without asking `stacked`,
    /// so the two cannot depend on each other.
    readonly property int stackedFontSize: Math.max(12, Math.min(16, Math.round(dockSize * 0.28)))

    /// One line of that size, so the layout can measure whether two of them fit
    /// instead of trusting a constant that only holds for one font.
    TextMetrics {
        id: stackLineMetrics
        font.pixelSize: root.stackedFontSize
        text: "100%"
    }

    // Two rows need two line heights of taskbar; on a thinner one the line stays
    // single rather than being clipped.
    readonly property bool stacked: style === "stacked" && !root.vertical
                                    && dockSize >= 2 * Math.ceil(stackLineMetrics.boundingRect.height)

    /// Between two columns of the stacked line, wide enough for the rule that
    /// separates them to sit in the middle of it.
    readonly property int stackedColumnSpacing: 12

    // Two rows do not fit in the taskbar next to the charts, and a chart squeezed
    // in half the height is not readable anyway. The numbers stay, so asking for
    // a chart-only line on a stacked item still draws something.
    readonly property bool showCharts: (chartMode === "both" || chartMode === "line") && !root.stacked
    readonly property bool showValues: chartMode !== "line" || root.stacked
    // Both sides follow the dock's thickness, so the item resizes with the
    // taskbar and a chart keeps its shape — 3:1 — whatever the taskbar is set to.
    //
    // The height deliberately does *not* follow the font: the font is clamped to
    // 13..18px so the digits stay readable, and a chart tied to it would stop
    // growing while the taskbar kept getting taller.
    readonly property int chartHeight: Math.max(12, Math.min(34, Math.round(root.dockSize * 0.42)))
    // A trend has to be long enough to read its shape from: roughly a dock's
    // thickness and a quarter, about as wide as the label and the number it
    // follows. A vertical chart follows the value cell, but even its preferred
    // minimum must yield to the width of the dock.
    readonly property int chartWidth: root.vertical
                                      ? Math.min(root.dockSize, Math.max(24, root.valueWidth))
                                      : Math.max(28, Math.round(root.dockSize * 1.25))
    /// Between a number and its chart.
    readonly property int chartGap: 4

    // Readable on a taskbar: never below 13px, never above 18px. A stacked line
    // has to fit two of them into the same height, so it asks for a smaller one.
    readonly property int fontSize: root.stacked
                                    ? root.stackedFontSize
                                    : Math.max(13, Math.min(18, Math.round(dockSize * 0.34)))

    // ------------------------------------------------------------- load colors
    // Three levels (normal / high / extreme) per theme. Every colour is at
    // least 4.5:1 against the background that DockPalette.iconTextPalette
    // assumes for that theme (white in light, near-black in dark).
    readonly property color normalColor: darkTheme ? "#5FD08A" : "#157F45"
    readonly property color highColor: darkTheme ? "#F2B441" : "#A55F00"
    readonly property color extremeColor: darkTheme ? "#FF6B6B" : "#C62828"
    readonly property color separatorColor: darkTheme ? Qt.rgba(1, 1, 1, 0.35)
                                                      : Qt.rgba(0, 0, 0, 0.35)
    /// The plate behind a metric's chart: the separator colour at full strength
    /// would make eight of them read as blocks rather than as trends.
    readonly property color chartPlateColor: darkTheme ? Qt.rgba(1, 1, 1, 0.14)
                                                       : Qt.rgba(0, 0, 0, 0.10)

    readonly property real usageHigh: 0.60
    readonly property real usageExtreme: 0.85
    readonly property real temperatureHigh: 70
    readonly property real temperatureExtreme: 85

    function usageColor(usage) {
        if (usage >= usageExtreme)
            return extremeColor
        if (usage >= usageHigh)
            return highColor
        return normalColor
    }

    function temperatureColor(celsius) {
        if (celsius < 0)
            return separatorColor // no sensor available
        if (celsius >= temperatureExtreme)
            return extremeColor
        if (celsius >= temperatureHigh)
            return highColor
        return normalColor
    }

    // ----------------------------------------------------------------- values
    readonly property string cpuValue: Math.round(cpuUsage * 100) + "%"
    readonly property string temperatureValue: cpuTemperature >= 0
                                               ? Math.round(cpuTemperature) + "℃"
                                               : "--"
    readonly property string memoryValue: Math.round(memoryUsage * 100) + "%"
    readonly property string swapValue: Math.round(swapUsage * 100) + "%"
    readonly property string powerValue: powerWatts >= 0 ? Math.round(powerWatts) + "W" : "--"
    readonly property string fanValue: fanMaximum > 0 ? String(fanMaximum) : "--"
    readonly property string downloadValue: root.vertical ? Format.rateCompact(netDownloadRate)
                                                          : Format.rateText(netDownloadRate)
    readonly property string uploadValue: root.vertical ? Format.rateCompact(netUploadRate)
                                                        : Format.rateText(netUploadRate)

    readonly property string temperatureDetail: cpuTemperature >= 0
                                                ? Math.round(cpuTemperature) + "℃"
                                                : qsTr("unavailable")

    /// The tooltip repeats the line item by item, so a metric that is switched
    /// off does not turn up here either.
    readonly property string tooltipText: {
        const lines = []
        if (showCpu)
            lines.push(qsTr("CPU") + ": " + cpuValue)
        if (showTemperature)
            lines.push(qsTr("Temperature") + ": " + temperatureDetail)
        if (showMemory)
            lines.push(qsTr("Memory") + ": " + memoryDetail + " (" + memoryValue + ")")
        if (showSwap)
            lines.push(qsTr("Swap") + ": " + swapDetail + " (" + swapValue + ")")
        if (showNetwork)
            lines.push(qsTr("Network") + ": ↓ " + Format.rateDetail(netDownloadRate) + " ↑ " + Format.rateDetail(netUploadRate))
        if (showPower && powerWatts >= 0)
            lines.push(qsTr("Power") + ": " + powerWatts.toFixed(1) + " W"
                       + (powerSource.length > 0 ? " (" + powerSource + ")" : ""))
        if (showFan && fanMaximum > 0)
            lines.push(qsTr("Fan") + ": " + fanMaximum + " RPM")
        if (showBalance) {
            lines.push((balance.name || qsTr("API balance")) + ": " + (balance.balance || "--"))
            if (balance.todayCost)
                lines.push(qsTr("Today’s actual cost: %1").arg(balance.todayCost))
            if (balance.todayRequests)
                lines.push(qsTr("Today’s requests: %1").arg(balance.todayRequests))
            if (balance.updated)
                lines.push(qsTr("Last updated: %1").arg(balance.updated))
            if (balance.status)
                lines.push(balance.status)
        }
        return lines.join("\n")
    }

    /// In a vertical dock every value stands on its own line and carries no
    /// separator; horizontally a metric only needs one when something precedes
    /// it, so hiding the leading metrics does not leave a dangling separator.
    readonly property var metricVisibility: [showCpu, showTemperature, showMemory, showSwap,
                                              showNetwork, showNetwork, showPower, showFan, showBalance]

    readonly property int visibleCount: {
        let count = 0
        for (let i = 0; i < metricVisibility.length; ++i) {
            if (metricVisibility[i])
                ++count
        }
        return Math.max(1, count)
    }

    function needsSeparator(index) {
        // A stacked line spaces its columns instead of spelling out the gaps.
        if (root.vertical || root.stacked)
            return false
        for (let i = 0; i < index; ++i) {
            if (metricVisibility[i])
                return true
        }
        return false
    }

    /// The label every metric draws, in the order the metrics are declared below.
    /// One place for the text, so a column's labels and the width they are drawn
    /// in cannot drift apart.
    readonly property var metricLabels: [qsTr("CPU") + " ", qsTr("TEMP") + " ", qsTr("MEM") + " ",
                                         qsTr("SWP") + " ", "↓ ", "↑ ", "PWR ", "FAN ",
                                         (root.balance.name || qsTr("API")) + " "]

    function startsColumn(index) {
        const cell = root.metricLayout[index]
        return root.stacked && !!cell && cell.column > 0 && cell.firstMetric === index
    }

    // ------------------------------------------------- fixed cells, no jitter
    // Every value is drawn in a cell sized for the widest text it can ever
    // show, so the widget keeps its size while the numbers change.
    TextMetrics {
        id: percentMetrics
        font.pixelSize: root.fontSize
        text: "100%"
    }

    TextMetrics {
        id: temperatureMetrics
        font.pixelSize: root.fontSize
        text: "100℃"
    }

    readonly property int valueWidth: {
        const preferred = Math.ceil(Math.max(percentMetrics.advanceWidth, temperatureMetrics.advanceWidth))
        return root.vertical ? Math.min(root.dockSize, preferred) : preferred
    }

    TextMetrics {
        id: rateMetrics
        font.pixelSize: root.fontSize
        text: "999.9M/s"
    }

    readonly property real rateWidth: Math.ceil(rateMetrics.advanceWidth)

    /// Vertical docks draw the compact form, which must line up with the other
    /// cells instead of being wider than the dock itself.
    readonly property real rateCellWidth: root.vertical ? root.valueWidth : root.rateWidth

    TextMetrics {
        id: balanceMetrics
        font.pixelSize: root.fontSize
        text: "−$888.88M"
    }

    FontMetrics {
        id: balanceFont
        font.pixelSize: root.fontSize
    }

    readonly property var metricValueWidths: [root.valueWidth, root.valueWidth, root.valueWidth, root.valueWidth,
                                             root.rateCellWidth, root.rateCellWidth, root.valueWidth, root.valueWidth,
                                             root.vertical ? Math.max(0, root.dockSize - 8)
                                                           : Math.ceil(balanceMetrics.advanceWidth)]

    // Each visible pair shares one record for its labels, values and column rule.
    readonly property var metricLayout: {
        const layout = []
        if (!root.stacked)
            return layout
        let visible = 0
        let column
        for (let i = 0; i < root.metricVisibility.length; ++i) {
            if (!root.metricVisibility[i]) {
                layout.push(null)
                continue
            }
            if (visible % 2 === 0)
                column = {column: visible / 2, firstMetric: i, labelWidth: 0, valueWidth: 0}
            column.labelWidth = Math.max(column.labelWidth,
                                         Math.ceil(balanceFont.advanceWidth(root.metricLabels[i])))
            column.valueWidth = Math.max(column.valueWidth, root.metricValueWidths[i])
            layout.push(column)
            ++visible
        }
        return layout
    }

    function labelWidthOf(index) {
        const cell = root.metricLayout[index]
        return root.stacked && cell ? cell.labelWidth : 0
    }

    function valueWidthOf(index) {
        const cell = root.metricLayout[index]
        return root.stacked && cell ? cell.valueWidth : root.metricValueWidths[index]
    }

    implicitWidth: root.vertical ? root.dockSize : Math.round(content.implicitWidth + 12)
    implicitHeight: root.vertical ? Math.round(content.implicitHeight + 8) : root.dockSize

    // One line in a horizontal dock, one value per line in a vertical dock
    // (a vertical dock is only dockSize wide), and two rows filled column by
    // column when the style asks for the stacked line — which is what pairs the
    // metrics up and lets each column carry its own rule.
    Grid {
        id: content
        anchors.centerIn: parent
        flow: root.stacked ? Grid.TopToBottom : Grid.LeftToRight
        columns: root.vertical ? 1 : (root.stacked ? -1 : root.visibleCount)
        rows: root.stacked ? 2 : -1
        columnSpacing: root.stacked ? root.stackedColumnSpacing : 0

        // CPU over temperature, memory over swap, download over upload: both
        // cells of a column carry their label padded to one width, so the two
        // numbers of a column still end at the same edge.
        MetricGroup {
            fontSize: root.fontSize
            visible: root.showCpu
            showSeparator: root.needsSeparator(0)
            stackColumnStart: root.startsColumn(0)
            label: root.vertical ? "" : root.metricLabels[0]
            labelWidth: root.labelWidthOf(0)
            value: root.cpuValue
            valueWidth: root.valueWidthOf(0)
            valueColor: root.usageColor(root.cpuUsage)
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.cpuHistory
            scaleMax: 100
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(1)
            stackColumnStart: root.startsColumn(1)
            visible: root.showTemperature
            label: root.vertical ? "" : root.metricLabels[1]
            labelWidth: root.labelWidthOf(1)
            value: root.temperatureValue
            valueWidth: root.valueWidthOf(1)
            valueColor: root.temperatureColor(root.cpuTemperature)
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.temperatureHistory
            scaleMax: 100
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(2)
            stackColumnStart: root.startsColumn(2)
            visible: root.showMemory
            label: root.vertical ? "" : root.metricLabels[2]
            labelWidth: root.labelWidthOf(2)
            value: root.memoryValue
            valueWidth: root.valueWidthOf(2)
            valueColor: root.usageColor(root.memoryUsage)
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.memoryHistory
            scaleMax: 100
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(3)
            stackColumnStart: root.startsColumn(3)
            visible: root.showSwap
            label: root.vertical ? "" : root.metricLabels[3]
            labelWidth: root.labelWidthOf(3)
            value: root.swapValue
            valueWidth: root.valueWidthOf(3)
            valueColor: root.usageColor(root.swapUsage)
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.swapHistory
            scaleMax: 100
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(4)
            stackColumnStart: root.startsColumn(4)
            visible: root.showNetwork
            label: root.vertical ? "" : root.metricLabels[4]
            labelWidth: root.labelWidthOf(4)
            value: root.downloadValue
            valueWidth: root.valueWidthOf(4)
            valueColor: root.normalColor
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            // A transfer rate has no ceiling to scale against, so the chart
            // fits its own window; the fan chart does, and is scaled like its
            // gauge in the panel.
            values: root.downloadHistory
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(5)
            stackColumnStart: root.startsColumn(5)
            visible: root.showNetwork
            label: root.vertical ? "" : root.metricLabels[5]
            labelWidth: root.labelWidthOf(5)
            value: root.uploadValue
            valueWidth: root.valueWidthOf(5)
            valueColor: root.normalColor
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.uploadHistory
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(6)
            stackColumnStart: root.startsColumn(6)
            visible: root.showPower
            label: root.vertical ? "" : root.metricLabels[6]
            labelWidth: root.labelWidthOf(6)
            value: root.powerValue
            valueWidth: root.valueWidthOf(6)
            valueColor: root.powerWatts >= 0 ? root.normalColor : root.separatorColor
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.powerHistory
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(7)
            stackColumnStart: root.startsColumn(7)
            visible: root.showFan
            label: root.vertical ? "" : root.metricLabels[7]
            labelWidth: root.labelWidthOf(7)
            value: root.fanValue
            valueWidth: root.valueWidthOf(7)
            valueColor: root.fanMaximum > 0 ? root.normalColor : root.separatorColor
            separatorColor: root.separatorColor
            showChart: root.showCharts
            showValue: root.showValues
            values: root.fanHistory
            scaleMax: root.fanCeiling
        }
        MetricGroup {
            fontSize: root.fontSize
            showSeparator: root.needsSeparator(8)
            stackColumnStart: root.startsColumn(8)
            visible: root.showBalance
            label: root.vertical ? "" : root.metricLabels[8]
            labelWidth: root.labelWidthOf(8)
            value: root.balance.compact || "--"
            valueWidth: root.valueWidthOf(8)
            valueColor: root.balance.status ? root.separatorColor : root.normalColor
            separatorColor: root.separatorColor
            fitValue: true
        }
    }

    /// One metric: the separator, its label and its number on one line, with its
    /// history beside them. A horizontal dock has width to spare and a fixed
    /// height, so the chart goes to the right of the number; a vertical dock is
    /// only dockSize wide and has no room for that, so there the chart goes under
    /// it instead.
    ///
    /// The chart is as wide as the taskbar asks and never as wide as its samples,
    /// which is what keeps the item's size independent of the readings.
    component MetricGroup: Item {
        id: group

        property int fontSize: 13
        property bool showSeparator: false
        property string separator: " · "
        property string label: ""
        property string value: ""
        property real valueWidth: 0
        property color valueColor: "black"
        property color separatorColor: "gray"
        property bool showChart: false
        property bool showValue: true
        property bool fitValue: false
        /// 0 draws the label at its own width; a value pads it so the column's
        /// labels share one right edge.
        property real labelWidth: 0
        property var values: []
        property real scaleMax: 0
        /// True for the top metric of a stacked column that is not the first one:
        /// it draws the rule between its column and the one before it.
        property bool stackColumnStart: false

        readonly property bool chartBeside: !root.vertical
        readonly property bool fitText: root.vertical || group.fitValue

        implicitWidth: group.chartBeside
                       ? cells.width + (group.showChart ? root.chartGap + root.chartWidth : 0)
                       : Math.max(cells.width, group.showChart ? root.chartWidth : 0)
        implicitHeight: group.chartBeside
                        ? Math.max(cells.height, group.showChart ? root.chartHeight : 0)
                        : cells.height + (group.showChart ? root.chartGap + root.chartHeight : 0)

        /// The rule spans both rows of the column, so it is drawn from the top
        /// cell down; two rows are exactly two cell heights, which keeps this out
        /// of the layout's own height and free of binding loops.
        Rectangle {
            visible: group.stackColumnStart
            x: -Math.round(root.stackedColumnSpacing / 2)
            width: 1
            height: 2 * cells.height
            color: root.separatorColor
        }

        Row {
            id: cells
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            Text {
                visible: group.showSeparator
                text: group.separator
                font.pixelSize: group.fontSize
                color: group.separatorColor
            }

            Text {
                text: group.label
                width: group.labelWidth > 0 ? group.labelWidth : implicitWidth
                textFormat: Text.PlainText
                font.pixelSize: group.fontSize
                color: group.valueColor
            }

            Text {
                visible: group.showValue
                text: group.value
                textFormat: Text.PlainText
                width: group.valueWidth
                horizontalAlignment: Text.AlignRight
                font.pixelSize: group.fontSize
                height: group.fitText ? Math.ceil(balanceFont.height) : implicitHeight
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: group.fitText ? Text.HorizontalFit : Text.FixedSize
                minimumPixelSize: 8
                elide: group.fitText ? Text.ElideRight : Text.ElideNone
                color: group.valueColor
            }
        }

        Sparkline {
            id: chart

            visible: group.showChart
            width: root.chartWidth
            height: root.chartHeight
            capacity: 60
            theme: ({ dark: root.darkTheme, track: root.chartPlateColor })
            lineColor: group.valueColor
            lineWidth: 1.5
            plateRadius: 2
            scaleMax: group.scaleMax
            values: group.values

            anchors.left: cells.right
            anchors.leftMargin: root.chartGap
            anchors.verticalCenter: parent.verticalCenter
        }

        states: State {
            name: "vertical"
            when: root.vertical

            AnchorChanges {
                target: chart
                anchors.left: parent.left
                anchors.top: cells.bottom
                anchors.verticalCenter: undefined
            }

            PropertyChanges {
                target: chart
                anchors.leftMargin: 0
                anchors.topMargin: root.chartGap
            }
        }
    }
}
