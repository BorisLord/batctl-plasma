/*
THESIS: batctl remains the product; this surface removes terminal friction without copying its hardware logic.
OWN-WORLD: native Plasma colors, spacing, typography, controls, and iconography with no independent visual skin.
STORY: inspect actual battery state, choose an offered preset, and immediately verify the applied thresholds.
FIRST VIEWPORT: device identity and refresh lead into battery readings; available presets are the primary actions.
FORM: compact operate-mode system utility, deliberately following the standard Plasma panel-widget pattern.
*/

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasmoid
import "backend" as Backend

PlasmoidItem {
    id: root

    Plasmoid.icon: "battery"
    toolTipMainText: "Battery charge thresholds"
    toolTipSubText: backend.compactText.length > 0
        ? backend.compactText + "%"
        : "Open battery controls"

    Backend.BatctlBackend {
        id: backend
    }

    onExpandedChanged: {
        if (root.expanded) {
            backend.refresh()
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

            PlasmaComponents.Label {
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

        PlasmaComponents.ScrollView {
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

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: backend.product.length > 0 ? backend.product : "Battery manager"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            text: backend.backend.length > 0 ? backend.backend + " backend" : "Powered by batctl"
                            color: Kirigami.Theme.disabledTextColor
                            elide: Text.ElideRight
                        }
                    }

                    PlasmaComponents.ToolButton {
                        icon.name: "view-refresh"
                        text: "Refresh"
                        display: PlasmaComponents.AbstractButton.IconOnly
                        enabled: !backend.busy
                        onClicked: backend.refresh()
                        PlasmaComponents.ToolTip.text: text
                        PlasmaComponents.ToolTip.visible: hovered
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

                    PlasmaComponents.Label {
                        text: "Batteries"
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: backend.batteries

                        delegate: ColumnLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            RowLayout {
                                Layout.fillWidth: true

                                PlasmaComponents.Label {
                                    Layout.fillWidth: true
                                    text: modelData.name + "  " + modelData.capacity
                                    font.weight: Font.Medium
                                }

                                PlasmaComponents.Label {
                                    text: modelData.status
                                    color: Kirigami.Theme.disabledTextColor
                                }
                            }

                            PlasmaComponents.ProgressBar {
                                Layout.fillWidth: true
                                from: 0
                                to: 100
                                value: parseInt(modelData.capacity) || 0
                                Accessible.name: modelData.name + " charge: " + modelData.capacity
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.smallSpacing

                                PlasmaComponents.Label { text: "Thresholds"; color: Kirigami.Theme.disabledTextColor }
                                PlasmaComponents.Label {
                                    text: modelData.startThreshold !== undefined && modelData.stopThreshold !== undefined
                                        ? modelData.startThreshold + "–" + modelData.stopThreshold + "%"
                                        : modelData.stopThreshold !== undefined
                                            ? "Stop at " + modelData.stopThreshold + "%"
                                            : "Not exposed"
                                }
                                PlasmaComponents.Label { text: "Health"; color: Kirigami.Theme.disabledTextColor }
                                PlasmaComponents.Label { text: modelData.health + " · " + modelData.cycles + " cycles" }
                                PlasmaComponents.Label { text: "Behaviour"; color: Kirigami.Theme.disabledTextColor }
                                PlasmaComponents.Label { text: modelData.behaviour }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: backend.installed
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
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

                            delegate: PlasmaComponents.Button {
                                required property string modelData
                                Layout.fillWidth: true
                                text: modelData.replace(/-/g, " ").replace(/\b\w/g, function(letter) { return letter.toUpperCase(); })
                                enabled: !backend.busy
                                onClicked: backend.applyPreset(modelData)
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: backend.installed

                    Kirigami.Icon {
                        source: backend.bootPersistence && backend.resumePersistence
                            ? "security-high"
                            : "security-low"
                        implicitWidth: Kirigami.Units.iconSizes.small
                        implicitHeight: implicitWidth
                    }

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        text: backend.bootPersistence && backend.resumePersistence
                            ? "Persistent after restart and resume"
                            : "Persistence is not fully enabled"
                        color: Kirigami.Theme.disabledTextColor
                    }

                    PlasmaComponents.Button {
                        text: backend.bootPersistence && backend.resumePersistence ? "Disable" : "Enable"
                        enabled: !backend.busy
                        onClicked: backend.setPersistence(!(backend.bootPersistence && backend.resumePersistence))
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !backend.installed

                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        text: "The bundled batctl binary is missing. Reinstall Batctl Battery Manager to repair the installation."
                    }
                }

                PlasmaComponents.BusyIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    visible: backend.busy
                    running: visible
                }
            }
        }
    }
}
