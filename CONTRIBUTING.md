# Contributing

Help people understand their own meal responses without turning everyday eating into a glucose scorecard.

## Product boundaries

- Capture first, analyze later. Save a photo and optional note without waiting for AI.
- Lead with the reading and chart. Operational settings belong outside the everyday path unless something needs attention.
- Compare repeated whole meals. Preserve portions, preparation and uncertainty; never label a single ingredient harmful from one excursion.
- Keep measurements separate from AI estimates. Sleep and activity are context, not proof of cause.
- Prefer native, accessible controls and concise labels over instructions on every screen.

## Engineering boundaries

- Preserve glucose history, meals, photos, sensor state, credentials, app groups and saved integrations across upgrades.
- Keep existing copyright/license notices. Describe and date modifications; see [NOTICE.md](NOTICE.md).
- Separate UI, sensor transport, persistence and analysis. Do not create a second sensor manager or make background work depend on a visible screen.
- Add tests for observation rules, queue behavior and migrations. Exercise fresh/stale/empty states, rotation and larger text for UI changes.
- Use synthetic fixtures and mocked API responses. Do not upload private data, spend API credits, alter alarms, revoke certificates or re-pair sensors to test unrelated changes.
- Keep secrets, real device logs, provisioning files, generated projects, build products and research caches out of Git.

See [development](docs/DEVELOPMENT.md), [privacy](docs/PRIVACY.md), and [licensing](docs/LICENSING.md). Application contributions use GPL-3.0-or-later; dependency-specific licenses remain intact. This guide introduces no copyright-assignment requirement.
