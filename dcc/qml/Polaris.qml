
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
    // 图标取控制中心自带的 DCI，不自己画：插件自造图标在侧边栏渲染尺寸不对（见
    // luminalock 的注释）。high_performance 是电源模块的性能表盘，语义上最接近
    // “监视硬件状态”，且不与侧边栏的“系统”“设备”分组图标重复。
    icon: "high_performance"
    // 排在“蓝牙与设备”(40) 之后、“电源”(50) 之前，靠近其他系统类模块。
    weight: 45
}
