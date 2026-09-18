import QtQuick

Text {
    id: symbol

    property real fill: 0
    property int symbolWeight: 500
    property int grade: 0

    color: "#dce6f5"
    font.family: "Material Symbols Rounded"
    font.pixelSize: 20
    font.variableAxes: {
        "FILL": fill,
        "GRAD": grade,
        "opsz": 24,
        "wght": symbolWeight
    }
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
}
