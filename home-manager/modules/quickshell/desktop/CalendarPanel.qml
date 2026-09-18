import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var shell

    visible: shell.overlayMode === "calendar"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#9905080e"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-overlay"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function calendarName(value) {
        if (value.includes("coralogix")) return "Work"
        if (value.includes("group.calendar.google.com")) return "Personal"
        return value
    }

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
            GradientStop { position: 0; color: "#fa202b3c" }
            GradientStop { position: 0.5; color: "#fa171d29" }
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
                    color: "#2672d7ff"
                    Symbol { anchors.centerIn: parent; text: "calendar_month"; color: "#72d7ff"; fill: 1; font.pixelSize: 34 }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Agenda"; color: "#f5f8fd"; font.pixelSize: 31; font.bold: true }
                    Text { text: Qt.formatDate(new Date(), "dddd, d MMMM"); color: "#93a2b8"; font.pixelSize: 15 }
                }
                IconButton { icon: "refresh"; tooltip: "Refresh agenda"; onClicked: panel.shell.refreshCalendar() }
                IconButton {
                    icon: "open_in_new"
                    tooltip: "Open interactive calendar"
                    onClicked: Quickshell.execDetached(["kitty", "--class", "floating-calendar", "-o", "confirm_os_window_close=0", "-e", "khal", "interactive"])
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 118
                radius: 24
                color: shell.calendarStatus["class"] === "urgent" ? "#303f2632" : "#30314459"
                border.width: 1
                border.color: shell.calendarStatus["class"] === "urgent" ? "#80ff7b86" : "#6072d7ff"
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 18
                    Symbol {
                        text: shell.calendarStatus["class"] === "no-events" ? "event_available" : "event_upcoming"
                        color: shell.calendarStatus["class"] === "urgent" ? "#ff8d98" : "#72d7ff"
                        fill: 1
                        font.pixelSize: 34
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text { text: shell.calendarStatus.title || "No events"; color: "#f2f5fa"; font.pixelSize: 20; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            text: shell.calendarStatus.time ? `${shell.calendarStatus.time} · ${shell.calendarStatus.detail}` : shell.calendarStatus.detail
                            color: shell.calendarStatus["class"] === "urgent" ? "#ff9ca5" : "#a9b5c8"
                            font.pixelSize: 14
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "TODAY & TOMORROW"; color: "#8392a8"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1.4 }
                Item { Layout.fillWidth: true }
                Text { text: `${shell.calendarAgenda.length} events`; color: "#69788e"; font.pixelSize: 12 }
            }

            Controls.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ColumnLayout {
                    width: parent.width
                    spacing: 10
                    Repeater {
                        model: shell.calendarAgenda
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 82
                            radius: 19
                            color: eventMouse.containsMouse ? "#384456" : "#28313f"
                            border.width: 1
                            border.color: "#3b4a60"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 15
                                ColumnLayout {
                                    Layout.preferredWidth: 100
                                    spacing: 1
                                    Text { text: modelData.start || "All day"; color: "#72d7ff"; font.pixelSize: 16; font.bold: true }
                                    Text { text: modelData.end ? `until ${modelData.end}` : modelData.date; color: "#73839a"; font.pixelSize: 11 }
                                }
                                Rectangle { Layout.preferredWidth: 3; Layout.fillHeight: true; radius: 2; color: "#72d7ff" }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Text { text: modelData.title; color: "#edf2f9"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: `${modelData.date} · ${panel.calendarName(modelData.calendar)}`; color: "#8d9bb0"; font.pixelSize: 12; elide: Text.ElideRight; Layout.fillWidth: true }
                                }
                            }
                            MouseArea { id: eventMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
                        }
                    }
                    Item {
                        visible: !shell.calendarLoading && shell.calendarAgenda.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            Symbol { anchors.horizontalCenter: parent.horizontalCenter; text: "event_available"; color: "#66758b"; font.pixelSize: 42 }
                            Text { text: "Nothing scheduled"; color: "#9aa8bb"; font.pixelSize: 15 }
                        }
                    }
                }
            }
        }
    }
}
