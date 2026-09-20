# Build 4235 — Your foods

## Delivered scope

- Insights now opens a photo-led **Your foods** library, with whole-meal response traces, usable observation counts, and typical rise after three usable calendar days. All library thumbnails use a shared vertical scale; explicit comparisons also share a scale.
- Food detail shows repeated traces, median rise, full observed rise range, ingredients, source meals and available on-device sleep/workout context. Side-by-side comparison keeps meal combinations intact. Sorting by larger typical rises is available, without a good/bad-food score.
- Matching is deliberately conservative: exact normalized food names, serving descriptions, preparation, brand and ripeness, not substring matching or nutrient totals. Low-confidence identities, unknown portions and unanalysed photos stay separate. A user can exclude a mismatched meal from grouping using Meal options, then allow matching again later.
- New photo analysis records optional food identity/provenance metadata and prioritizes actual foods and combinations over nutrient totals. Original photos and notes remain intact. Historical photos are not automatically sent for re-analysis; new capture remains photo → optional note → leave.
- A pure Foundation analysis module separates matching and calculations from AI, SwiftUI and sensor code. Derived results rebuild after meal edits, deletion and incoming readings. The library loads 90 days of available glucose; the everyday chart remains 14 days. All older records remain stored.
- Analysis uses a two-hour window, stricter coverage/edge checks, nearby-meal exclusion, source continuity, baseline-relative peak and positive incremental area. Boundary interpolation only occurs across short identified same-sensor intervals; no extrapolation or interpolation across sensor changes. All typical values are descriptive observations, not causal ingredient effects or longevity scores.

## Explicit limits

- Three days is an engineering display safeguard, not a statistical confidence guarantee.
- Matching does not automatically merge synonyms or infer a culprit ingredient from unrelated mixed meals. Photos and estimated portions may be wrong; users can inspect the underlying meals.
- Available Health context is shown, not treated as a causal adjustment. The current Health read window remains 14 days; missing context is labeled unavailable.
- The release does not implement automated randomized experiments, a validated personal prediction model, or lifespan estimates.

## Verification

- 40 pure Swift tests pass, including 12 new food-response tests: whole-composition matching, portion distinctions, uncertain identities, user separation, repeated-day gating, overlap exclusion, missing data, sensor changes, future/deleted records, area integration and bounded interpolation.
- Simulator persistence checks pass for legacy meal/item decoding, optional evidence round-trip, schema requirements, meal IDs/timestamps/photos/Health references, corrupt-index write protection and failed-write rollback.
- Existing Health authorization, quiet notification defaults and saved-first/background meal-analysis regression checks pass.
- Simulator and signed device builds pass; signature verified.
- Synthetic library, food detail and same-scale comparison screens were visually inspected. Synthetic data is guarded by DEBUG + simulator only and is not written to the phone.
- No live OpenAI upload or physical camera capture was initiated for testing. The new prompt/schema will be exercised by the next user-captured meal; transport/background behavior was tested with mocks.
- No Bluetooth/NFC/sensor activation changes in this release. No re-pairing step.

Deployment backup: `/private/tmp/libre-4235-upgrade.zZDW45` (private local data, outside Git).

Installed in place and launched on the physical iPhone; device reports build 4235. Post-install checks found no missing/changed prior glucose rows or alert entries/types. Meal JSON and photo files are byte-identical. Sensor identity/start/end dates are unchanged; only its Core Data revision counter advanced as readings arrived before installation. After a transient Bluetooth timeout, the existing connection manager reconnected automatically. Build 4235 received a fresh glucose reading at 16:43:28 local time; total readings increased from 232 in the pre-install backup to 239. No NFC scan or re-pair was used.

The comparison screen was also visually checked at accessibility-extra-large text size; content expands and remains scrollable. Simulator text size was restored afterward. Final exact-source regression run: 40 tests, zero failures.
