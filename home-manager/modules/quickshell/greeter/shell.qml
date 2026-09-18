import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Greetd

ShellRoot {
    id: root
    property string status: ""
    property string pendingPassword: ""
    property bool authenticating: false

    Connections {
        target: Greetd
        function onAuthMessage(message, error, responseRequired, echoResponse) {
            root.status = error ? message : ""
            if (responseRequired) {
                Greetd.respond(root.pendingPassword)
                root.pendingPassword = ""
            }
        }
        function onAuthFailure(message) {
            root.authenticating = false
            root.status = message || "Authentication failed"
            password.text = ""
            password.forceActiveFocus()
        }
        function onError(error) {
            root.authenticating = false
            root.status = error
        }
        function onReadyToLaunch() {
            Greetd.launch(["@uwsm@", "start", "-F", "--", "@hyprland@"])
        }
    }

    FloatingWindow {
        visible: true
        width: 1280
        height: 720
        title: "Login"
        color: "#0b0d14"

        Image {
            anchors.fill: parent
            source: "@wallpaper@"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.32
        }

        Rectangle {
            width: 430
            height: 390
            anchors.centerIn: parent
            radius: 28
            color: "#ec12121b"
            border.color: "#6633ccff"
            border.width: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 38
                spacing: 18

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "amd-pc"
                    color: "white"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 30
                    font.bold: true
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Hyprland / QuickShell"
                    color: "#8b9bb4"
                    font.family: "FiraCode Nerd Font"
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: "#252536"
                    TextInput {
                        id: username
                        anchors.fill: parent
                        anchors.margins: 12
                        text: "flakm"
                        color: "white"
                        selectByMouse: true
                        font.pixelSize: 17
                        onAccepted: password.forceActiveFocus()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    color: "#252536"
                    border.color: password.activeFocus ? "#33ccff" : "transparent"
                    TextInput {
                        id: password
                        anchors.fill: parent
                        anchors.margins: 12
                        color: "white"
                        echoMode: TextInput.Password
                        font.pixelSize: 17
                        focus: true
                        onAccepted: loginButton.login()
                        Component.onCompleted: forceActiveFocus()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.status !== ""
                    text: root.status
                    color: "#ff7b7b"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Rectangle {
                    id: loginButton
                    Layout.fillWidth: true
                    implicitHeight: 48
                    radius: 12
                    enabled: !root.authenticating
                    color: root.authenticating ? "#4b6070" : loginMouse.containsMouse ? "#62dcff" : "#33ccff"

                    function login() {
                        if (!Greetd.available) {
                            root.status = "Login service unavailable"
                            return
                        }
                        if (!username.text || !password.text) {
                            root.status = "Enter username and password"
                            return
                        }
                        if (root.authenticating) return
                        root.authenticating = true
                        root.status = "Authenticating..."
                        root.pendingPassword = password.text
                        Greetd.createSession(username.text)
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.authenticating ? "Authenticating..." : "Log in"
                        color: "#101018"
                        font.pixelSize: 17
                        font.bold: true
                    }
                    MouseArea {
                        id: loginMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: loginButton.login()
                    }
                }
            }
        }
    }
}
