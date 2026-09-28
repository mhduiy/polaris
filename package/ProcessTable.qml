// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 2.15
import QtQuick.Controls 2.15

/**
 * The process list in the popup: the busiest processes, each with a bar for its
 * share of the busiest one and a button that asks it to terminate.
 *
 * Deliberately free of dde-shell imports so it can be rendered standalone.
 */
Item {
    id: root

    /// [{ pid, name, cpu, memory }], cpu in percent of the whole machine,
    /// memory in bytes. A missing or malformed field counts as zero.
    property var processes: []
    /// The panel's colour roles; one the palette does not carry falls back to
    /// a literal, so the table draws something either way.
    property var theme: null
    /// Shown in the footer after a refused kill, cleared by statusTimer.
    property string statusMessage: ""
    /// What the list is ordered by — the applet does the ranking, this only says
    /// which figure the rows are showing. "cpu" or "memory".
    property string sortMode: "cpu"
    /// Every size below is derived from this one, so the panel scales the whole
    /// table by setting it.
    property int fontSize: 13

    signal killRequested(int pid)
    /// The user picked the other ordering; the caller stores it as a setting.
    signal sortRequested(string mode)

    readonly property int padding: Math.round(fontSize * 0.92)
    readonly property int rowHeight: Math.round(fontSize * 2.3)
    readonly property int nameWidth: Math.round(fontSize * 16.5)
    readonly property int cpuWidth: Math.round(fontSize * 4)
    readonly property int memoryWidth: Math.round(fontSize * 4.8)
    readonly property int killWidth: Math.round(fontSize * 2)
    readonly property int gutter: Math.round(fontSize / 3)
    readonly property int rowRadius: Math.round(fontSize * 0.46)
    readonly property int visibleRows: 10

    implicitWidth: padding * 2 + nameWidth + cpuWidth + memoryWidth + killWidth
    implicitHeight: header.height + divider.height + list.height + footer.height

    function role(name, fallback) {
        const palette = root.theme || {}
        const value = palette[name]
        return value === undefined || value === null ? fallback : value
    }

    readonly property bool dark: role("dark", false) === true
    readonly property color textColor: role("text", dark ? "#F2F2F2" : "#1A1A1A")
    readonly property color dimColor: role("dim", dark ? "#8C8C8C" : "#737373")
    readonly property color hoverColor: role("cardHover", dark ? "#1AFFFFFF" : "#12000000")
    readonly property color borderColor: role("border", dark ? "#24FFFFFF" : "#1A000000")
    readonly property color cpuColor: role("cpu", "#4A90D9")
    readonly property color memoryColor: role("memory", "#9B7BF7")
    readonly property color warnColor: role("warn", dark ? "#F2B441" : "#A55F00")
    readonly property color dangerColor: role("danger", dark ? "#FF6B6B" : "#C62828")

    readonly property bool sortedByMemory: root.sortMode === "memory"
    readonly property color accentColor: sortedByMemory ? memoryColor : cpuColor

    /// The in-row bar is the accent colour seen through a low alpha, so the
    /// figure it stands behind stays legible.
    readonly property color barColor: Qt.rgba(accentColor.r, accentColor.g, accentColor.b, 0.22)

    /// The busiest row sets the scale for the in-row bars, so a cheap machine
    /// and a loaded one both show which process stands out.
    readonly property real busiestValue: {
        if (!root.processes)
            return 0
        let busiest = 0
        for (let i = 0; i < root.processes.length; ++i)
            busiest = Math.max(busiest, root.valueOf(root.processes[i]))
        return busiest
    }

    function cpuOf(process) {
        const cpu = process ? Number(process.cpu) : 0
        return isFinite(cpu) && cpu > 0 ? cpu : 0
    }

    function memoryOf(process) {
        const memory = process ? Number(process.memory) : 0
        return isFinite(memory) && memory > 0 ? memory : 0
    }

    function nameOf(process) {
        return process && process.name ? String(process.name) : ""
    }

    function pidOf(process) {
        const pid = process ? Number(process.pid) : 0
        return isFinite(pid) ? pid : 0
    }

    /// The figure this row is ranked by: the one the list is sorted on, so the
    /// bars always explain the order the rows are in.
    function valueOf(process) {
        return root.sortedByMemory ? memoryOf(process) : cpuOf(process)
    }

    /// How much of the widest bar this row's share earns it, 0 when nothing in
    /// the list stands out at all.
    function rowShare(process) {
        const busiest = root.busiestValue
        return busiest > 0 ? Math.min(1, valueOf(process) / busiest) : 0
    }

    /// Rounding to whole units keeps the column readable; the exact figures are
    /// what a terminal is for.
    function formatBytes(bytes) {
        const value = isFinite(bytes) && bytes > 0 ? bytes : 0
        if (value < 1000)
            return Math.round(value) + "B"
        if (value < 1000 * 1000)
            return Math.round(value / 1000) + "K"
        if (value < 1000 * 1000 * 1000)
            return (value / (1000 * 1000)).toFixed(1) + "M"
        return (value / (1000 * 1000 * 1000)).toFixed(1) + "G"
    }

    function showStatus(message) {
        root.statusMessage = message
        statusTimer.restart()
    }

    Timer {
        id: statusTimer
        interval: 3000
        onTriggered: root.statusMessage = ""
    }

    component SortTab: Rectangle {
        id: tab

        required property var table
        property string mode: ""
        property string label: ""

        readonly property bool active: tab.table.sortMode === tab.mode
        readonly property color accent: tab.mode === "memory" ? tab.table.memoryColor : tab.table.cpuColor

        width: tabLabel.implicitWidth + 14
        height: tabLabel.implicitHeight + 4
        radius: height / 2
        color: tab.active ? Qt.rgba(tab.accent.r, tab.accent.g, tab.accent.b, 0.20) : "transparent"
        border.width: 1
        border.color: tab.active ? Qt.rgba(tab.accent.r, tab.accent.g, tab.accent.b, 0.55)
                                 : tab.table.borderColor

        Text {
            id: tabLabel
            anchors.centerIn: parent
            text: tab.label
            font.pixelSize: tab.table.fontSize - 2
            color: tab.active ? tab.accent : tab.table.dimColor
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                if (!tab.active)
                    tab.table.sortRequested(tab.mode)
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 0

        Item {
            id: header
            width: parent.width
            height: root.padding * 2 + headerText.implicitHeight

            Text {
                id: headerText
                anchors.left: parent.left
                anchors.leftMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("进程")
                font.pixelSize: root.fontSize + 1
                font.bold: true
                color: root.textColor
            }

            // Two picks instead of a hint line: the list can be read either way
            // round, and saying which one is on is more useful than saying that
            // some order exists.
            Row {
                anchors.left: headerText.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                SortTab { table: root; mode: "cpu"; label: qsTr("按 CPU") }
                SortTab { table: root; mode: "memory"; label: qsTr("按内存") }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    width: root.cpuWidth
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("CPU")
                    font.pixelSize: root.fontSize - 2
                    color: root.dimColor
                }

                Text {
                    width: root.memoryWidth
                    horizontalAlignment: Text.AlignRight
                    text: qsTr("内存")
                    font.pixelSize: root.fontSize - 2
                    color: root.dimColor
                }

                Item { width: root.killWidth }
            }
        }

        Rectangle {
            id: divider
            width: parent.width
            height: 1
            color: root.borderColor
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(contentHeight, root.visibleRows * root.rowHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.processes || []
            ScrollBar.vertical: ScrollBar { }

            delegate: Item {
                id: row
                width: list.width
                height: root.rowHeight

                HoverHandler {
                    id: rowHover
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: root.gutter
                    anchors.rightMargin: root.gutter
                    radius: root.rowRadius
                    color: rowHover.hovered ? root.hoverColor : "transparent"
                }

                // The row's share of the busiest process, behind the figures it
                // belongs to rather than behind the command name.
                Item {
                    id: rowBar
                    anchors.left: cpu.left
                    anchors.leftMargin: -root.padding / 2
                    anchors.right: memory.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Math.round(root.rowHeight * 0.6)

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.round(parent.width * root.rowShare(modelData))
                        height: parent.height
                        radius: height / 2
                        color: root.barColor
                        visible: width > 0
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.padding
                    anchors.right: cpu.left
                    anchors.rightMargin: root.padding * 0.75
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.nameOf(modelData)
                    // A process chooses its own name, so it is shown as text and
                    // never as markup.
                    textFormat: Text.PlainText
                    elide: Text.ElideMiddle
                    font.pixelSize: root.fontSize
                    color: root.textColor
                }

                Text {
                    id: cpu
                    anchors.right: memory.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.cpuWidth
                    horizontalAlignment: Text.AlignRight
                    text: root.cpuOf(modelData).toFixed(1) + "%"
                    font.pixelSize: root.fontSize - 1
                    color: root.cpuOf(modelData) >= 50 ? root.warnColor : root.dimColor
                }

                Text {
                    id: memory
                    anchors.right: killButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.memoryWidth
                    horizontalAlignment: Text.AlignRight
                    text: root.formatBytes(root.memoryOf(modelData))
                    font.pixelSize: root.fontSize - 1
                    color: root.dimColor
                }

                // Drawn rather than taken from the icon theme: the popup lives
                // in the dock's process, where a missing theme icon would leave
                // an empty button and no way to tell what it does.
                Item {
                    id: killButton
                    anchors.right: parent.right
                    anchors.rightMargin: root.gutter
                    anchors.verticalCenter: parent.verticalCenter
                    width: root.killWidth
                    height: root.killWidth
                    visible: rowHover.hovered

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: killMouse.pressed || killMouse.containsMouse
                               ? root.hoverColor : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: root.fontSize + 6
                            color: killMouse.containsMouse ? root.dangerColor : root.dimColor
                        }
                    }

                    MouseArea {
                        id: killMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.killRequested(root.pidOf(modelData))
                    }
                }
            }
        }

        Item {
            id: footer
            width: parent.width
            height: root.padding * 2 + footerText.implicitHeight

            Text {
                id: footerText
                anchors.left: parent.left
                anchors.leftMargin: root.padding
                anchors.right: parent.right
                anchors.rightMargin: root.padding
                anchors.verticalCenter: parent.verticalCenter
                text: root.statusMessage.length > 0 ? root.statusMessage
                                                    : qsTr("悬停一行显示结束按钮")
                elide: Text.ElideRight
                font.pixelSize: root.fontSize - 2
                color: root.statusMessage.length > 0 ? root.dangerColor : root.dimColor
            }
        }
    }
}
