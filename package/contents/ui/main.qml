/*
THESIS: batctl remains the product; this surface removes terminal friction without copying its hardware logic.
OWN-WORLD: Plasma spacing, typography, controls, and iconography; colors mirror the batctl TUI palette (see
internal/tui/styles.go upstream) so the widget reads as the same product as the terminal tool.
STORY: inspect actual battery state, choose an offered preset, and immediately verify the applied thresholds.
FIRST VIEWPORT: device identity and refresh lead into battery readings; available presets are the primary actions.
FORM: compact operate-mode system utility, deliberately following the standard Plasma panel-widget pattern.
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.batctl.plasma
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // batctl TUI palette (truecolor). Source: github.com/Ooooze/batctl internal/tui/styles.go
    QtObject {
        id: palette
        // titleStyle / accentStyle / selectedStyle / helpKeyStyle
        readonly property color accent: "#FF6600"
        // valueStyle (bold)
        readonly property color value: "#FFFFFF"
        // successStyle / gaugeFullStyle
        readonly property color success: "#00CC66"
        // warningStyle
        readonly property color warning: "#FFAA00"
        // errorStyle
        readonly property color error: "#FF3333"
        // labelStyle
        readonly property color label: "#AAAAAA"
        // subtitleStyle / statusBarStyle / helpDescStyle
        readonly property color subtitle: "#888888"
        // dimStyle
        readonly property color dim: "#666666"
        // gaugeEmptyStyle
        readonly property color track: "#333333"
        // boxStyle border
        readonly property color border: "#444444"
    }

    Plasmoid.icon: "battery"
    toolTipMainText: "Battery charge thresholds"
    toolTipSubText: backend.compactText.length > 0 ? backend.compactText + "%" : "Open battery controls"

    BatctlBackend {
        id: backend
    }

    onExpandedChanged: {
        if (root.expanded) {
            backend.refresh();
        }
    }

    compactRepresentation: MouseArea {
        id: compact

        Layout.minimumWidth: compactRow.implicitWidth
        Layout.preferredWidth: compactRow.implicitWidth
        Layout.fillHeight: true
        activeFocusOnTab: true
        Accessible.name: "Open battery charge controls"
        Accessible.role: Accessible.Button

        onClicked: root.expanded = !root.expanded
        Keys.onSpacePressed: root.expanded = !root.expanded
        Keys.onReturnPressed: root.expanded = !root.expanded

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "battery"
                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                implicitHeight: implicitWidth
            }

            PlasmaComponents3.Label {
                visible: backend.compactText.length > 0 && root.width >= implicitWidth + Kirigami.Units.gridUnit * 2
                text: backend.compactText
            }
        }
    }

    fullRepresentation: Item {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2

        Timer {
            interval: 30000
            running: root.expanded
            repeat: true
            onTriggered: backend.refresh()
        }

        PlasmaComponents3.ScrollView {
            anchors.fill: parent
            contentWidth: availableWidth

            ColumnLayout {
                id: content
                width: parent.width
                spacing: Kirigami.Units.largeSpacing

                RowLayout {
                    Layout.fillWidth: true

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: backend.product.length > 0 ? backend.product : "Battery manager"
                            font.weight: Font.Bold
                            color: palette.accent
                            elide: Text.ElideRight
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: backend.backend.length > 0 ? backend.backend + " backend" : "Powered by batctl"
                            color: palette.subtitle
                            elide: Text.ElideRight
                        }
                    }

                    PlasmaComponents3.ToolButton {
                        icon.name: "view-refresh"
                        text: "Refresh"
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        enabled: !backend.busy
                        onClicked: backend.refresh()
                        PlasmaComponents3.ToolTip.text: text
                        PlasmaComponents3.ToolTip.visible: hovered
                    }
                }

                // Kirigami.InlineMessage colors are theme-driven by `type`; cannot override to
                // palette.error/success without replacing the component (no public color property).
                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: backend.error.length > 0
                    type: Kirigami.MessageType.Error
                    text: backend.error
                }

                Kirigami.InlineMessage {
                    Layout.fillWidth: true
                    visible: backend.error.length === 0 && backend.message.length > 0
                    type: Kirigami.MessageType.Positive
                    text: backend.message
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: backend.installed
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: "Batteries"
                        font.weight: Font.DemiBold
                        color: palette.label
                    }

                    Repeater {
                        model: backend.batteries

                        delegate: ColumnLayout {
                            id: batteryDelegate
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: batteryDelegate.modelData.name + "  " + batteryDelegate.modelData.capacity
                                    font.weight: Font.Bold
                                    color: palette.accent
                                }

                                PlasmaComponents3.Label {
                                    text: batteryDelegate.modelData.status
                                    color: palette.dim
                                }
                            }

                            // Charge gauge mirroring batctl: orange fill (#FF6600) on dark track (#333333)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Kirigami.Units.largeSpacing
                                radius: 2
                                color: palette.track

                                property real ratio: Math.max(0, Math.min(1, (parseInt(batteryDelegate.modelData.capacity) || 0) / 100))

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: parent.width * parent.ratio
                                    radius: parent.radius
                                    color: palette.accent
                                }

                                Accessible.name: batteryDelegate.modelData.name + " charge: " + batteryDelegate.modelData.capacity
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: "Thresholds"
                                    color: palette.label
                                }
                                PlasmaComponents3.Label {
                                    text: batteryDelegate.modelData.startThreshold !== undefined && batteryDelegate.modelData.stopThreshold !== undefined ? batteryDelegate.modelData.startThreshold + "–" + batteryDelegate.modelData.stopThreshold + "%" : batteryDelegate.modelData.stopThreshold !== undefined ? "Stop at " + batteryDelegate.modelData.stopThreshold + "%" : "Not exposed"
                                    font.weight: Font.Bold
                                    color: palette.value
                                }
                                PlasmaComponents3.Label {
                                    text: "Health"
                                    color: palette.label
                                }
                                PlasmaComponents3.Label {
                                    text: batteryDelegate.modelData.health + " · " + batteryDelegate.modelData.cycles + " cycles"
                                    font.weight: Font.Bold
                                    color: palette.value
                                }
                                PlasmaComponents3.Label {
                                    text: "Behaviour"
                                    color: palette.label
                                }
                                PlasmaComponents3.Label {
                                    text: batteryDelegate.modelData.behaviour
                                    font.weight: Font.Bold
                                    color: palette.value
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: backend.installed
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents3.Label {
                        text: "Presets from batctl"
                        font.weight: Font.DemiBold
                        color: palette.label
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Kirigami.Units.smallSpacing
                        rowSpacing: Kirigami.Units.smallSpacing

                        Repeater {
                            model: backend.presets

                            delegate: PlasmaComponents3.Button {
                                id: presetButton
                                required property string modelData
                                Layout.fillWidth: true
                                text: presetButton.modelData.replace(/-/g, " ").replace(/\b\w/g, function (letter) {
                                    return letter.toUpperCase();
                                })
                                enabled: !backend.busy
                                onClicked: backend.applyPreset(presetButton.modelData)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: backend.installed

                    Kirigami.Icon {
                        source: backend.bootPersistence && backend.resumePersistence ? "security-high" : "security-low"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: implicitWidth
                        color: backend.bootPersistence && backend.resumePersistence ? palette.success : palette.warning
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: backend.bootPersistence && backend.resumePersistence ? "Persistent after restart and resume" : "Persistence is not fully enabled"
                        color: backend.bootPersistence && backend.resumePersistence ? palette.success : palette.warning
                    }

                    PlasmaComponents3.Button {
                        text: backend.bootPersistence && backend.resumePersistence ? "Disable" : "Enable"
                        enabled: !backend.busy
                        onClicked: backend.setPersistence(!(backend.bootPersistence && backend.resumePersistence))
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !backend.installed

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "The bundled batctl binary is missing. Reinstall Batctl Battery Manager to repair the installation."
                    }
                }

                PlasmaComponents3.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    visible: backend.busy
                    running: visible
                }
            }
        }
    }
}
