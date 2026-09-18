import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var shell

    visible: shell.overlayMode === "tailscale"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#9905080e"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-overlay"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int onlinePeers: shell.tailscaleState.peers.filter(peer => peer.online).length

    onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

    MouseArea { anchors.fill: parent; onClicked: shell.overlayMode = "" }
    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: shell.overlayMode = ""
    }

    Rectangle {
        width: Math.min(760, panel.width - 48)
        height: Math.min(900, panel.height - 104)
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 84
        anchors.rightMargin: 24
        radius: 32
        color: "#f5161c28"
        gradient: Gradient {
            GradientStop { position: 0; color: "#fa20332f" }
            GradientStop { position: 0.5; color: "#fa171f28" }
            GradientStop { position: 1; color: "#fa10151f" }
        }
        border.width: 1
        border.color: "#526f70"
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
                    color: shell.tailscaleState.online ? "#2672e4ae" : "#26313d4f"
                    Symbol {
                        anchors.centerIn: parent
                        text: shell.tailscaleState.online ? "device_hub" : "hub_off"
                        color: shell.tailscaleState.online ? "#72e4ae" : "#8794a8"
                        fill: shell.tailscaleState.online ? 1 : 0
                        font.pixelSize: 34
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Tailscale"; color: "#f5f8fd"; font.pixelSize: 31; font.bold: true }
                    Text { text: shell.tailscaleState.online ? `${panel.onlinePeers} peers online` : "Private network disconnected"; color: "#93a2b8"; font.pixelSize: 15 }
                }
                IconButton { icon: "refresh"; tooltip: "Refresh status"; onClicked: panel.shell.refreshTailscale() }
                IconButton { icon: "open_in_new"; tooltip: "Open Tailscale admin"; onClicked: Quickshell.execDetached(["xdg-open", "https://login.tailscale.com/admin/machines"]) }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 122
                radius: 24
                color: shell.tailscaleState.online ? "#30364b45" : "#302d323e"
                border.width: 1
                border.color: shell.tailscaleState.online ? "#6072e4ae" : "#485469"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18
                    Symbol { text: "computer"; color: shell.tailscaleState.online ? "#72e4ae" : "#8794a8"; fill: 1; font.pixelSize: 34 }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text { text: shell.tailscaleState.name; color: "#f2f5fa"; font.pixelSize: 19; font.bold: true }
                        Text { text: shell.tailscaleState.ip || "No Tailscale address"; color: "#91a0b5"; font.pixelSize: 14 }
                    }
                    Rectangle {
                        Layout.preferredWidth: 76
                        Layout.preferredHeight: 38
                        radius: 19
                        color: shell.tailscaleState.online ? "#72e4ae" : "#465369"
                        opacity: shell.tailscaleLoading ? 0.5 : 1
                        Rectangle {
                            width: 30
                            height: 30
                            radius: 15
                            y: 4
                            x: shell.tailscaleState.online ? 42 : 4
                            color: shell.tailscaleState.online ? "#071510" : "#d6deea"
                            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !shell.tailscaleLoading
                            cursorShape: Qt.PointingHandCursor
                            onClicked: shell.setTailscaleOnline(!shell.tailscaleState.online)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "DEVICES"; color: "#8392a8"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.4 }
                Item { Layout.fillWidth: true }
                Text { text: `${panel.onlinePeers} online · ${shell.tailscaleState.peers.length} known`; color: "#69788e"; font.pixelSize: 12 }
            }

            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: shell.tailscaleState.peers
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 76
                            radius: 19
                            color: "#28313f"
                            border.width: 1
                            border.color: modelData.online ? "#45685d" : "#384559"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 15
                                Rectangle {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42
                                    radius: 14
                                    color: modelData.online ? "#24483d" : "#303947"
                                    Symbol {
                                        anchors.centerIn: parent
                                        text: modelData.os === "android" || modelData.os === "iOS" ? "smartphone" : "computer"
                                        color: modelData.online ? "#72e4ae" : "#77869b"
                                        font.pixelSize: 23
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: modelData.name; color: modelData.online ? "#edf2f9" : "#a5b0c0"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: `${modelData.ip}${modelData.os ? ` · ${modelData.os}` : ""}`; color: "#78889f"; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                                Rectangle { Layout.preferredWidth: 9; Layout.preferredHeight: 9; radius: 5; color: modelData.online ? "#72e4ae" : "#556276" }
                            }
                        }
                    }
                }
            }
        }
    }
}
