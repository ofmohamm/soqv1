import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property var fallbackModel: ({
        historyPoints: [],
        audioStatusLabel: "AUDIO STALE"
    })
    property var telemetryModel: null
    property var viewModel: telemetryModel ? telemetryModel : fallbackModel

    radius: 30
    color: "#ffffff"
    border.color: "#d7dfeb"
    border.width: 1

    property real pad: 28
    property real lockBandDeg: 5.0

    Column {
        x: pad
        y: 24
        spacing: 6

        Text {
            text: "Audio Field History"
            color: "#101828"
            font.pixelSize: 28
            font.weight: Font.DemiBold
        }

        Text {
            text: "Captured audio activity with the tracked music path over time"
            color: "#64748b"
            font.pixelSize: 16
        }
    }

    Rectangle {
        width: 140
        height: 38
        radius: 19
        anchors.right: parent.right
        anchors.rightMargin: pad
        anchors.top: parent.top
        anchors.topMargin: 24
        color: viewModel.audioStatusLabel === "SOURCE LIVE" ? "#edf5ff" : "#f3f6fb"

        Text {
            anchors.centerIn: parent
            text: "10 SEC"
            color: "#64748b"
            font.pixelSize: 14
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        id: chartFrame
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: pad
        anchors.rightMargin: pad
        anchors.topMargin: 100
        anchors.bottomMargin: pad
        radius: 24
        color: "#f7f9fd"
        border.color: "#dbe3ef"
        border.width: 1
    }

    Canvas {
        id: chart
        anchors.fill: chartFrame
        anchors.margins: 18

        Connections {
            target: root.telemetryModel
            function onHistoryChanged() { chart.requestPaint() }
            function onTelemetryChanged() { chart.requestPaint() }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()

            const w = width
            const h = height
            const midY = h * 0.5

            function clamp(value, low, high) {
                return Math.max(low, Math.min(high, value))
            }

            function mapY(value) {
                return h - clamp((value + 90.0) / 180.0, 0, 1) * h
            }

            function mapX(timestamp, oldest, newest) {
                const span = Math.max(0.001, newest - oldest)
                return clamp((timestamp - oldest) / span, 0, 1) * w
            }

            const points = viewModel.historyPoints
            const now = Date.now() / 1000
            const oldest = now - 10.0

            const bins = []
            const binCount = Math.max(80, Math.floor(w / 4))
            for (let i = 0; i < binCount; ++i) {
                bins.push({
                    activity: 0.0,
                    validCount: 0,
                    angleSum: 0.0,
                    state: "IDLE"
                })
            }

            for (let i = 0; i < points.length; ++i) {
                const point = points[i]
                const xRatio = clamp((point.timestamp - oldest) / 10.0, 0, 0.999999)
                const index = Math.floor(xRatio * binCount)
                const bin = bins[index]
                bin.activity = Math.max(bin.activity, point.activity || 0.0)

                if (point.valid && point.value !== null) {
                    bin.validCount += 1
                    bin.angleSum += point.value
                    if (point.state === "LOCKED")
                        bin.state = "LOCKED"
                    else if (bin.state !== "LOCKED")
                        bin.state = "TRACKING"
                }
            }

            const lockTop = h * (0.5 - root.lockBandDeg / 180.0)
            const lockBottom = h * (0.5 + root.lockBandDeg / 180.0)
            ctx.fillStyle = "rgba(48, 209, 88, 0.10)"
            ctx.fillRect(0, lockTop, w, lockBottom - lockTop)

            ctx.strokeStyle = "rgba(152, 162, 179, 0.36)"
            ctx.lineWidth = 1
            ctx.beginPath()
            ctx.moveTo(0, midY)
            ctx.lineTo(w, midY)
            ctx.stroke()

            for (let i = 0; i < binCount; ++i) {
                const bin = bins[i]
                if (bin.activity <= 0.02)
                    continue

                const x = (i / binCount) * w
                const binWidth = (w / binCount) + 1
                const intensity = Math.pow(bin.activity, 1.15)
                const alpha = 0.025 + intensity * 0.16
                const gradient = ctx.createLinearGradient(x, 0, x, h)
                gradient.addColorStop(0.0, `rgba(10,132,255,${alpha * 0.15})`)
                gradient.addColorStop(0.45, `rgba(10,132,255,${alpha})`)
                gradient.addColorStop(1.0, `rgba(10,132,255,${alpha * 0.28})`)
                ctx.fillStyle = gradient
                ctx.fillRect(x, 0, binWidth, h)
            }

            const trackPoints = []
            for (let i = 0; i < binCount; ++i) {
                const bin = bins[i]
                if (bin.validCount <= 0)
                    continue

                const x = ((i + 0.5) / binCount) * w
                const angle = bin.angleSum / bin.validCount
                trackPoints.push({
                    x: x,
                    y: mapY(angle),
                    state: bin.state,
                    activity: bin.activity
                })
            }

            if (trackPoints.length >= 2) {
                ctx.lineCap = "round"
                ctx.lineJoin = "round"

                ctx.beginPath()
                ctx.moveTo(trackPoints[0].x, trackPoints[0].y)
                for (let i = 1; i < trackPoints.length; ++i) {
                    const prev = trackPoints[i - 1]
                    const curr = trackPoints[i]
                    const midX = (prev.x + curr.x) / 2
                    const midY = (prev.y + curr.y) / 2
                    ctx.quadraticCurveTo(prev.x, prev.y, midX, midY)
                }
                const last = trackPoints[trackPoints.length - 1]
                ctx.lineTo(last.x, last.y)
                ctx.lineWidth = 16
                ctx.strokeStyle = "rgba(10,132,255,0.10)"
                ctx.stroke()

                for (let i = 1; i < trackPoints.length; ++i) {
                    const prev = trackPoints[i - 1]
                    const curr = trackPoints[i]
                    ctx.beginPath()
                    ctx.moveTo(prev.x, prev.y)
                    ctx.lineTo(curr.x, curr.y)
                    ctx.lineWidth = 4
                    ctx.strokeStyle = prev.state === "LOCKED" || curr.state === "LOCKED" ? "#30d158" : "#0a84ff"
                    ctx.stroke()
                }

                const head = trackPoints[trackPoints.length - 1]
                ctx.beginPath()
                ctx.arc(head.x, head.y, 6, 0, Math.PI * 2)
                ctx.fillStyle = head.state === "LOCKED" ? "#30d158" : "#0a84ff"
                ctx.fill()
            }
        }
    }

    Repeater {
        model: [
            { label: "+90°", ratio: 0.05 },
            { label: "0°", ratio: 0.50 },
            { label: "-90°", ratio: 0.95 }
        ]

        Text {
            text: modelData.label
            color: "#98a2b3"
            font.pixelSize: 13
            anchors.right: chartFrame.right
            anchors.rightMargin: 16
            y: chartFrame.y + 18 + (chart.height * modelData.ratio) - 9
        }
    }
}
