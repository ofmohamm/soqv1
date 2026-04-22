# SOQv1

SOQ is a Kinect-audio tracking demo with a live visualizer.

The system uses Kinect v1 microphone audio to estimate left/right source direction, reads absolute heading from a pan-mounted IMU controller, and renders the result in a Qt visualizer.

## Hardware

- XBox Kinect 360
- Arduino-compatible controller
- Adafruit BNO055 IMU
- Pan servo
- Host computer with USB access to Kinect and controller
- USB cables and power as required for the controller/servo setup

The controller firmware lives in `soqv1/soqv1.ino`.

## Project Files

- `read_kinect.py`: reads Kinect audio from `audio_capture`, reads IMU heading over serial, and sends telemetry to the visualizer
- `visualizer.py`: Qt/PySide6 desktop visualizer
- `ui/`: QML UI for the visualizer
- `libfreenect/examples/audio_capture.c`: Kinect audio capture program
- `soqv1/soqv1.ino`: controller firmware for servo + BNO055 heading reporting

## Software Requirements

- Python 3
- `numpy`
- `pyserial`
- `PySide6`
- `libfreenect` built locally so `audio_capture` can run

Example Python install:

```bash
pip install numpy pyserial PySide6
```

## Before You Run

Set the controller serial port in `read_kinect.py`:

```python
SERIAL_PORT = "/dev/cu.usbmodem1301"
```

Make sure that path matches your machine.

You also need a built `audio_capture` binary from `libfreenect/examples/`.

## How To Run

Start the visualizer in one terminal:

```bash
python visualizer.py
```

Start Kinect audio capture and tracking in a second terminal:

```bash
./libfreenect/examples/audio_capture | python read_kinect.py
```

If your Python is in a virtual environment, use that interpreter instead.

## Runtime Flow

1. `audio_capture` streams 4-channel Kinect microphone audio to stdout.
2. `read_kinect.py` computes audio direction from the outer microphone pair.
3. `read_kinect.py` reads heading data from the controller over serial.
4. `read_kinect.py` sends telemetry to `127.0.0.1:5555`.
5. `visualizer.py` receives that telemetry and renders the UI.

## Notes

- The visualizer listens on local UDP port `5555`.
- The controller reports heading as `0..360`, and the visualizer remaps it for display.
- `libfreenect` is included in this repo because the Kinect audio capture path depends on it.
