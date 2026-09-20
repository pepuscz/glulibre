# iOS journey audit — build 4236

Research and implementation: 19 September 2026.

## Verdict

Keep the four destinations: Today, Journal, Insights, Settings. Keep photo-first capture, native navigation and system controls. The foundation is appropriate, but the audit found consequential gaps in food correction, time attribution, privacy communication, empty-state recovery and keyboard behavior. Fixing these is more valuable than another decorative redesign.

This is an experience for exploring personal meal responses, not a causal ingredient detector or a longevity score. Existing sensor services, alarms, historical readings and specialist tools remain intact.

## Research translated into decisions

| Primary source | Applicable pattern | Antipattern avoided |
| --- | --- | --- |
| [Apple: Design foundations from idea to interface](https://developer.apple.com/videos/play/wwdc2025/359/) | Start from specific tasks and content hierarchy; validate complete journeys. | Judging quality from a polished home-screen screenshot alone. |
| [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/) | Let system navigation supply the material layer; keep content readable beneath it. | Turning every card into a decorative glass panel. |
| [Apple: Writing for interfaces](https://developer.apple.com/videos/play/wwdc2022/10037/) | Purposeful labels, anticipated next steps, concise contextual feedback. | Generic “Learning,” contradictory upload claims, repeated explanation on everyday paths. |
| [Apple HIG: Entering data](https://developer.apple.com/design/human-interface-guidelines/entering-data) | Prefill known information, use suitable native input controls, allow correction. | Forcing AI-generated food names to be authoritative or treating import time as eating time. |
| [Apple HIG: Generative AI](https://developer.apple.com/design/human-interface-guidelines/generative-ai) | Make AI participation understandable and results correctable. | “Connected” implying a saved key was validated; no independent way to stop automatic uploads. |
| [Apple: Design an effective chart](https://developer.apple.com/videos/play/wwdc2022/110340/) | Comparable scales, readable series and explicit context. | Different scales creating apparent effects, UUID series names, hidden information for accessibility. |
| [Apple: Hello Swift Charts](https://developer.apple.com/videos/play/wwdc2022/10137/) | Preserve chart accessibility and meaningful data labels. | Flattening detailed charts into a single inaccessible image-like element. |

These sources guide product judgment; they do not establish that fewer words or fewer taps are always better. A useful correction, privacy disclosure or error-recovery action earns its place. Nutrient review does not belong in the default photo-to-journal journey.

## Implemented fixes

| Priority | Finding | Change |
| --- | --- | --- |
| High | Imported photos were attributed to the time of import. | Read available EXIF original time, reject invalid/future timestamps, expose editable eating time immediately after save. With no metadata, use current time and explicitly ask the user to check it. |
| High | Food names and portions could not be corrected through the everyday interface. | Native Edit meal form for title, time, note and food/portion list. Human overrides are separate from original AI estimates. Editing does not upload the photo. |
| High | Upload disclosure contradicted automatic processing. | Accurate disclosure, API key saved status and independent automatic-analysis switch. Turning it off invalidates queued requests; it cannot unsend requests already transmitted. Explicit analysis remains available. |
| High | A recent food comparison could link to an older meal with an empty chart. | Individual meal curves now use the same 90-day data source as the food library. Original historical records remain saved. |
| High | A successful field save could hide another field's failed save. | Capture note and eating time are persisted atomically; failed saves block dismissal and offer retry. |
| High | Ordinary edits could change a travel meal's historical timezone. | Preserve timezone unless eating time actually changes. |
| Medium | Keyboard compressed the saved-photo time label. | Scrollable, keyboard-aware capture content; hide camera controls after capture instead of leaving their empty space. |
| Medium | “Learning” confused pending data, missing data and missing food identity. | Specific status labels derived from actual quality limitations; usable-day progress is distinct from collecting the two-hour window. |
| Medium | Meal comparisons showed little contextual detail. | Optional Portions & context disclosure for the actual meals and available sleep/workouts; shared scales and no ingredient verdict. |
| Medium | Empty screens had no next step. | Meal logging actions in empty food/journal screens, Health-access recovery from empty activity, camera-settings recovery after denied permission. |
| Medium | Everyday editing was buried under nutrient controls. | Edit meal is prominent; nutrition review and Health export remain in a secondary disclosure. |
| Medium | Chart labels and visual consistency needed work. | Date/time series labels, detailed chart accessibility children, visible two-hour axis endpoint and consistent accent. |
| Medium | Accessibility text squeezed response headings, metrics and chart endpoint labels. | Vertical metric/header layouts at accessibility sizes, inward axis-label anchors, fewer axis labels and multiline meal fields. No screen-wide font cap. |
| Medium | Alarm customization required returning through unrelated legacy configuration to close. | A direct Done action returns to the original notification task. |
| Low | Nonessential success alert and inconsistent screen title. | Inline model-saved feedback; About readings title matches the navigation destination. |

## Verification method

An independent agent reviewed research, source, product journeys and final persistence/privacy correctness. The main agent ran actual simulator taps with XCUITest and inspected captured screens/accessibility trees. Native desktop capture was unavailable; no claim is made that the agent manually operated the macOS UI.

`Tests/JourneyAudit` is an independent UI-test harness that launches an already-installed app. Synthetic simulator-only fixtures supply meals, readings and workouts. They do not activate a sensor, call OpenAI or write food into Apple Health.

Journeys covered by the harness:

- Today → delayed sensor status → chart options → reading information.
- Today → camera → system photo picker → cancel → Journal → meal detail.
- Insights → food → comparison picker → shared-scale comparison.
- Insights → activity → workout detail → reading information.
- Settings → Sensor, Notifications, Apple Health, Meal analysis, Privacy & data, Advanced.
- API-key sheet validation/cancel and model disclosure, without submitting a real key.
- Notifications → original alarm settings; Advanced → original configuration, device diagnostics, treatment records, classic dashboard and back.
- Native meal edit → save → reopen and verify the correction persists.
- Saved capture → optional note keyboard → Done; editable date control present.
- Empty Today/Journal/foods/activity → contextual logging or Health recovery.
- Secondary nutrition review, without confirming an estimate or exporting to Health.
- Read-only legacy subdestinations where available.

Regression results so far:

- 42 Foundation/Swift tests passed, including EXIF time parsing and existing glucose/food/notification rules.
- Simulator and generic iPhone compilation passed; no signing or installation on the physical phone.
- Isolated simulator production-store checks passed: legacy decoding, manual override round trip, import time, retained photos/IDs/Health references, corrupt-index write protection and failed-write rollback.
- Mock analysis queue checks passed: saved-first capture, note-before-upload, no historical uploads, stale/deleted reply rejection, bounded retries, API denial and opt-out cancellation.
- Health authorization-type and notification-default compatibility checks passed.
- Dark/accessibility-extra-large journeys ran with screenshot inspection. Inspection found visual defects despite successful taps; these were fixed rather than treating a green navigation test as proof of layout quality.

Earlier failed runs exposed the alarm dismissal issue and a system-picker navigation check. Xcode also reused an older test runner for one targeted run. Final acceptance uses a clean test build and freshly installed disposable runner. No failed or stale run is counted as final acceptance.

### Final acceptance

Twelve distinct journey definitions were exercised. The clean full run passed ten and exposed two failures: alarm dismissal and a photo-picker test that did not wait for the remote system picker to appear. The alarm task now provides Done from the navigation lifecycle; the test waits for actual picker presentation rather than an arbitrary animation delay.

After those corrections and the accessibility refinements, all four affected acceptance journeys passed on build 4236 in dark mode at accessibility-extra-large text: chart/food comparison layouts, all everyday settings destinations, meal correction/saved capture, and Today/camera/system picker/Journal. That run includes both formerly failing paths. The other eight journeys have passing earlier runs; the whole twelve-test suite was not rerun after the last small layout/navigation change.

- Final acceptance: **4 tests, 0 failures**, 192 seconds, `/private/tmp/libre-audit-verified4236.xcresult`.
- Earlier clean full audit: `/private/tmp/libre-audit-fresh4236.xcresult` (contains the two diagnosed failures, not a green acceptance run).
- Final simulator build: `/private/tmp/libre-4236-verified-build.log` — succeeded.
- Final unsigned iPhone build: `/private/tmp/libre-4236-device-verified.log` — succeeded.
- Swift regressions: `/private/tmp/libre-4236-tests-final.log` — **42 tests, 0 failures**.
- Final screenshots and accessibility trees: `/private/tmp/libre-audit-verified4236-attachments`.

Visual inspection confirmed that the response heading is no longer split into narrow columns, Meal/120m labels fit, metric rows reflow, the eating-time label survives the keyboard, and the alarm task has a visible Done button. Simulator appearance was restored to its original light/large settings. Temporary result bundles are local diagnostics; the workspace test sources provide the repeatable audit. CoreSimulator/XCUITest ran successfully, but this Xcode installation has no launchable Simulator.app at its standard location, so opening a separate Simulator GUI at handoff was unavailable.

## Data and scope boundaries

The old meal JSON remains decodable. New manual-override fields are optional. Original photos, AI estimates, IDs and Health correlation references are retained. No database migration, sensor re-pairing, credential replacement or automatic historical-photo upload is part of this release.

The audit is not a claim that every conditional xDrip integration screen was exercised. Real NFC/Bluetooth hardware, camera capture, denied-permission recovery on a device, live API networking, external service accounts and every specialist hardware configuration need separate device/integration verification. VoiceOver is not manually certified by accessibility-tree inspection. The legacy settings remain deliberately available under Advanced rather than being rewritten during a food-journal audit.

This turn does not install or alter the app on the physical iPhone.
