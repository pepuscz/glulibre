# Functional redesign — build 4237

## Product decisions

The main loop is **capture → observe → compare**: photograph food, optionally add a note, leave, then compare repeated meal responses with activity/sleep context. Nutrition confirmation remains optional and separate from capture. No longevity score, universal flat-glucose target or ingredient-level causal claim is introduced.

This completion pass replaces the remaining navigation into the old controller-based dashboard, settings, Bluetooth tables, treatment list, alarm editor and nutrition editor. Old controllers are retained only where they own existing engine dependencies. Their database, Bluetooth and notification behavior is not rewritten as a second stack.

## Completed journeys

- **Sensor:** status and freshness, Bluetooth-only reconnect, explicit new-sensor activation, warm-up countdown, and a separate finish-connection action. Both NFC actions have a visible cancellation path. Opening a screen does not scan or activate anything. Warm-up notifications open setup.
- **Saved devices:** show existing names/serials and explicitly pause/resume a saved connection. Pairing is retained. Enabling a second CGM or enabling direct CGM while following remote data is rejected.
- **Alarms:** native category list, schedules, thresholds, per-period sound, silent override and snooze. Add periods by copying the preceding period; delete only after confirmation. Midnight cannot be moved/deleted, and duplicate times are rejected. Edits to shared sound profiles are isolated so other alarms retain their configuration. Native snooze sheets call the original alert engine’s handlers.
- **Settings:** everyday controls first; lesser-used sharing, Watch, spoken readings, calendar/contact display and reading-source options live under Other connections. Existing integration view models retain validation and storage; no duplicate credential store. Watch readings have an explicit on/off control and a concise stale-reading warning; Cancel on the consent sheet leaves the current setting unchanged.
- **Nutrition:** a native optional review form, independent of the existing photograph-and-go capture and meal correction flows. Unknown quantities remain blank. Explicit confirmation is required before sharing nutrition with Health.
- **Historical records:** searchable, read-only archive of existing treatment records. New treatment entry is deliberately not a primary longevity workflow. No records are deleted by this change.
- **Storage:** truthful export scope (readings/calibrations/treatments, not photos/notes/pairing/settings). Retention input is validated; reducing it requires a destructive-action confirmation. No retention value changes on upgrade or screen opening.

## Architecture and preservation

- `JournalManagement`: injectable adapter over the existing Core Data and Bluetooth managers.
- `JournalManagementViews`: native sensor, device, alarm and history views.
- `JournalServiceAdapter`: native presentation over existing integration models, keeping their business logic.
- `JournalNutritionView`: separate, optional nutrition confirmation.
- `JournalExperienceCoordinator`: owns navigation; no legacy-screen escape hatch.
- No Core Data schema migration, sensor-identifier reset, credential reset or mass meal rewrite.
- Existing engine owners stay retained while old presentation routes are removed. Deleting their source wholesale would risk hidden engine dependencies, so that is not part of this UI completion.
- Alarm deletion uses a child context; newly inserted objects receive permanent IDs before passing through parent contexts. No broad rollback of unrelated incoming readings.

## Verification

- Simulator build 4237: passed.
- Generic iPhone build 4237 (unsigned compilation): passed.
- Swift core suite: 42 tests passed.
- Isolated simulator checks: legacy meal decode/reload, image and IDs, manual overrides, Health correlation references, corrupt-store protection and failed-write behavior passed.
- Saved-first capture/analysis checks: passed, including opt-out, cancellation, offline retry, stale/deleted results and no automatic historical uploads.
- Alarm checks: passed for read-only opening/cancel, exact threshold preservation, shared-profile isolation, schedule add/delete, midnight protection, duplicate rejection, global enable and parent/child persistence. Local clock times were additionally checked on both Prague daylight-saving transition dates in 2026.
- Notification defaults and Health authorization-type checks: passed.
- First full UI pass: 11/12 passed; missing visible Cancel in sensor confirmation was fixed.
- Full UI rerun: **12/12 passed**, including capture/correction, food comparisons, activity, empty states, every settings destination, all seven integration destinations, sensor confirmation cancellation, alarm schedules/editor/add cancellation, nutrition review and retention cancellation. Result bundle: `/private/tmp/libre-redesign4237b.xcresult`.
- Dark mode at the largest accessibility text size: food comparisons, every everyday settings destination, sensor/alarms/storage, native snooze response and nutrition review passed. The Watch-consent test initially tapped the expanded label rather than the nested switch; after correcting its target, Watch cancellation and the sensor/alarm/storage journey both passed again on the final build. Bundles: `/private/tmp/libre-redesign4237c.xcresult` and `/private/tmp/libre-redesign4237d.xcresult`. In total, **14 distinct UI journeys passed**, with targeted accessibility reruns.
- Reviewed exported screenshots for Today, Settings, Connections, food responses, sensor confirmation, alarm schedules/editor, storage, nutrition, native snoozing and Watch consent. Largest-text forms reflow and scroll; they do not clamp the user's accessibility size. Simulator appearance restored to light / normal large text afterward.
- Final visual review shortened the inherited Watch consent wall of text while keeping its existing acceptance handler and stale-reading warning. The largest-text cancellation test passed again: `/private/tmp/libre-redesign4237e.xcresult`. Both final build targets compiled successfully after that copy change.

## Scope of verification

Tests use synthetic simulator data. No real health upload, API request, NFC activation, destructive retention change or physical-device installation was performed in this pass. Physical sensor connection, camera capture, push delivery, real Health export and background Bluetooth were not revalidated by the simulator. External integrations were navigated without enabling them or transmitting data.

The fork remains a development build. Direct Libre NFC setup currently uses the existing DEBUG-gated implementation; this is not a claim of production/App Store readiness or universal sensor support.

## Evidence

See [research synthesis](research/redesign-4237/SYNTHESIS.md) and the saved raw last30days report. X was included. Recent social evidence was sparse/promotional; primary clinical literature and Apple guidance informed decisions instead of treating post counts as validation.

## Physical-device deployment — 2026-09-19

- Signed Debug build 4237 installed in place over 4235 on the connected iPhone, using the existing bundle and team identity. Signature verification passed, including HealthKit and NFC entitlements.
- Private pre/post data backup: `/private/tmp/libre-4237-upgrade.9iCrPR` (outside Git).
- All 589 pre-backup glucose rows were preserved without changes; sensor IDs/start/end dates and alert entries were unchanged. The entire meal folder, including JSON and photos, compared byte-for-byte equal after installation.
- Device reports build 4237 and the app launched successfully. It received and persisted a fresh sensor reading at 23:34:30 CEST, bringing the reading count to 591. No NFC scan, activation, uninstall or re-pairing was performed.
- This deployment contains the completed redesign, not the subsequently discussed Sinclair-inspired profile; that remains a proposal. Physical camera/Health export and background delivery were not retested during this deployment.
