
// SPDX-License-Identifier: GPL-3.0-or-later
import org.deepin.dcc 1.0

// 插件元数据：控制中心侧边栏与首页的模块入口。name 与插件名一致，控制中心用它
// 按 org.deepin.ds.dock.polaris DConfig 判断模块是否隐藏；页面是同目录的
// PolarisMain.qml，加载方式见 DccPluginLoader::loadMain()。
DccObject {
    name: "polaris"
    parentName: "root"
    displayName: qsTr("系统监视器")
    description: qsTr("在任务栏上显示 CPU 占用、温度、内存、交换分区与网络速率")
    // 复用系统 DCI 图标，避免自带图标在侧边栏渲染尺寸异常。
    icon: "qutescoop"
    // 排在“蓝牙与设备”(40) 之后、“电源”(50) 之前，靠近其他系统类模块。
    weight: 45
}
