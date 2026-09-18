import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland

PanelWindow {
    id: panel
    required property var shell

    visible: shell.overlayMode === "audio"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#9905080e"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property var output: Pipewire.defaultAudioSink
    readonly property var input: Pipewire.defaultAudioSource
    readonly property var outputs: Pipewire.nodes.values.filter(node => !node.isStream && node.isSink && node.audio)
    readonly property var inputs: Pipewire.nodes.values.filter(node => !node.isStream && !node.isSink && node.audio)

    function nodeName(node) {
        return node?.description || node?.nickname || node?.name || "Unknown device"
    }

    function setVolume(node, value) {
        if (!node?.audio) return
        node.audio.muted = false
        node.audio.volume = Math.max(0, Math.min(1.5, value))
    }

    onVisibleChanged: if (visible) keyHandler.forceActiveFocus()

    PwObjectTracker {
        objects: [panel.output, panel.input, ...panel.outputs, ...panel.inputs].filter(node => node)
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
            GradientStop { position: 0; color: "#fa292338" }
            GradientStop { position: 0.45; color: "#fa1b1d2b" }
            GradientStop { position: 1; color: "#fa11151f" }
        }
        border.width: 1
        border.color: "#6f6683a5"
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
                    color: "#306d5cff"
                    Symbol {
                        anchors.centerIn: parent
                        text: "graphic_eq"
                        color: "#b5a8ff"
                        fill: 1
                        font.pixelSize: 34
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    Text { text: "Sound"; color: "#f5f8fd"; font.pixelSize: 31; font.bold: true }
                    Text {
                        text: `${panel.nodeName(panel.output)} · ${panel.nodeName(panel.input)}`
                        color: "#a29bb5"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                IconButton {
                    icon: "settings"
                    tooltip: "Open advanced sound settings"
                    onClicked: Quickshell.execDetached(["pavucontrol"])
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
                    Layout.preferredHeight: 142
                    radius: 24
                    color: "#303b3653"
                    border.width: 1
                    border.color: "#666d5cff"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            Symbol {
                                text: panel.output?.audio?.muted ? "volume_off" : "volume_up"
                                color: panel.output?.audio?.muted ? "#ff8d98" : "#b5a8ff"
                                fill: 1
                                font.pixelSize: 29
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: "OUTPUT"; color: "#8f86a4"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                                Text { text: panel.nodeName(panel.output); color: "#eef2fa"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Text {
                                text: `${Math.round((panel.output?.audio?.volume || 0) * 100)}%`
                                color: "#dcd6ed"
                                font.pixelSize: 16
                                font.bold: true
                            }
                            IconButton {
                                icon: panel.output?.audio?.muted ? "volume_off" : "volume_up"
                                active: panel.output?.audio?.muted || false
                                accent: "#ff8d98"
                                tooltip: panel.output?.audio?.muted ? "Unmute output" : "Mute output"
                                onClicked: if (panel.output?.audio) panel.output.audio.muted = !panel.output.audio.muted
                            }
                        }
                        Rectangle {
                            id: outputTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            radius: 5
                            color: "#394356"
                            Rectangle {
                                width: parent.width * Math.min(1, (panel.output?.audio?.volume || 0) / 1.5)
                                height: parent.height
                                radius: parent.radius
                                color: "#b5a8ff"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: event => panel.setVolume(panel.output, event.x / width * 1.5)
                                onPositionChanged: event => { if (pressed) panel.setVolume(panel.output, event.x / width * 1.5) }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 142
                    radius: 24
                    color: "#30343d4d"
                    border.width: 1
                    border.color: "#60577786"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 12
                        RowLayout {
                            Layout.fillWidth: true
                            Symbol {
                                text: panel.input?.audio?.muted ? "mic_off" : "mic"
                                color: panel.input?.audio?.muted ? "#ff8d98" : "#72d7ff"
                                fill: 1
                                font.pixelSize: 29
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text { text: "INPUT"; color: "#8099ad"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                                Text { text: panel.nodeName(panel.input); color: "#eef2fa"; font.pixelSize: 15; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                            }
                            Text {
                                text: `${Math.round((panel.input?.audio?.volume || 0) * 100)}%`
                                color: "#d7e1ed"
                                font.pixelSize: 16
                                font.bold: true
                            }
                            IconButton {
                                icon: panel.input?.audio?.muted ? "mic_off" : "mic"
                                active: panel.input?.audio?.muted || false
                                accent: "#ff8d98"
                                tooltip: panel.input?.audio?.muted ? "Unmute microphone" : "Mute microphone"
                                onClicked: if (panel.input?.audio) panel.input.audio.muted = !panel.input.audio.muted
                            }
                        }
                        Rectangle {
                            id: inputTrack
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            radius: 5
                            color: "#394356"
                            Rectangle {
                                width: parent.width * Math.min(1, (panel.input?.audio?.volume || 0) / 1.5)
                                height: parent.height
                                radius: parent.radius
                                color: "#72d7ff"
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onPressed: event => panel.setVolume(panel.input, event.x / width * 1.5)
                                onPositionChanged: event => { if (pressed) panel.setVolume(panel.input, event.x / width * 1.5) }
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    Text { text: "OUTPUT DEVICES"; color: "#8f86a4"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                    ListView {
                        id: outputList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        clip: true
                        model: panel.outputs
                        delegate: Rectangle {
                            required property var modelData
                            width: outputList.width
                            height: 76
                            radius: 19
                            color: modelData === panel.output ? "#354d4767" : outputMouse.containsMouse ? "#30394a" : "#222936"
                            border.width: 1
                            border.color: modelData === panel.output ? "#76b5a8ff" : "#303b4d"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 12
                                Rectangle {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 46
                                    radius: 15
                                    color: modelData === panel.output ? "#35b5a8ff" : "#293446"
                                    Symbol { anchors.centerIn: parent; text: (modelData.name || "").includes("bluez") ? "headphones" : "speaker"; color: modelData === panel.output ? "#c9c0ff" : "#b6c2d4"; fill: modelData === panel.output ? 1 : 0; font.pixelSize: 25 }
                                }
                                Text { Layout.fillWidth: true; text: panel.nodeName(modelData); color: "#edf3fc"; font.pixelSize: 14; font.bold: modelData === panel.output; elide: Text.ElideRight }
                                Symbol { visible: modelData === panel.output; text: "check_circle"; color: "#b5a8ff"; fill: 1; font.pixelSize: 23 }
                            }
                            MouseArea { id: outputMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Pipewire.preferredDefaultAudioSink = modelData }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    Text { text: "INPUT DEVICES"; color: "#8099ad"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.2 }
                    ListView {
                        id: inputList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        clip: true
                        model: panel.inputs
                        delegate: Rectangle {
                            required property var modelData
                            width: inputList.width
                            height: 76
                            radius: 19
                            color: modelData === panel.input ? "#3044535d" : inputMouse.containsMouse ? "#30394a" : "#222936"
                            border.width: 1
                            border.color: modelData === panel.input ? "#6672d7ff" : "#303b4d"
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 13
                                spacing: 12
                                Rectangle {
                                    Layout.preferredWidth: 46
                                    Layout.preferredHeight: 46
                                    radius: 15
                                    color: modelData === panel.input ? "#3572d7ff" : "#293446"
                                    Symbol { anchors.centerIn: parent; text: "mic"; color: modelData === panel.input ? "#a8e5ff" : "#b6c2d4"; fill: modelData === panel.input ? 1 : 0; font.pixelSize: 25 }
                                }
                                Text { Layout.fillWidth: true; text: panel.nodeName(modelData); color: "#edf3fc"; font.pixelSize: 14; font.bold: modelData === panel.input; elide: Text.ElideRight }
                                Symbol { visible: modelData === panel.input; text: "check_circle"; color: "#72d7ff"; fill: 1; font.pixelSize: 23 }
                            }
                            MouseArea { id: inputMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: Pipewire.preferredDefaultAudioSource = modelData }
                        }
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Scroll the bar volume to adjust · Right click opens pavucontrol"
                color: "#716d82"
                font.pixelSize: 11
            }
        }
    }
}
