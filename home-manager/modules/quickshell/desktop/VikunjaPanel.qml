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
    readonly property var focusedTask: shell.vikunjaFocused
    readonly property var importantTasks: shell.vikunjaImportant.filter(task => task.id !== focusedTask?.id)
    // Each task appears once: the focused one in W TOKU, important ones in WAŻNE,
    // everything else in the pinned project list. Otherwise keyboard navigation
    // would stop on the same task twice.
    readonly property var projectTasks: shell.vikunjaTasks.filter(task =>
        task.project_id === project?.id
        && task.id !== focusedTask?.id
        && !importantTasks.some(other => other.id === task.id))
    readonly property int projectOpenCount: shell.vikunjaTasks.filter(task =>
        task.project_id === project?.id && task.id !== focusedTask?.id).length

    // Flat order the keyboard walks: current task, important tasks, then the
    // pinned project's tasks. selectedId survives refreshes, so acting on a task
    // (star, due date, focus) keeps the cursor on it.
    readonly property var visibleTasks: {
        let out = []
        if (focusedTask) out.push(focusedTask)
        out = out.concat(importantTasks)
        return out.concat(projectTasks)
    }
    property int selectedId: 0
    // Cleared when the panel opens, so the first refresh lands the cursor on the
    // top task; once the user moves, the selection sticks to that task.
    property bool selectionTouched: false
    readonly property int selectedIndex: visibleTasks.findIndex(task => task.id === selectedId)

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
        ensureVisible(selectedId)
    }

    function ensureVisible(taskId) {
        if (focusedTask && focusedTask.id === taskId) focusList.positionViewAtIndex(0, ListView.Contain)
        let index = importantTasks.findIndex(task => task.id === taskId)
        if (index >= 0) importantList.positionViewAtIndex(index, ListView.Contain)
        index = projectTasks.findIndex(task => task.id === taskId)
        if (index >= 0) taskList.positionViewAtIndex(index, ListView.Contain)
    }

    function nextDuePreset(task) {
        if (!task.due_date || task.due_date.startsWith("0001-")) return "today"
        const due = new Date(task.due_date)
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

    function activateSelected() {
        const task = selectedTask()
        if (!task) return
        openTask(task.id)
    }

    function toggleSelectedFocus() {
        const task = selectedTask()
        if (!task) return
        panel.shell.setVikunjaFocus(task.id, !(focusedTask && focusedTask.id === task.id))
    }

    function toggleSelectedPriority() {
        const task = selectedTask()
        if (!task) return
        panel.shell.setVikunjaPriority(task.id, (task.priority ?? 0) >= 2 ? 0 : 4)
    }

    function cycleSelectedDue() {
        const task = selectedTask()
        if (!task) return
        panel.shell.setVikunjaDue(task.id, nextDuePreset(task))
    }

    function completeSelected() {
        const task = selectedTask()
        if (!task) return
        panel.shell.completeVikunjaTask(task.id)
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
        }
        return false
    }

    function openTask(taskId) {
        Qt.openUrlExternally(`https://tasks.house.flakm.com/tasks/${taskId}`)
    }

    onVisibleChanged: {
        if (!visible) return
        selectionTouched = false
        syncSelection()
        keyHandler.forceActiveFocus()
        shell.refreshVikunja()
    }

    onVisibleTasksChanged: syncSelection()

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
        width: Math.min(980, panel.width - 48)
        height: Math.min(940, panel.height - 96)
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
            spacing: 16

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
                        text: shell.vikunjaLoading ? "Odświeżam taski..."
                            : shell.vikunjaError ? shell.vikunjaError
                            : `${panel.importantTasks.length} ważnych · ${panel.projectOpenCount} w ${panel.project?.title || "projekcie"}`
                        color: shell.vikunjaError ? "#ff8d98" : "#9bb5aa"
                        font.pixelSize: 15
                    }
                }
                IconButton {
                    icon: "open_in_new"
                    tooltip: "Otwórz Vikunję"
                    onClicked: Qt.openUrlExternally("https://tasks.house.flakm.com/")
                }
                IconButton {
                    icon: "refresh"
                    tooltip: "Odśwież"
                    active: shell.vikunjaLoading
                    onClicked: shell.refreshVikunja()
                }
                IconButton {
                    icon: "close"
                    tooltip: "Zamknij (Esc)"
                    onClicked: panel.shell.overlayMode = ""
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 108
                    radius: 24
                    color: "#2d3b36"
                    border.width: 1
                    border.color: "#6672e4ae"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 18
                        Rectangle {
                            Layout.preferredWidth: 60
                            Layout.preferredHeight: 60
                            radius: 20
                            color: "#2872e4ae"
                            Symbol { anchors.centerIn: parent; text: "home_work"; color: "#72e4ae"; fill: 1; font.pixelSize: 30 }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: panel.project?.title || "Pinned project"
                                    color: "#f3f8f5"
                                    font.pixelSize: 21
                                    font.bold: true
                                }
                                Symbol { text: "keep"; color: "#72e4ae"; fill: 1; font.pixelSize: 17 }
                                Item { Layout.fillWidth: true }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: panel.project?.description || "Twój przypięty projekt (ulubiony albo pierwszy)"
                                color: "#a5b8b0"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }
                        ColumnLayout {
                            spacing: 0
                            Text { text: panel.projectOpenCount; color: "#f3f8f5"; font.pixelSize: 28; font.bold: true; Layout.alignment: Qt.AlignHCenter }
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
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 108
                    radius: 24
                    color: "#3a3427"
                    border.width: 1
                    border.color: "#5f5433"
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Symbol { text: "star"; color: "#f6c177"; fill: 1; font.pixelSize: 25; Layout.alignment: Qt.AlignHCenter }
                        Text { text: panel.importantTasks.length; color: "#f6c177"; font.pixelSize: 22; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "WAŻNE"; color: "#c9b077"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1; Layout.alignment: Qt.AlignHCenter }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 108
                    radius: 24
                    color: "#292f3a"
                    border.width: 1
                    border.color: "#3f5261"
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 4
                        Symbol { text: "checklist"; color: "#72d7ff"; font.pixelSize: 25; Layout.alignment: Qt.AlignHCenter }
                        Text { text: shell.vikunjaTaskCount; color: "#f2f6fc"; font.pixelSize: 22; font.bold: true; Layout.alignment: Qt.AlignHCenter }
                        Text { text: "WSZYSTKIE"; color: "#8298aa"; font.pixelSize: 10; font.bold: true; font.letterSpacing: 1; Layout.alignment: Qt.AlignHCenter }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: panel.focusedTask !== null
                Text { text: "W TOKU"; color: "#72d7ff"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                Item { Layout.fillWidth: true }
                Text { text: "▶ przy zadaniu ustawia bieżący task (jeden naraz)"; color: "#789386"; font.pixelSize: 12 }
            }

            ListView {
                id: focusList
                Layout.fillWidth: true
                Layout.preferredHeight: contentHeight
                visible: panel.focusedTask !== null
                spacing: 9
                clip: true
                model: panel.focusedTask ? [panel.focusedTask] : []

                delegate: VikunjaTaskRow {
                    required property var modelData
                    shell: panel.shell
                    task: modelData
                    focused: true
                    selected: panel.selectedId === modelData.id
                    onOpenRequested: panel.openTask(modelData.id)
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: "WAŻNE (⭐ = PRIORYTET 4)"; color: "#c9b077"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                Item { Layout.fillWidth: true }
                Text { text: "Gwiazdka dodaje, ✓ zamyka, ikona kalendarza przesuwa termin"; color: "#789386"; font.pixelSize: 12 }
            }

            ListView {
                id: importantList
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 420)
                spacing: 9
                clip: true
                model: panel.importantTasks
                visible: panel.importantTasks.length > 0

                delegate: VikunjaTaskRow {
                    required property var modelData
                    shell: panel.shell
                    task: modelData
                    selected: panel.selectedId === modelData.id
                    onOpenRequested: panel.openTask(modelData.id)
                }
            }

            Text {
                visible: panel.importantTasks.length === 0
                Layout.fillWidth: true
                text: shell.vikunjaLoading ? "Wczytuję..." : "Nic nie jest oznaczone jako ważne — ⭐ przy zadaniu doda je tutaj."
                color: "#93a79f"
                font.pixelSize: 14
            }

            RowLayout {
                Layout.fillWidth: true
                Text { text: `PROJEKT: ${(panel.project?.title || "").toUpperCase()}`; color: "#789386"; font.pixelSize: 11; font.bold: true; font.letterSpacing: 1.4 }
                Item { Layout.fillWidth: true }
                Text { text: "Klik w zadanie otwiera je w przeglądarce"; color: "#789386"; font.pixelSize: 12 }
            }

            ListView {
                id: taskList
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 9
                clip: true
                model: panel.projectTasks

                delegate: VikunjaTaskRow {
                    required property var modelData
                    shell: panel.shell
                    task: modelData
                    showProject: false
                    selected: panel.selectedId === modelData.id
                    onOpenRequested: panel.openTask(modelData.id)
                }

                Text {
                    anchors.centerIn: parent
                    visible: !shell.vikunjaLoading && taskList.count === 0
                    text: shell.vikunjaError || "Wszystko zrobione 🎉"
                    color: "#93a79f"
                    font.pixelSize: 18
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: "↑↓ / j k — wybór   ·   ⏎ — otwórz w Vikunji   ·   p — pracuję nad tym   ·   s — ważne   ·   t — termin   ·   d — zrobione   ·   Esc — zamknij"
                color: "#67827a"
                font.pixelSize: 12
            }
        }
    }
}
