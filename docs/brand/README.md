# GluLibre identity

**Your glucose. Your data. Your choice.**

The name combines glucose and *libre*: an open-source app with user-owned data.
It does not imply that every sensor or platform is open or supported.

The original teal mark combines an open G with a glucose-response curve.
It is generated from editable geometry, not adapted from Abbott or xDrip's logo.
Run `swift scripts/render_app_icon.swift` from the repository root on macOS to
rebuild the SVG, preview and iPhone/Watch/widget icons. Assets follow this
repository's GPL-3.0-or-later terms; see [NOTICE.md](../../NOTICE.md).

The rename does not alter signing, bundle IDs, app groups, Keychain access,
Core Data entities, UserDefaults keys, Health metadata, widget kinds, existing
deep links or the legacy Bluetooth restoration prefix. Internal `xDrip` and
`LibreDebug` identifiers remain for compatibility, and original credits remain.

## Build 4245 verification

- Signed iPhone and Watch builds, plus both simulator builds, passed.
- All 59 pure observation/Watch tests passed.
- Two iPhone simulator journeys passed: GluLibre branding/offline licenses and chart-first landing.
- Two 40 mm Watch journeys passed: chart visibility in both units and empty/stale/meal states. The empty-state prompt names GluLibre.
- Signed app and extension metadata reports GluLibre. Installation bundle IDs and signing entitlements match the prior build, and the Bluetooth restoration prefix matches the former display name.
- Existing Contact Image integrations retain their saved contact identifier; fallback lookup accepts the former app name without deleting contacts.

These checks do not reactivate sensors, upload food, change Health permissions or enable new sharing. Personal device backups and screenshots stay outside this public repository.
