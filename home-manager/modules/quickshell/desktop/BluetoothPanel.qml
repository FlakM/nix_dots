import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: panel
    required property var shell

    visible: shell.overlayMode === "bluetooth"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#9905080e"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: adapter ? [...adapter.devices.values].sort((a, b) =>
        Number(b.connected) - Number(a.connected)
        || Number(b.paired) - Number(a.paired)
        || (a.name || a.address).localeCompare(b.name || b.address)) : []
    readonly property int connectedCount: devices.filter(device => device.connected).length

    function deviceIcon(device) {
        const icon = (device.icon || "").toLowerCase()
        if (icon.includes("headset") || icon.includes("headphone")) return "headphones"
        if (icon.includes("audio") || icon.includes("speaker")) return "speaker"
        if (icon.includes("phone")) return "smartphone"
        if (icon.includes("mouse")) return "mouse"
        if (icon.includes("keyboard")) return "keyboard"
        if (icon.includes("game")) return "sports_esports"
        if (icon.includes("computer")) return "computer"
        return "devices_other"
    }

    function deviceStatus(device) {
        if (device.pairing) return "Pairing…"
        if (device.connected) return device.batteryAvailable ? `Connected · ${Math.round(device.battery * 100)}%` : "Connected"
        if (device.paired) return "Paired"
        return "Available"
    }

    onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

    MouseArea {
        anchors.fill: parent
        onClicked: shell.overlayMode = ""
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: shell.overlayMode = ""
    }

    Rectangle {
        width: Math.min(980, panel.width - 48)
        height: Math.min(980, panel.height - 104)
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 84
        anchors.rightMargin: 24
        radius: 32
        color: "#f5161c28"
        gradient: Gradient {
            GradientStop { position: 0; color: "#fa202a3b" }
            GradientStop { position: 0.45; color: "#fa171d29" }
            GradientStop { position: 1; color: "#fa10151f" }
        }
        border.width: 1
        border.color: "#5b708f"
        clip: true

        MouseArea { anchors.fill: parent; onClicked: event => event.accepted = true }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 20

            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 66
                    Layout.preferredHeight: 66
                    radius: 21
                    color: panel.adapter?.enabled ? "#2672d7ff" : "#26313d4f"
                    Symbol {
                        anchors.centerIn: parent
                        text: panel.adapter?.enabled ? "bluetooth" : "bluetooth_disabled"
                        color: panel.adapter?.enabled ? "#72d7ff" : "#8794a8"
                        fill: panel.connectedCount > 0 ? 1 : 0
                        font.pixelSize: 34
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text {
                        text: "Bluetooth"
                        color: "#f5f8fd"
                        font.pixelSize: 31
                        font.bold: true
                    }
                    Text {
                        text: !panel.adapter ? "No adapter found"
                            : !panel.adapter.enabled ? "Powered off"
                            : panel.connectedCount > 0 ? `${panel.connectedCount} connected`
                            : panel.adapter.discovering ? "Scanning for devices…" : "Ready to connect"
                        color: "#93a2b8"
                        font.pixelSize: 15
                    }
                }

                IconButton {
                    icon: "settings"
                    tooltip: "Open Blueman"
                    onClicked: Quickshell.execDetached(["blueman-manager"])
                }
                IconButton {
                    icon: "close"
                    tooltip: "Close"
                    onClicked: panel.shell.overlayMode = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 104
                    radius: 22
                    color: panel.adapter?.enabled ? "#304263" : "#202632"
                    border.width: 1
                    border.color: panel.adapter?.enabled ? "#5472d7ff" : "#354158"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 16
                        Symbol {
                            text: panel.adapter?.enabled ? "bluetooth_connected" : "bluetooth_disabled"
                            color: panel.adapter?.enabled ? "#72d7ff" : "#8794a8"
                            fill: panel.adapter?.enabled ? 1 : 0
                            font.pixelSize: 30
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Text { text: "Bluetooth radio"; color: "#ecf2fb"; font.pixelSize: 17; font.bold: true }
                            Text { text: panel.adapter?.enabled ? "Visible and ready to connect" : "Turn on to connect devices"; color: "#a5b3c8"; font.pixelSize: 13 }
                        }
                        Rectangle {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 26
                            radius: 13
                            color: panel.adapter?.enabled ? "#72d7ff" : "#465369"
                            Rectangle {
                                width: 20
                                height: 20
                                radius: 10
                                y: 3
                                x: panel.adapter?.enabled ? 23 : 3
                                color: panel.adapter?.enabled ? "#071018" : "#d6deea"
                                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (panel.adapter) panel.adapter.enabled = !panel.adapter.enabled
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 310
                    Layout.preferredHeight: 104
                    radius: 22
                    color: panel.adapter?.discovering ? "#294b4a3f" : "#252c3a"
                    border.width: 1
                    border.color: panel.adapter?.discovering ? "#6072e4ae" : "#354158"
                    opacity: panel.adapter?.enabled ? 1 : 0.45

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 13
                        Symbol {
                            text: panel.adapter?.discovering ? "radar" : "search"
                            color: panel.adapter?.discovering ? "#72e4ae" : "#c5d0e0"
                            font.pixelSize: 28
                            RotationAnimation on rotation {
                                running: panel.adapter?.discovering || false
                                from: 0
                                to: 360
                                duration: 1800
                                loops: Animation.Infinite
                            }
                        }
                        Text {
                            text: panel.adapter?.discovering ? "Stop scan" : "Scan"
                            color: "#e8eef8"
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: panel.adapter?.enabled || false
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: panel.adapter.discovering = !panel.adapter.discovering
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: panel.connectedCount > 0 ? "DEVICES" : "AVAILABLE DEVICES"
                    color: "#7f90a8"
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.4
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: `${panel.devices.length} found`
                    color: "#7f90a8"
                    font.pixelSize: 12
                }
            }

            GridView {
                id: deviceList
                Layout.fillWidth: true
                Layout.fillHeight: true
                cellWidth: width / 2
                cellHeight: 116
                clip: true
                model: panel.devices

                delegate: Rectangle {
                    id: deviceRow
                    required property var modelData
                    width: deviceList.cellWidth - 8
                    height: 104
                    radius: 22
                    color: modelData.connected ? "#30465c55" : rowMouse.containsMouse ? "#30394a" : "#222936"
                    border.width: 1
                    border.color: modelData.connected ? "#6072e4ae" : rowMouse.containsMouse ? "#52647f" : "#303b4d"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 15
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 58
                            Layout.preferredHeight: 58
                            radius: 19
                            color: modelData.connected ? "#2872e4ae" : "#293446"
                            Symbol {
                                anchors.centerIn: parent
                                text: panel.deviceIcon(deviceRow.modelData)
                                color: modelData.connected ? "#72e4ae" : "#b6c2d4"
                                fill: modelData.connected ? 1 : 0
                                font.pixelSize: 30
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: modelData.name || modelData.deviceName || modelData.address
                                color: "#edf3fc"
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                text: panel.deviceStatus(deviceRow.modelData)
                                color: modelData.connected ? "#72e4ae" : "#8f9eb4"
                                font.pixelSize: 13
                            }
                        }

                        Rectangle {
                            visible: modelData.batteryAvailable
                            Layout.preferredWidth: 70
                            Layout.preferredHeight: 32
                            radius: 10
                            color: "#293446"
                            Row {
                                anchors.centerIn: parent
                                spacing: 4
                                Symbol {
                                    text: modelData.battery < 0.2 ? "battery_alert" : "battery_full"
                                    color: modelData.battery < 0.2 ? "#ff7b86" : "#9fb0c6"
                                    font.pixelSize: 17
                                }
                                Text {
                                    text: `${Math.round(modelData.battery * 100)}%`
                                    color: "#c8d3e2"
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }

                        IconButton {
                            visible: modelData.paired && !modelData.connected
                            icon: "delete"
                            tooltip: "Forget device"
                            onClicked: modelData.forget()
                        }
                        IconButton {
                            icon: modelData.connected ? "link_off" : modelData.pairing ? "progress_activity" : "link"
                            active: modelData.connected
                            accent: "#72e4ae"
                            tooltip: modelData.connected ? "Disconnect" : modelData.paired ? "Connect" : "Pair"
                            onClicked: {
                                if (modelData.connected) modelData.disconnect()
                                else if (modelData.paired) modelData.connect()
                                else modelData.pair()
                            }
                        }
                    }

                    MouseArea {
                        id: rowMouse
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                }

                Text {
                    visible: panel.devices.length === 0
                    anchors.centerIn: parent
                    width: parent.width - 60
                    horizontalAlignment: Text.AlignHCenter
                    text: !panel.adapter ? "No Bluetooth adapter was found"
                        : !panel.adapter.enabled ? "Turn Bluetooth on to see devices"
                        : panel.adapter.discovering ? "Looking for nearby devices…"
                        : "No devices found. Start a scan or open Blueman for advanced pairing."
                    color: "#8392a8"
                    font.pixelSize: 14
                    wrapMode: Text.Wrap
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Esc closes · Devices are sorted by connection and pairing status"
                color: "#67768c"
                font.pixelSize: 11
            }
        }
    }
}
