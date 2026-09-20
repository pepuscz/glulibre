# Fork history

GluLibre is a modified version of [xDrip4iOS / xdripswift](https://github.com/JohanDegraeve/xdripswift), not an upstream release. Original copyrights, source headers and the GPL license remain in place. See [NOTICE.md](NOTICE.md).

## Starting point

- Upstream checkpoint: 6.3.3, [`69eb8833`](https://github.com/JohanDegraeve/xdripswift/commit/69eb8833).
- Fork modifications: 24 August–20 September 2026.
- `main` contains the original fork checkpoint; ongoing work lives on feature branches. Consult the actual branch before assuming a screen or feature is released.
- `master` was retained as an upstream 7.x mirror. Do not automatically merge that architecture into this fork; port deliberately and revalidate on hardware.

## What changed

- GluLibre branding in build 4245: new name and original teal icon across iPhone, Watch and glance surfaces. Storage, signing and Bluetooth restoration identities are retained; upstream credits and license text are unchanged.

- Libre 2/2+ diagnostic flow, warm-up completion notification, completion haptics and Bluetooth handoff recovery. The replacement Libre 2 Plus EU sensor delivered valid readings in physical-device testing on 19 September 2026. The fork's diagnostic additions are Debug-only; this does not certify every sensor or region.
- Photo-first meal journal with optional notes, durable saving before background analysis, editable food estimates and confirmed nutrition export.
- Optional OpenAI analysis using a Keychain-stored user key and editable model ID. New meals can be analyzed automatically when enabled; **the original tap-Analyze-only description is no longer current**.
- Repeated whole-meal response comparisons, with sensor coverage and meal timing checks. Workouts and sleep from Apple Health provide context, not causal adjustments.
- Native iPhone presentation, chart-first Today, landscape inspection and an Apple Watch companion with complications.
- Repository documentation, preserved license/credits, bundled legal text and explicit release checks.

The original sensor, persistence and integration machinery remains underneath the new presentation. Removing an old screen is not permission to remove users' data or saved connections.

## Working with this fork

Use [DEVELOPMENT.md](docs/DEVELOPMENT.md) for local builds and [CONTRIBUTING.md](CONTRIBUTING.md) for change boundaries. Historical implementation notes under `docs/` describe individual checkpoints; they are not current feature promises.

Upstream provenance and history are intentionally preserved. Upstream synchronization is a maintainer decision, not an automated prerequisite to building the fork.
