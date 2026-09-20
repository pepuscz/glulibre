# Watch UI audit

Build/install the Debug `xDrip Watch App` scheme on a **Watch simulator**, then:

```
xcodegen generate --spec Tests/WatchJourneyAudit/project.yml
xcodebuild test -project Tests/WatchJourneyAudit/LibreWatchJourneyAudit.xcodeproj -scheme WatchJourneyAudit -destination 'platform=watchOS Simulator,id=SIMULATOR_ID' -derivedDataPath /private/tmp/LibreWatchJourneyAudit CODE_SIGNING_ALLOWED=NO
```

Use a unique `-resultBundlePath` to retain screenshots and element trees. Inspect screenshots, not only test assertions. Simulator-only fixtures include fresh, stale, empty, mg/dL, collecting and limited meal responses; large type and dimmed privacy are also covered. No credentials, pairing, meal writes or Health export occur. Never run this suite on a physical Watch.

Run on 40 mm and 49 mm Ultra simulators. `testChartIsReadableWithoutScrolling` checks chart height, value/chart ordering and full chart visibility in both glucose units. Accessibility text may scroll, but the reading must remain legible.

`testDigitalCrownScrollsMealAndReturnsToGlucose` sends native `XCUIDevice.rotateDigitalCrown` events without first tapping or swiping. It checks forward navigation to the meal's end, the last-page boundary, and reverse navigation back to glucose. The same journey runs with large accessibility text and a long meal title. `testNowAndMealWithoutConnectionPage` separately checks touch navigation and the absence of a Connection/Refresh page.

The suite skips physical devices. Simulator Crown events verify app navigation, not the feel of a particular watch's hardware; check that on an installed device separately.
