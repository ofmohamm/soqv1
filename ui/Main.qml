import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ApplicationWindow {
    id: window
    width: 1720
    height: 1080
    visible: true
    visibility: Window.FullScreen
    color: "#eef3fa"
    title: "Song Tracker"
    font.family: Qt.platform.os === "osx" ? "Helvetica Neue" : "Arial"

    property real chromePadding: Math.max(28, width * 0.02)
    property real panelGap: Math.max(18, width * 0.013)
    property real heroHeight: height * 0.60

    Shortcut {
        sequence: "Esc"
        onActivated: Qt.quit()
    }

    Shortcut {
        sequence: "F"
        onActivated: {
            window.visibility = window.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen
        }
    }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#f5f8fd" }
            GradientStop { position: 1.0; color: "#e8eef8" }
        }
    }

    Rectangle {
        width: parent.width * 0.34
        height: width
        radius: width / 2
        x: -width * 0.26
        y: parent.height * 0.58
        color: "#30d158"
        opacity: 0.035
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: chromePadding
        spacing: panelGap

        HeroStage {
            Layout.fillWidth: true
            Layout.preferredHeight: heroHeight
            telemetryModel: telemetry
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: panelGap

            SignalPanel {
                Layout.preferredWidth: window.width * 0.30
                Layout.fillHeight: true
                telemetryModel: telemetry
            }

            HistoryPanel {
                Layout.fillWidth: true
                Layout.fillHeight: true
                telemetryModel: telemetry
            }
        }
    }
}
