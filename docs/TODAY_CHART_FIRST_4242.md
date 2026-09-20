# Today: chart-first landing — 4242

## Product hierarchy

1. Current glucose, units and trend with the chart, in one primary surface.
2. One-tap meal capture immediately below it.
3. Today's meal history below the primary actions.

Replace the large navigation title and full date with an inline Today title. Remove the standalone reading card, repeated Glucose heading, healthy-connection icon and routine freshness row. Keep explicit past-reading, age and sensor recovery controls when data is stale or absent. Move notification settings into the existing overflow menu; do not change alert behavior or saved preferences.

Use a 250-point portrait chart. The selected-value readout now overlays the chart only while inspecting, without reserving an empty 50-point row or moving the plot underneath a drag. Exact samples, gap handling, VoiceOver adjustment, vertical scrolling and landscape remain supported. Meal capture uses a compact native button, with the existing capture workflow unchanged.

## Scope

Presentation only: no schema, sensor, pairing, glucose-processing, API, HealthKit or notification-policy changes. Upgrade the same app identifier in place. Never run synthetic fixture arguments on the physical phone.

## Acceptance

`testTodayChartIsVisibleWithoutScrolling` asserts that the complete plot and capture button fit above the tab bar with both fresh and stale readings, then opens the camera. Also check chart inspection/scrolling, rotation, sensor recovery, empty state and accessibility sizing. Inspect rendered screenshots before installing the signed build.

## Verification receipts

- 59 package unit tests passed (`/private/tmp/libre-4242-unit.log`).
- Five iPhone 17 Pro simulator journeys passed: landing, inspection/vertical scroll, rotation, sensor recovery and empty state (`/private/tmp/libre-4242-today.xcresult`).
- iPhone 15 landing journey passed with both fresh and stale data; screenshot review confirms the full plot and capture button above the tab bar (`/private/tmp/libre-4242-iphone15.xcresult`).
- Dark appearance at accessibility-extra-large inspected visually; value, units and trend remain visible. Scrolling remains appropriate at accessibility text sizes. This is a visual check, not a full VoiceOver audit.
- Final signed build 4242 passes deep/strict code-signature verification.
- Final iPhone 15 landing regression passed after the Dynamic Type sizing adjustment (`/private/tmp/libre-4242-iphone15-final.xcresult`). Build 4242 was installed in place on the physical test iPhone; its device identifier is intentionally omitted from public documentation.

Temporary build-cache folders `LibreChartNoHintRunner`, `LibreModel4241Runner` and `LibreChart4240FreshRunner` were removed after the Mac ran out of disk space. These are reproducible test-build outputs; their result bundles, source files and user data were retained.
The throwaway iPhone 15 simulator created for this check (`44ECB9E9-24E8-4E58-868B-50FF05C94431`) was shut down and deleted after testing; screenshots and results remain in `/private/tmp`.
