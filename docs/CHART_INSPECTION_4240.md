# Chart-first landscape and recorded-value inspection — build 4240

## Changes

- Landscape Today is a full-width chart, with only duration, units, chart options
  and inspection readout above it. No reading card, meal-capture card, journal
  list or navigation heading takes space from the plot. Native tabs remain
  available. Accessibility text sizes use the scrollable portrait-style layout.
- Portrait retains the existing dashboard. Time-range state survives rotation.
- Tap a chart sample or drag horizontally to inspect it: vertical and horizontal
  crosshairs, a selected point, actual sample timestamp and value in the chosen
  unit. Clear returns to the unselected chart. VoiceOver has an adjustable action
  for stepping through samples. The clear action has a 44-point target.
- Touch arbitration uses native UIKit tap/pan recognizers in the chart overlay.
  Vertical drags are rejected before the inspection pan begins, allowing the
  parent scroll view to handle them, rather than filtering direction only after
  a drag has already been recognized.
- The common chart component provides inspection on Today and other views that
  already use `JournalGlucoseChart` (for example meal details).
- Selection returns actual stored samples, never interpolated glucose. Selection
  farther than five minutes from a sample shows “No reading”; invalid/future and
  out-of-window samples are excluded. Existing missing-data/sensor-change breaks
  and meal/activity context remain.
- No sensor, database, meal, credentials, notification policy or alarm-schedule
  changes. Notification work in this turn is a review, recorded separately in
  `NOTIFICATION_AUDIT_4240.md`.

## Verification

- Simulator and signed iPhone build succeed.
- 59 Foundation tests pass: 48 observation/notification tests (including six new
  chart-selection tests) plus 11 Watch tests.
- First UI run passes three journeys: exact-value tap/drag and missing-data
  selection; landscape cold launch with all tabs; both rotation directions,
  retained duration, sensor navigation and portrait meal capture.
- Visual review: full-width landscape plot, x/y crosshairs and exact-value label;
  portrait inspection; no-reading state. Synthetic fixtures only.
- The explicit vertical-scroll regression begins inside the plot. The first
  version attempted to scroll farther at the page boundary; the corrected test
  scrolls back toward the top. Final results are recorded below.

Uses Apple's public Swift Charts `ChartProxy` overlay APIs. Reference:
[Swift Charts interaction guidance](https://developer.apple.com/videos/play/wwdc2022/10137/).

## Final verification and deployment

- Cold landscape launch/all tabs and bidirectional rotation/duration/meal capture
  pass in `/private/tmp/libre-4240-chart-reboot.xcresult` (the earlier inspection
  assertion in that bundle is superseded by the corrected final test below).
- Tap, horizontal drag, exact sample readout, missing-data selection, clear,
  portrait inspection and vertical scrolling all pass in
  `/private/tmp/libre-4240-gestures-fresh.xcresult`.
- The simulator had to be restarted once to restore orientation events. Xcode
  also reused an old test runner after test-source edits; only the generated
  `com.libredebug.JourneyAudit.xctrunner` was removed, then rebuilt in fresh
  derived data. Libre Debug and its data were never uninstalled.
- Final screenshots exported to `/private/tmp/libre-4240-verified-screens`;
  landscape crosshairs visually reviewed.
- Signed build 4240 verified with deep/strict codesign and installed in place
  on the connected iPhone as `com.652PWHFDA9.libredebug`. No sensor scan, reset,
  data export or saved-alarm changes were performed.
