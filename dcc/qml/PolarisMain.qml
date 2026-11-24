
// SPDX-License-Identifier: GPL-3.0-or-later
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import org.deepin.dcc 1.0
import org.deepin.dtk 1.0 as D

// 系统监视器设置页：dccData 是 C++ 导出的 Polaris 对象，读写与任务栏小程序同一份
// org.deepin.ds.dock.polaris DConfig。
//
// 每行都带 backgroundType: DccObject.Normal，才会渲染成和其他设置页一致的卡片。
// 编辑器自己写入后会打断 value/checked 的绑定，所以每个编辑器都跟着 dccData 的
// NOTIFY 信号重新同步，外部改了配置这里不会显示旧值。
DccObject {
    id: root

    DccTitleObject {
        name: "metricsTitle"
        parentName: "polaris"
        displayName: qsTr("显示项")
        weight: 10
    }

    DccObject {
        name: "showCpu"
        parentName: "polaris"
        displayName: qsTr("CPU 占用")
        description: qsTr("在任务栏上显示 CPU 占用率")
        weight: 12
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: cpuSwitch
            checked: dccData.showCpu
            onCheckedChanged: dccData.setShowCpu(checked)

            Connections {
                target: dccData
                function onShowCpuChanged() {
                    cpuSwitch.checked = dccData.showCpu
                }
            }
        }
    }

    DccObject {
        name: "showTemperature"
        parentName: "polaris"
        displayName: qsTr("CPU 温度")
        description: qsTr("在任务栏上显示 CPU 温度")
        weight: 14
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: temperatureSwitch
            checked: dccData.showTemperature
            onCheckedChanged: dccData.setShowTemperature(checked)

            Connections {
                target: dccData
                function onShowTemperatureChanged() {
                    temperatureSwitch.checked = dccData.showTemperature
                }
            }
        }
    }

    DccObject {
        name: "showMemory"
        parentName: "polaris"
        displayName: qsTr("内存占用")
        description: qsTr("在任务栏上显示内存占用")
        weight: 16
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: memorySwitch
            checked: dccData.showMemory
            onCheckedChanged: dccData.setShowMemory(checked)

            Connections {
                target: dccData
                function onShowMemoryChanged() {
                    memorySwitch.checked = dccData.showMemory
                }
            }
        }
    }

    DccObject {
        name: "showSwap"
        parentName: "polaris"
        displayName: qsTr("交换分区占用")
        description: qsTr("在任务栏上显示交换分区占用")
        weight: 18
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: swapSwitch
            checked: dccData.showSwap
            onCheckedChanged: dccData.setShowSwap(checked)

            Connections {
                target: dccData
                function onShowSwapChanged() {
                    swapSwitch.checked = dccData.showSwap
                }
            }
        }
    }

    DccObject {
        name: "showNetwork"
        parentName: "polaris"
        displayName: qsTr("网络速率")
        description: qsTr("在任务栏上显示下载与上传速率")
        weight: 20
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: networkSwitch
            checked: dccData.showNetwork
            onCheckedChanged: dccData.setShowNetwork(checked)

            Connections {
                target: dccData
                function onShowNetworkChanged() {
                    networkSwitch.checked = dccData.showNetwork
                }
            }
        }
    }

    DccObject {
        name: "showPower"
        parentName: "polaris"
        displayName: qsTr("功耗")
        description: qsTr("在任务栏上显示整机功耗；多数系统上内核只允许特权用户读取，读不到时显示 --")
        weight: 22
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: powerSwitch
            checked: dccData.showPower
            onCheckedChanged: dccData.setShowPower(checked)

            Connections {
                target: dccData
                function onShowPowerChanged() {
                    powerSwitch.checked = dccData.showPower
                }
            }
        }
    }

    DccObject {
        name: "showFan"
        parentName: "polaris"
        displayName: qsTr("风扇转速")
        description: qsTr("在任务栏上显示最高的风扇转速")
        weight: 24
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            id: fanSwitch
            checked: dccData.showFan
            onCheckedChanged: dccData.setShowFan(checked)

            Connections {
                target: dccData
                function onShowFanChanged() {
                    fanSwitch.checked = dccData.showFan
                }
            }
        }
    }

    DccObject {
        name: "showBalance"
        parentName: "polaris"
        displayName: qsTr("在任务栏显示 API 余额")
        weight: 25
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Switch {
            checked: dccData.showBalance
            onToggled: dccData.setShowBalance(checked)
        }
    }

    DccObject {
        name: "balanceSettings"
        parentName: "polaris"
        displayName: qsTr("余额查询平台")
        weight: 29
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: Button {
            id: settingsButton
            text: qsTr("配置")
            Accessible.name: qsTr("配置余额查询平台")
            onClicked: editor.open()

            Dialog {
                id: editor
                parent: settingsButton.Window.window ? settingsButton.Window.window.contentItem : settingsButton
                anchors.centerIn: parent
                width: Math.min(460, parent.width - 24)
                modal: true
                title: qsTr("余额查询平台")

                property var saved: ({})
                property string validationError: ""

                function fill(config) {
                    platformName.text = config.name
                    endpoint.text = config.url
                    auth.currentIndex = Math.max(0, auth.modes.indexOf(config.auth))
                    fieldPath.text = config.path
                    unit.text = config.unit
                    minutes.value = config.minutes
                    key.clear()
                    validationError = ""
                }

                onAboutToShow: {
                    saved = dccData.balanceConfig()
                    const preset = dccData.defaultBalanceConfig()
                    platform.currentIndex = saved.url === preset.url && saved.auth === preset.auth
                            && saved.name === preset.name && saved.path === preset.path && saved.unit === preset.unit ? 0 : 1
                    fill(saved)
                }
                onClosed: key.clear()

                contentItem: ColumnLayout {
                    spacing: 12

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 8

                        Label { text: qsTr("平台") }
                        ComboBox {
                            id: platform
                            Layout.fillWidth: true
                            Accessible.name: qsTr("平台")
                            model: ["AIHub", qsTr("自定义 HTTPS 接口")]
                            onActivated: index => {
                                if (index === 0) {
                                    const interval = minutes.value
                                    editor.fill(dccData.defaultBalanceConfig())
                                    minutes.value = interval
                                }
                            }
                        }

                        Label { text: qsTr("显示名称"); visible: platform.currentIndex === 1 }
                        TextField {
                            id: platformName
                            visible: platform.currentIndex === 1
                            Layout.fillWidth: true
                            Accessible.name: qsTr("显示名称")
                            maximumLength: 16
                        }
                        Label { text: qsTr("接口地址"); visible: platform.currentIndex === 1 }
                        TextField {
                            id: endpoint
                            visible: platform.currentIndex === 1
                            Layout.fillWidth: true
                            Accessible.name: qsTr("接口地址")
                            placeholderText: "https://example.com/v1/usage"
                            onTextEdited: key.clear()
                        }
                        Label { text: qsTr("鉴权方式"); visible: platform.currentIndex === 1 }
                        ComboBox {
                            id: auth
                            visible: platform.currentIndex === 1
                            Layout.fillWidth: true
                            Accessible.name: qsTr("鉴权方式")
                            readonly property var modes: ["bearer", "x-api-key", "none"]
                            model: ["Authorization: Bearer", "x-api-key", qsTr("无需鉴权")]
                            onActivated: key.clear()
                        }
                        Label { text: qsTr("余额字段"); visible: platform.currentIndex === 1 }
                        TextField {
                            id: fieldPath
                            visible: platform.currentIndex === 1
                            Layout.fillWidth: true
                            Accessible.name: qsTr("余额字段")
                            placeholderText: "data.balance"
                        }
                        Label { text: qsTr("显示单位"); visible: platform.currentIndex === 1 }
                        TextField {
                            id: unit
                            visible: platform.currentIndex === 1
                            Layout.fillWidth: true
                            Accessible.name: qsTr("显示单位")
                            placeholderText: "USD"
                            maximumLength: 8
                        }
                        Label { text: "API Key"; visible: key.visible }
                        TextField {
                            id: key
                            visible: auth.currentIndex !== 2
                            Layout.fillWidth: true
                            Accessible.name: "API Key"
                            echoMode: TextInput.Password
                            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                            placeholderText: editor.saved.hasKey && editor.saved.url === endpoint.text.trim()
                                             && editor.saved.auth === auth.modes[auth.currentIndex]
                                             ? qsTr("已保存，留空保留") : qsTr("输入此平台的 API Key")
                        }
                        Label { text: qsTr("刷新间隔（分钟）") }
                        SpinBox {
                            id: minutes
                            Accessible.name: qsTr("刷新间隔（分钟）")
                            from: 5
                            to: 60
                            value: 5
                        }
                    }

                    Label {
                        Layout.fillWidth: true
                        visible: text.length > 0
                        text: editor.validationError
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        Button { text: qsTr("取消"); onClicked: editor.reject() }
                        Button {
                            text: qsTr("保存")
                            onClicked: {
                                editor.validationError = dccData.saveBalance({
                                    name: platformName.text, url: endpoint.text, auth: auth.modes[auth.currentIndex],
                                    path: fieldPath.text, unit: unit.text, minutes: minutes.value
                                }, key.text)
                                if (!editor.validationError)
                                    editor.accept()
                            }
                        }
                    }
                }
            }
        }
    }

    DccObject {
        name: "dockStyle"
        parentName: "polaris"
        displayName: qsTr("任务栏布局")
        description: qsTr("两行显示按顺序将可见指标两两排成列，列间有分隔线；宽度取决于字体和显示项。实际两行时只显示数字。竖向任务栏保持原布局，横向高度不足时回退单行，这两种情况仍按折线图设置显示。改完任务栏立即生效")
        weight: 26
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            id: styleCombo
            flat: true
            // Single line first, so a value the applet does not recognise is shown
            // as the layout it actually falls back to.
            model: [qsTr("单行显示（带标签）"), qsTr("两行显示")]
            readonly property var modes: ["label", "stacked"]
            currentIndex: Math.max(0, modes.indexOf(dccData.dockStyle))
            onActivated: index => dccData.setDockStyle(modes[index])

            Connections {
                target: dccData
                function onDockStyleChanged() {
                    styleCombo.currentIndex = Math.max(0, styleCombo.modes.indexOf(dccData.dockStyle))
                }
            }
        }
    }

    DccObject {
        name: "dockChartMode"
        parentName: "polaris"
        displayName: qsTr("任务栏折线图")
        description: qsTr("任务栏小程序怎么画：只显示数字 / 数字加折线图 / 只画折线图。画哪几项由上面的显示项开关决定，改完任务栏立即生效。实际两行布局只显示数字；竖向任务栏或单行回退时仍按此设置显示")
        weight: 27
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            id: chartCombo
            flat: true
            model: [qsTr("只显示数字"), qsTr("数字加折线图"), qsTr("只画折线图")]
            readonly property var modes: ["off", "both", "line"]
            currentIndex: Math.max(0, modes.indexOf(dccData.dockChartMode))
            onActivated: index => dccData.setDockChartMode(modes[index])

            Connections {
                target: dccData
                function onDockChartModeChanged() {
                    chartCombo.currentIndex = Math.max(0, chartCombo.modes.indexOf(dccData.dockChartMode))
                }
            }
        }
    }

    DccTitleObject {
        name: "behaviourTitle"
        parentName: "polaris"
        displayName: qsTr("刷新与进程")
        weight: 30
    }

    DccObject {
        name: "refreshIntervalMs"
        parentName: "polaris"
        displayName: qsTr("刷新间隔")
        description: qsTr("读数更新间隔，单位毫秒，可选 500 - 10000")
        weight: 32
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            id: intervalSpin
            from: 500
            to: 10000
            stepSize: 500
            editable: true
            value: dccData.refreshIntervalMs
            onValueChanged: dccData.setRefreshIntervalMs(value)

            Connections {
                target: dccData
                function onRefreshIntervalMsChanged() {
                    intervalSpin.value = dccData.refreshIntervalMs
                }
            }
        }
    }

    DccObject {
        name: "fanScaleRpm"
        parentName: "polaris"
        displayName: qsTr("风扇量程")
        description: qsTr("风扇转速条的满量程；芯片没报最高转速时按这个值计算")
        weight: 28
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            id: fanScaleSpin
            from: 500
            to: 10000
            stepSize: 500
            editable: true
            value: dccData.fanScaleRpm
            onValueChanged: dccData.setFanScaleRpm(value)

            Connections {
                target: dccData
                function onFanScaleRpmChanged() {
                    fanScaleSpin.value = dccData.fanScaleRpm
                }
            }
        }
    }

    DccObject {
        name: "processSort"
        parentName: "polaris"
        displayName: qsTr("进程排序方式")
        description: qsTr("面板里的进程列表按 CPU 占用还是按内存占用排序")
        weight: 35
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.ComboBox {
            id: sortCombo
            flat: true
            model: [qsTr("按 CPU 占用"), qsTr("按内存占用")]
            currentIndex: dccData.processSort === "memory" ? 1 : 0
            onActivated: index => dccData.setProcessSort(index === 1 ? "memory" : "cpu")

            Connections {
                target: dccData
                function onProcessSortChanged() {
                    sortCombo.currentIndex = dccData.processSort === "memory" ? 1 : 0
                }
            }
        }
    }

    DccObject {
        name: "processCount"
        parentName: "polaris"
        displayName: qsTr("进程列表条数")
        description: qsTr("点击任务栏小程序弹出的进程列表里显示多少条，可选 3 - 30")
        weight: 34
        backgroundType: DccObject.Normal
        pageType: DccObject.Editor
        page: D.SpinBox {
            id: processSpin
            from: 3
            to: 30
            editable: true
            value: dccData.processCount
            onValueChanged: dccData.setProcessCount(value)

            Connections {
                target: dccData
                function onProcessCountChanged() {
                    processSpin.value = dccData.processCount
                }
            }
        }
    }
}
