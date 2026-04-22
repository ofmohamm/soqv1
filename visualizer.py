import json
import math
import socket
import sys
import time
from pathlib import Path

try:
    from PySide6.QtCore import QObject, Property, QTimer, Signal, Slot, QUrl
    from PySide6.QtGui import QGuiApplication
    from PySide6.QtQml import QQmlApplicationEngine
    PYSIDE_AVAILABLE = True
except ModuleNotFoundError:
    PYSIDE_AVAILABLE = False

    class QObject:
        def __init__(self, *args, **kwargs):
            super().__init__()

    class Signal:
        def __init__(self, *args, **kwargs):
            pass

        def emit(self, *args, **kwargs):
            pass

    class QTimer:
        def __init__(self, *args, **kwargs):
            pass

        @property
        def timeout(self):
            return self

        def connect(self, *args, **kwargs):
            pass

        def start(self, *args, **kwargs):
            pass

    class QUrl:
        @staticmethod
        def fromLocalFile(path):
            return path

    def Property(*args, **kwargs):
        def decorator(func):
            return property(func)

        return decorator

    def Slot(*args, **kwargs):
        def decorator(func):
            return func

        return decorator

    class QGuiApplication:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("PySide6 is required to run the visualizer UI")

    class QQmlApplicationEngine:
        def __init__(self, *args, **kwargs):
            raise RuntimeError("PySide6 is required to run the visualizer UI")


UDP_HOST = "127.0.0.1"
UDP_PORT = 5555
TIMELINE_SECONDS = 10.0
AUDIO_STALE_SECONDS = 0.6
RMS_REFERENCE = 560_000.0
HEADING_OFFSET_DEG = 0.0
LEVEL_EMA_ALPHA = 0.04
AUDIO_DOT_POSITION_EMA_ALPHA = 0.22
AUDIO_DOT_EDGE_HEADING_DEG = 85.0
SCREEN_LEFT_HEADING_DEG = 30.0
SCREEN_CENTER_HEADING_DEG = 126.3
SCREEN_RIGHT_HEADING_DEG = 187.0


def clamp(value, low, high):
    return max(low, min(high, value))


def rms_to_relative_db(rms):
    if rms <= 0:
        return -60.0
    return clamp(20.0 * math.log10(rms / RMS_REFERENCE), -60.0, 24.0)


def wrap_degrees(value):
    wrapped = value % 360.0
    if wrapped < 0:
        wrapped += 360.0
    return wrapped


def wrap_signed_degrees(value):
    wrapped = (value + 180.0) % 360.0 - 180.0
    if wrapped == -180.0:
        return 180.0
    return wrapped


def normalize_heading_for_screen(value, left_deg, right_deg):
    span = (right_deg - left_deg) % 360.0
    if span == 0.0:
        return 0.0
    relative = (wrap_degrees(value) - wrap_degrees(left_deg)) % 360.0
    normalized = relative / span
    return clamp(normalized * 2.0 - 1.0, -1.0, 1.0)


def normalize_centered_heading_for_screen(value, left_deg, center_deg, right_deg):
    value = wrap_degrees(value)
    left_deg = wrap_degrees(left_deg)
    center_deg = wrap_degrees(center_deg)
    right_deg = wrap_degrees(right_deg)

    if not (left_deg <= center_deg <= right_deg):
        return normalize_heading_for_screen(value, left_deg, right_deg)

    if value <= center_deg:
        left_span = max(0.001, center_deg - left_deg)
        normalized = -((center_deg - value) / left_span)
    else:
        right_span = max(0.001, right_deg - center_deg)
        normalized = (value - center_deg) / right_span

    return clamp(normalized, -1.0, 1.0)


def heading_to_audio_dot_normalized(heading_deg, edge_heading_deg=AUDIO_DOT_EDGE_HEADING_DEG):
    signed_heading_deg = wrap_signed_degrees(heading_deg)
    edge_heading_deg = max(0.001, float(edge_heading_deg))
    return clamp(-(signed_heading_deg / edge_heading_deg), -1.0, 1.0)


def heading_to_display_angle_deg(heading_deg):
    return clamp(wrap_signed_degrees(heading_deg), -90.0, 90.0)


class TelemetryBridge(QObject):
    telemetryChanged = Signal()
    historyChanged = Signal()
    staleChanged = Signal()

    def __init__(self, bind_socket=True):
        super().__init__()
        now = time.time()
        self._timestamp = now
        self._rms = 0.0
        self._display_rms = 0.0
        self._measurement_valid = False
        self._raw_error_deg = None
        self._smoothed_error_deg = 0.0
        self._tracker_heading_deg = None
        self._imu_valid = False
        self._state = "IDLE"
        self._last_packet_time = 0.0
        self._state_since = now
        self._history = []
        self._audio_dot_normalized = 0.0
        self._audio_dot_initialized = False

        self._socket = None
        if bind_socket:
            self._socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self._socket.bind((UDP_HOST, UDP_PORT))
            self._socket.setblocking(False)

        self._poll_timer = QTimer(self)
        self._poll_timer.timeout.connect(self.poll_socket)
        self._poll_timer.start(16)

        self._stale_timer = QTimer(self)
        self._stale_timer.timeout.connect(self._emit_periodic_updates)
        self._stale_timer.start(100)

    @Property(str, notify=telemetryChanged)
    def state(self):
        return self._state

    @Property(str, notify=telemetryChanged)
    def stateLabel(self):
        if self.audioStale:
            return "Audio Stale"
        if self._state == "IDLE":
            return "Idle"
        return self._state.title()

    @Property(bool, notify=telemetryChanged)
    def measurementValid(self):
        return self._measurement_valid

    @Property(float, notify=telemetryChanged)
    def rawErrorDeg(self):
        return 0.0 if self._raw_error_deg is None else self._raw_error_deg

    @Property(float, notify=telemetryChanged)
    def smoothedErrorDeg(self):
        return self._smoothed_error_deg

    @Property(float, notify=telemetryChanged)
    def trackerHeadingDeg(self):
        return 0.0 if self._tracker_heading_deg is None else self._tracker_heading_deg

    @Property(bool, notify=telemetryChanged)
    def imuValid(self):
        return self._imu_valid and self._tracker_heading_deg is not None

    @Property(bool, notify=telemetryChanged)
    def headingAvailable(self):
        return self._tracker_heading_deg is not None

    @Property(float, notify=telemetryChanged)
    def rms(self):
        return self._rms

    @Property(float, notify=telemetryChanged)
    def rawDbLevel(self):
        return rms_to_relative_db(self._display_rms)

    @Property(float, notify=telemetryChanged)
    def dbLevel(self):
        return max(0.0, self.rawDbLevel)

    @Property(float, notify=telemetryChanged)
    def energy(self):
        value = clamp((self.rawDbLevel + 36.0) / 42.0, 0.0, 1.0)
        if not self._measurement_valid:
            value *= 0.35
        if self.audioStale:
            value *= 0.08
        return value

    @Property(float, notify=telemetryChanged)
    def sourceOffsetNormalized(self):
        if not self._measurement_valid or self._raw_error_deg is None:
            return 0.0
        return clamp(self._raw_error_deg / 90.0, -1.0, 1.0)

    @Property(float, notify=telemetryChanged)
    def headingNormalized(self):
        if not self.imuValid:
            return 0.0
        return normalize_heading_for_screen(
            self.trackerHeadingDeg + HEADING_OFFSET_DEG,
            SCREEN_LEFT_HEADING_DEG,
            SCREEN_RIGHT_HEADING_DEG,
        )

    @Property(float, notify=telemetryChanged)
    def displayHeadingDeg(self):
        if not self.imuValid:
            return 0.0
        return wrap_degrees(self.trackerHeadingDeg + HEADING_OFFSET_DEG)

    @Property(float, notify=telemetryChanged)
    def displayAngleDeg(self):
        if not self.headingAvailable:
            return 0.0
        return heading_to_display_angle_deg(self.trackerHeadingDeg + HEADING_OFFSET_DEG)

    @Property(float, notify=telemetryChanged)
    def sourceDirectionDeg(self):
        if not self._measurement_valid or self._raw_error_deg is None:
            if self._tracker_heading_deg is None:
                return 0.0
            return self._tracker_heading_deg
        if self._tracker_heading_deg is None:
            return self._raw_error_deg
        return wrap_degrees(self._tracker_heading_deg + self._raw_error_deg)

    @Property(float, notify=telemetryChanged)
    def displaySourceDeg(self):
        return wrap_degrees(self.sourceDirectionDeg)

    @Property(float, notify=telemetryChanged)
    def sourceDisplayNormalized(self):
        return self.audioDotNormalized

    @Property(float, notify=telemetryChanged)
    def audioDotNormalized(self):
        if self._tracker_heading_deg is None:
            return 0.0
        return self._audio_dot_normalized

    @Property(bool, notify=staleChanged)
    def audioStale(self):
        if self._last_packet_time == 0.0:
            return True
        return (time.time() - self._last_packet_time) > AUDIO_STALE_SECONDS

    @Property(bool, notify=staleChanged)
    def stale(self):
        return self.audioStale

    @Property(str, notify=telemetryChanged)
    def imuStatusLabel(self):
        if self.imuValid:
            return "IMU LIVE"
        if self._tracker_heading_deg is not None:
            return "IMU STALE"
        return "IMU UNAVAILABLE"

    @Property(str, notify=telemetryChanged)
    def audioStatusLabel(self):
        if self.audioStale:
            return "AUDIO STALE"
        if self._measurement_valid:
            return "SOURCE LIVE"
        return "NO TARGET"

    @Property(float, notify=telemetryChanged)
    def stateDuration(self):
        return max(0.0, time.time() - self._state_since)

    @Property(str, notify=telemetryChanged)
    def levelText(self):
        return f"{round(self.dbLevel):02.0f} dB"

    @Property(str, notify=telemetryChanged)
    def angleText(self):
        if not self.headingAvailable:
            return "--"
        return f"{self.displayAngleDeg:+05.1f}\N{DEGREE SIGN}"

    @Property(str, notify=telemetryChanged)
    def smoothedText(self):
        return f"{wrap_degrees(self._smoothed_error_deg):05.1f}\N{DEGREE SIGN}"

    @Property(str, notify=telemetryChanged)
    def headingText(self):
        if not self.imuValid:
            return "--"
        return f"{self.displayAngleDeg:+05.1f}\N{DEGREE SIGN}"

    @Property("QVariantList", notify=historyChanged)
    def historyPoints(self):
        return list(self._history)

    @Slot()
    def poll_socket(self):
        changed = False
        history_changed = False

        while True:
            if self._socket is None:
                break
            try:
                payload, _ = self._socket.recvfrom(65535)
            except BlockingIOError:
                break

            packet = json.loads(payload.decode("utf-8"))
            timestamp = float(packet["timestamp"])
            state = str(packet["state"])
            measurement_valid = bool(packet["measurement_valid"])
            raw_error = packet.get("raw_error_deg")
            heading = packet.get("tracker_heading_deg")

            if state != self._state:
                self._state_since = timestamp

            self._timestamp = timestamp
            self._rms = float(packet["rms"])
            if self._display_rms <= 0.0:
                self._display_rms = self._rms
            else:
                self._display_rms = (
                    LEVEL_EMA_ALPHA * self._rms
                    + (1.0 - LEVEL_EMA_ALPHA) * self._display_rms
                )
            self._measurement_valid = measurement_valid
            self._raw_error_deg = None if raw_error is None else float(raw_error)
            self._smoothed_error_deg = float(packet["smoothed_error_deg"])
            previous_heading = self._tracker_heading_deg
            self._tracker_heading_deg = None if heading is None else float(heading)
            self._imu_valid = bool(packet.get("imu_valid", False))
            self._state = state
            self._last_packet_time = timestamp
            if self._tracker_heading_deg is None:
                self._audio_dot_normalized = 0.0
                self._audio_dot_initialized = False
            else:
                target_audio_dot = heading_to_audio_dot_normalized(
                    self._tracker_heading_deg + HEADING_OFFSET_DEG
                )
                if previous_heading is None or not self._audio_dot_initialized:
                    self._audio_dot_normalized = target_audio_dot
                    self._audio_dot_initialized = True
                else:
                    self._audio_dot_normalized = (
                        AUDIO_DOT_POSITION_EMA_ALPHA * target_audio_dot
                        + (1.0 - AUDIO_DOT_POSITION_EMA_ALPHA) * self._audio_dot_normalized
                    )
            changed = True

            self._history.append(
                {
                    "timestamp": timestamp,
                    "value": None if raw_error is None else float(packet["smoothed_error_deg"]),
                    "valid": measurement_valid,
                    "activity": clamp((rms_to_relative_db(self._rms) + 36.0) / 42.0, 0.0, 1.0),
                    "state": state,
                }
            )
            history_changed = True

        cutoff = time.time() - TIMELINE_SECONDS
        if self._history and self._history[0]["timestamp"] < cutoff:
            self._history = [point for point in self._history if point["timestamp"] >= cutoff]
            history_changed = True

        if changed:
            self.telemetryChanged.emit()
            self.staleChanged.emit()
        if history_changed:
            self.historyChanged.emit()

    @Slot()
    def _emit_periodic_updates(self):
        self.staleChanged.emit()
        self.telemetryChanged.emit()


def main():
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Song Tracker")

    bridge = TelemetryBridge()

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("telemetry", bridge)

    qml_path = Path(__file__).resolve().parent / "ui" / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_path)))
    if not engine.rootObjects():
        return 1

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
