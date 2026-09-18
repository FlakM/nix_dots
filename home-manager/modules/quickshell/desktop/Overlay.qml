import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: overlay
    required property var shell
    required property var notifications

    visible: ["launcher", "clipboard", "notifications"].includes(shell.overlayMode)
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: shell.overlayMode === "notifications" ? "#7005080e" : "#b0080810"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    WlrLayershell.namespace: "quickshell-overlay"

    property var applications: [...DesktopEntries.applications.values]
        .filter(entry => {
            const query = search.text.toLowerCase()
            const searchable = `${entry.name} ${entry.genericName} ${entry.comment} ${entry.keywords}`.toLowerCase()
            return !query || searchable.includes(query)
        })
        .slice(0, 40)
    property var clipboardEntries: []
    property int selectedIndex: 0

    function activateSelected() {
        const items = shell.overlayMode === "launcher" ? applications : clipboardEntries
        if (selectedIndex < 0 || selectedIndex >= items.length) return
        if (shell.overlayMode === "launcher") items[selectedIndex].execute()
        else Quickshell.execDetached(["quickshell-clipboard", "copy", items[selectedIndex].id, items[selectedIndex].mime])
        shell.overlayMode = ""
    }

    onVisibleChanged: {
        if (!visible) return
        search.text = ""
        search.forceActiveFocus()
        selectedIndex = 0
        if (shell.overlayMode === "clipboard") clipboardProcess.running = true
    }

    Process {
        id: clipboardProcess
        command: ["quickshell-clipboard", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    overlay.clipboardEntries = JSON.parse(text)
                    overlay.selectedIndex = 0
                } catch (error) {
                    console.warn("Unable to parse clipboard history:", error)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: shell.overlayMode = ""
    }

    Rectangle {
        width: Math.min(920, overlay.width - 80)
        height: Math.min(760, overlay.height - 120)
        anchors.centerIn: parent
        radius: 28
        color: shell.overlayMode === "notifications" ? "#d3131824" : "#f3131824"
        border.color: shell.overlayMode === "notifications" ? "#7072d7ff" : "#665ecfff"
        border.width: 2

        MouseArea { anchors.fill: parent; onClicked: event => event.accepted = true }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 14

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: shell.overlayMode === "launcher" ? "Applications" : shell.overlayMode === "clipboard" ? "Clipboard" : "Notifications"
                    color: "white"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 26
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                Text {
                    visible: shell.overlayMode === "clipboard"
                    text: "Clear history"
                    color: "#ff8a8a"
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Quickshell.execDetached(["quickshell-clipboard", "clear"])
                            overlay.clipboardEntries = []
                        }
                    }
                }
                Text {
                    visible: shell.overlayMode === "notifications" && notifications.trackedNotifications.values.length > 0
                    text: "Clear all"
                    color: "#ff8a8a"
                    font.pixelSize: 16
                    MouseArea {
                        anchors.fill: parent
                        onClicked: notifications.trackedNotifications.values.forEach(notification => notification.dismiss())
                    }
                }
            }

            Rectangle {
                visible: shell.overlayMode !== "notifications"
                Layout.fillWidth: true
                implicitHeight: 56
                radius: 16
                color: "#252b3a"
                border.color: search.activeFocus ? "#72d7ff" : "#354158"

                Symbol {
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    text: "search"
                    color: "#72d7ff"
                    font.pixelSize: 23
                }

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 48
                    anchors.rightMargin: 14
                    anchors.topMargin: 12
                    anchors.bottomMargin: 12
                    color: "white"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 19
                    clip: true
                    onTextChanged: overlay.selectedIndex = 0
                    Keys.onPressed: event => {
                        const count = shell.overlayMode === "launcher" ? overlay.applications.length : overlay.clipboardEntries.length
                        if (event.key === Qt.Key_Escape) shell.overlayMode = ""
                        else if (event.key === Qt.Key_Down) overlay.selectedIndex = Math.min(count - 1, overlay.selectedIndex + 1)
                        else if (event.key === Qt.Key_Up) overlay.selectedIndex = Math.max(0, overlay.selectedIndex - 1)
                        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) overlay.activateSelected()
                    }
                }
            }

            ListView {
                id: results
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6
                clip: true
                model: shell.overlayMode === "launcher" ? overlay.applications
                    : shell.overlayMode === "clipboard" ? overlay.clipboardEntries
                    : notifications.trackedNotifications
                currentIndex: overlay.selectedIndex

                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: results.width
                    height: shell.overlayMode === "notifications" ? 124
                        : shell.overlayMode === "launcher" ? 70
                        : modelData.type === "image" ? 110 : 60
                    radius: 15
                    color: shell.overlayMode === "notifications" ? "#b51d2634"
                        : index === overlay.selectedIndex ? "#40506b86" : "#202634"
                    border.width: shell.overlayMode === "notifications" || index === overlay.selectedIndex ? 1 : 0
                    border.color: shell.overlayMode === "notifications" ? "#354b6078" : "#72d7ff"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 12

                        IconImage {
                            visible: shell.overlayMode === "launcher"
                            implicitSize: 42
                            source: visible ? Quickshell.iconPath(modelData.icon, "application-x-executable") : ""
                        }
                        Rectangle {
                            property string appIcon: modelData.appIcon || ""
                            visible: shell.overlayMode === "notifications"
                            Layout.preferredWidth: visible ? 52 : 0
                            Layout.preferredHeight: 52
                            radius: 16
                            color: "#40303d50"
                            border.width: 1
                            border.color: "#305b718d"
                            IconImage {
                                visible: parent.appIcon !== ""
                                anchors.centerIn: parent
                                implicitSize: 34
                                source: visible ? Quickshell.iconPath(parent.appIcon) : ""
                            }
                            Symbol {
                                visible: parent.appIcon === ""
                                anchors.centerIn: parent
                                text: "notifications"
                                color: "#72d7ff"
                                font.pixelSize: 25
                            }
                        }
                        Rectangle {
                            visible: shell.overlayMode === "clipboard" && modelData.type === "image"
                            Layout.preferredWidth: visible ? 90 : 0
                            Layout.fillHeight: true
                            radius: 10
                            color: "#151a24"
                            clip: true

                            Image {
                                anchors.fill: parent
                                anchors.margins: 4
                                source: parent.visible ? `file://${modelData.preview}` : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: shell.overlayMode === "launcher" ? (modelData.name || "")
                                    : shell.overlayMode === "clipboard" ? (modelData.text || "")
                                    : (modelData.summary || "")
                                color: "white"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: shell.overlayMode === "notifications" ? 20 : 17
                                font.bold: shell.overlayMode !== "clipboard"
                                elide: Text.ElideRight
                            }
                            Text {
                                visible: shell.overlayMode === "notifications" || shell.overlayMode === "launcher"
                                Layout.fillWidth: true
                                text: shell.overlayMode === "launcher" ? (modelData.genericName || modelData.comment || "") : visible ? (modelData.body || "") : ""
                                textFormat: Text.PlainText
                                color: "#929eb3"
                                font.pixelSize: shell.overlayMode === "notifications" ? 16 : 13
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                                elide: Text.ElideRight
                            }
                        }
                        Symbol {
                            visible: shell.overlayMode === "notifications"
                            text: "close"
                            color: "#ff8a8a"
                            font.pixelSize: 21
                            MouseArea { anchors.fill: parent; onClicked: modelData.dismiss() }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        z: -1
                        onClicked: {
                            overlay.selectedIndex = index
                            if (shell.overlayMode !== "notifications") overlay.activateSelected()
                        }
                    }
                }

                Text {
                    visible: shell.overlayMode === "notifications" && results.count === 0
                    anchors.centerIn: parent
                    text: "You're all caught up"
                    color: "#93a2b8"
                    font.pixelSize: 18
                }
            }

            Text {
                visible: shell.overlayMode !== "notifications"
                Layout.alignment: Qt.AlignHCenter
                text: "↑↓ navigate    Enter select    Esc close"
                color: "#738096"
                font.family: "FiraCode Nerd Font"
                font.pixelSize: 12
            }
        }
    }
}
