# Watch face refresh — 4272

## Finding

The user reported a dash, “7m” and a clock on the face. Before opening either app, the physical Watch snapshot and shared complication cache both matched the phone's roughly two-minute-old reading. This localized the observed mismatch to the display timeline, rather than missing phone-to-Watch data. Build 4271 had no provider diagnostics, so the exact reason watchOS retained the old timeline cannot be proved retrospectively.

The code requested a timeline reload for accepted snapshots even when only delivery metadata changed, and again when loading its cache after a background launch. Logs contained bursts of repeated sends. The priority-transfer interval was 17 minutes, which could exceed Apple's 50 daily transfers; its timestamp also reset on app launch.

## Changes

- Compare and persist the actual complication content before requesting a targeted reload. The reading timestamp is part of its identity, so a new reading with an unchanged value still renews freshness. Meal updates, historical backfill and transport metadata do not spend the face's reload budget.
- Coalesce unchanged background application context. Continue replying to foreground Watch requests.
- Persist priority-transfer timing and content across launches. Routine priority wakes are at least 30 minutes apart (at most 48/day); honor slower saved intervals. No priority transfer when inactive or out of quota. Deliberate visibility changes may use remaining budget promptly.
- Keep the seven-minute expiry timeline. Use a system-managed relative date for the circular stale age, rather than freezing the text at the expiry time. Do not extend freshness or invent readings.
- Use a 30-minute fallback timeline request; fresh data requests its own reload. No polling loop, keep-alive, workout session or extra network service.
- Record only the latest reload-request time and provider timeline/reading timestamps in shared defaults. These bounded diagnostics distinguish cache delivery from actual timeline generation.

## Validation

All 131 Foundation tests passed, including five refresh regressions covering lifecycle bursts, unchanged values with new timestamps, meal/backfill isolation, relaunch timing and quota exhaustion. Combined signed iPhone/Watch build passed.

Installed and launched 4272 on the physical iPhone and Watch Ultra; versions were read back. The provider recorded a newly generated timeline using the same reading as the phone. The following sensor reading also reached a new provider timeline about eight seconds after its timestamp. All 7,019 pre-update readings, sensor records, 42 existing meal records and saved adjustments were unchanged; a new meal and photo were added during the check. This proves successive provider refreshes after installation; sustained background timing, on-face rendering and battery consumption require longer observation. WidgetKit retains control of display scheduling.

## Apple references

- [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date): dynamic budgets, changed-data reloads and system-managed dates.
- [Transferring data with Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity): replaceable context, complication transfers and physical-device testing.
- [Remaining complication transfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/remainingcomplicationuserinfotransfers): 50 daily priority transfers for an active complication; calls at zero fall back to queued user-info delivery.
