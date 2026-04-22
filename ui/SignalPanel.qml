import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var fallbackModel: ({
        stateLabel: "Idle",
        audioStatusLabel: "AUDIO STALE",
        imuStatusLabel: "IMU UNAVAILABLE",
        levelText: "00.0 dB",
        angleText: "--",
        smoothedText: "+00.0°",
        headingText: "--",
        stateDuration: 0.0
    })
    property var telemetryModel: null
    property var viewModel: telemetryModel ? telemetryModel : fallbackModel
    property real rmsReference: 560000.0
    property real dbCalibrationOffset: 40.0
    property real greenThreshold: 65.0
    property real yellowThreshold: 85.0

    function rawDbFromRms(rms) {
        if (rms <= 0)
            return 0.0
        return 20.0 * (Math.log(rms / rmsReference) / Math.LN10) + dbCalibrationOffset
    }

    function noiseBand(dbValue) {
        if (dbValue >= yellowThreshold)
            return "RED"
        if (dbValue >= greenThreshold)
            return "YELLOW"
        return "GREEN"
    }

    function noiseFill(band) {
        if (band === "RED")
            return "#fff1f0"
        if (band === "YELLOW")
            return "#fff8e7"
        return "#edf9f0"
    }

    function noiseAccent(band) {
        if (band === "RED")
            return "#d92d20"
        if (band === "YELLOW")
            return "#b54708"
        return "#15803d"
    }

    radius: 30
    color: "#ffffff"
    border.color: "#d7dfeb"
    border.width: 1

    property real pad: 28

    Column {
        anchors.fill: parent
        anchors.margins: pad
        spacing: 18

        Row {
            width: parent.width
            spacing: 12

            Column {
                width: parent.width - statusChips.width - 12
                spacing: 6

                Text {
                    text: "Metrics"
                    color: "#101828"
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                }

            }

            Column {
                id: statusChips
                spacing: 10

                Repeater {
                    model: [
                        { label: viewModel.imuStatusLabel, fill: viewModel.imuStatusLabel === "IMU LIVE" ? "#edf5ff" : "#fff0ee", color: viewModel.imuStatusLabel === "IMU LIVE" ? "#0a84ff" : "#d03a2f" }
                    ]

                    Rectangle {
                        width: Math.max(170, chipText.implicitWidth + 28)
                        height: 38
                        radius: 19
                        color: modelData.fill

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: modelData.color
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }

        GridLayout {
            width: parent.width
            columns: 2
            rowSpacing: 16
            columnSpacing: 16

            Rectangle {
                id: audioCard
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                radius: 24
                property real liveDb: root.rawDbFromRms(viewModel.rms || 0)
                property string band: root.noiseBand(liveDb)
                color: root.noiseFill(band)
                border.color: Qt.darker(color, 1.08)
                border.width: 1

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Row {
                        width: parent.width
                        spacing: 8

                        Text {
                            text: "Audio level"
                            color: "#64748b"
                            font.pixelSize: 15
                        }

                        Rectangle {
                            width: Math.max(68, bandText.implicitWidth + 18)
                            height: 24
                            radius: 12
                            color: root.noiseAccent(audioCard.band)
                            opacity: 0.14

                            Text {
                                id: bandText
                                anchors.centerIn: parent
                                text: audioCard.band
                                color: root.noiseAccent(audioCard.band)
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                    }

                    Text {
                        text: `${Math.round(audioCard.liveDb)} dB`
                        color: root.noiseAccent(audioCard.band)
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 104
                radius: 24
                color: "#f7f9fd"
                border.color: "#dbe3ef"
                border.width: 1

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 18
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        text: "Angle"
                        color: "#64748b"
                        font.pixelSize: 15
                    }

                    Text {
                        text: viewModel.angleText
                        color: "#101828"
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }
            }
        }

        Item {
            width: 1
            height: Math.max(0, root.height - (statusChips.height + 104 * 2 + 16 + 64 + pad * 2 + 18 * 2 + 34))
        }

    }
}
