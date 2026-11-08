# Simulator journey audit

This independent XCUITest target drives the installed GluLibre app. It does not build or install the app itself.

Use a dedicated simulator, not one being driven by another task. Capture the
target app rather than the entire screen so unrelated apps cannot contaminate
the visual audit.

1. Build/install the Debug simulator app with bundle ID `com.652PWHFDA9.libredebug`.
2. Generate the ignored project: `xcodegen generate --spec Tests/JourneyAudit/project.yml`.
3. Run `xcodebuild test -project Tests/JourneyAudit/LibreJourneyAudit.xcodeproj -scheme JourneyAudit -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' -derivedDataPath /private/tmp/LibreJourneyAudit -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO`.

Add a unique `-resultBundlePath` to retain screens, element trees and per-step logs. Export with `xcrun xcresulttool export attachments --path RESULT.xcresult --output-path OUTPUT_DIRECTORY`.

For release acceptance, use a fresh derived-data directory and verify the expected named attachments/steps exist in the result. If Xcode reuses a stale runner, remove only `com.libredebug.JourneyAudit.xctrunner` from the simulator before retrying. Do not uninstall GluLibre to refresh the test harness.

Launch arguments supply synthetic readings, meals and workouts only in Debug simulator builds. Correction tests persist synthetic meal fixtures in that simulator. Tests do not pair sensors, provide an OpenAI key, analyze real photos or confirm nutrition into Apple Health. Never point this suite at a user's physical phone.

For large-text/dark inspection, record the simulator's current values first, set `simctl ui DEVICE content_size accessibility-extra-large` and `simctl ui DEVICE appearance dark`, run `testAccessibilityLayouts` plus `testMealCorrectionAndSavedCapture`, then restore the original values. Inspect attachments: navigation assertions alone are not an accessibility certification.

Coverage and remaining integration limits: `docs/IOS_JOURNEY_AUDIT_4236.md`.

Alarm regression journeys: `testAlarmTapOpensTodayWithoutSnoozePicker` and
`testForegroundAlarmDoesNotInterruptMealCapture`. Their simulator-only fixtures
exercise the production alarm interaction methods without delivering actual alarms.
They verify native presentation options, unchanged snooze state on ordinary taps,
the explicit Snooze action, chart routing and uninterrupted meal capture.

`testNotificationPresentation` renders the actual notification extension view
with fresh, stale and missing payloads. The Watch suite exercises its matching
view. This verifies copy/layout, not physical iPhone-to-Watch delivery.
`testSmartGuideSetupRequiresPreparationAndSerial` also checks that the sensor
chooser keeps Libre NFC actions out of the SmartGuide path.

## Native UI review (4255)

Re-read Apple's [Writing](https://developer.apple.com/design/human-interface-guidelines/writing),
[Layout](https://developer.apple.com/design/human-interface-guidelines/layout),
[Charts](https://developer.apple.com/design/human-interface-guidelines/charts) and
[Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) guidance.
Keep everyday labels short, prioritize the chart and move methodology behind disclosures;
do not hide safety, privacy or missing-data information to reduce word count.

- `testHealthOnboardingHasOneAction`: one Health connection prompt, no duplicate empty-workout prompt.
- `testMealDetailsKeepCoverageAndContext`: coverage and movement details remain discoverable after consolidation.
- `testEverydayMovementAndMissingData`: recorded, missing, permission-upgrade and refreshing states; missing never becomes zero.
- `testSettingsInventory`: concise landing rows. Inspect small-screen accessibility screenshots for icon overflow and wrapped labels.

Refreshes retain the current Health snapshot until replacement; empty results, errors and
disconnects still clear it. Simulator fixtures verify presentation, not Health permission
revocation, live sensor operation or physical notification delivery.

Review validation: 106 Swift tests passed; iPhone journeys covered capture/edit,
comparison, Settings, Health onboarding, notifications, sensor setup and empty states.
Inspected light/default-text and compact dark/accessibility-text screenshots. Final
coverage/movement disclosures and landscape inspection passed with a fresh test runner.
Watch suites passed 7 Ultra and 3 small-Watch journeys, including Crown scrolling.
The landscape test also retains a full-screen capture from the isolated simulator:
XCTest's app-cropped landscape image can be misrotated even when the screen is correct.
Build 4255 compiled for simulator and signed device; this review did not install it
on a physical device or exercise live sensors.
