import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property var fallbackModel: ({
        state: "IDLE",
        stateLabel: "Idle",
        measurementValid: false,
        imuValid: false,
        headingAvailable: false,
        audioStale: true,
        energy: 0.0,
        headingNormalized: 0.0,
        sourceOffsetNormalized: 0.0,
        audioDotNormalized: 0.0
    })
    property var telemetryModel: null
    property var viewModel: telemetryModel ? telemetryModel : fallbackModel

    radius: 34
    color: "#ffffff"
    border.color: "#d7dfeb"
    border.width: 1
    clip: true

    property real pad: Math.max(28, width * 0.018)
    property real trackerX: width * 0.5
    property real trackerY: height * 0.18
    property real orbitRadius: Math.min(width, height) * 0.32
    property real sourceOrbitDeg: 90 - viewModel.audioDotNormalized * 90
    property real sourceX: trackerX + Math.cos(sourceOrbitDeg * Math.PI / 180.0) * orbitRadius
    property real sourceY: trackerY + Math.sin(sourceOrbitDeg * Math.PI / 180.0) * orbitRadius
    property real trackerTiltDeg: viewModel.headingNormalized * 26
    property bool sourceVisible: viewModel.headingAvailable
    property bool sensorWaveActive: sourceVisible && viewModel.measurementValid && !viewModel.audioStale

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#ffffff" }
            GradientStop { position: 1.0; color: "#fbfcfe" }
        }
    }

    Rectangle {
        id: stateChip
        width: Math.max(150, chipLabel.implicitWidth + 30)
        height: 42
        radius: 21
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: pad
        color: viewModel.state === "LOCKED" ? "#ddf7e5" : (viewModel.state === "TRACKING" ? "#fff1d9" : "#f3f6fb")

        Text {
            id: chipLabel
            anchors.centerIn: parent
            text: viewModel.stateLabel.toUpperCase()
            color: viewModel.state === "LOCKED" ? "#198038" : (viewModel.state === "TRACKING" ? "#9a6200" : "#64748b")
            font.pixelSize: 15
            font.weight: Font.DemiBold
        }
    }

    Repeater {
        model: 6

        Canvas {
            anchors.fill: parent
            opacity: viewModel.audioStale ? 0.10 : 0.28
            property int bandIndex: modelData

            Connections {
                target: root.telemetryModel
                function onTelemetryChanged() { requestPaint() }
            }

            Timer {
                interval: 16
                running: true
                repeat: true
                onTriggered: parent.requestPaint()
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()

                const left = root.width * 0.08
                const right = root.width * 0.92
                const centerX = root.sourceVisible ? root.sourceX : root.trackerX
                const span = right - left
                const baseY = root.height * (0.34 + bandIndex * 0.062)
                const amplitude = (15 + bandIndex * 8) * (0.18 + viewModel.energy * 0.95)
                const phase = Date.now() / 820 + bandIndex * 0.42

                ctx.beginPath()
                ctx.lineWidth = Math.max(2.1, 5.6 - bandIndex * 0.5)
                ctx.strokeStyle = Qt.rgba(0.04, 0.52, 1.0, 0.11 - bandIndex * 0.012)

                for (let i = 0; i <= 140; ++i) {
                    const t = i / 140
                    const x = left + span * t
                    const spread = (x - centerX) / (root.width * 0.40)
                    const envelope = Math.exp(-spread * spread * 1.8)
                    const y = baseY
                        + Math.sin(t * Math.PI * 2.1 + phase) * amplitude * envelope
                        + Math.cos(t * Math.PI * 3.0 - phase * 0.5) * amplitude * 0.14
                    if (i === 0)
                        ctx.moveTo(x, y)
                    else
                        ctx.lineTo(x, y)
                }

                ctx.stroke()
            }
        }
    }

    Canvas {
        anchors.fill: parent
        visible: root.sensorWaveActive
        opacity: root.sensorWaveActive ? (0.24 + viewModel.energy * 0.36) : 0.0

        Connections {
            target: root.telemetryModel
            function onTelemetryChanged() { parent.requestPaint() }
        }

        Timer {
            interval: 33
            running: true
            repeat: true
            onTriggered: parent.requestPaint()
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            if (!root.sensorWaveActive)
                return

            const dx = root.trackerX - root.sourceX
            const dy = root.trackerY - root.sourceY
            const distance = Math.sqrt(dx * dx + dy * dy)
            if (distance < 1)
                return

            const ux = dx / distance
            const uy = dy / distance
            const nx = -uy
            const ny = ux
            const arcCount = 3
            const energy = Math.max(0.0, Math.min(1.0, viewModel.energy))
            const now = Date.now()
            const duration = 980 - energy * 260
            const strokeBase = viewModel.state === "LOCKED" ? [0.19, 0.82, 0.35] : [0.04, 0.52, 1.0]

            for (let i = 0; i < arcCount; ++i) {
                const phase = (now / duration + i / arcCount) % 1.0
                const eased = phase * phase * (3.0 - 2.0 * phase)
                const travel = distance * (0.18 + eased * 0.58)
                const cx = root.sourceX + ux * travel
                const cy = root.sourceY + uy * travel
                const width = 34 + energy * 18 - eased * 9
                const tailDepth = 7 + (1.0 - eased) * 5
                const noseDepth = 16 + energy * 10 - eased * 6
                const alpha = (0.18 + energy * 0.42) * (1.0 - eased * 0.72)
                const leftX = cx - nx * width * 0.5 - ux * tailDepth
                const leftY = cy - ny * width * 0.5 - uy * tailDepth
                const rightX = cx + nx * width * 0.5 - ux * tailDepth
                const rightY = cy + ny * width * 0.5 - uy * tailDepth
                const tipX = cx + ux * noseDepth
                const tipY = cy + uy * noseDepth
                const trailCenterX = cx - ux * 8
                const trailCenterY = cy - uy * 8
                const trailLeftX = trailCenterX - nx * width * 0.34 - ux * tailDepth * 0.55
                const trailLeftY = trailCenterY - ny * width * 0.34 - uy * tailDepth * 0.55
                const trailRightX = trailCenterX + nx * width * 0.34 - ux * tailDepth * 0.55
                const trailRightY = trailCenterY + ny * width * 0.34 - uy * tailDepth * 0.55
                const trailTipX = trailCenterX + ux * noseDepth * 0.48
                const trailTipY = trailCenterY + uy * noseDepth * 0.48

                ctx.beginPath()
                ctx.lineWidth = 2.2 + energy * 1.6
                ctx.strokeStyle = Qt.rgba(strokeBase[0], strokeBase[1], strokeBase[2], alpha)
                ctx.moveTo(leftX, leftY)
                ctx.quadraticCurveTo(tipX, tipY, rightX, rightY)
                ctx.stroke()

                ctx.beginPath()
                ctx.lineWidth = 1.2 + energy * 0.8
                ctx.strokeStyle = Qt.rgba(1.0, 1.0, 1.0, alpha * 0.55)
                ctx.moveTo(trailLeftX, trailLeftY)
                ctx.quadraticCurveTo(trailTipX, trailTipY, trailRightX, trailRightY)
                ctx.stroke()
            }
        }
    }

    Item {
        id: trackerBlob
        width: 176
        height: 176
        x: trackerX - width / 2
        y: trackerY - height / 2
        rotation: trackerTiltDeg
        transformOrigin: Item.Center
        opacity: viewModel.imuValid ? 1.0 : 0.30
        Behavior on rotation { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#ffffff"
            border.color: "#d7dfeb"
            border.width: 1
        }

        Rectangle {
            width: 86
            height: 86
            radius: 43
            anchors.centerIn: parent
            color: "#f3f7fe"
            border.color: "#e0e7f2"
            border.width: 1
        }

        Rectangle {
            width: 22
            height: 22
            radius: 11
            anchors.centerIn: parent
            color: viewModel.state === "LOCKED" ? "#30d158" : "#0a84ff"
        }
    }

    Rectangle {
        width: root.width * 0.16
        height: width
        radius: width / 2
        x: sourceX - width / 2
        y: sourceY - height / 2
        color: viewModel.state === "LOCKED" ? "#30d158" : "#58a6ff"
        opacity: sourceVisible ? (0.14 + viewModel.energy * 0.10) : 0.0
        Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    Rectangle {
        width: 28
        height: 28
        radius: 14
        x: sourceX - width / 2
        y: sourceY - height / 2
        color: viewModel.state === "LOCKED" ? "#30d158" : "#0a84ff"
        border.color: "#ffffff"
        border.width: 4
        visible: sourceVisible
        opacity: sourceVisible ? 1.0 : 0.0
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }
        Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutBack; easing.overshoot: 1.08 } }
        Behavior on opacity { NumberAnimation { duration: 110 } }
    }
}
