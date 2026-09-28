// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls
import "format.js" as Format

/**
 * The detail panel: everything the dock line has no room for — where the cpu
 * time went, what the memory is spent on, the transfer history and the busiest
 * processes.
 *
 * Every reading is bound straight to the applet (`source`), so the panel and the
 * taskbar always show the same sample. Free of dde-shell imports, so it can be
 * rendered standalone.
 */
Item {
    id: root

    required property var source
    required property var theme

    readonly property int fontSize: 13

    implicitHeight: column.implicitHeight + 28
    implicitWidth: 420

    function loadColor(percent) {
        if (percent >= 85)
            return root.theme.danger
        if (percent >= 60)
            return root.theme.warn
        return root.theme.cpu
    }

    function temperatureColor(celsius) {
        if (celsius < 0)
            return root.theme.dim
        if (celsius >= 85)
            return root.theme.danger
        if (celsius >= 70)
            return root.theme.warn
        return root.theme.temperature
    }

    /// "3 天 4 小时", dropping whatever is zero.
    function uptimeText(seconds) {
        const total = Math.max(0, Math.floor(seconds))
        const days = Math.floor(total / 86400)
        const hours = Math.floor((total % 86400) / 3600)
        const minutes = Math.floor((total % 3600) / 60)
        if (days > 0)
            return days + qsTr(" 天 ") + hours + qsTr(" 小时")
        if (hours > 0)
            return hours + qsTr(" 小时 ") + minutes + qsTr(" 分")
        return minutes + qsTr(" 分")
    }

    function percentage(part, whole) {
        return Math.round(part / Math.max(1, whole) * 100) + "%"
    }

    /// What the power figure is measuring — the panel must not let a gpu's draw
    /// read as the machine's.
    function powerSourceText(source) {
        if (source === "battery")
            return qsTr("整机")
        if (source === "rapl")
            return qsTr("CPU 封装")
        return source
    }

    function loadText(index) {
        return root.source.loadAverage.length > index
                ? root.source.loadAverage[index].toFixed(2) : "--"
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 14
        contentWidth: width
        contentHeight: column.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }

        Column {
            id: column
            width: parent.width
            spacing: 10

            // ------------------------------------------------------- title
            Item {
                width: parent.width
                implicitHeight: title.implicitHeight

                Text {
                    id: title
                    text: qsTr("系统监视")
                    font.pixelSize: root.fontSize + 3
                    font.bold: true
                    color: root.theme.text
                }

                Text {
                    anchors.left: title.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: title.verticalCenter
                    text: qsTr("已运行") + " " + root.uptimeText(root.source.uptimeSeconds)
                    font.pixelSize: root.fontSize - 2
                    color: root.theme.dim
                }

                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 2
                    anchors.verticalCenter: title.verticalCenter
                    spacing: 10

                    Chip { theme: root.theme; fontSize: root.fontSize - 2; label: qsTr("1分")
                           value: root.loadText(0); valueColor: root.theme.system }
                    Chip { theme: root.theme; fontSize: root.fontSize - 2; label: qsTr("5分")
                           value: root.loadText(1); valueColor: root.theme.system }
                    Chip { theme: root.theme; fontSize: root.fontSize - 2; label: qsTr("15分")
                           value: root.loadText(2); valueColor: root.theme.system }
                }
            }

            // ---------------------------------------------------------- cpu
            Card {
                theme: root.theme

                Column {
                    width: parent.width
                    spacing: 8

                    ValueRow {
                        theme: root.theme
                        label: qsTr("CPU")
                        value: Math.round(root.source.cpuUsage * 100) + "%"
                        valueFontSize: root.fontSize + 6
                        valueColor: root.loadColor(root.source.cpuUsage * 100)
                    }

                    SegmentedBar {
                        width: parent.width
                        theme: root.theme
                        segments: [
                            { value: root.source.cpuUserPercent, color: root.theme.cpu },
                            { value: root.source.cpuSystemPercent, color: root.theme.system },
                            { value: root.source.cpuIowaitPercent, color: root.theme.iowait },
                            { value: root.source.cpuIdlePercent, color: root.theme.track }
                        ]
                    }

                    Row {
                        width: parent.width
                        spacing: 14

                        Legend { theme: root.theme; dotColor: root.theme.cpu; label: qsTr("用户")
                                 value: root.source.cpuUserPercent.toFixed(1) + "%" }
                        Legend { theme: root.theme; dotColor: root.theme.system; label: qsTr("系统")
                                 value: root.source.cpuSystemPercent.toFixed(1) + "%" }
                        Legend { theme: root.theme; dotColor: root.theme.iowait; label: qsTr("等待")
                                 value: root.source.cpuIowaitPercent.toFixed(1) + "%" }
                        Legend { theme: root.theme; dotColor: root.theme.dim; label: qsTr("温度")
                                 value: root.source.cpuTemperature >= 0
                                        ? Math.round(root.source.cpuTemperature) + "℃" : "--"
                                 valueColor: root.temperatureColor(root.source.cpuTemperature) }
                    }

                    Sparkline {
                        width: parent.width
                        height: 44
                        theme: root.theme
                        lineColor: root.theme.cpu
                        values: root.source.cpuHistory
                    }

                    // One bar per core: a full row is easier to read at a glance
                    // than a list of numbers, and it shows a single pinned core.
                    Row {
                        width: parent.width
                        height: 26
                        spacing: 3
                        visible: coreBars.count > 0

                        Repeater {
                            id: coreBars
                            model: root.source.cpuCoreCount

                            Rectangle {
                                readonly property real percent: root.source.cpuCores.length > index
                                                                ? root.source.cpuCores[index] : 0

                                width: Math.max(2, (parent.width - (coreBars.count - 1) * 3)
                                                / Math.max(1, coreBars.count))
                                height: parent.height
                                radius: 2
                                color: root.theme.track

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * Math.min(1, parent.percent / 100))
                                    radius: parent.radius
                                    color: root.loadColor(parent.percent)
                                }
                            }
                        }
                    }
                }
            }

            // ------------------------------------------------------- memory
            Card {
                theme: root.theme

                Column {
                    width: parent.width
                    spacing: 8

                    ValueRow {
                        theme: root.theme
                        label: qsTr("内存")
                        value: Format.kibToGiB(root.source.memoryUsedKiB) + " / "
                               + Format.kibToGiB(root.source.memoryTotalKiB) + " GiB"
                    }

                    SegmentedBar {
                        width: parent.width
                        theme: root.theme
                        segments: [
                            { value: root.source.memoryUsedKiB, color: root.theme.memory },
                            { value: root.source.memoryCacheKiB, color: root.theme.cache },
                            { value: Math.max(0, root.source.memoryTotalKiB - root.source.memoryUsedKiB
                                              - root.source.memoryCacheKiB), color: root.theme.track }
                        ]
                    }

                    Row {
                        width: parent.width
                        spacing: 14

                        Legend { theme: root.theme; dotColor: root.theme.memory; label: qsTr("已用")
                                 value: root.percentage(root.source.memoryUsedKiB, root.source.memoryTotalKiB) }
                        Legend { theme: root.theme; dotColor: root.theme.cache; label: qsTr("缓存")
                                 value: root.percentage(root.source.memoryCacheKiB, root.source.memoryTotalKiB) }
                    }

                    Sparkline {
                        width: parent.width
                        height: 40
                        theme: root.theme
                        lineColor: root.theme.memory
                        values: root.source.memoryHistory
                    }

                    // Swap gets its own bar rather than a slice of the memory bar:
                    // it fills and empties on its own timescale, and a machine
                    // that has swapped everything out is not a machine with full
                    // memory. A machine without swap says so and draws nothing.
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.theme.track
                    }

                    ValueRow {
                        theme: root.theme
                        label: qsTr("交换分区")
                        value: root.source.swapTotalKiB > 0
                               ? Format.kibToGiB(root.source.swapUsedKiB) + " / "
                                 + Format.kibToGiB(root.source.swapTotalKiB) + " GiB"
                               : qsTr("未启用")
                        valueColor: root.source.swapTotalKiB > 0 ? root.theme.text : root.theme.dim
                    }

                    SwapBar {
                        width: parent.width
                        theme: root.theme
                        usedKiB: root.source.swapUsedKiB
                        totalKiB: root.source.swapTotalKiB
                    }

                    Legend {
                        theme: root.theme
                        visible: root.source.swapTotalKiB > 0
                        dotColor: root.theme.swap
                        label: qsTr("已用")
                        value: root.percentage(root.source.swapUsedKiB, root.source.swapTotalKiB)
                    }

                }
            }

            // ------------------------------------------------------ network
            Card {
                theme: root.theme

                Column {
                    width: parent.width
                    spacing: 6

                    ValueRow {
                        theme: root.theme
                        label: "↓ " + qsTr("下载")
                        labelColor: root.theme.netDown
                        value: Format.rateDetail(root.source.netDownloadRate)
                    }

                    Sparkline {
                        width: parent.width
                        height: 36
                        theme: root.theme
                        lineColor: root.theme.netDown
                        values: root.source.downloadHistory
                    }

                    ValueRow {
                        theme: root.theme
                        label: "↑ " + qsTr("上传")
                        labelColor: root.theme.netUp
                        value: Format.rateDetail(root.source.netUploadRate)
                    }

                    Sparkline {
                        width: parent.width
                        height: 36
                        theme: root.theme
                        lineColor: root.theme.netUp
                        values: root.source.uploadHistory
                    }

                    Text {
                        width: parent.width
                        topPadding: 4
                        text: qsTr("开机以来") + " ↓ " + Format.bytes(root.source.netDownloadTotal)
                              + "   ↑ " + Format.bytes(root.source.netUploadTotal)
                        font.pixelSize: root.fontSize - 2
                        color: root.theme.dim
                    }
                }
            }

            // --------------------------------------------- power and cooling
            // Only drawn when the machine actually reports one of the two: an
            // empty card would be worse than no card.
            Card {
                theme: root.theme
                visible: root.source.powerReadings.length > 0 || root.source.fans.length > 0

                Column {
                    width: parent.width
                    spacing: 8

                    // One row per source that answered, the first being what the
                    // dock line shows. They do not all measure the same thing,
                    // which is why every row names its own.
                    ValueRow {
                        theme: root.theme
                        label: root.source.powerReadings.length > 0
                               ? qsTr("功耗") + "（" + root.powerSourceText(root.source.powerReadings[0].source) + "）"
                               : qsTr("功耗")
                        value: root.source.powerReadings.length > 0
                               ? root.source.powerReadings[0].watts.toFixed(1) + " W" : "--"
                        valueColor: root.source.powerReadings.length > 0 ? root.theme.system : root.theme.dim
                    }

                    ValueRow {
                        theme: root.theme
                        visible: root.source.powerReadings.length > 1
                        label: root.source.powerReadings.length > 1
                               ? qsTr("功耗") + "（" + root.powerSourceText(root.source.powerReadings[1].source) + "）"
                               : ""
                        value: root.source.powerReadings.length > 1
                               ? root.source.powerReadings[1].watts.toFixed(1) + " W" : ""
                    }

                    Sparkline {
                        width: parent.width
                        height: 36
                        visible: root.source.powerWatts >= 0
                        theme: root.theme
                        lineColor: root.theme.system
                        values: root.source.powerHistory
                    }

                    // The kernel hands energy_uj to root only, so on most systems
                    // this is the line the user reads instead of a number.
                    Text {
                        width: parent.width
                        visible: root.source.powerReadings.length === 0
                        text: qsTr("内核未向当前用户提供功耗读数（/sys/class/powercap 通常仅 root 可读）")
                        font.pixelSize: root.fontSize - 2
                        color: root.theme.dim
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        width: parent.width
                        visible: root.source.fans.length > 0
                        text: qsTr("风扇转速")
                        font.pixelSize: root.fontSize - 1
                        color: root.theme.dim
                    }

                    Repeater {
                        model: root.source.fans

                        // The gauge sits in its own column at the end of the row:
                        // behind the text it would swallow the very figures it
                        // is meant to illustrate.
                        Item {
                            id: fanRow
                            // The card is narrower than the panel: a row sized by
                            // the panel would push the gauge out of the card.
                            width: parent.width
                            height: fanName.implicitHeight + 6

                            // Against the ceiling the chip reports, or the
                            // configured scale when it reports none.
                            readonly property real scale: root.source.fanCeiling > 0
                                                          ? root.source.fanCeiling : root.source.fanScaleRpm
                            readonly property real share: modelData.rpm > 0 && scale > 0
                                                          ? Math.min(1, modelData.rpm / scale) : 0

                            Text {
                                id: fanName
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.right: fanValue.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                // Chip labels come from sysfs and are shown as
                                // text, never as markup.
                                textFormat: Text.PlainText
                                elide: Text.ElideMiddle
                                font.pixelSize: root.fontSize
                                color: root.theme.text
                            }

                            Text {
                                id: fanValue
                                anchors.right: fanGauge.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.rpm > 0 ? modelData.rpm + " RPM" : qsTr("停转")
                                font.pixelSize: root.fontSize - 1
                                color: modelData.rpm > 0 ? root.theme.fan : root.theme.dim
                            }

                            Rectangle {
                                id: fanGauge
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                width: 54
                                height: 6
                                radius: 3
                                color: root.theme.track

                                Rectangle {
                                    anchors.left: parent.left
                                    width: Math.round(parent.width * fanRow.share)
                                    height: parent.height
                                    radius: parent.radius
                                    color: root.theme.fan
                                }
                            }
                        }
                    }

                    Sparkline {
                        width: parent.width
                        height: 36
                        visible: root.source.fanMaximum > 0
                        theme: root.theme
                        lineColor: root.theme.fan
                        values: root.source.fanHistory
                    }
                }
            }

            // ---------------------------------------------------- processes
            Card {
                theme: root.theme

                ProcessTable {
                    id: processTable
                    width: parent.width
                    theme: root.theme
                    fontSize: root.fontSize
                    processes: root.source.processes
                    sortMode: root.source.processSort
                    onSortRequested: function (mode) {
                        root.source.setProcessSort(mode)
                    }
                    onKillRequested: function (pid) {
                        if (!root.source.killProcess(pid))
                            processTable.showStatus(qsTr("无法结束该进程，可能属于其他用户"))
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------- pieces
    component Card: Rectangle {
        id: card
        required property var theme

        default property alias content: contentHolder.data

        width: parent.width
        implicitHeight: contentHolder.childrenRect.height + 24
        color: card.theme.card
        radius: 10
        border.width: 1
        border.color: card.theme.border

        Item {
            id: contentHolder
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
        }
    }

    /// A label on the left and its reading on the right, one line tall. A Row
    /// cannot do this: it lays its children out itself, so a child may not anchor
    /// itself to the right edge.
    component ValueRow: Item {
        id: valueRow
        required property var theme
        property int fontSize: root.fontSize
        property int valueFontSize: root.fontSize
        property string label: ""
        property string value: ""
        property color labelColor: valueRow.theme.text
        property color valueColor: valueRow.theme.text

        width: parent.width
        implicitHeight: Math.max(valueRowLabel.implicitHeight, valueRowValue.implicitHeight)

        Text {
            id: valueRowLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            // A device name or a fan label comes from hardware, not from us.
            textFormat: Text.PlainText
            text: valueRow.label
            font.pixelSize: valueRow.fontSize
            font.bold: true
            color: valueRow.labelColor
        }

        Text {
            id: valueRowValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: valueRow.value
            font.pixelSize: valueRow.valueFontSize
            font.bold: true
            color: valueRow.valueColor
        }
    }

    component Legend: Row {
        id: legend

        required property var theme
        property color dotColor: "transparent"
        property string label: ""
        property string value: ""
        property color valueColor: legend.theme.text

        spacing: 5

        Rectangle {
            width: 7
            height: 7
            radius: 3.5
            color: legend.dotColor
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: legend.label
            font.pixelSize: 11
            color: legend.theme.dim
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: legend.value
            font.pixelSize: 11
            color: legend.valueColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    component Chip: Row {
        id: chip

        required property var theme
        property int fontSize: 11
        property string label: ""
        property string value: ""
        property color valueColor: chip.theme.text

        spacing: 4

        Text {
            text: chip.label
            font.pixelSize: chip.fontSize
            color: chip.theme.dim
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: chip.value
            font.pixelSize: chip.fontSize
            color: chip.valueColor
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
