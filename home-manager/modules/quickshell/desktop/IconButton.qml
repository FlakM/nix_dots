import QtQuick

Rectangle {
    id: button

    property string icon
    property string statusText
    property string tooltip
    property bool active: false
    property color accent: "#72d7ff"
    signal clicked
    signal secondaryClicked
    signal wheel(real delta)

    implicitWidth: statusText ? buttonContent.implicitWidth + 24 : 48
    implicitHeight: 48
    radius: 15
    color: active ? Qt.alpha(accent, 0.22) : mouse.containsMouse ? "#70303b50" : "#55101520"
    border.width: 1
    border.color: active ? Qt.alpha(accent, 0.75) : mouse.containsMouse ? "#52647f" : "#304b5c76"

    Row {
        id: buttonContent
        anchors.centerIn: parent
        spacing: 6

        Symbol {
            text: button.icon
            color: button.active ? button.accent : "#c5d0e0"
            fill: button.active ? 1 : 0
            font.pixelSize: 25
        }
        Text {
            visible: button.statusText !== ""
            text: button.statusText
            color: "#dce6f5"
            font.pixelSize: 13
            font.bold: true
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: event => {
            if (event.button === Qt.RightButton)
                button.secondaryClicked()
            else
                button.clicked()
        }
        onWheel: event => button.wheel(event.angleDelta.y)
    }

    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
}
