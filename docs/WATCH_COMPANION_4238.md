# Watch companion — build 4238

## Product

The wrist answers three questions: **what is my latest glucose, what happened after my last meal, and why isn't it updating?** It does not reproduce the phone's settings, photo library, food rankings, sensor setup, or diagnostics.

- **Now:** large unit-aware reading, accessible trend, reading age, three-hour chart. A missing/stale value is a dash, not a plausible-looking current reading. The previous value remains clearly labeled as historical. Missing intervals and known sensor changes break the chart.
- **Last meal:** title, meal time, and a two-hour peak rise only when the phone's existing observation logic permits it. Collecting, insufficient data, overlap, sensor-change and no-meal states have separate presentations. A collecting snapshot never becomes completed merely because time elapsed. No carb score, causal ingredient attribution, longevity score, or Sinclair thresholds.
- **Connection:** one Refresh action, last-reading time, and an explanation that the iPhone remains the sensor connection. Existing connected-care status remains available here when configured.
- Native vertical paging and scrolling, black background, system type/SF Symbols, restrained mint accent. Compact layout for small watches; large text scrolls instead of being clamped. Always On replaces the entire health view, including the chart, with a raise-wrist message.
- Four complication families: circular, rectangular/Smart Stack, inline, corner. Readings respect the existing watch-face sharing preference. Rectangular displays the reading time. Missing/corrupt runtime state never falls back to fabricated sample data; samples remain preview-only.
- The existing phone alert engine and system notification actions are retained. Notification content is simplified and timestamps readings; stale values are not presented as current. No additional alerts or haptics are scheduled.

## Data and reliability

- Optional additions to `WatchState` preserve older phone/watch payload decoding. The phone derives a small read-only meal snapshot from `MealStore` and `GlucoseObservations`, including the same coverage, overlap and sensor-continuity checks. No new database or meal writes.
- `updateApplicationContext` replaces the pending background snapshot. Foreground messages and budgeted complication transfers remain. Old queued messages cannot roll back a newer generation; duplicate generations are ignored. The existing forced-complication-update argument is now propagated correctly.
- The Watch restores its last real snapshot, validates incoming arrays, safely ignores malformed envelopes, and handles empty/newer snapshots (including meal deletion). Refresh is throttled and has a visible timeout/offline fallback.
- Shared Foundation-only `WatchGlancePolicy` drives freshness, formats, trends, packet ordering and scheduled expiry. A complication timeline includes the seven-minute stale transition without another phone update. Seven minutes is a display-freshness policy inherited from the prior Watch presentation, not a glucose goal or guaranteed OS refresh cadence.
- App updates are requested while active and not dimmed. Apple controls actual background/complication delivery; these are not continuous live displays and do not replace the phone's alerts.
- Existing bundle/team identity, sensor setup, Core Data schema, meals/photos, API key store and alert configuration are unchanged. No new Health permissions or third-party uploads.

## Primary-source research

- [Apple: watchOS apps](https://developer.apple.com/documentation/watchos-apps): brief interactions and useful information at a glance informed the focused pages rather than a miniaturized phone app.
- [Apple: Design and build apps for watchOS](https://developer.apple.com/videos/play/wwdc2023/10138/): focused views, Digital Crown/touch navigation and Smart Stack-informed design.
- [Apple: Always On design](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state): protect health information and simplify the dimmed state.
- [Apple: application context](https://developer.apple.com/documentation/watchconnectivity/wcsession/updateapplicationcontext(_:)): newest-state replacement instead of queuing intermediate states.
- [Apple: keeping widgets up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date) and [WWDC26 watchOS lab](https://developer.apple.com/videos/play/wwdc2026/8014/): delivery is budgeted/system-controlled; use timelines and avoid real-time promises.

## Verification

- Watch simulator and combined iPhone/Watch compilation passed; signed build prepared with the existing identity.
- Foundation suites: 42 existing observation tests plus 11 Watch tests (53 total): freshness boundary, invalid/missing/future values, extreme display values, unit/rise formatting, age, timeline expiry, queue ordering, legacy decoding, meal round-trip/removal and unknown trends.
- 46 mm XCUITest: navigation and Refresh, empty/stale states, completed/collecting/limited meals and mg/dL rendering passed. Reviewed exported screenshots.
- 40 mm XCUITest: the same journeys plus large-text scrolling, reachable Refresh and a dimmed privacy fixture. Visual review found chart redaction insufficient; the complete health view was subsequently replaced when dimmed and this was rerun.
- Synthetic fixtures are DEBUG + simulator gated. No real sensor pairing or health upload is performed by tests. UI tests verify navigation, not actual Crown hardware or background complication delivery.

Repeatable suite: `Tests/WatchJourneyAudit/project.yml` and `Journeys/WatchJourneys.swift`. Generate with `xcodegen generate --spec Tests/WatchJourneyAudit/project.yml`; install the Watch simulator build first, then run the `WatchJourneyAudit` scheme. The runtime does not support `simctl ui content_size`; test-only `--watch-large` supplies a SwiftUI accessibility text-size environment instead. The separate Simulator GUI app is absent on this Mac; XCUITest and screenshots work.

## Device handoff — 2026-09-20

- Final 40 mm UI run passed all three test groups (navigation/refresh, six data states, large text/privacy). Bundle: `/private/tmp/libre-watch4238-small-final.xcresult`; reviewed final exported Now, meal and fully hidden dimmed screens.
- Signed build 4238 installed in place and launched on the iPhone. Signature verified. Private backup: `/private/tmp/libre-4238-upgrade.WtOavc`.
- All 605 pre-upgrade glucose rows were retained unchanged. Sensor IDs/start/end dates and alert entries are unchanged. Meal JSON and photos compare byte-for-byte equal after upgrade.
- Physical Apple Watch became reachable after unlocking, but CoreDevice reports `Developer mode is not enabled on device` (developer-image mount restriction). Direct Watch installation/runtime verification remains blocked until the user enables Developer Mode on the Watch and confirms after restarting. No attempt to bypass that protection.
- Physical WatchConnectivity delivery, complications on a real watch face, notification mirroring and Crown/Always On hardware behavior still require device acceptance. Simulator tests do not establish these.

## Physical Watch deployment — build 4239, 2026-09-20

- User enabled Watch Developer Mode and refreshed the Apple account in Xcode.
- A device-specific `xDrip Watch App` build with automatic provisioning and device
  registration succeeded. The signed profile now includes the physical Watch;
  the previous embedded profile only included the iPhone. Deep signature verification passed.
- Installed build 4239 directly on the physical Apple Watch Ultra successfully and
  launched `com.652PWHFDA9.libredebug.watchkitapp`. Also launched the existing iPhone
  app to permit companion synchronization. No uninstall, sensor scan, or reset.
- Device build: `/private/tmp/LibreWatchDevice4239/Build/Products/Debug-watchos/xDrip Watch App.app`.
  Build log: `/private/tmp/libre-watch-4239-device-retry.log`.
- Successful launch does not establish receipt of current glucose on the Watch;
  live sync, complications, notifications, and Always On still need acceptance checks.

## Chart layout follow-up — build 4244

- The chart is now 72 points tall on compact watches and 104 points on larger watches (previously 28/44).
- A single reading/arrow/units row replaces the fresh-state heading and update-age row. At accessibility text sizes, units move below the reading so the number stays legible.
- Explicit missing/stale labels, historical-value age and the seven-minute freshness policy remain. Larger text and stale details can scroll.
- The three-hour window, y-axis scaling, linear interpolation and missing-data/sensor boundaries are unchanged. This is a layout change, not a change in glucose interpretation or sensor behavior.
- The layout regression checks both glucose units, a minimum chart height and complete chart visibility without scrolling at standard text size. Large-text tests also check that the reading is not squeezed smaller by the units.
- Validation: simulator build 4244, 59 unit tests and four UI journeys on each of the 40 mm and 46 mm simulators passed. Standard and accessibility-size screenshots were inspected; large text intentionally scrolls. The README uses the final 40 mm capture with synthetic data. Physical-device installation and acceptance were not performed for this layout-only update.
