# Guava integration assessment

Reviewed 14 November 2026. No account was connected and no health data was sent.

## Recommendation

Start with **GluLibre → Apple Health → Guava**, with the user's permission in both apps. Guava explicitly supports Apple Health as a bridge for third-party apps and imports glucose. It also accepts glucose CSV imports. The doctor can use Guava's own sharing workflow; GluLibre need not manage a separate clinician account.

GluLibre already has **Settings → Apple Health → Share glucose readings** and an opt-in export of confirmed meal nutrition. Photos, notes, meal-response analysis and local historical glucose adjustments are not exported through that path. Watch activity and sleep can reach Guava directly through Health; do not re-export copies from GluLibre.

## Before calling it connected

- Validate a small, explicitly authorized sample end to end: source, units, original timestamp, cadence and duplicates in Guava. GluLibre cannot infer Guava authorization from its own Health permission.
- The current Health glucose writer exports original calculated values without calibration-status metadata. Guava's handling of uncalibrated estimates is unverified. Resolve this before using the bridge as a clinical handoff; do not imply that the app's historical adjustment has calibrated the sensor or changed the exported values.
- The existing exporter selects at most 2,016 recent readings and advances a timestamp watermark. This is not a full-history migration or a verified retry queue. Historical export needs its own deduplicated, date-bounded flow.
- Keep sharing opt-in. Do not activate existing Health exports or upload historical meals merely by opening a Guava settings page.

## A future Connected services entry

Use **Guava** with **Via Apple Health** as its subtitle. Reuse the existing Health settings and link to Guava's setup. Show **Open Guava**, not a fake Connected badge: only Guava can confirm its import permission and completed ingestion. Keep detailed setup off Today.

A direct **Connect Guava** OAuth integration is a separate option if we need meal notes, photos or richer provenance. Guava advertises OAuth 2.1 and JSON/REST; its developer portal distinguishes personal single-user integrations from organization/multi-user integrations. The portal requires login. We have not verified endpoint schemas, glucose write scopes, attachment support, rates, pricing or mobile-client registration. Register the appropriate application and inspect those contracts before implementation; do not invent endpoints or ship a secret inside the app. Use stable export IDs, explicit scopes, revocable credentials and a durable retry cursor.

## Sources and code

- [Guava supported apps](https://guavahealth.com/supported-apps): Apple Health bridge and glucose CSV import.
- [Guava FAQ](https://guavahealth.com/faq): supported metrics, including glucose, food, sleep and activity.
- [Guava API](https://guavahealth.com/api) and [developer portal](https://guavahealth.com/api-portal/apps): API standards and registration paths.
- `xdrip/Managers/HealthKit/HealthKitManager.swift`: current glucose export.
- `xdrip/Experience/JournalSettingsViews.swift`: existing opt-in Health controls.

This is a supported integration route to validate, not a claim of tested GluLibre-to-Guava synchronization.
