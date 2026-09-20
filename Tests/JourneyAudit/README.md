# Simulator journey audit

This independent XCUITest target drives the installed Libre Debug app. It does not build or install the app itself.

1. Build/install the Debug simulator app with bundle ID `com.652PWHFDA9.libredebug`.
2. Generate the ignored project: `xcodegen generate --spec Tests/JourneyAudit/project.yml`.
3. Run `xcodebuild test -project Tests/JourneyAudit/LibreJourneyAudit.xcodeproj -scheme JourneyAudit -destination 'platform=iOS Simulator,id=YOUR_SIMULATOR_ID' -derivedDataPath /private/tmp/LibreJourneyAudit -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO`.

Add a unique `-resultBundlePath` to retain screens, element trees and per-step logs. Export with `xcrun xcresulttool export attachments --path RESULT.xcresult --output-path OUTPUT_DIRECTORY`.

For release acceptance, use a fresh derived-data directory and verify the expected named attachments/steps exist in the result. If Xcode reuses a stale runner, remove only `com.libredebug.JourneyAudit.xctrunner` from the simulator before retrying. Do not uninstall Libre Debug to refresh the test harness.

Launch arguments supply synthetic readings, meals and workouts only in Debug simulator builds. Correction tests persist synthetic meal fixtures in that simulator. Tests do not pair sensors, provide an OpenAI key, analyze real photos or confirm nutrition into Apple Health. Never point this suite at a user's physical phone.

For large-text/dark inspection, record the simulator's current values first, set `simctl ui DEVICE content_size accessibility-extra-large` and `simctl ui DEVICE appearance dark`, run `testAccessibilityLayouts` plus `testMealCorrectionAndSavedCapture`, then restore the original values. Inspect attachments: navigation assertions alone are not an accessibility certification.

Coverage and remaining integration limits: `docs/IOS_JOURNEY_AUDIT_4236.md`.
