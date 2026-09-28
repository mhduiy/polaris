// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import QtQuick.Controls

import org.deepin.ds 1.0
import org.deepin.ds.dock 1.0
import org.deepin.dtk 1.0 as D

AppletItem {
    id: root

    // The dock is split in three parts: left (0, 10], center (10, 20],
    // right (20, 30]. 10 is the last slot of the left part, so the item sits
    // just before the centre group (launcher and running apps).
    property int dockOrder: 10

    readonly property bool vertical: Panel.position % 2
    // The dock's own thickness, which follows the "taskbar height" setting.
    // Deliberately not dockItemMaxSize: that one is the space each item gets,
    // solved for by the task manager, and it does not move when the taskbar is
    // made taller.
    readonly property int dockSize: Panel.rootObject.dockSize
    readonly property bool darkTheme: D.DTK.themeType === D.ApplicationHelper.DarkType

    implicitWidth: monitor.implicitWidth
    implicitHeight: monitor.implicitHeight

    // The dock's own hover/pressed background, inset so it reads as a pill
    // around the digits rather than filling the whole slot. It is also the click
    // target that opens the detail panel.
    AppletItemBackground {
        id: itemBackground
        anchors.fill: parent
        anchors.margins: 3
        isActive: detail.visible
        onClicked: function (mouse) {
            if (mouse.button === Qt.LeftButton)
                detail.toggle()
        }
    }

    MonitorItem {
        id: monitor
        anchors.centerIn: parent

        cpuUsage: Applet.cpuUsage
        cpuTemperature: Applet.cpuTemperature
        memoryUsage: Applet.memoryUsage
        swapUsage: Applet.swapUsage
        netDownloadRate: Applet.netDownloadRate
        netUploadRate: Applet.netUploadRate
        powerWatts: Applet.powerWatts
        powerSource: Applet.powerSource
        fanMaximum: Applet.fanMaximum
        memoryDetail: Applet.memoryText
        swapDetail: Applet.swapText

        // The histories the line draws when the settings ask for charts.
        chartMode: Applet.dockChartMode
        cpuHistory: Applet.cpuHistory
        temperatureHistory: Applet.temperatureHistory
        memoryHistory: Applet.memoryHistory
        swapHistory: Applet.swapHistory
        downloadHistory: Applet.downloadHistory
        uploadHistory: Applet.uploadHistory
        powerHistory: Applet.powerHistory
        fanHistory: Applet.fanHistory
        fanCeiling: Applet.fanCeiling

        showCpu: Applet.showCpu
        showTemperature: Applet.showTemperature
        showMemory: Applet.showMemory
        showSwap: Applet.showSwap
        showNetwork: Applet.showNetwork
        showPower: Applet.showPower
        showFan: Applet.showFan

        darkTheme: root.darkTheme
        vertical: root.vertical
        dockSize: root.dockSize
    }

    HoverHandler {
        onHoveredChanged: {
            if (hovered) {
                const point = root.mapToItem(null, root.width / 2, root.height / 2)
                toolTip.DockPanelPositioner.bounding = Qt.rect(point.x, point.y, toolTip.width, toolTip.height)
                toolTip.open()
            } else {
                toolTip.close()
            }
        }
    }

    PanelToolTip {
        id: toolTip
        toolTipX: DockPanelPositioner.x
        toolTipY: DockPanelPositioner.y
        text: monitor.tooltipText
    }

    DetailWindow {
        id: detail
        source: Applet
    }

}
