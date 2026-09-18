import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: cameras
    required property var shell

    visible: shell.overlayMode === "cameras"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#b0080810"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property double previewTimestamp: 0
    onVisibleChanged: {
        if (!visible) return
        previewTimestamp = Date.now()
        keyHandler.forceActiveFocus()
    }

    property var feeds: [
        { id: "front_left", stream: "front_left_desktop", name: "Podjazd" },
        { id: "front_right", stream: "front_right_desktop", name: "Podjazd prawy" },
        { id: "back", stream: "back_desktop", name: "Ogród" },
        { id: "babyline", stream: "babyline", name: "Babyline" }
    ]

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
        width: Math.min(2400, cameras.width - 80)
        height: Math.min(1200, cameras.height - 120)
        anchors.centerIn: parent
        radius: 28
        color: "#f3131824"
        border.color: "#665ecfff"
        border.width: 2

        MouseArea { anchors.fill: parent; onClicked: event => event.accepted = true }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Cameras"
                    color: "white"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 26
                    font.bold: true
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    icon: shell.cameraAlertsSnoozed ? "notifications_paused" : "snooze"
                    statusText: shell.cameraAlertsSnoozed ? "Snoozed" : "30m"
                    tooltip: shell.cameraAlertsSnoozed ? "Resume camera alerts" : "Snooze camera alerts for 30 minutes"
                    active: shell.cameraAlertsSnoozed
                    accent: "#f6c177"
                    onClicked: {
                        if (shell.cameraAlertsSnoozed)
                            shell.resumeCameraAlerts()
                        else
                            shell.snoozeCameraAlerts(30)
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 2
                columnSpacing: 14
                rowSpacing: 14

                Repeater {
                    model: cameras.feeds
                    delegate: Rectangle {
                        id: feed
                        required property var modelData
                        property bool hasFrame: false
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 16
                        color: "#151a24"
                        border.width: 1
                        border.color: modelData.id === shell.activeCamera ? "#ff7b86" : "#354158"
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: cameras.visible ? `https://frigate.house.flakm.com/desktop-camera/${modelData.id}/latest.jpg?t=${cameras.previewTimestamp}` : ""
                            asynchronous: true
                            cache: false
                            fillMode: Image.PreserveAspectCrop
                            visible: !feed.hasFrame
                        }

                        MediaPlayer {
                            id: feedPlayer
                            source: cameras.visible ? `https://frigate.house.flakm.com/desktop-stream/api/stream.mp4?src=${modelData.stream}&video=h264` : ""
                            videoOutput: feedOutput
                            playbackOptions.playbackIntent: PlaybackOptions.LowLatencyStreaming
                            // MP4 supplies codec parameters in its initialization header.
                            playbackOptions.probeSize: 32
                            playbackOptions.networkTimeoutMs: 5000
                            onSourceChanged: {
                                feed.hasFrame = false;
                                if (source.toString() !== "") play();
                            }
                        }

                        VideoOutput {
                            id: feedOutput
                            anchors.fill: parent
                            fillMode: VideoOutput.PreserveAspectCrop
                            visible: feed.hasFrame
                        }

                        Connections {
                            target: feedOutput.videoSink
                            function onVideoFrameChanged() {
                                if (cameras.visible && feedPlayer.playbackState === MediaPlayer.PlayingState)
                                    feed.hasFrame = true;
                            }
                        }

                        Text {
                            visible: cameras.visible && !feed.hasFrame && feedPlayer.error === MediaPlayer.NoError
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 16
                            text: "Connecting live video…"
                            color: "white"
                            style: Text.Outline
                            styleColor: "#101520"
                            font.pixelSize: 14
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 12
                            width: feedName.implicitWidth + 20
                            height: 32
                            radius: 9
                            color: "#cc101520"
                            Text {
                                id: feedName
                                anchors.centerIn: parent
                                text: modelData.name
                                color: "white"
                                font.pixelSize: 15
                                font.bold: true
                            }
                        }

                        Row {
                            visible: feedPlayer.error !== MediaPlayer.NoError
                            anchors.centerIn: parent
                            spacing: 7
                            Symbol { text: "videocam_off"; color: "#ff8a8a"; font.pixelSize: 22 }
                            Text { text: "Camera unavailable"; color: "#ff8a8a"; font.pixelSize: 18 }
                        }

                        Rectangle {
                            visible: modelData.id === shell.activeCamera
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 12
                            width: activityText.implicitWidth + 20
                            height: 32
                            radius: 9
                            color: "#e6ff5864"
                            Text {
                                id: activityText
                                anchors.centerIn: parent
                                text: "Person detected"
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["xdg-open", `https://frigate.house.flakm.com/#${modelData.id}`])
                        }
                    }
                }
            }
        }
    }
}
