# Song Tracker Visualizer Spec v2

## 1. Purpose

This application is a fullscreen presentation visualizer for a directional audio tracking demo.

The visual story is:

- a song is playing in the environment
- the tracker turns toward that source
- the UI shows the tracker orientation, source offset, and signal strength in a way that is easy to read live

The interface should feel polished and minimal, but it must also be intuitive at first glance. If a viewer has to mentally invert directions or decode engineering conventions, the design is wrong.

## 2. Design Corrections From Current Version

The next implementation must correct the following problems:

- the source should not appear at the bottom of the hero stage if that makes tracker motion read backward relative to real motion
- the top half should be visual only, not mixed with redundant metric cards
- sound level should not be shown as a negative relative dB readout in the live UI
- heading should not wrap from `0` to `360` in a way that visibly jumps at midpoint
- IMU calibration status should not be shown in the dashboard
- relative level should not appear twice

These are product requirements, not optional polish.

## 3. Product Goals

- Make the hero visualization directionally intuitive.
- Keep all numeric metrics in the bottom-left panel only.
- Use the top half for one strong visual composition.
- Show tracker heading in a signed demo-friendly range of `-90°` to `+90°`.
- Show sound level only as a positive quantity in the UI.
- Remove visual clutter that does not help a viewer understand the demo.

## 4. Non-Goals

- No radar metaphor
- No microphone metaphor
- No duplicated metrics
- No calibration/debug readouts in the presentation UI
- No absolute world-heading readout if it hurts readability

## 5. System Model

There are still three signal domains:

1. audio direction from host DSP
2. measured heading from controller / BNO-055
3. presentation state in the visualizer

Ownership remains:

- `raw_error_deg` from host DSP
- `smoothed_error_deg` from host DSP
- `state` from host DSP
- measured IMU heading from controller telemetry

The visualizer does not own tracking logic.

## 6. Telemetry Contract

### 6.1 Host -> Visualizer

UDP on `127.0.0.1:5555`

Required packet:

```json
{
  "timestamp": 1234567890.123,
  "rms": 15000000.0,
  "measurement_valid": true,
  "raw_error_deg": 12.3,
  "smoothed_error_deg": 8.1,
  "tracker_heading_deg": 121.4,
  "imu_valid": true,
  "state": "TRACKING"
}
```

### 6.2 Presentation-Derived Values

The UI may derive:

- `display_heading_deg`
- `display_level_db`
- source position for the hero stage

But these are presentation transforms only.

## 7. Coordinate and Display Rules

### 7.1 Tracker Heading

The raw IMU heading may be `0..360`, but the dashboard must not show that directly.

The displayed heading must be normalized to:

```text
-90° to +90°
```

where:

- `0°` means centered / forward in the demo frame
- negative values mean left of center
- positive values mean right of center

If the internal heading needs offsetting or wrapping to produce that display range, that transform belongs in the presentation layer.

### 7.2 Source Direction in the Hero Stage

The hero stage must be composed so that movement reads naturally:

- if the tracker turns right in real life, the visual tracker should also read as turning right
- if the source is to the right, the source indication should appear on the right side of the visual composition

The previous composition placed the source low in the frame and made motion feel inverted. That approach is rejected.

### 7.3 Recommended Hero Orientation

The tracker object should sit near the top center of the hero stage.

The source point should sit beneath the tracker.

This makes the composition read as:

- tracker above
- source point below
- source offset moving left/right across the upper-middle region

That vertical hierarchy is required.

## 8. Sound Level Display Rules

### 8.1 UI Requirement

The dashboard should only show positive sound level values.

The current relative dB implementation is technically valid but visually wrong for this product because:

- negative values read like an error state
- viewers do not care about dB below an arbitrary reference
- the display should communicate strength, not calibration philosophy

### 8.2 Required Display Behavior

Use a positive-only display metric for sound level.

Two acceptable options:

1. `Level dB`
   - clamp negative values to `0`
   - show only `0 dB` and above

2. `Level`
   - remap RMS to a positive scale such as `0..100`

For this product, the preferred option is:

- `Level dB`
- computed from the current RMS conversion
- clamped at the bottom to `0`

That means:

```text
display_level_db = max(0, relative_db)
```

The label should not say `relative`.

It should simply say:

- `Level`

or

- `Sound level`

## 9. State Model

### 9.1 IDLE

- no valid source measurement
- hero stage remains calm
- tracker still visible if IMU is valid

### 9.2 TRACKING

- source active
- source indication visible
- tracker and source offset clearly readable

### 9.3 LOCKED

- source stable near center
- hero stage tightens visually
- accent shifts toward green

### 9.4 STALE

Display condition only.

The UI should indicate stale data quietly, but this must not dominate the screen.

## 10. Layout

```text
+--------------------------------------------------------------+
|                                                              |
|                      HERO VISUALIZATION                      |
|                                                              |
+------------------------------+-------------------------------+
|                              |                               |
|        METRICS PANEL         |        ANGLE HISTORY          |
|                              |                               |
+------------------------------+-------------------------------+
```

### 10.1 Top Half: Hero Visualization

This area is visual only.

Do not place metric cards here.

Do not repeat the same metric shown below.

Allowed items:

- tracker core
- tracker heading cue
- source highlight
- energy field
- small state chip if needed

Not allowed:

- duplicated level value
- duplicated heading value
- duplicated angle value
- large metric cards

### 10.2 Bottom Left: Metrics Panel

All primary metrics belong here.

Required metrics:

- `Level`
- `Raw angle`
- `Smoothed`
- `Heading`

Optional:

- state text
- stale status

Not allowed:

- IMU calibration readout
- duplicate level display elsewhere

### 10.3 Bottom Right: Angle History

Show recent directional error.

Required behavior:

- valid points only
- visible gaps when measurements are invalid
- quiet styling

## 11. Hero Visualization Specification

### 11.1 Composition

The hero stage should be built around one central tracker core.

Recommended composition:

- tracker object anchored near the top-center area
- source point and source glow below it
- audio field opening downward from the tracker
- source offset moving horizontally left/right beneath the tracker

This prevents the visual inversion problem seen in the current design.

### 11.2 Motion

The hero stage should make three things obvious:

- where the tracker is facing
- where the source is relative to that facing direction
- how strong the current signal is

These should be separable without reading labels.

### 11.3 Visual Behavior Rules

- heading motion should be smooth but faithful
- source motion should feel direct and responsive
- energy should scale with sound level
- when no target is present, the source indicator should fade rather than sit in a misleading default position

## 12. Metrics Panel Specification

### 12.1 Metrics

The panel should contain exactly these four primary values:

1. `Level`
2. `Raw angle`
3. `Smoothed`
4. `Heading`

### 12.2 Level

- positive-only
- no negative display values
- no `dB rel` label

### 12.3 Heading

- display as signed `-90°..+90°`
- no `0..360` wrap behavior in the visible dashboard

### 12.4 Removed Fields

The following should not appear in the dashboard:

- `IMU CAL`
- `CAL:3`
- any explicit calibration status text

If IMU is invalid or stale, show only a simple degraded-state label such as:

- `IMU unavailable`

## 13. Angle History Specification

The history panel should continue showing raw angle over recent time.

Rules:

- use `raw_error_deg`
- show gaps for invalid intervals
- keep labels minimal
- visually subordinate to the hero stage

## 14. High-DPI and Presentation Requirements

- fullscreen by default
- crisp on Retina displays
- no overlapping elements
- no metric duplication
- no visual inversion between physical tracker motion and displayed motion

Recommended implementation remains:

- `PySide6`
- `Qt Quick / QML`

## 15. Acceptance Criteria

The redesign is acceptable only if all of the following are true:

1. The hero stage reads direction intuitively.
2. The source no longer appears in a way that makes tracker motion feel backward.
3. The top half contains visualization only, not duplicated metric cards.
4. Sound level is displayed as a positive-only value.
5. Heading is displayed in a signed `-90°..+90°` form without visible `0/360` jump behavior.
6. IMU calibration is removed from the dashboard.
7. Relative level is not shown twice.
8. All metrics live in the bottom-left panel.
9. The layout remains clean at fullscreen presentation scale.

## 16. Implementation Plan

### Phase 1: Data Presentation Rules

- add display-only heading normalization from raw heading to signed demo heading
- add positive-only sound level transform
- remove IMU calibration from the view model

### Phase 2: Layout Cleanup

- remove duplicated top-half metric cards
- keep all metrics in the bottom-left panel
- preserve only state/status chips in the hero area if needed

### Phase 3: Hero Redesign

- move source indication into the upper tracking field
- ensure left/right motion matches physical intuition
- keep tracker core anchored low enough to read as “looking upward”

### Phase 4: Final Polish

- verify fullscreen spacing
- verify no overlap
- verify live behavior with IMU and audio updates

## 17. Open Questions

1. Should positive-only sound level be shown as `dB` or as a unitless level scale?
2. What exact visual transform best maps raw IMU heading into the signed demo frame?
3. Should the hero stage include a small state chip, or should all text remain below?
