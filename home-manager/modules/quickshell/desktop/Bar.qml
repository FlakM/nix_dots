import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: bar
    required property var shell

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 64
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Top

    property var player: {
        const players = Mpris.players.values
        return players.find(candidate => candidate.isPlaying) || players[0] || null
    }
    readonly property int bluetoothConnectedCount: Bluetooth.devices.values.filter(device => device.connected).length
    function usageColor(value, warning, critical) {
        if (value >= critical) return "#ff7b86"
        if (value >= warning) return "#f6c177"
        return "#72e4ae"
    }
    function formatRate(bytes) {
        if (bytes >= 1048576) return `${(bytes / 1048576).toFixed(bytes >= 10485760 ? 0 : 1)}M/s`
        if (bytes >= 1024) return `${(bytes / 1024).toFixed(bytes >= 102400 ? 0 : 1)}K/s`
        return `${bytes}B/s`
    }
    function networkRateColor(bytes) {
        if (bytes >= 52428800) return "#ff7b86"
        if (bytes >= 10485760) return "#f6c177"
        if (bytes >= 1048576) return "#72e4ae"
        return "#b8c8d8"
    }
    readonly property real peakNetworkRate: Math.max(shell.networkRxRate, shell.networkTxRate)

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    Timer {
        interval: 1000
        running: bar.player !== null && bar.player.isPlaying && bar.player.positionSupported
        repeat: true
        onTriggered: bar.player.positionChanged()
    }

    Rectangle {
        id: surface
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: "#581b2230" }
            GradientStop { position: 1; color: "#30101520" }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: "#5572d7ff"
        }

        RowLayout {
            id: content
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            spacing: 6

            Rectangle {
                implicitWidth: workspaces.implicitWidth + 10
                implicitHeight: 44
                radius: 12
                color: "#55101520"
                border.width: 1
                border.color: "#304b5c76"

                Row {
                    id: workspaces
                    anchors.centerIn: parent
                    spacing: 3
                    Repeater {
                        model: Hyprland.workspaces
                        delegate: Rectangle {
                            required property var modelData
                            visible: modelData.id > 0 && modelData.id <= 10
                            width: visible ? 34 : 0
                            height: 34
                            radius: 10
                            color: modelData.focused ? "#72d7ff" : modelData.active ? "#35465e" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.id
                                color: modelData.focused ? "#071018" : "#c8d1e2"
                                font.family: "FiraCode Nerd Font"
                                font.pixelSize: 15
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: modelData.activate()
                            }
                        }
                    }
                }
            }

            Rectangle {
                visible: bar.width >= 1600
                implicitWidth: visible ? 460 : 0
                implicitHeight: 44
                radius: 12
                color: "#42101520"
                border.width: 1
                border.color: "#304b5c76"

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: Text.AlignVCenter
                    text: Hyprland.activeToplevel?.title || "Desktop"
                    elide: Text.ElideRight
                    color: "#c8d1e2"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 15
                }
            }

            Item { Layout.fillWidth: true }

            Item {
                visible: bar.width >= 2600 && bar.player !== null
                implicitWidth: visible ? 430 : 0
                implicitHeight: 44

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 3
                    height: 2
                    radius: 1
                    color: "#29443835"
                    Rectangle {
                        width: parent.width * (bar.player?.length > 0 ? Math.max(0, Math.min(1, bar.player.position / bar.player.length)) : 0)
                        height: parent.height
                        radius: 1
                        color: "#1ed760"
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 8
                    anchors.bottomMargin: 3
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 8
                        clip: true
                        color: "#24332b"
                        Image {
                            anchors.fill: parent
                            source: bar.player?.trackArtUrl || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        Symbol {
                            visible: !bar.player?.trackArtUrl
                            anchors.centerIn: parent
                            text: "music_note"
                            color: "#1ed760"
                            font.pixelSize: 20
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: bar.player?.trackTitle || "Unknown track"
                            elide: Text.ElideRight
                            color: "#f2f6f3"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 13
                            font.bold: true
                        }
                        Text {
                            Layout.fillWidth: true
                            text: bar.player?.trackArtist || bar.player?.identity || "Spotify"
                            elide: Text.ElideRight
                            color: "#8da398"
                            font.family: "FiraCode Nerd Font"
                            font.pixelSize: 11
                        }
                    }

                    Symbol {
                        text: "skip_previous"
                        color: bar.player?.canGoPrevious ? "#aebbb4" : "#46514c"
                        font.pixelSize: 21
                        MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: if (bar.player?.canGoPrevious) bar.player.previous() }
                    }
                    Rectangle {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        radius: 15
                        color: playMouse.containsMouse ? "#43e57d" : "#1ed760"
                        Symbol {
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: bar.player?.isPlaying ? 0 : 1
                            text: bar.player?.isPlaying ? "pause" : "play_arrow"
                            color: "#07120b"
                            fill: 1
                            font.pixelSize: 20
                        }
                        MouseArea {
                            id: playMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: if (bar.player?.canTogglePlaying) bar.player.togglePlaying()
                        }
                    }
                    Symbol {
                        text: "skip_next"
                        color: bar.player?.canGoNext ? "#aebbb4" : "#46514c"
                        font.pixelSize: 21
                        MouseArea { anchors.fill: parent; anchors.margins: -5; onClicked: if (bar.player?.canGoNext) bar.player.next() }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            IconButton {
                icon: bar.shell.cameraAlertsSnoozed ? "videocam_off" : "videocam"
                tooltip: bar.shell.cameraAlertsSnoozed ? "Camera alerts snoozed" : "Cameras"
                active: bar.shell.overlayMode === "cameras" || bar.shell.cameraAlertsSnoozed
                accent: bar.shell.cameraAlertsSnoozed ? "#f6c177" : "#72d7ff"
                onClicked: bar.shell.toggle("cameras")
            }

            IconButton {
                icon: !Bluetooth.defaultAdapter?.enabled ? "bluetooth_disabled"
                    : bar.bluetoothConnectedCount > 0 ? "bluetooth_connected" : "bluetooth"
                tooltip: !Bluetooth.defaultAdapter ? "No Bluetooth adapter"
                    : !Bluetooth.defaultAdapter.enabled ? "Bluetooth off"
                    : bar.bluetoothConnectedCount > 0 ? `${bar.bluetoothConnectedCount} Bluetooth device(s) connected` : "Bluetooth"
                active: bar.shell.overlayMode === "bluetooth" || bar.bluetoothConnectedCount > 0
                accent: "#8ea8ff"
                onClicked: bar.shell.toggle("bluetooth")
            }

            IconButton {
                property var audio: Pipewire.defaultAudioSink?.audio

                icon: audio?.muted ? "volume_off" : "volume_up"
                statusText: `${Math.round((audio?.volume || 0) * 100)}%`
                tooltip: audio?.muted ? "Audio muted" : "Audio output"
                active: bar.shell.overlayMode === "audio" || (audio?.muted ?? false)
                accent: audio?.muted ? "#ff7b86" : "#72d7ff"
                onClicked: bar.shell.toggle("audio")
                onSecondaryClicked: Quickshell.execDetached(["pavucontrol"])
                onWheel: delta => {
                    if (!audio) return
                    audio.volume = Math.max(0, Math.min(1.5, audio.volume + (delta > 0 ? 0.05 : -0.05)))
                }
            }

            IconButton {
                icon: "task_alt"
                statusText: `${bar.shell.vikunjaTasks.filter(task => task.project_id === bar.shell.vikunjaPinnedProject?.id).length}`
                tooltip: bar.shell.vikunjaError || `${bar.shell.vikunjaPinnedProject?.title || "Vikunja"} tasks`
                active: bar.shell.overlayMode === "tasks"
                accent: "#72e4ae"
                onClicked: bar.shell.toggle("tasks")
                onSecondaryClicked: Qt.openUrlExternally("https://tasks.house.flakm.com/")
            }

            Rectangle {
                visible: bar.width >= 1800
                implicitWidth: visible ? resources.implicitWidth + 18 : 0
                implicitHeight: 44
                radius: 12
                color: "#55101520"
                border.width: 1
                border.color: "#304b5c76"

                Row {
                    id: resources
                    anchors.centerIn: parent
                    spacing: 14
                    Row {
                        spacing: 4
                        Symbol { text: "memory"; color: bar.usageColor(bar.shell.cpuUsage, 70, 85); font.pixelSize: 18 }
                        Text { text: `${bar.shell.cpuUsage}%`; color: bar.usageColor(bar.shell.cpuUsage, 70, 85); font.pixelSize: 14 }
                    }
                    Row {
                        spacing: 4
                        Symbol { text: "hard_drive"; color: bar.usageColor(bar.shell.diskUsage, 80, 90); font.pixelSize: 18 }
                        Text { text: `${bar.shell.diskUsage}%`; color: bar.usageColor(bar.shell.diskUsage, 80, 90); font.pixelSize: 14 }
                    }
                    Row {
                        spacing: 4
                        Symbol { text: "device_thermostat"; color: bar.usageColor(bar.shell.temperature, 70, 85); font.pixelSize: 18 }
                        Text { text: `${bar.shell.temperature}°`; color: bar.usageColor(bar.shell.temperature, 70, 85); font.pixelSize: 14 }
                    }
                }

                MouseArea {
                    id: resourcesMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }

            Rectangle {
                implicitWidth: 260
                implicitHeight: 44
                radius: 12
                color: bar.peakNetworkRate >= 52428800 ? "#70351f2b"
                    : bar.peakNetworkRate >= 10485760 ? "#70413728"
                    : networkMouse.containsMouse ? "#70202a3a" : "#55101520"
                border.color: bar.shell.networkInterface === "offline" ? "#60ff7b86"
                    : bar.peakNetworkRate >= 52428800 ? "#dfff7b86"
                    : bar.peakNetworkRate >= 10485760 ? "#bff6c177" : "#40586f8c"
                border.width: bar.peakNetworkRate >= 10485760 ? 2 : 1
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Symbol {
                        text: bar.shell.networkInterface === "offline" ? "signal_wifi_off"
                            : bar.shell.networkType === "wifi" ? "wifi"
                            : bar.shell.networkType === "vpn" ? "vpn_lock" : "lan"
                        color: bar.shell.networkInterface === "offline" ? "#ff7b86" : "#72d7ff"
                        fill: bar.shell.networkInterface !== "offline" ? 1 : 0
                        font.pixelSize: 21
                    }
                    ColumnLayout {
                        Layout.preferredWidth: 76
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            text: bar.shell.networkInterface
                            color: bar.shell.networkInterface === "offline" ? "#ff7b86" : "#dce6f5"
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: bar.shell.networkAddress || (bar.shell.networkInterface === "offline" ? "No route" : bar.shell.networkType)
                            color: "#75869d"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                    ColumnLayout {
                        id: networkRates
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Symbol { text: "arrow_downward"; color: bar.networkRateColor(bar.shell.networkRxRate); font.pixelSize: 16 }
                            Text {
                                text: bar.formatRate(bar.shell.networkRxRate)
                                color: bar.networkRateColor(bar.shell.networkRxRate)
                                font.pixelSize: bar.shell.networkRxRate >= 10485760 ? 16 : bar.shell.networkRxRate >= 1048576 ? 15 : 13
                                font.bold: bar.shell.networkRxRate >= 1048576
                                font.family: "FiraCode Nerd Font"
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Symbol { text: "arrow_upward"; color: bar.networkRateColor(bar.shell.networkTxRate); font.pixelSize: 16 }
                            Text {
                                text: bar.formatRate(bar.shell.networkTxRate)
                                color: bar.networkRateColor(bar.shell.networkTxRate)
                                font.pixelSize: bar.shell.networkTxRate >= 10485760 ? 16 : bar.shell.networkTxRate >= 1048576 ? 15 : 13
                                font.bold: bar.shell.networkTxRate >= 1048576
                                font.family: "FiraCode Nerd Font"
                            }
                        }
                        SequentialAnimation {
                            running: bar.peakNetworkRate >= 52428800
                            loops: Animation.Infinite
                            NumberAnimation { target: networkRates; property: "opacity"; from: 1; to: 0.45; duration: 420 }
                            NumberAnimation { target: networkRates; property: "opacity"; from: 0.45; to: 1; duration: 420 }
                            onStopped: networkRates.opacity = 1
                        }
                    }
                }
                MouseArea { id: networkMouse; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
            }

            Rectangle {
                implicitWidth: 270
                implicitHeight: 44
                radius: 12
                color: calendarMouse.containsMouse ? "#70202a3a" : "#55101520"
                border.width: 1
                border.color: bar.shell.calendarStatus["class"] === "urgent" ? "#80ff7b86"
                    : bar.shell.calendarStatus["class"] === "has-events" ? "#6072d7ff"
                    : "#304b5c76"

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 9
                    color: bar.shell.calendarStatus["class"] === "urgent" ? "#ff7b86"
                        : bar.shell.calendarStatus["class"] === "has-events" ? "#72d7ff"
                        : "#263244"

                    Symbol {
                        anchors.centerIn: parent
                        text: "calendar_month"
                        color: bar.shell.calendarStatus["class"] === "no-events" ? "#9aa7ba" : "#071018"
                        fill: bar.shell.calendarStatus["class"] !== "no-events" ? 1 : 0
                        font.pixelSize: 19
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 46
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: bar.shell.calendarStatus.title || "Calendar"
                        color: "#e6edf7"
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: bar.shell.calendarStatus.time
                            ? `${bar.shell.calendarStatus.time}  ${bar.shell.calendarStatus.detail}`
                            : bar.shell.calendarStatus.detail
                        color: bar.shell.calendarStatus["class"] === "urgent" ? "#ff9ca5" : "#8998ac"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: calendarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton)
                            Quickshell.execDetached(["sh", "-lc", "$HOME/.local/bin/khal-notify"])
                        else
                            bar.shell.toggle("calendar")
                    }
                }
            }

            Rectangle {
                implicitWidth: 210
                implicitHeight: 44
                radius: 12
                color: vpnMouse.containsMouse ? "#70202a3a" : "#55101520"
                border.width: 1
                border.color: bar.shell.vpnStatus["class"] === "disconnected" ? "#60ff7b86"
                    : bar.shell.vpnStatus["class"] === "tailscale" ? "#6072d7ff"
                    : "#6072e4ae"

                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    radius: 9
                    color: bar.shell.vpnStatus["class"] === "disconnected" ? "#ff7b86"
                        : bar.shell.vpnStatus["class"] === "tailscale" ? "#72d7ff"
                        : "#72e4ae"

                    Symbol {
                        anchors.centerIn: parent
                        text: bar.shell.vpnStatus["class"] === "disconnected" ? "vpn_lock_off" : "vpn_lock"
                        color: "#071018"
                        fill: 1
                        font.pixelSize: 19
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 46
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        width: parent.width
                        text: bar.shell.vpnStatus.title || "VPN"
                        color: "#e6edf7"
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: bar.shell.vpnStatus.detail || "Checking..."
                        color: bar.shell.vpnStatus["class"] === "disconnected" ? "#ff9ca5" : "#8998ac"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: vpnMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton)
                            Quickshell.execDetached(["kitty", "--hold", "-e", "vpn", "s"])
                        else
                            bar.shell.toggle("tailscale")
                    }
                }
            }

            Rectangle {
                implicitWidth: systemRow.implicitWidth + 18
                implicitHeight: 44
                radius: 12
                color: "#55101520"
                border.width: 1
                border.color: "#304b5c76"

                Row {
                    id: systemRow
                    anchors.centerIn: parent
                    spacing: 11

                    Row {
                        spacing: 7
                        Repeater {
                            model: ScriptModel {
                                values: SystemTray.items.values.filter(item => {
                                    const identity = `${item.id} ${item.title}`.toLowerCase()
                                    return !identity.includes("blueman")
                                        && !identity.includes("bluetooth")
                                        && !identity.includes("nextcloud")
                                        && !identity.includes("slack")
                                        && !identity.includes("spotify")
                                })
                            }
                            delegate: IconImage {
                                required property var modelData
                                implicitSize: 24
                                source: modelData.icon
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: event => {
                                        if (event.button === Qt.RightButton && modelData.hasMenu)
                                            modelData.display(bar, parent.x, bar.height)
                                        else
                                            modelData.activate()
                                    }
                                }
                            }
                        }
                    }

                }
            }

            SystemClock { id: clock; precision: SystemClock.Minutes }
            Rectangle {
                implicitWidth: clockText.implicitWidth + 18
                implicitHeight: 44
                radius: 12
                color: "#66304a66"
                border.width: 1
                border.color: "#6072d7ff"
                Text {
                    id: clockText
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(clock.date, "ddd  yyyy-MM-dd  HH:mm")
                    color: "#f2f6fc"
                    font.family: "FiraCode Nerd Font"
                    font.pixelSize: 15
                    font.bold: true
                }
            }
        }
    }
}
