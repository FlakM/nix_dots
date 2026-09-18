import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var shell

    visible: shell.overlayMode === "tasks"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#9905080e"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var project: shell.vikunjaPinnedProject
    readonly property var projectTasks: shell.vikunjaTasks.filter(task => task.project_id === project?.id)

    function dueText(task) {
        if (!task.due_date || task.due_date.startsWith("0001-")) return "No due date"
        return new Date(task.due_date).toLocaleString(Qt.locale(), Locale.ShortFormat)
    }

    function priorityColor(priority) {
        if (priority >= 4) return "#ff7b86"
        if (priority >= 2) return "#f6c177"
        return "#72e4ae"
    }

    onVisibleChanged: {
        if (!visible) return
        keyHandler.forceActiveFocus()
        shell.refreshVikunja()
    }

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
            GradientStop { position: 0; color: "#fa20332f" }
            GradientStop { position: 0.45; color: "#fa18221f" }
            GradientStop { position: 1; color: "#fa101815" }
        }
        border.width: 1
        border.color: "#597d70"
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
                    color: "#2672e4ae"
                    Symbol {
                        anchors.centerIn: parent
                        text: "task_alt"
                        color: "#72e4ae"
                        fill: 1
                        font.pixelSize: 34
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Vikunja"; color: "#f5f8fd"; font.pixelSize: 31; font.bold: true }
                    Text {
                        text: shell.vikunjaLoading ? "Refreshing tasks..."
                            : shell.vikunjaError ? shell.vikunjaError
                            : `${panel.project?.title || "Pinned project"} · ${panel.projectTasks.length} open tasks`
                        color: shell.vikunjaError ? "#ff8d98" : "#9bb5aa"
                        font.pixelSize: 15
                    }
                }
                IconButton {
                    icon: "open_in_new"
                    tooltip: "Open Vikunja"
                    onClicked: Qt.openUrlExternally("https://tasks.house.flakm.com/")
                }
                IconButton {
                    icon: "refresh"
                    tooltip: "Refresh tasks"
                    active: shell.vikunjaLoading
                    onClicked: shell.refreshVikunja()
                }
                IconButton {
                    icon: "close"
                    tooltip: "Close"
                    onClicked: panel.shell.overlayMode = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 126
                    radius: 24
                    color: "#2d3b36"
                    border.width: 1
                    border.color: "#6672e4ae"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 22
                        spacing: 18
                        Rectangle {
                            Layout.preferredWidth: 68
                            Layout.preferredHeight: 68
                            radius: 22
                            color: "#2872e4ae"
                            Symbol { anchors.centerIn: parent; text: "home_work"; color: "#72e4ae"; fill: 1; font.pixelSize: 34 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: panel.project?.title || "Pinned project"
                                    color: "#f3f8f5"
                                    font.pixelSize: 22
                                    font.bold: true
                                }
                                Symbol { text: "keep"; color: "#72e4ae"; fill: 1; font.pixelSize: 18 }
                                Item { Layout.fillWidth: true }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: panel.project?.description || "Your pinned Vikunja project"
                                color: "#a5b8b0"
                                font.pixelSize: 13
                                elide: Text.ElideRight
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text { text: panel.projectTasks.length; color: "#f3f8f5"; font.pixelSize: 30; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                            Text { text: "OPEN"; color: "#72e4ae"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1.2; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(`https://tasks.house.flakm.com/projects/${panel.project?.id}`)
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 142
                    Layout.preferredHeight: 126
                    radius: 24
                    color: "#292f3a"
                    border.width: 1
                    border.color: "#3f5261"
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 5
                        Symbol { text: "checklist"; color: "#72d7ff"; font.pixelSize: 27; Layout.alignment: Qt.AlignHCenter }
                        Text { text: shell.vikunjaTaskCount; color: "#f2f6fc"; font.pixelSize: 23; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "ALL TASKS"; color: "#8298aa"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "OPEN TASKS"; color: "#789386"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                Item { Layout.fillWidth: true }
                Text { text: "Click a task to open it"; color: "#789386"; font.pixelSize: 12 }
            }

            ListView {
                id: taskList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 9
                clip: true
                model: panel.projectTasks

                delegate: Rectangle {
                    id: taskRow
                    required property var modelData
                    width: taskList.width
                    height: 84
                    radius: 20
                    color: taskMouse.containsMouse ? "#303b3a" : "#222b2a"
                    border.width: 1
                    border.color: taskMouse.containsMouse ? "#527d70" : "#344641"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 14

                        Rectangle {
                            Layout.preferredWidth: 46
                            Layout.preferredHeight: 46
                            radius: 14
                            color: Qt.alpha(panel.priorityColor(modelData.priority), 0.14)
                            Symbol {
                                anchors.centerIn: parent
                                text: modelData.priority >= 2 ? "priority_high" : "assignment"
                                color: panel.priorityColor(modelData.priority)
                                fill: modelData.priority >= 2 ? 1 : 0
                                font.pixelSize: 24
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: "#eef4f2"
                                font.pixelSize: 16
                                font.bold: true
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: `${modelData.project_title} · ${panel.dueText(modelData)}`
                                color: "#8ca098"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        IconButton {
                            icon: "check"
                            tooltip: "Mark complete"
                            accent: "#72e4ae"
                            onClicked: panel.shell.completeVikunjaTask(modelData.id)
                        }
                    }

                    MouseArea {
                        id: taskMouse
                        anchors.fill: parent
                        z: -1
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally(`https://tasks.house.flakm.com/tasks/${modelData.id}`)
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !shell.vikunjaLoading && taskList.count === 0
                    text: shell.vikunjaError || "Everything is done"
                    color: "#93a79f"
                    font.pixelSize: 18
                }
            }
        }
    }
}
