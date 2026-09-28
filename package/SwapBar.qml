// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick 2.15

/**
 * Swap as its own bar: the used share of the total, with the free part left as
 * the track so a full bar always means swap is full.
 *
 * A machine with no swap has nothing to draw, and says so by taking no space.
 */
Item {
    id: root

    /// What is in use, and the size of the partition, both in KiB as the kernel
    /// reports them.
    property real usedKiB: 0
    property real totalKiB: 0
    /// The window's colour roles; one the palette does not carry falls back to a
    /// literal, so the bar draws something either way.
    property var theme: null
    property real barHeight: 10

    readonly property bool enabled: root.totalKiB > 0
    /// 0..1, with anything the kernel reports out of range pulled back in.
    readonly property real usedShare: enabled ? Math.min(1, Math.max(0, root.usedKiB / root.totalKiB)) : 0

    implicitHeight: root.enabled ? root.barHeight : 0

    SegmentedBar {
        id: bar

        anchors.fill: parent
        visible: root.enabled
        theme: root.theme
        barHeight: root.barHeight
        segments: root.enabled
                  ? [{ value: root.usedShare, color: bar.role("swap", "#F08C6E") },
                     { value: 1 - root.usedShare, color: bar.trackColor }]
                  : []
    }
}
