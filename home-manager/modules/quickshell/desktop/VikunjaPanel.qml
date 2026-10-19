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

    readonly property real cardWidth: Math.min(3600, panel.width - 96)
    readonly property real cardHeight: Math.min(1280, panel.height - 96)
    readonly property real columnsWidth: cardWidth - 60 - 54
    readonly property var weekProject: shell.vikunjaWeekProject
    readonly property var workProject: shell.vikunjaWorkProject
    readonly property var focusedTask: shell.vikunjaFocused

    // Task detail overlay: opened by clicking a row or ⏎, browsed with ↑↓.
    property int detailTaskId: 0
    readonly property var detailTask: detailTaskId > 0
        ? (visibleTasks.find(task => task.id === detailTaskId) || null)
        : null
    readonly property color detailPriorityColor: !detailTask ? "#72e4ae"
        : (detailTask.priority ?? 0) >= 4 ? "#ff7b86"
        : (detailTask.priority ?? 0) >= 2 ? "#f6c177"
        : "#72e4ae"
    readonly property string detailMeta: {
        if (!detailTask) return ""
        const parts = [detailTask.project_title || "?"]
        if (detailTask.identifier) parts.push(detailTask.identifier)
        if (detailTask.created) parts.push(`utworzono ${Qt.formatDateTime(new Date(detailTask.created), "dd.MM.yyyy HH:mm")}`)
        return parts.join(" · ")
    }

    function openDetails(taskId) {
        detailTaskId = taskId
    }

    function closeDetails() {
        detailTaskId = 0
    }

    function openSelectedInBrowser() {
        const task = selectedTask()
        if (!task) return
        detailTaskId = 0
        shell.overlayMode = ""
        openTask(task.id)
    }

    // Vikunja stores rich text; the overlay shows it as plain multi-line text.
    function plainText(value) {
        if (!value) return ""
        return value
            .replace(/<br\s*\/?>/gi, "\n")
            .replace(/<\/p>/gi, "\n")
            .replace(/<[^>]*>/g, "")
            .replace(/&nbsp;/g, " ")
            .replace(/&amp;/g, "&")
            .replace(/&lt;/g, "<")
            .replace(/&gt;/g, ">")
            .replace(/\n{3,}/g, "\n\n")
            .trim()
    }

    // Re-evaluated after midnight so the week range and day cards roll over.
    property int dayTick: 0

    function startOfWeek() {
        const d = new Date()
        d.setHours(0, 0, 0, 0)
        d.setDate(d.getDate() - ((d.getDay() + 6) % 7))
        return d
    }

    function endOfWeek() {
        const d = startOfWeek()
        d.setDate(d.getDate() + 7)
        return d
    }

    function taskDue(task) {
        if (!task.due_date || task.due_date.startsWith("0001-")) return null
        return new Date(task.due_date)
    }

    function compareDue(a, b) {
        const da = taskDue(a)
        const db = taskDue(b)
        if (!da && !db) return (b.priority ?? 0) - (a.priority ?? 0)
        if (!da) return 1
        if (!db) return -1
        return da - db
    }

    function comparePriority(a, b) {
        const pa = a.priority ?? 0
        const pb = b.priority ?? 0
        if (pa !== pb) return pb - pa
        return compareDue(a, b)
    }

    function projectTasks(project) {
        if (!project) return []
        return shell.vikunjaTasks
            .filter(task => task.project_id === project.id)
            .sort(comparePriority)
    }

    // My "this week" project is the plan; the shared Dom project is the pool it
    // is filled from; Coralogix is the work queue.
    readonly property var weekTasks: {
        const tick = dayTick
        return projectTasks(weekProject)
    }
    readonly property var workTasks: {
        const tick = dayTick
        return projectTasks(workProject)
    }

    // Keyboard order: current task, then the three task columns.
    readonly property var visibleTasks: {
        const seen = {}
        const out = []
        const add = list => {
            for (let i = 0; i < list.length; i++) {
                const task = list[i]
                if (seen[task.id]) continue
                seen[task.id] = true
                out.push(task)
            }
        }
        if (focusedTask) add([focusedTask])
        add(weekTasks)
        add(workTasks)
        return out
    }

    function columns() {
        const lists = []
        if (focusedTask) lists.push([focusedTask])
        lists.push(weekTasks)
        lists.push(workTasks)
        return lists
    }

    property int selectedId: 0
    property bool selectionTouched: false
    readonly property int selectedIndex: visibleTasks.findIndex(task => task.id === selectedId)

    readonly property var weekDays: {
        const tick = dayTick
        const start = startOfWeek()
        const todayKey = Qt.formatDate(new Date(), "yyyy-MM-dd")
        const days = []
        for (let i = 0; i < 7; i++) {
            const date = new Date(start)
            date.setDate(start.getDate() + i)
            const key = Qt.formatDate(date, "yyyy-MM-dd")
            days.push({
                key: key,
                label: `${panel.weekdayNames[(date.getDay() + 6) % 7]} ${Qt.formatDate(date, "dd.MM")}`,
                today: key === todayKey,
                events: shell.calendarWeek
                    .filter(event => event.date === key)
                    .sort((a, b) => (a.start || "").localeCompare(b.start || ""))
            })
        }
        return days
    }

    // Qt follows the session locale (en_US here), so the Polish weekday names
    // are spelled out instead of relying on "ddd".
    readonly property var weekdayNames: ["pon", "wt", "śr", "czw", "pt", "sob", "ndz"]

    readonly property string weekRange: {
        const tick = dayTick
        const start = startOfWeek()
        const end = endOfWeek()
        end.setDate(end.getDate() - 1)
        return `${Qt.formatDate(start, "dd.MM")} – ${Qt.formatDate(end, "dd.MM.yyyy")}`
    }

    function selectedTask() {
        return selectedIndex >= 0 ? visibleTasks[selectedIndex] : null
    }

    function syncSelection() {
        if (!visible) return
        if (visibleTasks.length === 0) {
            selectedId = 0
            return
        }
        if (!selectionTouched || selectedIndex < 0) selectedId = visibleTasks[0].id
    }

    function moveSelection(delta) {
        if (visibleTasks.length === 0) return
        selectionTouched = true
        const current = selectedIndex
        const next = current < 0
            ? (delta > 0 ? 0 : visibleTasks.length - 1)
            : Math.max(0, Math.min(visibleTasks.length - 1, current + delta))
        selectedId = visibleTasks[next].id
        if (detailTaskId > 0) detailTaskId = selectedId
        ensureVisible(selectedId)
    }

    // ← / → hop to the neighbouring column that has tasks, keeping the row
    // index (clamped to the shorter column).
    function moveColumn(delta) {
        const lists = columns()
        let current = -1
        let index = 0
        for (let i = 0; i < lists.length; i++) {
            const at = lists[i].findIndex(task => task.id === selectedId)
            if (at >= 0) {
                current = i
                index = at
                break
            }
        }
        selectionTouched = true
        if (current < 0) {
            for (let i = 0; i < lists.length; i++) {
                if (lists[i].length > 0) {
                    selectedId = lists[i][0].id
                    ensureVisible(selectedId)
                    return
                }
            }
            return
        }
        for (let i = current + delta; i >= 0 && i < lists.length; i += delta) {
            if (lists[i].length > 0) {
                const target = Math.min(index, lists[i].length - 1)
                selectedId = lists[i][target].id
                ensureVisible(selectedId)
                return
            }
        }
    }

    function ensureVisible(taskId) {
        if (focusedTask && focusedTask.id === taskId) focusList.positionViewAtIndex(0, ListView.Contain)
        let index = weekTasks.findIndex(task => task.id === taskId)
        if (index >= 0) weekList.positionViewAtIndex(index, ListView.Contain)
        index = workTasks.findIndex(task => task.id === taskId)
        if (index >= 0) workList.positionViewAtIndex(index, ListView.Contain)
    }

    function nextDuePreset(task) {
        const due = taskDue(task)
        if (!due) return "today"
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const dueDay = new Date(due)
        dueDay.setHours(0, 0, 0, 0)
        const days = Math.round((dueDay - today) / 86400000)
        if (days === 0) return "tomorrow"
        if (days === 1) return "week"
        if (days >= 2 && days <= 7) return "clear"
        return "today"
    }

    function openTask(taskId) {
        Qt.openUrlExternally(`https://tasks.house.flakm.com/tasks/${taskId}`)
    }

    function activateSelected() {
        const task = selectedTask()
        if (task) openDetails(task.id)
    }

    function toggleSelectedFocus() {
        const task = selectedTask()
        if (!task) return
        shell.setVikunjaFocus(task.id, !(focusedTask && focusedTask.id === task.id))
    }

    function toggleSelectedPriority() {
        const task = selectedTask()
        if (!task) return
        shell.setVikunjaPriority(task.id, (task.priority ?? 0) >= 2 ? 0 : 4)
    }

    function cycleSelectedDue() {
        const task = selectedTask()
        if (!task) return
        shell.setVikunjaDue(task.id, nextDuePreset(task))
    }

    function completeSelected() {
        const task = selectedTask()
        if (!task) return
        shell.completeVikunjaTask(task.id)
    }

    // `e` in the preview: hand the description to vim in a terminal window.
    function editSelectedDescription() {
        const task = selectedTask()
        if (!task) return
        detailTaskId = 0
        shell.overlayMode = ""
        Quickshell.execDetached(["vikunja-edit-description", `${task.id}`])
    }

    function refreshAll() {
        shell.refreshVikunja()
        shell.refreshCalendar()
    }

    function handleKey(event) {
        switch (event.key) {
        case Qt.Key_Escape:
            if (detailTaskId > 0) {
                closeDetails()
                return true
            }
            shell.overlayMode = ""
            return true
        case Qt.Key_Q:
            shell.overlayMode = ""
            return true
        case Qt.Key_O:
            openSelectedInBrowser()
            return true
        case Qt.Key_E:
            editSelectedDescription()
            return true
        case Qt.Key_Down:
        case Qt.Key_J:
            moveSelection(1)
            return true
        case Qt.Key_Up:
        case Qt.Key_K:
            moveSelection(-1)
            return true
        case Qt.Key_Right:
        case Qt.Key_L:
            moveColumn(1)
            return true
        case Qt.Key_Left:
        case Qt.Key_H:
            moveColumn(-1)
            return true
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateSelected()
            return true
        case Qt.Key_P:
            toggleSelectedFocus()
            return true
        case Qt.Key_S:
            toggleSelectedPriority()
            return true
        case Qt.Key_T:
            cycleSelectedDue()
            return true
        case Qt.Key_D:
            completeSelected()
            return true
        case Qt.Key_R:
            refreshAll()
            return true
        }
        return false
    }

    function calendarColor(calendar) {
        if (calendar.includes("coralogix")) return "#72d7ff"
        if (calendar.includes("group.calendar.google.com")) return "#d79bff"
        return "#9aa8bb"
    }

    onVisibleChanged: {
        if (!visible) return
        selectionTouched = false
        syncSelection()
        keyHandler.forceActiveFocus()
        refreshAll()
    }

    onVisibleTasksChanged: syncSelection()

    Timer {
        interval: 300000
        running: true
        repeat: true
        onTriggered: panel.dayTick += 1
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
                        text: "calendar_view_week"
                        color: "#72e4ae"
                        fill: 1
                        font.pixelSize: 29
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text { text: "Tydzień"; color: "#f5f8fd"; font.pixelSize: 28; font.bold: true }
                    Text {
                        text: shell.vikunjaLoading ? "Odświeżam..." : `${panel.weekRange} · ${panel.weekTasks.length} w tygodniu · ${panel.workTasks.length} Coralogix · ${shell.calendarWeek.length} wydarzeń`
                        color: shell.vikunjaError ? "#ff8d98" : "#9bb5aa"
                        font.pixelSize: 14
                    }
                }
                IconButton {
                    icon: "open_in_new"
                    tooltip: "Otwórz Vikunję"
                    onClicked: Qt.openUrlExternally("https://tasks.house.flakm.com/")
                }
                IconButton {
                    icon: "refresh"
                    tooltip: "Odśwież (r)"
                    active: shell.vikunjaLoading
                    onClicked: panel.refreshAll()
                }
                IconButton {
                    icon: "close"
                    tooltip: "Zamknij (Esc)"
                    onClicked: panel.shell.overlayMode = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: panel.focusedTask !== null
                spacing: 12
                Text { text: "W TOKU"; color: "#72d7ff"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                ListView {
                    id: focusList
                    Layout.fillWidth: true
                    Layout.preferredHeight: contentHeight
                    spacing: 9
                    clip: true
                    model: panel.focusedTask ? [panel.focusedTask] : []
                    delegate: VikunjaTaskRow {
                        required property var modelData
                        shell: panel.shell
                        task: modelData
                        focused: true
                        selected: panel.selectedId === modelData.id
                        onOpenRequested: panel.openDetails(modelData.id)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 18

                // ── my week plan ────────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: Math.round(panel.columnsWidth * 0.40)
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: `${(panel.weekProject?.title || "Mój tydzień").toUpperCase()}`; color: "#72e4ae"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
                        Item { Layout.fillWidth: true }
                        Text { text: `${panel.weekTasks.length}`; color: "#789386"; font.pixelSize: 12 }
                    }

                    ListView {
                        id: weekList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        clip: true
                        model: panel.weekTasks

                        delegate: VikunjaTaskRow {
                            required property var modelData
                            shell: panel.shell
                            task: modelData
                            showProject: false
                            selected: panel.selectedId === modelData.id
                            onOpenRequested: panel.openDetails(modelData.id)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !shell.vikunjaLoading && weekList.count === 0
                            text: "Pusty plan tygodnia — przenieś tu taski z Dom albo dodaj nowe"
                            color: "#93a79f"
                            font.pixelSize: 15
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // ── Coralogix ───────────────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: Math.round(panel.columnsWidth * 0.28)
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: `${(panel.workProject?.title || "Prace").toUpperCase()}`; color: "#72d7ff"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
                        Item { Layout.fillWidth: true }
                        Text { text: `${panel.workTasks.length}`; color: "#789386"; font.pixelSize: 12 }
                    }

                    ListView {
                        id: workList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 8
                        clip: true
                        model: panel.workTasks

                        delegate: VikunjaTaskRow {
                            required property var modelData
                            shell: panel.shell
                            task: modelData
                            showProject: false
                            selected: panel.selectedId === modelData.id
                            onOpenRequested: panel.openDetails(modelData.id)
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: workList.count === 0
                            text: "Brak otwartych tasków"
                            color: "#93a79f"
                            font.pixelSize: 15
                        }
                    }
                }

                // ── calendar: this week ─────────────────────────────────────
                ColumnLayout {
                    Layout.preferredWidth: Math.round(panel.columnsWidth * 0.32)
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        Text { text: "KALENDARZ · TEN TYDZIEŃ"; color: "#a9b5c8"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.3 }
                        Item { Layout.fillWidth: true }
                        Text { text: `${shell.calendarWeek.length} wydarzeń`; color: "#789386"; font.pixelSize: 12 }
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6
                        clip: true
                        model: panel.weekDays

                        delegate: Rectangle {
                            id: dayCard
                            required property var modelData
                            width: ListView.view ? ListView.view.width : parent.width
                            implicitHeight: dayBody.implicitHeight + 16
                            radius: 14
                            color: modelData.today ? "#233029" : "#1f2729"
                            border.width: 1
                            border.color: modelData.today ? "#4a7d63" : "#2f3d42"

                            ColumnLayout {
                                id: dayBody
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 10
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: dayCard.modelData.label
                                        color: dayCard.modelData.today ? "#72e4ae" : "#c9d6d2"
                                        font.pixelSize: 13
                                        font.bold: true
                                    }
                                    Rectangle {
                                        visible: dayCard.modelData.today
                                        Layout.preferredWidth: todayText.implicitWidth + 10
                                        Layout.preferredHeight: 16
                                        radius: 5
                                        color: "#2a72e4ae"
                                        Text {
                                            id: todayText
                                            anchors.centerIn: parent
                                            text: "DZIŚ"
                                            color: "#72e4ae"
                                            font.pixelSize: 9
                                            font.bold: true
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: dayCard.modelData.events.length === 0 ? "wolne" : `${dayCard.modelData.events.length} wyd.`
                                        color: dayCard.modelData.events.length === 0 ? "#5d6f6a" : "#8ca098"
                                        font.pixelSize: 11
                                    }
                                }

                                Repeater {
                                    model: dayCard.modelData.events

                                    delegate: RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Text {
                                            Layout.preferredWidth: 54
                                            text: modelData.all_day ? "cały dzień" : modelData.start
                                            color: "#72d7ff"
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 3
                                            Layout.preferredHeight: 15
                                            radius: 2
                                            color: panel.calendarColor(modelData.calendar)
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            color: "#e6eef2"
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                Text {
                                    visible: dayCard.modelData.events.length === 0
                                    text: "—"
                                    color: "#4d5f5b"
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "↑↓ / j k — wybór   ·   ←→ / h l — kolumna   ·   ⏎ — szczegóły · o — otwórz w Vikunji · e — edytuj opis   ·   p — pracuję nad tym   ·   s — ważne   ·   t — termin   ·   d — zrobione   ·   r — odśwież   ·   Esc — zamknij"
                color: "#67827a"
                font.pixelSize: 13
            }
        }

        // ── task details ─────────────────────────────────────────────────────
        Rectangle {
            id: detailOverlay
            visible: panel.detailTask !== null
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 30
            anchors.rightMargin: 30
            anchors.topMargin: 100
            height: Math.min(detailBody.implicitHeight + 52, parent.height - 130)
            radius: 24
            color: "#f518221f"
            border.width: 1
            border.color: "#5aa7c8"
            clip: true

            MouseArea { anchors.fill: parent; onClicked: event => event.accepted = true }

            ColumnLayout {
                id: detailBody
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 26
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    Rectangle {
                        Layout.preferredWidth: 54
                        Layout.preferredHeight: 54
                        radius: 17
                        color: Qt.alpha(panel.detailPriorityColor, 0.16)
                        Symbol {
                            anchors.centerIn: parent
                            text: (panel.detailTask?.priority ?? 0) >= 2 ? "priority_high" : "assignment"
                            color: panel.detailPriorityColor
                            fill: (panel.detailTask?.priority ?? 0) >= 2 ? 1 : 0
                            font.pixelSize: 27
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3
                        Text {
                            Layout.fillWidth: true
                            text: panel.detailTask?.title || ""
                            color: "#f3f8f5"
                            font.pixelSize: 26
                            font.bold: true
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            Layout.fillWidth: true
                            text: panel.detailMeta
                            color: "#8ca098"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                    }
                    IconButton {
                        icon: "open_in_new"
                        tooltip: "Otwórz w Vikunji (o)"
                        onClicked: panel.openSelectedInBrowser()
                    }
                    IconButton {
                        icon: "close"
                        tooltip: "Wróć do listy (Esc)"
                        onClicked: panel.closeDetails()
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Rectangle {
                        Layout.preferredWidth: priorityDetail.implicitWidth + 16
                        Layout.preferredHeight: 26
                        radius: 8
                        color: Qt.alpha(panel.detailPriorityColor, 0.16)
                        Text {
                            id: priorityDetail
                            anchors.centerIn: parent
                            text: `PRIORYTET ${panel.detailTask?.priority ?? 0}`
                            color: panel.detailPriorityColor
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: dueDetail.implicitWidth + 16
                        Layout.preferredHeight: 26
                        radius: 8
                        color: panel.detailTask && panel.taskDue(panel.detailTask) ? "#2a72d7ff" : "#26323838"
                        Text {
                            id: dueDetail
                            anchors.centerIn: parent
                            text: panel.detailTask && panel.taskDue(panel.detailTask)
                                ? `TERMIN ${Qt.formatDateTime(panel.taskDue(panel.detailTask), "dd.MM.yyyy HH:mm")}`
                                : "BEZ TERMINU"
                            color: panel.detailTask && panel.taskDue(panel.detailTask) ? "#72d7ff" : "#93a79f"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    Rectangle {
                        visible: panel.focusedTask !== null && panel.detailTask !== null && panel.focusedTask.id === panel.detailTask.id
                        Layout.preferredWidth: focusDetail.implicitWidth + 16
                        Layout.preferredHeight: 26
                        radius: 8
                        color: "#2a72d7ff"
                        Text {
                            id: focusDetail
                            anchors.centerIn: parent
                            text: "W TOKU"
                            color: "#72d7ff"
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }

                    Repeater {
                        model: panel.detailTask?.labels ?? []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredWidth: labelText.implicitWidth + 16
                            Layout.preferredHeight: 26
                            radius: 8
                            color: "#2d3b36"
                            Text {
                                id: labelText
                                anchors.centerIn: parent
                                text: `#${modelData.title}`
                                color: "#a9c4b8"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    Repeater {
                        model: panel.detailTask?.assignees ?? []
                        delegate: Rectangle {
                            required property var modelData
                            Layout.preferredWidth: assigneeText.implicitWidth + 16
                            Layout.preferredHeight: 26
                            radius: 8
                            color: "#2b3a45"
                            Text {
                                id: assigneeText
                                anchors.centerIn: parent
                                text: `@${modelData.username}`
                                color: "#9dc3d4"
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(descriptionText.implicitHeight + 8, 420)
                    contentHeight: descriptionText.implicitHeight + 8
                    clip: true

                    Text {
                        id: descriptionText
                        width: parent.width
                        text: panel.plainText(panel.detailTask?.description) || "— brak opisu —"
                        color: "#d7e3e0"
                        font.pixelSize: 15
                        lineHeight: 1.3
                        wrapMode: Text.WordWrap
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    IconButton {
                        icon: panel.focusedTask !== null && panel.detailTask !== null && panel.focusedTask.id === panel.detailTask.id ? "pause" : "play_arrow"
                        tooltip: "Pracuję nad tym (p)"
                        accent: "#72d7ff"
                        active: panel.focusedTask !== null && panel.detailTask !== null && panel.focusedTask.id === panel.detailTask.id
                        onClicked: panel.toggleSelectedFocus()
                    }
                    IconButton {
                        icon: "star"
                        tooltip: "Ważne (s)"
                        accent: "#f6c177"
                        active: (panel.detailTask?.priority ?? 0) >= 2
                        onClicked: panel.toggleSelectedPriority()
                    }
                    IconButton {
                        icon: "event"
                        tooltip: "Przesuń termin (t)"
                        accent: "#72d7ff"
                        onClicked: panel.cycleSelectedDue()
                    }
                    IconButton {
                        icon: "check"
                        tooltip: "Zrobione (d)"
                        accent: "#72e4ae"
                        onClicked: panel.completeSelected()
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "p — pracuję · s — ważne · t — termin · d — zrobione · e — edytuj opis w vimie · ↑↓ — następny task · o — przeglądarka · Esc — wróć"
                        color: "#67827a"
                        font.pixelSize: 12
                    }
                }
            }
        }
    }
}
