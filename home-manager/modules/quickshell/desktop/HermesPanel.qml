import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// Read-only view of ~/.cache/hermes/bridge.json, published by hermes-bridge.
// Threads/jobs/notifications arrive through shell.qml's FileView, so this
// panel never talks to the API itself (and never blocks the bar).
PanelWindow {
    id: panel
    required property var shell

    visible: shell.overlayMode === "hermes"
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    exclusionMode: ExclusionMode.Ignore
    color: "#9905080e"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property real cardWidth: Math.min(3600, panel.width - 96)
    readonly property real cardHeight: Math.min(1280, panel.height - 96)
    readonly property real columnsWidth: cardWidth - 60
    readonly property var threads: shell.hermesThreads || []
    readonly property var jobs: shell.hermesJobs || []
    readonly property var events: shell.hermesEvents || []
    readonly property bool connected: shell.hermesConnected
    readonly property string bridgeError: shell.hermesBridgeError
    readonly property int waitingCount: threads.filter(thread => thread.waiting).length
    readonly property int runningCount: jobs.filter(job => job.status === "running" || job.status === "pending" || job.status === "queued").length

    property string selectedKey: ""
    property bool selectionTouched: false
    // Re-evaluated every 30s so "3m ago" ages without a reload.
    property int timeTick: 0

    function threadIndex(key) {
        for (let i = 0; i < threads.length; i++) if (threads[i].key === key) return i
        return -1
    }

    readonly property int selectedIndex: threadIndex(selectedKey)

    function syncSelection() {
        if (!visible) return
        if (threads.length === 0) {
            selectedKey = ""
            return
        }
        if (!selectionTouched || threadIndex(selectedKey) < 0) selectedKey = threads[0].key
    }

    function moveSelection(delta) {
        if (threads.length === 0) return
        selectionTouched = true
        const current = selectedIndex
        const next = current < 0
            ? (delta > 0 ? 0 : threads.length - 1)
            : Math.max(0, Math.min(threads.length - 1, current + delta))
        selectedKey = threads[next].key
        threadList.positionViewAtIndex(next, ListView.Contain)
    }

    function selectedThread() {
        return selectedIndex >= 0 ? threads[selectedIndex] : null
    }

    function openThread(thread) {
        if (!thread || !thread.link) return
        Qt.openUrlExternally(thread.link)
    }

    function openSelected() {
        openThread(selectedThread())
    }

    function openTui() {
        shell.overlayMode = ""
        Quickshell.execDetached(["kitty", "-e", "hermes-tui"])
    }

    function refresh() {
        shell.refreshHermes()
    }

    function formatAge(seconds) {
        if (seconds === undefined || seconds === null || isNaN(seconds)) return "—"
        const value = Math.max(0, Number(seconds))
        if (value < 60) return "now"
        if (value < 3600) return `${Math.floor(value / 60)}m`
        if (value < 86400) return `${Math.floor(value / 3600)}h`
        if (value < 1209600) return `${Math.floor(value / 86400)}d`
        return `${Math.floor(value / 604800)}w`
    }

    function ageSince(ts) {
        const tick = panel.timeTick
        if (!ts) return "—"
        return formatAge(Date.now() / 1000 - Number(ts))
    }

    function priorityColor(thread) {
        const priority = Number(thread?.priority ?? 0)
        if (priority >= 4) return "#ff7b86"
        if (priority >= 2) return "#f6c177"
        if (priority >= 1) return "#72e4ae"
        return "#8ca098"
    }

    function statusColor(status) {
        switch (status) {
        case "done": return "#72e4ae"
        case "error":
        case "failed": return "#ff7b86"
        case "running":
        case "pending":
        case "queued": return "#72d7ff"
        default: return "#8ca098"
        }
    }

    function eventIcon(type) {
        switch (type) {
        case "reminder": return "alarm"
        case "thread.update": return "forum"
        case "job.done": return "task_alt"
        default: return "notifications"
        }
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Q:
            shell.overlayMode = ""
            return true
        case Qt.Key_Down:
        case Qt.Key_J:
            moveSelection(1)
            return true
        case Qt.Key_Up:
        case Qt.Key_K:
            moveSelection(-1)
            return true
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_O:
            openSelected()
            return true
        case Qt.Key_T:
            openTui()
            return true
        case Qt.Key_R:
            refresh()
            return true
        }
        return false
    }

    onVisibleChanged: {
        if (!visible) return
        selectionTouched = false
        syncSelection()
        keyHandler.forceActiveFocus()
        refresh()
        // Opening the panel acknowledges the badge; bridge.json keeps the list.
        if (shell.hermesUnread > 0) {
            Quickshell.execDetached(["hermes", "read"])
            readReload.restart()
        }
    }

    onThreadsChanged: syncSelection()

    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: panel.timeTick += 1
    }

    Timer {
        id: readReload
        interval: 400
        onTriggered: panel.refresh()
    }

    MouseArea {
        anchors.fill: parent
        onClicked: shell.overlayMode = ""
    }

    Item {
        id: keyHandler
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (panel.handleKey(event)) event.accepted = true
        }
    }

    Rectangle {
        width: panel.cardWidth
        height: panel.cardHeight
        anchors.centerIn: parent
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
            spacing: 14

            // ── header ──────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Rectangle {
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 18
                    color: "#2672e4ae"
                    Symbol {
                        anchors.centerIn: parent
                        text: shell.hermesUnread > 0 ? "notifications_active" : "forum"
                        color: "#72e4ae"
                        fill: 1
                        font.pixelSize: 29
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Hermes"
                        color: "#f5f8fd"
                        font.pixelSize: 28
                        font.bold: true
                    }
                    Text {
                        text: panel.connected
                            ? `${panel.threads.length} tracked · ${panel.waitingCount} waiting on you · ${panel.runningCount} job(s) running`
                            : `bridge offline — ${panel.bridgeError || "no data yet"}`
                        color: panel.connected ? "#9bb5aa" : "#ff8d98"
                        font.pixelSize: 14
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    Layout.preferredWidth: connectionText.implicitWidth + 20
                    Layout.preferredHeight: 28
                    radius: 9
                    color: panel.connected ? "#2a72e4ae" : "#2aff7b86"
                    Text {
                        id: connectionText
                        anchors.centerIn: parent
                        text: panel.connected ? "LIVE" : "OFFLINE"
                        color: panel.connected ? "#72e4ae" : "#ff9ca5"
                        font.pixelSize: 11
                        font.bold: true
                    }
                }

                IconButton {
                    icon: "terminal"
                    tooltip: "Otwórz hermes-tui (t)"
                    onClicked: panel.openTui()
                }
                IconButton {
                    icon: "refresh"
                    tooltip: "Odśwież (r)"
                    onClicked: panel.refresh()
                }
                IconButton {
                    icon: "close"
                    tooltip: "Zamknij (Esc)"
                    onClicked: panel.shell.overlayMode = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                // ── tracked threads ─────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: Math.round(panel.columnsWidth * 0.38)
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "TRACKED THREADS"
                            color: "#72e4ae"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.3
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: `${panel.threads.length}`
                            color: "#789386"
                            font.pixelSize: 12
                        }
                    }

                    ListView {
                        id: threadList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        clip: true
                        model: panel.threads

                        delegate: Rectangle {
                            id: threadCard
                            required property var modelData
                            readonly property bool selected: panel.selectedKey === modelData.key
                            width: ListView.view ? ListView.view.width : 0
                            implicitHeight: threadBody.implicitHeight + 20
                            radius: 14
                            color: selected ? "#233029" : threadMouse.containsMouse ? "#1f2b26" : "#1a2220"
                            border.width: 1
                            border.color: selected ? "#72e4ae" : modelData.waiting ? "#47755f" : "#2f3d42"

                            MouseArea {
                                id: threadMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    panel.selectionTouched = true
                                    panel.selectedKey = threadCard.modelData.key
                                }
                                onDoubleClicked: panel.openThread(threadCard.modelData)
                            }

                            ColumnLayout {
                                id: threadBody
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 11
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.preferredWidth: priorityText.implicitWidth + 12
                                        Layout.preferredHeight: 19
                                        radius: 6
                                        color: Qt.alpha(panel.priorityColor(threadCard.modelData), 0.16)
                                        Text {
                                            id: priorityText
                                            anchors.centerIn: parent
                                            text: threadCard.modelData.priority_label || "–"
                                            color: panel.priorityColor(threadCard.modelData)
                                            font.pixelSize: 10
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: threadCard.modelData.summary || threadCard.modelData.key || ""
                                        color: "#e6eef2"
                                        font.pixelSize: 14
                                        font.bold: threadCard.selected
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        visible: threadCard.modelData.importance === true
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 18
                                        radius: 6
                                        color: "#2af6c177"
                                        Symbol {
                                            anchors.centerIn: parent
                                            text: "star"
                                            color: "#f6c177"
                                            fill: 1
                                            font.pixelSize: 13
                                        }
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        visible: threadCard.modelData.waiting === true
                                        Layout.preferredWidth: waitingText.implicitWidth + 12
                                        Layout.preferredHeight: 17
                                        radius: 6
                                        color: "#2a72d7ff"
                                        Text {
                                            id: waitingText
                                            anchors.centerIn: parent
                                            text: "CZEKA NA CIEBIE"
                                            color: "#72d7ff"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: [
                                            threadCard.modelData.age || "—",
                                            threadCard.modelData.cadence || "—",
                                            threadCard.modelData.kind || "—"
                                        ].join(" · ")
                                        color: "#8ca098"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: threadList.count === 0
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            text: panel.connected
                                ? "Brak śledzonych wątków.\nUżyj `track <url>` w Slacku albo w hermes-tui."
                                : "Bridge nie ma jeszcze danych.\nSprawdź `systemctl --user status hermes-bridge`."
                            color: "#93a79f"
                            font.pixelSize: 14
                        }
                    }
                }

                // ── jobs + notifications ───────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "JOBS"
                            color: "#72d7ff"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.3
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: panel.runningCount > 0 ? `${panel.runningCount} running` : `${panel.jobs.length} recent`
                            color: "#789386"
                            font.pixelSize: 12
                        }
                    }

                    ListView {
                        id: jobList
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.round(panel.cardHeight * 0.30)
                        spacing: 8
                        clip: true
                        model: panel.jobs

                        delegate: Rectangle {
                            id: jobCard
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            implicitHeight: jobBody.implicitHeight + 18
                            radius: 14
                            color: "#1a2220"
                            border.width: 1
                            border.color: panel.statusColor(jobCard.modelData.status) === "#8ca098"
                                ? "#2f3d42" : Qt.alpha(panel.statusColor(jobCard.modelData.status), 0.45)

                            ColumnLayout {
                                id: jobBody
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 11
                                spacing: 5

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: jobCard.modelData.title || jobCard.modelData.id || "job"
                                        color: "#e6eef2"
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        Layout.preferredWidth: jobStatus.implicitWidth + 12
                                        Layout.preferredHeight: 18
                                        radius: 6
                                        color: Qt.alpha(panel.statusColor(jobCard.modelData.status), 0.16)
                                        Text {
                                            id: jobStatus
                                            anchors.centerIn: parent
                                            text: (jobCard.modelData.status || "?").toUpperCase()
                                            color: panel.statusColor(jobCard.modelData.status)
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }
                                }

                                Repeater {
                                    model: (jobCard.modelData.steps || []).slice(-5)

                                    delegate: Text {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: `· ${modelData.label || modelData.detail || ""}`
                                        color: "#9bb5aa"
                                        font.pixelSize: 11
                                        elide: Text.ElideRight
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: !!jobCard.modelData.result || !!jobCard.modelData.error
                                    text: jobCard.modelData.error || jobCard.modelData.result || ""
                                    color: jobCard.modelData.error ? "#ff9ca5" : "#a9c4b8"
                                    font.pixelSize: 11
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 3
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: jobList.count === 0
                            text: "Brak jobów"
                            color: "#93a79f"
                            font.pixelSize: 14
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Text {
                            text: "RECENT NOTIFICATIONS"
                            color: "#a9b5c8"
                            font.pixelSize: 11
                            font.bold: true
                            font.letterSpacing: 1.3
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: panel.events.length > 0 ? `${panel.events.length}` : "brak"
                            color: "#789386"
                            font.pixelSize: 12
                        }
                    }

                    ListView {
                        id: eventList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6
                        clip: true
                        model: panel.events

                        delegate: Rectangle {
                            id: eventCard
                            required property var modelData
                            width: ListView.view ? ListView.view.width : 0
                            implicitHeight: eventBody.implicitHeight + 16
                            radius: 12
                            color: eventMouse.containsMouse ? "#1f2b26" : "#18201d"
                            border.width: 1
                            border.color: "#2a3632"

                            MouseArea {
                                id: eventMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !!eventCard.modelData.link
                                onClicked: if (eventCard.modelData.link) Qt.openUrlExternally(eventCard.modelData.link)
                            }

                            RowLayout {
                                id: eventBody
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 9
                                spacing: 9

                                Symbol {
                                    text: panel.eventIcon(eventCard.modelData.type)
                                    color: eventCard.modelData.type === "reminder" ? "#f6c177" : "#72d7ff"
                                    font.pixelSize: 17
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: eventCard.modelData.title || eventCard.modelData.type || ""
                                            color: "#e6eef2"
                                            font.pixelSize: 12
                                            font.bold: true
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: panel.ageSince(eventCard.modelData.ts)
                                            color: "#67827a"
                                            font.pixelSize: 10
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: eventCard.modelData.body || ""
                                        color: "#9bb5aa"
                                        font.pixelSize: 11
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: eventList.count === 0
                            text: "Brak powiadomień"
                            color: "#93a79f"
                            font.pixelSize: 14
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "↑↓ / j k — wybór   ·   ⏎ / o — otwórz link   ·   t — hermes-tui   ·   r — odśwież   ·   Esc — zamknij"
                color: "#67827a"
                font.pixelSize: 13
            }
        }
    }
}
