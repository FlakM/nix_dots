import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

ShellRoot {
    id: root

    property string overlayMode: ""
    property var toastNotifications: []
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
    property bool cameraPrivateMode: false
    property bool cameraPrivateKnown: false
    property bool cameraPrivateLoading: false
    property bool cameraPrivateTarget: false
    property var calendarStatus: ({ "text": "Calendar", "title": "Calendar", "time": "", "detail": "Loading...", "tooltip": "Loading calendar...", "class": "no-events" })
    property var calendarAgenda: []
    property var calendarWeek: []
    property bool calendarLoading: false
    property var vpnStatus: ({ "text": "VPN", "title": "VPN", "detail": "Checking...", "tooltip": "Loading VPN status...", "class": "disconnected" })
    property var tailscaleState: ({ "online": false, "name": "This device", "ip": "", "peers": [] })
    property bool tailscaleLoading: false
    property var vikunjaTasks: []
    property var vikunjaImportant: []
    property var vikunjaFocused: null
    property var vikunjaPinnedProject: null
    property var vikunjaWeekProject: null
    property var vikunjaWorkProject: null
    property int vikunjaTaskCount: 0
    property bool vikunjaLoading: true
    property string vikunjaError: ""
    // Hermes bridge cache (~/.cache/hermes/bridge.json), read-only.
    property var hermesBridge: ({})
    property int hermesUnread: 0
    property bool hermesConnected: false
    property string hermesBridgeError: ""
    property var hermesThreads: []
    property var hermesJobs: []
    property var hermesEvents: []
    property var hermesUpdated: 0
    property string hermesBridgeRaw: ""
    readonly property string hermesBridgePath: `${Quickshell.env("HOME") || "/home/flakm"}/.cache/hermes/bridge.json`

    function toggle(mode) {
        if (mode === "cameras") cameraAutoOpened = false
        if (mode === "calendar") refreshCalendar()
        if (mode === "tailscale") refreshTailscale()
        if (mode === "hermes") refreshHermes()
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

    function addToast(notification) {
        const timeout = notification.expireTimeout
        const expiresAt = timeout === 0 ? 0 : Date.now() + (timeout > 0 ? timeout : 8000)
        const remaining = toastNotifications.filter(item => item.notification.id !== notification.id)
        toastNotifications = [{ notification, expiresAt }].concat(remaining)
    }

    function hideToastById(id) {
        toastNotifications = toastNotifications.filter(item => item.notification && item.notification.id !== id)
    }

    function activateNotification(notification) {
        if (!notification) return
        for (let i = 0; i < notification.actions.length; i++) {
            const action = notification.actions[i]
            if (action.identifier === "default") {
                hideToastById(notification.id)
                action.invoke()
                return
            }
        }
    }

    function dismissToast(notification) {
        if (!notification) return
        hideToastById(notification.id)
        notification.dismiss()
    }

    function pruneToasts() {
        const now = Date.now()
        toastNotifications = toastNotifications.filter(item => item.expiresAt === 0 || item.expiresAt > now)
    }

    function refreshCalendar() {
        if (calendarAgendaProcess.running) return
        calendarLoading = true
        calendarAgendaProcess.running = true
        if (!calendarWeekProcess.running) calendarWeekProcess.running = true
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
        if (cameraAlertsAction.running) return
        cameraAlertsAction.command = ["quickshell-camera-alerts", "snooze"]
        cameraAlertsAction.running = true
    }

    function resumeCameraAlerts() {
        if (cameraAlertsAction.running) return
        cameraAlertsAction.command = ["quickshell-camera-alerts", "resume"]
        cameraAlertsAction.running = true
    }

    function toggleCameraPrivateMode() {
        if (!cameraPrivateKnown || cameraPrivateLoading) return
        cameraPrivateLoading = true
        cameraPrivateTarget = !cameraPrivateMode
        cameraPrivateTimeout.restart()
        cameraPrivateAction.command = ["quickshell-camera-private", "set", cameraPrivateTarget ? "on" : "off"]
        cameraPrivateAction.running = true
    }

    function refreshVikunja() {
        if (vikunjaProcess.running) return
        vikunjaLoading = true
        vikunjaProcess.running = true
    }

    function refreshHermes() {
        hermesBridgeFile.reload()
    }

    // bridge.json is written atomically by hermes-bridge; tolerate an empty or
    // missing file (first boot, service down) without spamming the log.
    function applyHermesBridge(raw) {
        if (!raw || raw === root.hermesBridgeRaw) return
        try {
            const data = JSON.parse(raw)
            if (!data || typeof data !== "object") return
            root.hermesBridgeRaw = raw
            root.hermesBridge = data
            root.hermesUnread = Number(data.unread || 0)
            root.hermesThreads = Array.isArray(data.threads) ? data.threads : []
            root.hermesJobs = Array.isArray(data.jobs) ? data.jobs : []
            root.hermesEvents = Array.isArray(data.events) ? data.events : []
            root.hermesUpdated = Number(data.updated || 0)
            root.hermesConnected = data.connection ? data.connection.connected !== false : true
            root.hermesBridgeError = data.connection && data.connection.error
                ? String(data.connection.error) : ""
        } catch (error) {
            console.warn("Unable to parse Hermes bridge cache:", error)
        }
    }

    function completeVikunjaTask(taskId) {
        if (vikunjaAction.running) return
        vikunjaAction.command = ["quickshell-vikunja", "done", `${taskId}`]
        vikunjaAction.running = true
    }

    function setVikunjaPriority(taskId, priority) {
        if (vikunjaAction.running) return
        vikunjaAction.command = ["quickshell-vikunja", "priority", `${taskId}`, `${priority}`]
        vikunjaAction.running = true
    }

    function setVikunjaDue(taskId, preset) {
        if (vikunjaAction.running) return
        vikunjaAction.command = ["quickshell-vikunja", "due", `${taskId}`, preset]
        vikunjaAction.running = true
    }

    function setVikunjaFocus(taskId, focused) {
        if (vikunjaAction.running) return
        vikunjaAction.command = ["quickshell-vikunja", focused ? "focus" : "unfocus", `${taskId}`]
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
        function toggleHermes(): void { root.toggle("hermes") }
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
            const id = notification.id
            const actions = []
            for (let i = 0; i < notification.actions.length; i++) actions.push(notification.actions[i].identifier)
            notification.tracked = true
            notification.closed.connect(() => root.hideToastById(id))
            console.info("Notification received:", notification.appName, notification.desktopEntry,
                JSON.stringify(notification.summary), actions.join(","))
            root.addToast(notification)
        }
    }

    Timer {
        interval: 250
        running: true
        repeat: true
        onTriggered: root.pruneToasts()
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
        command: ["quickshell-camera-alerts", "watch"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const state = data.trim().toUpperCase()
                if (state === "ON" || state === "OFF")
                    root.cameraAlertsSnoozed = state === "ON"
            }
        }
    }

    Process {
        id: cameraAlertsAction
    }

    Process {
        command: ["quickshell-camera-private", "watch"]
        running: true
        stdout: SplitParser {
            onRead: data => {
                const state = data.trim().toUpperCase()
                if (state !== "ON" && state !== "OFF") return
                root.cameraPrivateMode = state === "ON"
                root.cameraPrivateKnown = true
                if (root.cameraPrivateLoading && root.cameraPrivateMode === root.cameraPrivateTarget) {
                    root.cameraPrivateLoading = false
                    cameraPrivateTimeout.stop()
                }
            }
        }
    }

    Process {
        id: cameraPrivateAction
    }

    Timer {
        id: cameraPrivateTimeout
        interval: 35000
        onTriggered: root.cameraPrivateLoading = false
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
        id: calendarWeekProcess
        command: ["quickshell-calendar", "week", "7"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.calendarWeek = JSON.parse(text)
                } catch (error) {
                    root.calendarWeek = []
                    console.warn("Unable to parse calendar week:", error)
                }
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
                    root.vikunjaImportant = data.important || []
                    root.vikunjaFocused = data.focused || null
                    root.vikunjaTaskCount = data.count || 0
                    root.vikunjaPinnedProject = data.pinned_project || null
                    root.vikunjaWeekProject = data.week_project || null
                    root.vikunjaWorkProject = data.work_project || null
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

    // Hermes: the bridge owns the SSE connection; quickshell only renders its
    // cache. watchChanges catches atomic renames, the timer is a safety net.
    FileView {
        id: hermesBridgeFile
        path: root.hermesBridgePath
        watchChanges: true
        printErrors: false
        onLoaded: root.applyHermesBridge(hermesBridgeFile.text())
        onTextChanged: root.applyHermesBridge(hermesBridgeFile.text())
        onFileChanged: hermesBridgeFile.reload()
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: hermesBridgeFile.reload()
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

    Timer {
        interval: 300000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!calendarWeekProcess.running) calendarWeekProcess.running = true
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

    HermesPanel {
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
