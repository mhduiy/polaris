// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.deepin.ds 1.0
import org.deepin.dtk 1.0 as D

Window {
    id: root

    required property var source

    property int panelGap: 10
    property int screenMargin: 12

    readonly property bool darkTheme: D.DTK.themeType === D.ApplicationHelper.DarkType
    readonly property var theme: darkTheme ? darkThemeColors : lightThemeColors

    // macOS-ish: light chrome on dark, white card on light, with a colour per
    // metric so the windows never read as one flat shade.
    readonly property var darkThemeColors: ({
        dark: true,
        background: Qt.rgba(0.11, 0.11, 0.12, 0.82),
        card: Qt.rgba(1, 1, 1, 0.06),
        cardHover: Qt.rgba(1, 1, 1, 0.11),
        border: Qt.rgba(1, 1, 1, 0.14),
        text: "#F5F5F7",
        dim: Qt.rgba(1, 1, 1, 0.55),
        track: Qt.rgba(1, 1, 1, 0.14),
        cpu: "#4F9DF7",
        system: "#F7A94F",
        iowait: "#E8C547",
        memory: "#9B7BF7",
        cache: "#5AA9E6",
        swap: "#F08C6E",
        netDown: "#3FD08A",
        netUp: "#4FD1E0",
        fan: "#F08CC0",
        temperature: "#8ED081",
        warn: "#F2B441",
        danger: "#FF6B6B"
    })

    readonly property var lightThemeColors: ({
        dark: false,
        background: Qt.rgba(0.97, 0.97, 0.98, 0.86),
        card: Qt.rgba(0, 0, 0, 0.045),
        cardHover: Qt.rgba(0, 0, 0, 0.08),
        border: Qt.rgba(0, 0, 0, 0.10),
        text: "#1A1A1A",
        dim: Qt.rgba(0, 0, 0, 0.55),
        track: Qt.rgba(0, 0, 0, 0.10),
        cpu: "#1E6FD9",
        system: "#B46510",
        iowait: "#9A7B0A",
        memory: "#6A45D0",
        cache: "#2B7BB9",
        swap: "#C2522F",
        netDown: "#15804E",
        netUp: "#0E7C8C",
        fan: "#B0336E",
        temperature: "#2F7D32",
        warn: "#A55F00",
        danger: "#C62828"
    })

    visible: false
    color: "transparent"
    flags: Qt.Tool

    // The dock's own screen, not the first one: the window has to open next to
    // the item the pointer is on.
    screen: {
        const dock = DS.applet("org.deepin.ds.dock")
        if (!dock)
            return Qt.application.screens[0]
        for (let i = 0; i < Qt.application.screens.length; ++i) {
            if (Qt.application.screens[i].name === dock.screenName)
                return Qt.application.screens[i]
        }
        return Qt.application.screens[0]
    }

    // ------------------------------------------------------------ placement
    /// Where the dock item is, in screen coordinates.
    readonly property point anchorPoint: {
        const applet = DS.applet("org.deepin.ds.dock.polaris")
        const item = applet ? applet.rootObject : null
        if (!item)
            return Qt.point(0, 0)
        return item.mapToItem(null, item.width / 2, item.height / 2)
    }

    /// The dock's own rectangle, so the window clears it instead of covering it.
    readonly property rect dockRect: {
        const dock = DS.applet("org.deepin.ds.dock")
        if (!dock)
            return Qt.rect(0, 0, 0, 0)
        const ratio = screen ? screen.devicePixelRatio : 1
        const front = dock.frontendWindowRect
        return Qt.rect(front.x / ratio, front.y / ratio, front.width / ratio, front.height / ratio)
    }

    function clampToScreen(value, limit) {
        // Without a screen or a dock applet to measure, the inputs are not numbers
        // at all; a NaN would place the window anywhere, including off-screen.
        if (!isFinite(value) || !isFinite(limit) || limit <= 2 * root.screenMargin)
            return root.screenMargin
        const maximum = Math.max(root.screenMargin, limit - root.screenMargin)
        return Math.round(Math.max(root.screenMargin, Math.min(value, maximum)))
    }

    readonly property int screenWidth: screen ? screen.width : 0
    readonly property int screenHeight: screen ? screen.height : 0

    readonly property int placedX: clampToScreen(anchorPoint.x - width / 2, screenWidth - width)
    readonly property int placedY: clampToScreen(anchorPoint.y - height / 2, screenHeight - height)

    DLayerShellWindow.layer: DLayerShellWindow.LayerOverlay
    DLayerShellWindow.exclusionZone: 0
    DLayerShellWindow.scope: "polaris/panel"
    DLayerShellWindow.keyboardInteractivity: DLayerShellWindow.KeyboardInteractivityOnDemand
    DLayerShellWindow.anchors: {
        switch (Panel.position) {
        case 0: // dock on top: hang the window under it
            return DLayerShellWindow.AnchorTop | DLayerShellWindow.AnchorLeft
        case 1: // dock on the right: sit to its left
            return DLayerShellWindow.AnchorRight | DLayerShellWindow.AnchorTop
        case 3: // dock on the left
            return DLayerShellWindow.AnchorLeft | DLayerShellWindow.AnchorTop
        default: // dock at the bottom
            return DLayerShellWindow.AnchorBottom | DLayerShellWindow.AnchorLeft
        }
    }
    DLayerShellWindow.topMargin: {
        switch (Panel.position) {
        case 0:
            return Math.round(dockRect.height) + root.panelGap
        case 1:
        case 3:
            return placedY
        default:
            return 0
        }
    }
    DLayerShellWindow.bottomMargin: Panel.position === 2 ? Math.round(dockRect.height) + root.panelGap : 0
    DLayerShellWindow.leftMargin: {
        switch (Panel.position) {
        case 0:
        case 2:
            return placedX
        default:
            return Math.round(dockRect.width) + root.panelGap
        }
    }
    DLayerShellWindow.rightMargin: Panel.position === 1 ? Math.round(dockRect.width) + root.panelGap : 0

    // The frosted backdrop; when the compositor cannot blur, the background
    // colour below still gives an opaque enough surface to read against.
    D.StyledBehindWindowBlur {
        anchors.fill: parent
        cornerRadius: background.radius
        blendColor: root.theme.background
        control: parent
    }

    Rectangle {
        id: background
        anchors.fill: parent
        radius: 14
        color: root.theme.background
        border.width: 1
        border.color: root.theme.border
    }

    width: 420
    height: Math.min(body.implicitHeight, Math.round((screen ? screen.height : 800) * 0.72))

    // --------------------------------------------------------- open and close
    function toggle() {
        if (visible)
            hide()
        else
            show()
    }

    // Taking focus is what makes a click anywhere else deactivate the window,
    // which is how the panel closes; without it the window would linger.
    onVisibleChanged: {
        // The applet only walks /proc while something is looking at the process
        // list, and it is this window that does the looking.
        source.setPanelVisible(visible)
        if (visible)
            requestActivate()
    }

    // Clicking anywhere else deactivates the window, which is what closes the
    // panel; the dock closing its popup and hiding the panel do the same.
    onActiveChanged: {
        if (!active)
            hide()
    }

    Connections {
        target: DS.applet("org.deepin.ds.dock")
        function onRequestClosePopup() {
            root.hide()
        }
    }

    Connections {
        target: Panel
        function onVisibleChanged() {
            if (!Panel.visible)
                root.hide()
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: root.hide()
    }

    DetailPanel {
        id: body
        anchors.fill: parent
        anchors.margins: 1 // inside the border
        source: root.source
        theme: root.theme

        opacity: 0
        transform: Translate { id: slide; y: -10 }

        // macOS-like: fade in and slide down from the item, and back out again.
        states: State {
            name: "shown"
            when: root.visible
            PropertyChanges { body.opacity: 1 }
            PropertyChanges { slide.y: 0 }
        }

        transitions: Transition {
            NumberAnimation { properties: "opacity,y"; duration: 140; easing.type: Easing.OutCubic }
        }
    }
}
