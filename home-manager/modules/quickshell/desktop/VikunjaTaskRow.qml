import QtQuick
import QtQuick.Layouts

Rectangle {
    id: row

    required property var shell
    required property var task
    property bool showProject: true
    property bool focused: false
    property bool selected: false

    signal openRequested

    readonly property int priority: task.priority ?? 0
    readonly property bool important: priority >= 2
    readonly property color priorityColor: priority >= 4 ? "#ff7b86" : priority >= 2 ? "#f6c177" : "#72e4ae"
    readonly property string description: (task.description ?? "")
        .replace(/<br\s*\/?>/gi, " ")
        .replace(/<[^>]*>/g, " ")
        .trim()

    readonly property string dueLabel: {
        if (!task.due_date || task.due_date.startsWith("0001-")) return "Bez terminu"
        return new Date(task.due_date).toLocaleString(Qt.locale(), Locale.ShortFormat)
    }

    // Where the due date sits relative to today, used for colour and for the
    // cycle the due button walks through.
    readonly property string bucket: {
        if (!task.due_date || task.due_date.startsWith("0001-")) return "none"
        const due = new Date(task.due_date)
        const today = new Date()
        today.setHours(0, 0, 0, 0)
        const dueDay = new Date(due)
        dueDay.setHours(0, 0, 0, 0)
        const days = Math.round((dueDay - today) / 86400000)
        if (days < 0) return "overdue"
        if (days === 0) return "today"
        if (days === 1) return "tomorrow"
        if (days <= 7) return "week"
        return "later"
    }

    readonly property color dueColor: bucket === "overdue" ? "#ff7b86"
        : bucket === "today" ? "#f6c177"
        : bucket === "tomorrow" ? "#72e4ae"
        : "#8ca098"

    readonly property string nextDuePreset: {
        switch (bucket) {
        case "today": return "tomorrow"
        case "tomorrow": return "week"
        case "week": return "clear"
        default: return "today"
        }
    }

    readonly property string nextDueTooltip: {
        switch (nextDuePreset) {
        case "tomorrow": return "Termin: przesuń na jutro"
        case "week": return "Termin: przesuń o tydzień"
        case "clear": return "Termin: wyczyść"
        default: return "Termin: ustaw na dziś 18:00"
        }
    }

    width: ListView.view ? ListView.view.width : parent.width
    implicitHeight: body.implicitHeight + 26
    radius: 20
    color: selected ? "#2f4249" : hover.containsMouse ? "#303b3a" : focused ? "#25333a" : "#222b2a"
    border.width: selected ? 2 : 1
    border.color: selected ? "#7fd4f0" : focused ? "#5aa7c8" : hover.containsMouse ? "#527d70" : important ? "#4d5a45" : "#344641"

    RowLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 14
        spacing: 14

        Rectangle {
            Layout.preferredWidth: 46
            Layout.preferredHeight: 46
            radius: 14
            color: Qt.alpha(row.priorityColor, 0.14)
            Symbol {
                anchors.centerIn: parent
                text: row.priority >= 2 ? "priority_high" : "assignment"
                color: row.priorityColor
                fill: row.priority >= 2 ? 1 : 0
                font.pixelSize: 24
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    Layout.fillWidth: true
                    text: row.task.title
                    color: "#eef4f2"
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: row.priority > 0
                    Layout.preferredWidth: priorityText.implicitWidth + 12
                    Layout.preferredHeight: 20
                    radius: 7
                    color: Qt.alpha(row.priorityColor, 0.16)
                    Text {
                        id: priorityText
                        anchors.centerIn: parent
                        text: `P${row.priority}`
                        color: row.priorityColor
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: row.task.due_date && !row.task.due_date.startsWith("0001-")
                    ? `${row.showProject ? row.task.project_title + " · " : ""}termin: ${row.dueLabel}`
                    : `${row.showProject ? row.task.project_title + " · " : ""}bez terminu`
                color: row.dueColor
                font.pixelSize: 12
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: row.description !== ""
                text: row.description
                color: "#8ca098"
                font.pixelSize: 12
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        IconButton {
            icon: row.focused ? "pause" : "play_arrow"
            tooltip: row.focused ? "Przestań nad tym pracować" : "Pracuję nad tym teraz"
            accent: "#72d7ff"
            active: row.focused
            onClicked: row.shell.setVikunjaFocus(row.task.id, !row.focused)
        }

        IconButton {
            icon: "star"
            tooltip: row.important ? "Zdejmij z ważnych" : "Dodaj do ważnych (⭐)"
            accent: "#f6c177"
            active: row.important
            onClicked: row.shell.setVikunjaPriority(row.task.id, row.important ? 0 : 4)
        }

        IconButton {
            icon: "event"
            tooltip: row.nextDueTooltip
            accent: row.dueColor
            active: row.bucket !== "none"
            onClicked: row.shell.setVikunjaDue(row.task.id, row.nextDuePreset)
        }

        IconButton {
            icon: "check"
            tooltip: "Oznacz jako zrobione"
            accent: "#72e4ae"
            onClicked: row.shell.completeVikunjaTask(row.task.id)
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        z: -1
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.openRequested()
    }
}
