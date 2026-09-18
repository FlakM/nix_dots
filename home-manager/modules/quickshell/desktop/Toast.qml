import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: toast
    required property var shell

    visible: shell.toastNotifications.length > 0 && shell.overlayMode !== "notifications"
    anchors.top: true
    margins.top: 10
    implicitWidth: 620
    implicitHeight: Math.min(shell.toastNotifications.length, 5) * 190 - 10
    exclusiveZone: 0
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-toast"

    ListView {
        id: toastList
        anchors.fill: parent
        model: shell.toastNotifications
        spacing: 10
        clip: true

        delegate: Rectangle {
            required property var modelData
            property var notification: modelData.notification

            width: toastList.width
            height: 180
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
                    property string appIcon: notification.appIcon || ""
                    property string notificationImage: notification.image || ""
                    visible: notificationImage !== "" || appIcon !== ""
                    Layout.preferredWidth: notificationImage !== "" ? 132 : visible ? 56 : 0
                    Layout.preferredHeight: notificationImage !== "" ? 132 : 56
                    radius: 18
                    color: "#50303d50"
                    border.width: 1
                    border.color: "#385b718d"
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: parent.notificationImage
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: parent.notificationImage !== ""
                    }

                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 38
                        source: parent.notificationImage === "" && parent.appIcon !== "" ? Quickshell.iconPath(parent.appIcon) : ""
                        visible: parent.notificationImage === "" && parent.appIcon !== ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    Text {
                        Layout.fillWidth: true
                        text: notification.appName || "Notification"
                        color: "#72d7ff"
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: notification.summary || "Notification"
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true
                        text: shell.renderNotificationBody(notification.body || "")
                        textFormat: Text.RichText
                        color: "#aeb9cb"
                        linkColor: "#72d7ff"
                        font.pixelSize: 16
                        maximumLineCount: 4
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        onLinkActivated: link => Qt.openUrlExternally(link)
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
                        onClicked: shell.dismissToast(notification)
                    }
                }
            }
        }
    }
}
