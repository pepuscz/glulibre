# Build 4234 — quick capture and visual glucose context

- Everyday Log a meal opens a native camera directly. Shutter commits the photo
  locally off the main thread. The saved-photo screen has one optional autosaved
  note and Done; swiping it away also finishes. No Use Photo, Analyze, nutrition
  review, Health permission or confirmation gate is on the capture path. Library
  selection remains available from the camera screen.
- With an existing OpenAI key, only newly captured/explicitly queued meals get
  background analysis. The meal is already safely saved before upload. The note
  is held until Done/dismissal or backgrounding. iOS grants limited background
  time, not indefinite execution; durable requests resume when the app runs.
- Optional Codable queue metadata preserves decoding of old meal records.
  Input tokens reject obsolete replies, atomic updates reject deleted records,
  network retries are bounded, and permanent errors keep the photo without
  interrupting capture. No old journal records are auto-uploaded. No unreviewed
  nutrient estimates are silently exported to Health.
- Privacy copy now describes automatic analysis with the user's key.
- Charts show a 70–140 mg/dL research-reference band and amber above-reference
  shading, by default. Current readings have accessible color/status and an
  observed trend arrow when recent same-sensor samples support it. Stale or
  invalid readings never receive a green classification. Alarm settings are
  independent and unchanged.
- Meal detail foregrounds the chart, with a dashed pre-meal baseline, observed
  peak marker and signed baseline-to-peak difference. Insights adds sparklines.
  Quality gates remain: sparse data, changed sensors or overlapping meals do not
  produce a confident numeric meal comparison. A rise is not causal proof or a
  longevity/food score.

Reference: [Shah et al., healthy-participant CGM profiles](https://academic.oup.com/jcem/article/104/10/4356/5479355).
This reference is descriptive, not a universal treatment target. Values below
54 and above 250 mg/dL use very-low/very-high visual flags consistent with CGM
reporting categories; they do not create or alter clinical alarm rules.

## Verification

- 28 pure Swift tests pass (observation, notification and reference/slope logic).
- Simulator capture checks pass with mocked analysis, not paid API calls:
  save-before-upload, final note usage, no historical uploads, stale/deleted
  result rejection, interrupted-request recovery, three-attempt offline limit,
  missing key and permanent API denial.
- Existing meal upgrade and Health authorization regression checks pass.
- Simulator and signed iPhone builds pass; signature verified.
- Visually inspected saved-photo, Today/reference band, and meal peak/baseline
  screens using explicitly synthetic data.
- Physical camera capture and live OpenAI requests require a new user-taken meal;
  no private camera scene was captured or historical photo uploaded for testing.
- Pre-upgrade backup: `/private/tmp/libre-4234-upgrade.nWH3Tb` (outside Git).
- Installed build 4234 in place. Readings increased 212 → 214, with a fresh
  post-upgrade reading at 16:15:28 local time. No prior readings or sensor records
  changed; alarm entries/types unchanged; meal JSON and images byte-identical.
