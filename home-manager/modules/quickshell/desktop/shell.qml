import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

ShellRoot {
    id: root

    property string overlayMode: ""
    property var latestNotification: null
    property bool toastVisible: false
    property int cpuUsage: 0
    property int memoryUsage: 0
    property int diskUsage: 0
    property int temperature: 0
    property int loadUsage: 0
    property int ioPressure: 0
    property int memoryPressure: 0
    property string networkInterface: "offline"
    property string networkType: "offline"
    property string networkAddress: ""
    property int networkRxRate: 0
    property int networkTxRate: 0
    property string activeCamera: ""
    property bool cameraAutoOpened: false
    property bool cameraAlertsSnoozed: false
    property var calendarStatus: ({ "text": "Calendar", "title": "Calendar", "time": "", "detail": "Loading...", "tooltip": "Loading calendar...", "class": "no-events" })
    property var calendarAgenda: []
    property bool calendarLoading: false
    property var vpnStatus: ({ "text": "VPN", "title": "VPN", "detail": "Checking...", "tooltip": "Loading VPN status...", "class": "disconnected" })
    property var tailscaleState: ({ "online": false, "name": "This device", "ip": "", "peers": [] })
    property bool tailscaleLoading: false
    property var vikunjaTasks: []
    property var vikunjaPinnedProject: null
    property int vikunjaTaskCount: 0
    property bool vikunjaLoading: true
    property string vikunjaError: ""

    function toggle(mode) {
        if (mode === "cameras") cameraAutoOpened = false
        if (mode === "calendar") refreshCalendar()
        if (mode === "tailscale") refreshTailscale()
        overlayMode = overlayMode === mode ? "" : mode
    }

    function renderNotificationBody(body) {
        if (/<\/?[a-z][^>]*>/i.test(body)) return body

        return body
            .replace(/&/g, "&amp;")
            .replace(/</g, "&lt;")
            .replace(/>/g, "&gt;")
            .replace(/```(?:[^\n]*)\n([\s\S]*?)```/g, "<pre>$1</pre>")
            .replace(/^### (.+)$/gm, "<h3>$1</h3>")
            .replace(/^## (.+)$/gm, "<h2>$1</h2>")
            .replace(/^# (.+)$/gm, "<h1>$1</h1>")
            .replace(/!\[([^\]]*)\]\(([^)]+)\)/g, '<img src="$2" alt="$1">')
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
            .replace(/\*\*(.+?)\*\*/g, "<b>$1</b>")
            .replace(/__(.+?)__/g, "<b>$1</b>")
            .replace(/~~(.+?)~~/g, "<s>$1</s>")
            .replace(/`(.+?)`/g, "<code>$1</code>")
            .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<i>$2</i>")
            .replace(/^\s*[-*+] (.+)$/gm, "&#8226; $1")
            .replace(/\n/g, "<br>")
    }

    function refreshCalendar() {
        if (calendarAgendaProcess.running) return
        calendarLoading = true
        calendarAgendaProcess.running = true
    }

    function refreshTailscale() {
        if (tailscaleStatusProcess.running) return
        tailscaleLoading = true
        tailscaleStatusProcess.running = true
    }

    function setTailscaleOnline(online) {
        if (tailscaleActionProcess.running) return
        tailscaleLoading = true
        tailscaleActionProcess.command = ["quickshell-tailscale", online ? "up" : "down"]
        tailscaleActionProcess.running = true
    }

    function showCameraActivity(camera) {
        if (cameraAlertsSnoozed) return
        activeCamera = camera
        if (overlayMode === "") {
            overlayMode = "cameras"
            cameraAutoOpened = true
            cameraAutoClose.restart()
        } else if (overlayMode === "cameras" && cameraAutoOpened) {
            cameraAutoClose.restart()
        }
    }

    function snoozeCameraAlerts(minutes) {
        cameraAlertsSnoozed = true
        cameraSnoozeTimer.interval = minutes * 60000
        cameraSnoozeTimer.restart()
    }

    function resumeCameraAlerts() {
        cameraSnoozeTimer.stop()
        cameraAlertsSnoozed = false
    }

    function refreshVikunja() {
        if (vikunjaProcess.running) return
        vikunjaLoading = true
        vikunjaProcess.running = true
    }

    function completeVikunjaTask(taskId) {
        if (vikunjaAction.running) return
        vikunjaAction.command = ["quickshell-vikunja", "done", `${taskId}`]
        vikunjaAction.running = true
    }

    IpcHandler {
        target: "desktop"
        function toggleLauncher(): void { root.toggle("launcher") }
        function toggleClipboard(): void { root.toggle("clipboard") }
        function toggleNotifications(): void { root.toggle("notifications") }
        function toggleCameras(): void { root.toggle("cameras") }
        function snoozeCameras(): void { root.snoozeCameraAlerts(30) }
        function toggleBluetooth(): void { root.toggle("bluetooth") }
        function toggleAudio(): void { root.toggle("audio") }
        function toggleTasks(): void { root.toggle("tasks") }
        function toggleCalendar(): void { root.toggle("calendar") }
        function toggleTailscale(): void { root.toggle("tailscale") }
    }

    NotificationServer {
        id: notificationServer
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        imageSupported: true
        persistenceSupported: true
        keepOnReload: true
        onNotification: notification => {
            notification.tracked = true
            root.latestNotification = notification
            root.toastVisible = true
            toastTimer.restart()
        }
    }

    Timer {
        id: toastTimer
        interval: 8000
        onTriggered: root.toastVisible = false
    }

    Timer {
        id: cameraAutoClose
        interval: 20000
        onTriggered: {
            if (root.cameraAutoOpened && root.overlayMode === "cameras") root.overlayMode = ""
            root.cameraAutoOpened = false
            root.activeCamera = ""
        }
    }

    Timer {
        id: cameraSnoozeTimer
        interval: 1800000
        onTriggered: root.cameraAlertsSnoozed = false
    }

    Process {
        command: ["quickshell-camera-activity"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const parts = data.trim().split(/\s+/)
                if (parts.length !== 2 || Number(parts[1]) <= 0) return
                root.showCameraActivity(parts[0].split("/")[1])
            }
        }
    }

    Process {
        id: statsProcess
        command: ["quickshell-stats"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.cpuUsage = data.cpu
                    root.memoryUsage = data.memory
                    root.diskUsage = data.disk
                    root.temperature = data.temperature
                    root.loadUsage = data.load
                    root.ioPressure = data.ioPressure
                    root.memoryPressure = data.memoryPressure
                    root.networkInterface = data.network
                    root.networkType = data.networkType
                    root.networkAddress = data.networkAddress
                    root.networkRxRate = data.rxRate
                    root.networkTxRate = data.txRate
                } catch (error) {
                    console.warn("Unable to parse system statistics:", error)
                }
            }
        }
    }

    Process {
        id: calendarProcess
        command: ["sh", "-lc", "$HOME/.local/bin/khal-waybar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.calendarStatus = JSON.parse(text)
                } catch (error) {
                    console.warn("Unable to parse calendar status:", error)
                }
            }
        }
    }

    Process {
        id: calendarAgendaProcess
        command: ["quickshell-calendar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.calendarAgenda = JSON.parse(text)
                } catch (error) {
                    root.calendarAgenda = []
                    console.warn("Unable to parse calendar agenda:", error)
                }
                root.calendarLoading = false
            }
        }
    }

    Process {
        id: vpnProcess
        command: ["vpn-waybar"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.vpnStatus = JSON.parse(text)
                } catch (error) {
                    console.warn("Unable to parse VPN status:", error)
                }
            }
        }
    }

    Process {
        id: tailscaleStatusProcess
        command: ["quickshell-tailscale", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.tailscaleState = JSON.parse(text)
                } catch (error) {
                    console.warn("Unable to parse Tailscale status:", error)
                }
                root.tailscaleLoading = false
            }
        }
    }

    Process {
        id: tailscaleActionProcess
        stdout: StdioCollector { onStreamFinished: root.refreshTailscale() }
    }

    Process {
        id: vikunjaProcess
        command: ["quickshell-vikunja", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.vikunjaTasks = data.tasks || []
                    root.vikunjaTaskCount = data.count || 0
                    root.vikunjaPinnedProject = data.pinned_project || null
                    root.vikunjaError = ""
                } catch (error) {
                    root.vikunjaError = "Unable to load tasks"
                    console.warn("Unable to parse Vikunja tasks:", error)
                }
                root.vikunjaLoading = false
            }
        }
    }

    Process {
        id: vikunjaAction
        stdout: StdioCollector {
            onStreamFinished: root.refreshVikunja()
        }
    }

    Timer {
        interval: 3000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!statsProcess.running) statsProcess.running = true
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!calendarProcess.running) calendarProcess.running = true
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!vpnProcess.running) vpnProcess.running = true
    }

    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshVikunja()
    }

    Variants {
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
            shell: root
        }
    }

    Overlay {
        shell: root
        notifications: notificationServer
    }

    Cameras {
        shell: root
    }

    BluetoothPanel {
        shell: root
    }

    AudioPanel {
        shell: root
    }

    VikunjaPanel {
        shell: root
    }

    CalendarPanel {
        shell: root
    }

    TailscalePanel {
        shell: root
    }

    Toast {
        shell: root
    }
}
