# Storage and recovery

Local-first, no account required. Save first; export and Health sharing are separate operations.

- Keep existing Core Data and meal paths/identities. Do not migrate a working sensor database just to adopt SwiftData.
- Use atomic writes and iOS Data Protection (until first unlock for background capture).
- Keep history by default. Honor explicit retention choices; never silently prune restored history.
- Provide an encrypted portable archive with a tested restore path, not just an export button.
- HealthKit holds authorized measurements and confirmed nutrients—not photos or a full journal.
- Do not automatically upload personal health information to CloudKit. Apple review policy 5.1.3(ii) restricts this. Device backup and Health sync are not an app-managed CloudKit database.

## Format v1

`GLULIBRE-BACKUP-1\n` + 16-byte random salt + AES-256-GCM combined nonce, ciphertext and tag. Header/salt are authenticated. Password derivation: PBKDF2-HMAC-SHA256, 600,000 iterations, 32-byte key. Passwords are never persisted. Foundation/CryptoKit/CommonCrypto only; no new dependency or proprietary server.

Payload is versioned JSON: creation time, app build, exact Codable meal records, photo bytes with SHA-256, and portable glucose records with source identifiers, numeric values and flags. Maximum encrypted file: 256 MB. Credentials, Bluetooth state, preference files, Health workout/sleep records and treatment/calibration objects are deliberately excluded. This is a **journal backup**, not a complete device clone.

Restore decrypts/authenticates, checks version, unique IDs, filenames, photo hashes/decodability and finite timestamps/values before writing. Missing meals get fresh photo filenames, keeping existing files safe; existing meal IDs win. Queued AI jobs are removed from restored meals. Glucose is merged by stable ID into protected historical storage, never into the CGM database. The journal merges this with live points, preferring live readings at identical timestamps. No Health records are written or deleted by restore.

Both stores are idempotent, not one cross-store transaction: a crash may leave a partial restore. Retrying the same archive completes it without replacing existing records. Do not report success until both stores commit. A failed index save may leave unused photo files; these are safer than deleting originals, and are not automatically pruned.

## Verification

`swift test` covers encryption roundtrip/randomization, Unicode passwords, incorrect passwords, tampering, damaged hashes, path traversal, version rejection, merge deduplication and retention defaults.

Simulator `--journal-storage-checks` additionally runs production meal/history stores against disposable fixtures: byte-identical photos, metadata, repeated restore, newer edit preservation, cleared AI jobs, missing-photo rejection and reopen persistence. `JourneyAudit/testBackupAndRestoreEntryPoints` covers the native settings/password/Files journey. Never run fixture arguments on a physical phone.

Remaining limits: no automatic cloud sync, no scheduled off-device backup, no treatment restore, and no independent cryptographic security audit. Export status is not proof that a file provider finished uploading. Test a spare-device restore before relying on an archive as the only copy. Preserve an external pre-upgrade snapshot before deploying storage changes.

## Apple references (checked 15 October 2026)

- [File system and device backup](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively)
- [CloudKit architecture options](https://developer.apple.com/documentation/cloudkit/deciding-whether-cloudkit-is-right-for-your-app)
- [Health and health research policy](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research)
- [HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
