/*
THESIS: batctl remains the product; this surface removes terminal friction without copying its hardware logic.
OWN-WORLD: native Plasma colors, spacing, typography, controls, and iconography with no independent visual skin.
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
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        PlasmaComponents3.Label {
                            Layout.fillWidth: true
                            text: backend.backend.length > 0 ? backend.backend + " backend" : "Powered by batctl"
                            color: Kirigami.Theme.disabledTextColor
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
                    }

                    Repeater {
                        model: backend.batteries

                        delegate: ColumnLayout {
                            id: batteryDelegate
                            required property var battery
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true

                                PlasmaComponents3.Label {
                                    Layout.fillWidth: true
                                    text: batteryDelegate.battery.name + "  " + batteryDelegate.battery.capacity
                                    font.weight: Font.Medium
                                }

                                PlasmaComponents3.Label {
                                    text: batteryDelegate.battery.status
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }

                            PlasmaComponents3.ProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: parseInt(batteryDelegate.battery.capacity) || 0
                                Accessible.name: batteryDelegate.battery.name + " charge: " + batteryDelegate.battery.capacity
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: "Thresholds"
                                    color: Kirigami.Theme.disabledTextColor
                                }
                                PlasmaComponents3.Label {
                                    text: batteryDelegate.battery.startThreshold !== undefined && batteryDelegate.battery.stopThreshold !== undefined ? batteryDelegate.battery.startThreshold + "–" + batteryDelegate.battery.stopThreshold + "%" : batteryDelegate.battery.stopThreshold !== undefined ? "Stop at " + batteryDelegate.battery.stopThreshold + "%" : "Not exposed"
                                }
                                PlasmaComponents3.Label {
                                    text: "Health"
                                    color: Kirigami.Theme.disabledTextColor
                                }
                                PlasmaComponents3.Label {
                                    text: batteryDelegate.battery.health + " · " + batteryDelegate.battery.cycles + " cycles"
                                }
                                PlasmaComponents3.Label {
                                    text: "Behaviour"
                                    color: Kirigami.Theme.disabledTextColor
                                }
                                PlasmaComponents3.Label {
                                    text: batteryDelegate.battery.behaviour
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
                                required property string preset
                                Layout.fillWidth: true
                                text: presetButton.preset.replace(/-/g, " ").replace(/\b\w/g, function (letter) {
                                    return letter.toUpperCase();
                                })
                                enabled: !backend.busy
                                onClicked: backend.applyPreset(presetButton.preset)
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
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: backend.bootPersistence && backend.resumePersistence ? "Persistent after restart and resume" : "Persistence is not fully enabled"
                        color: Kirigami.Theme.disabledTextColor
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
