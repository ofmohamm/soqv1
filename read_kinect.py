import json
import socket
import sys
import time

import numpy as np
import serial

# Audio constants
SAMPLE_RATE = 16000
MIC_SPACING = 0.226
SPEED_OF_SOUND = 343
MAX_TAU = MIC_SPACING / SPEED_OF_SOUND
BLOCK_SIZE = 128
BLOCK_BYTES = BLOCK_SIZE * 4 * 4

# Visualizer transport
VIZ_ADDR = ("127.0.0.1", 5555)

# Serial to controller
SERIAL_PORT = "/dev/cu.usbmodem1301"
BAUD_RATE = 115200

# Tracking thresholds
THRESHOLD = 8000000
LOCK_BAND_DEG = 5.0
LOCK_HOLD_SECONDS = 1.0
IDLE_HOLD_SECONDS = 0.5
ERROR_EMA_ALPHA = 0.3
IMU_STALE_SECONDS = 0.75


arduino = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0)
arduino.reset_input_buffer()
arduino.reset_output_buffer()


def gcc_phat(sig, refsig):
    n = len(sig) + len(refsig)
    sig_fft = np.fft.rfft(sig, n=n)
    refsig_fft = np.fft.rfft(refsig, n=n)
    cross_power = sig_fft * np.conj(refsig_fft)
    cross_power /= np.abs(cross_power) + 1e-10
    cross_correlation = np.fft.irfft(cross_power)
    max_shift = int(SAMPLE_RATE * MAX_TAU) + 1
    cross_correlation = np.concatenate(
        (cross_correlation[-max_shift:], cross_correlation[: max_shift + 1])
    )
    shift = np.argmax(cross_correlation) - max_shift
    return shift / SAMPLE_RATE


def derive_state(signal_present, measurement_valid, smoothed_error_deg, in_lock_since, now):
    if not signal_present:
        return "IDLE", None

    if measurement_valid and abs(smoothed_error_deg) <= LOCK_BAND_DEG:
        if in_lock_since is None:
            in_lock_since = now
        if now - in_lock_since >= LOCK_HOLD_SECONDS:
            return "LOCKED", in_lock_since
        return "TRACKING", in_lock_since

    return "TRACKING", None


def send_packet(sock, packet):
    sock.sendto(json.dumps(packet).encode("utf-8"), VIZ_ADDR)


def parse_controller_line(line):
    line = line.strip()
    if not line:
        return None

    if line.startswith("{"):
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            return None
        heading = payload.get("heading_deg")
        if heading is None:
            return None
        imu_valid = payload.get("imu_valid")
        calibration = payload.get("calibration")
        try:
            heading = float(heading)
        except (TypeError, ValueError):
            return None
        return {
            "heading_deg": heading,
            "imu_valid": bool(imu_valid) if imu_valid is not None else True,
            "calibration": calibration,
        }

    parts = [part.strip() for part in line.split(",") if part.strip()]
    heading = None
    imu_valid = True
    calibration = None

    for part in parts:
        if part.startswith("H:"):
            try:
                heading = float(part.split(":", 1)[1])
            except ValueError:
                return None
        elif part.startswith("CAL:"):
            try:
                calibration = int(part.split(":", 1)[1])
            except ValueError:
                calibration = None
        elif part.startswith("IMU:"):
            value = part.split(":", 1)[1].strip().lower()
            imu_valid = value in {"1", "true", "live", "ok", "valid"}

    if heading is None:
        return None

    return {
        "heading_deg": heading,
        "imu_valid": imu_valid,
        "calibration": calibration,
    }


def poll_controller_heading(
    serial_port, current_heading, imu_valid_flag, calibration, last_update, pending_buffer
):
    waiting = serial_port.in_waiting
    if waiting:
        raw_bytes = serial_port.read(waiting)
        if raw_bytes:
            pending_buffer += raw_bytes.decode("utf-8", errors="ignore")

    while "\n" in pending_buffer:
        line, pending_buffer = pending_buffer.split("\n", 1)
        parsed = parse_controller_line(line)
        if parsed is None:
            continue

        current_heading = parsed["heading_deg"] % 360.0
        imu_valid_flag = parsed["imu_valid"]
        calibration = parsed["calibration"]
        last_update = time.time()

    return current_heading, imu_valid_flag, calibration, last_update, pending_buffer


print("Listening...", file=sys.stderr)
viz_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

counter = 0
last_errors = []
smoothed_error = 0.0
last_signal_time = 0.0
in_lock_since = None
tracker_heading_deg = None
imu_valid_flag = False
imu_calibration = None
imu_last_update = 0.0
controller_buffer = ""


while True:
    raw = sys.stdin.buffer.read(BLOCK_BYTES)
    if len(raw) < BLOCK_BYTES:
        break

    tracker_heading_deg, imu_valid_flag, imu_calibration, imu_last_update, controller_buffer = poll_controller_heading(
        arduino,
        tracker_heading_deg,
        imu_valid_flag,
        imu_calibration,
        imu_last_update,
        controller_buffer,
    )

    data = np.frombuffer(raw, dtype=np.int32).reshape(-1, 4)
    mic1 = data[:, 0].astype(np.float64)
    mic4 = data[:, 3].astype(np.float64)

    rms = float(np.sqrt(np.mean(mic1**2)))
    counter += 1
    now = time.time()
    signal_present = rms >= THRESHOLD
    raw_error = None
    measurement_valid = False
    imu_is_fresh = (
        tracker_heading_deg is not None
        and imu_valid_flag
        and (now - imu_last_update) <= IMU_STALE_SECONDS
    )

    if not signal_present:
        last_errors.clear()
        arduino.write(b"0\n")
        signal_is_live = (now - last_signal_time) < IDLE_HOLD_SECONDS
        state, in_lock_since = derive_state(
            signal_is_live,
            False,
            smoothed_error,
            in_lock_since,
            now,
        )
        send_packet(
            viz_sock,
            {
                "timestamp": now,
                "rms": rms,
                "measurement_valid": False,
                "raw_error_deg": None,
                "smoothed_error_deg": float(smoothed_error),
                "tracker_heading_deg": tracker_heading_deg,
                "imu_valid": imu_is_fresh,
                "imu_calibration": imu_calibration,
                "state": state,
            },
        )
        if counter % 100 == 0:
            print(
                f"quiet rms: {rms:.0f} imu={'live' if imu_is_fresh else 'stale'}",
                file=sys.stderr,
            )
        continue

    tau = gcc_phat(mic1, mic4)
    ratio = np.clip((tau * SPEED_OF_SOUND) / MIC_SPACING, -1, 1)

    if abs(ratio) > 0.9:
        continue

    raw_error = float(np.degrees(np.arcsin(ratio)))
    measurement_valid = True
    last_signal_time = now
    smoothed_error = ERROR_EMA_ALPHA * raw_error + (1.0 - ERROR_EMA_ALPHA) * smoothed_error
    last_errors.append(raw_error)

    if len(last_errors) >= 3:
        recent = last_errors[-3:]
        spread = max(recent) - min(recent)
        if spread < 15:
            avg_error = sum(recent) / len(recent)
            arduino.write(f"{int(avg_error)}\n".encode("utf-8"))
            print(f"SEND error: {avg_error:.1f} rms: {rms:.0f}", file=sys.stderr)
            last_errors.clear()
        elif len(last_errors) > 5:
            last_errors.pop(0)

    state, in_lock_since = derive_state(
        True,
        measurement_valid,
        smoothed_error,
        in_lock_since,
        now,
    )
    send_packet(
        viz_sock,
        {
            "timestamp": now,
            "rms": rms,
            "measurement_valid": measurement_valid,
            "raw_error_deg": raw_error,
            "smoothed_error_deg": float(smoothed_error),
            "tracker_heading_deg": tracker_heading_deg,
            "imu_valid": imu_is_fresh,
            "imu_calibration": imu_calibration,
            "state": state,
        },
    )

    print(
        "raw error: "
        f"{raw_error:.1f} rms: {rms:.0f} imu={'live' if imu_is_fresh else 'stale'} "
        f"heading={'--' if tracker_heading_deg is None else f'{tracker_heading_deg:.1f}'}",
        file=sys.stderr,
    )
