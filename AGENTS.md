# GluLibre: north stars

An open, local-first iPhone + Watch companion for longevity-curious people:
**Which meals repeatedly produce larger glucose responses for me, and in what context?**
**Capture → observe → compare.** Not a diabetes console or calorie tracker. Users own their data.

## Product rules

- **Snap and go:** photo, optional note, leave. Save locally first; AI runs in background. No mandatory nutrition form, waiting or confirmation to save.
- **Chart first:** glucose, trend and history before dates or operational details. Landscape expands the chart; inspection shows exact values/times.
- **Native, not instructional:** platform controls, short labels, useful defaults. No legacy dashboards or unnecessary settings. Support Dynamic Type, VoiceOver and dark mode; color alone is insufficient.
- **Watch is a glance:** glucose + arrow + chart, then meals. Automatic updates, native Crown scrolling and useful complications/widgets—not Connection/Sync chores. Stale readings must look stale.
- **Notify for a reason:** one connection-loss notice per outage, not endless retries. No routine-reading spam, automatic snooze popup or glucose-as-unread badge. Preserve glucose safety alerts and saved choices; policy changes need review/tests.

## Evidence and engineering guardrails

- Group nearby course photos non-destructively; show overlapping observations, but keep stricter **whole-meal** comparison gates. Show count/spread, coverage and sleep/activity context. Missing is not zero; association is not causation.
- Flatter curves are not proven longevity or food-quality scores. No universal “perfect” targets, invented confidence or Sinclair clinical protocols. Primary studies support claims; social/X posts suggest questions, not clinical truth.
- Preserve originals, timestamps, corrections and provenance. AI estimates food, not glucose. Health context stays local; sharing is opt-in, nutrition export requires confirmation, historical photos never auto-upload.
- Reuse sensor/persistence engines through testable adapters. Separate capture, extraction, deterministic analysis and UI; no duplicate stacks.
- Upgrade in place: preserve identities, app groups, Keychain, schemas, preferences and sensor state. Never uninstall/reset/NFC-reactivate for a UI fix. Retain GPL/upstream notices.
- Test journeys visually, including accessibility and Watch/Crown. Fixtures are simulator-only. Verify installed versions/data preservation; builds do not prove physical/background behavior. No publishing private data without permission.

## Read when relevant

[Evidence](docs/EVIDENCE.md) · [Food-response design](docs/PERSONAL_FOOD_RESPONSES.md) ·
[Research synthesis](docs/research/redesign-4237/SYNTHESIS.md) · [Privacy](docs/PRIVACY.md) ·
[Build/test guide](docs/DEVELOPMENT.md).
Historical notes may describe superseded UI; follow these current rules.
