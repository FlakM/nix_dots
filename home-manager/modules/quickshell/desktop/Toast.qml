import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: toast
    required property var shell

    visible: shell.toastVisible && shell.latestNotification !== null && shell.overlayMode !== "notifications"
    anchors.top: true
    margins.top: 10
    implicitWidth: 540
    implicitHeight: 144
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-toast"

    Rectangle {
        anchors.fill: parent
        radius: 22
        color: "#c9111823"
        border.color: "#8872d7ff"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 18
            color: "transparent"
            border.width: 1
            border.color: "#244b6078"
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: 10
            width: 4
            radius: 2
            gradient: Gradient {
                GradientStop { position: 0; color: "#72d7ff" }
                GradientStop { position: 1; color: "#8ea8ff" }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 16
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 14

            Rectangle {
                property string appIcon: shell.latestNotification?.appIcon || ""
                visible: appIcon !== ""
                Layout.preferredWidth: visible ? 56 : 0
                Layout.preferredHeight: 56
                radius: 18
                color: "#50303d50"
                border.width: 1
                border.color: "#385b718d"

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 38
                    source: parent.visible ? Quickshell.iconPath(parent.appIcon) : ""
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                Text {
                    Layout.fillWidth: true
                    text: shell.latestNotification?.appName || "Notification"
                    color: "#72d7ff"
                    font.pixelSize: 14
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: shell.latestNotification?.summary || "Notification"
                    color: "white"
                    font.pixelSize: 20
                    font.bold: true
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: shell.latestNotification?.body || ""
                    textFormat: Text.PlainText
                    color: "#aeb9cb"
                    font.pixelSize: 16
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                }
            }
            Rectangle {
                Layout.preferredWidth: 34
                Layout.preferredHeight: 34
                radius: 12
                color: closeMouse.containsMouse ? "#35ff7b86" : "#29313d4f"
                Symbol {
                    anchors.centerIn: parent
                    text: "close"
                    color: closeMouse.containsMouse ? "#ff8a8a" : "#8997aa"
                    font.pixelSize: 19
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        shell.latestNotification.dismiss()
                        shell.toastVisible = false
                    }
                }
            }
        }
    }
}
