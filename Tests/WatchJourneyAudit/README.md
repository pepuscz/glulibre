# Watch UI audit

Build/install the Debug `xDrip Watch App` scheme on a **Watch simulator**, then:

```
xcodegen generate --spec Tests/WatchJourneyAudit/project.yml
xcodebuild test -project Tests/WatchJourneyAudit/LibreWatchJourneyAudit.xcodeproj -scheme WatchJourneyAudit -destination 'platform=watchOS Simulator,id=SIMULATOR_ID' -derivedDataPath /private/tmp/LibreWatchJourneyAudit CODE_SIGNING_ALLOWED=NO
```

Use a unique `-resultBundlePath` to retain screenshots and element trees. Inspect screenshots, not only test assertions. Simulator-only fixtures include fresh, stale, empty, mg/dL, collecting and limited meal responses; large type and dimmed privacy are also covered. No credentials, pairing, meal writes or Health export occur. Never run this suite on a physical Watch.
