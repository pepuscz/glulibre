# Contextual glucose journal — next-release candidate

Prepared 2026-09-19, on `feature/contextual-glucose-v0.2`, based on the working
`libre-debug-v0.1.0` fork. This is a candidate, not a published release or a
claim that physical-device acceptance is complete.

## Product decision

Make the everyday experience a native glucose-and-meal journal: see the latest
reading and its age, capture a meal quickly, and examine its surrounding curve.
Keep the original sensor, treatment, alert, settings, and advanced-dashboard
controllers. Their service ownership is more important than replacing every
screen at once.

Implemented:

- Native Today and searchable Journal screens, semantic light/dark colors,
  Dynamic Type, native navigation/sheets, and SF Symbols.
- Latest reading with explicit freshness and stale-reading wording. Charts break
  across missing intervals and sensor changes rather than joining them.
- Camera or privacy-preserving photo picker, editable eating time and notes,
  existing explicit AI analysis and nutrition review, and existing Health export.
- Meal detail with photo, note, two-hour trace, coverage, and a descriptive
  baseline/peak comparison only when the window passes conservative checks.
- A Patterns explanation with 14-day coverage, uncertainty, and context guidance.
  It is not an automated pattern-discovery engine.
- Existing configured chart limits are optional in the new view, off by default;
  this does not disable or change existing alarms.
- Safer meal persistence and Keychain replacement, with surfaced errors.

Not implemented: sleep/activity HealthKit ingestion, causal food rankings,
diagnosis, dosing advice, a longevity score, automatic cloud photo uploads, or a
complete rewrite of the legacy settings/sensor/treatment screens. Notes can
capture sleep/activity context now without changing the stored schema.

## Research and evidence

Three Sol research streams covered clinical evidence, recent glucose/longevity
discussion, and current iOS design. Life Science Research guided primary-source
retrieval; last30days gathered current discourse. The initial X searches were
overconstrained and inadequate. Corrective X-primary runs retained 22 glucose
posts and 15 design posts from August 20–September 19. These are retrieved samples,
not exhaustive coverage or evidence of consensus. Dedicated microcopy and
accessibility X queries were not retained by the engine; those decisions remain
grounded in Apple guidance, not claimed X consensus.

Clinical anchors:

- [ADA 2026 diagnosis](https://doi.org/10.2337/dc26-s002): CGM is not a substitute
  for validated diagnosis/screening.
- [ADA 2026 glycemic goals](https://doi.org/10.2337/dc26-s006): diabetes treatment
  targets must not be relabeled as universal healthy-adult longevity targets.
- [Diet, activity and sleep in adults without diabetes](https://pmc.ncbi.nlm.nih.gov/articles/PMC11658231/)
  and [sleep and meal responses](https://pmc.ncbi.nlm.nih.gov/articles/PMC8741723/):
  context matters; an association does not prove a food caused a response.

Design anchors:

- [Apple charts guidance](https://developer.apple.com/design/human-interface-guidelines/charts)
  and [VoiceOver guidance](https://developer.apple.com/design/human-interface-guidelines/voiceover).
- Recent practitioner posts on [native interaction fidelity](https://x.com/kylemacomber/status/2100286491260076348),
  [real UIKit platform views](https://x.com/berkaypng/status/2101083728193683837),
  and [system sheets](https://x.com/sarunw/status/2100781999082414530).
- Recent glucose debate includes [the risk of pathologizing normal meal rises](https://x.com/drterrysimpson/status/2092286888317268453).
  This is discussion, not a clinical guideline or longevity outcome study.

These findings favor context and honest uncertainty over narrow “optimal” bands,
spike scores, or decorative custom glass. The 10-minute gap, 15-minute baseline,
two-hour window, and 70% meal-window coverage are transparent product heuristics,
not clinically validated cutoffs. In particular, the two-hour coverage check is
not a clinical 14-day reporting standard.

## Architecture and upgrade invariants

- `JournalExperienceCoordinator` installs presentation inside the existing
  storyboard root and adds one Journal tab. The root retains all CGM services.
- `JournalModel` reads snapshots through the existing accessor/context and reacts
  to saves/foreground changes. It creates no second Core Data or Bluetooth manager.
- `GlucoseObservations` is a pure Foundation module, independently unit tested.
  Its outputs are presentation-only and never written back to glucose readings.
- `JournalViews` contains SwiftUI presentation; capture/edit still uses the
  existing meal store, AI client, HealthKit flow, and native UIKit controllers.
- No bundle identity, entitlements, Core Data model version, glucose database
  path, sensor entities, pairing values, NFC/BLE protocol code, or meal Codable
  shape changed. Keep the existing signing/bundle configuration for upgrades.
- Meal files remain in Application Support/LibreMeals. IDs, photos, timestamps,
  timezone, revision, AI provenance, and HealthKit correlation references persist.
- OpenAI Keychain service/account are unchanged. Updating a key no longer deletes
  the previous key before attempting its replacement.
- A failed JSON decode blocks mutations and reports the error; it does not
  interpret unreadable data as an empty journal. Failed writes leave memory
  unchanged. New orphan photos are removed only if their own create fails.
- Legacy Health/local deletion reports partial failure rather than silently
  pretending both operations succeeded. There is no cross-store transaction.

## Verification

Completed:

- Debug simulator build (iOS 26.5, iPhone 17 Pro).
- Unsigned generic iPhone-target build; this is compilation, not installation or
  device execution.
- 14 pure observation tests: validation/deduplication, gaps/sensor changes,
  time-weighted coverage, baseline, incomplete windows, overlap, absent sensor
  identity, and future-reading exclusion.
- Simulator-only isolated persistence tests: legacy-format decode and edit/reload,
  unchanged IDs/time/photo/nutrition/Health reference, corrupt-index write
  protection, and failed-write rollback. The fixtures live in a disposable test
  directory, never in a user's store.
- In-place simulator install preserves its existing meal fixture.
- Rendered simulator checks of Today, Journal, meal detail/editor, and the
  preserved alert/sensor/settings routes; dark mode and large text inspection.
- `git diff --check`.

Reproducible pure tests:

```sh
swift test --scratch-path /private/tmp/libre-observation-tests
```

Simulator-only DEBUG launch arguments (excluded from iPhone execution):

- `--journal-ui-testing`: suppress initial license/notification test blockers.
- `--journal-demo`: synthetic, visibly labeled glucose; never writes CGM data.
- `--journal-storage-checks`: isolated persistence assertions and PASS log.
- `--journal-screen`, `--journal-meal`, `--journal-editor`, `--journal-patterns`,
  `--journal-alerts`, `--journal-sensor`, `--journal-settings`,
  `--journal-treatments`, `--journal-capture`: deterministic presentation routes.
- Meal/editor routes create a clearly labeled synthetic meal only in the simulator.

## Acceptance before release

During the initial simulator work, the real iPhone and its sensor were not touched. Do not publish a
release on the strength of simulator screenshots alone. Interactive automation
was unavailable because screen-capture permission was denied; routed screenshots
do not prove every gesture or assistive-technology interaction.

1. Install in place using the existing bundle/signing identity; never uninstall,
   reset storage, replace the paired sensor, or repeat activation for a UI upgrade.
2. Verify existing meals/photos/notes, glucose history, settings, and paired sensor
   are present; confirm new readings arrive in foreground and after backgrounding.
3. Exercise camera/picker, note editing, save/cancel, search, detail, and return
   navigation on device. Confirm an AI request requires explicit user action.
4. Check Health authorization/export and real alert behavior without changing the
   user's existing thresholds. Verify VoiceOver and large-text scrolling.
5. Only after acceptance, update release metadata and tag/publish the candidate.

## Device installation and meal crash correction — 2026-09-19

At the user's request, signed build 4231 was installed in place on the existing
iPhone app. The meal store and app database/settings were backed up locally first;
no uninstall, NFC scan, sensor activation, or pairing reset was performed.

The reported meal crash was an Objective-C exception in HealthKit authorization
after local meal confirmation, not image capture. `MealHealthKitWriter` included
the food correlation type in its authorization sets. Apple requires permission
for the constituent nutrient types, not the correlation container:
[HKCorrelationQuery authorization documentation](https://developer.apple.com/documentation/healthkit/hkcorrelationquery).
Both read/share sets now contain only the six nutrient quantity types; a guard
rejects correlation types before HealthKit can raise an exception. Simulator
regression assertions verify these sets and passed alongside the storage tests.

After installation, the saved meal JSON and JPEG compared byte-for-byte equal to
their pre-upgrade copies. All previous reading and sensor IDs were retained.
The existing sensor delivered a new persisted reading without re-pairing. No new
app crash report appeared during this verification. App identity, signed
HealthKit/NFC entitlements, and installed build 4231 were verified.

Still requires hands-on acceptance: retry Confirm meal and approve the system
Health permission sheet as desired, new-camera capture, background delivery,
and assistive-technology interactions. The earlier meal remains locally saved
with its analysis; it does not need to be photographed or analyzed again.
