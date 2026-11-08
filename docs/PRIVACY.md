# Data and sharing

## On the iPhone

Meal photos, notes, timestamps, AI estimates and glucose history are stored locally. API credentials use the iOS Keychain. Updating in place is intended to preserve data; uninstalling can remove it. Local storage does not mean exclusion from device backups or immunity to device compromise.

## Recovery

Settings → **Backup & restore** exports a password-encrypted `.glulibre` file through the native Files picker. It contains meals, original saved photo bytes, comments, estimates/corrections and glucose history (including raw numeric attributes and source identifiers). It does **not** contain API keys, live sensor pairing, settings, calibration objects or treatment records. Retain the password separately; there is no password reset for an encrypted archive.

Restore validates the entire archive and photo hashes, then adds missing records. Existing IDs and edits win. Restored glucose is journal history only: it never enters the live sensor, alert, calibration or Health-write pipeline. Imported meals are not queued for AI. A restore interrupted between the two local stores can be safely retried; it never replaces the current database. Files over 256 MB are not supported in this version.

The app does not upload backups or implement CloudKit sync. A Files destination is chosen by the user. Export completion means the file provider accepted the save, not that a remote upload or future recovery has been verified. iOS device backups and Apple Health synchronization are separate system services; GluLibre cannot confirm their contents. Do not treat sync as a versioned backup. Apple's [health-data policy](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research) must be reviewed before adding any app-managed health-data cloud service.

New/default installations keep history indefinitely. Explicit older retention choices are respected; Storage & export can disable automatic removal. Photos/notes and restored history are not pruned by legacy housekeeping. The Core Data store and meal/recovered-history files use Data Protection available after the first device unlock, so legitimate background sensor recording can continue while locked.

## Optional services

- **OpenAI:** with a key and automatic meal analysis enabled, new meal photos and notes are sent for analysis. Older meals are not automatically resubmitted. Manual analysis also sends the selected meal. The request uses `store: false`; that is not a guarantee of zero provider retention. Your account terms, data controls and usage charges apply. Changing the model does not itself upload anything.
- **Apple Health:** optional read access provides steps, walking/running distance, stand minutes, active energy, workouts and recorded sleep. Movement is read as merged five-minute HealthKit statistics for the last 91 days; Watch and iPhone records are not manually added together. Meal-boundary totals are approximate and may be incomplete or delayed. Gaps never establish sitting or lying. Sleep is the union of asleep intervals in the 24 hours before a meal, not a sleep-quality score. Context is re-read locally rather than saved into meal records or portable backups. Glucose sharing is separate; estimated meal nutrition is exported only after the user's confirmation. Movement, workouts and sleep are not included in the meal AI request. Existing context users explicitly enable the additional movement permissions.
- **Apple Watch:** adding a GluLibre complication shows glucose and trend by default. Hide them in Settings → Apple Watch → Show glucose; an existing off choice is preserved on upgrade. Out-of-date values are hidden. The Watch app can also show recent meal context.
- **Widgets and Live Activities:** selected readings or meal context can appear outside the app when enabled. Consider visibility on a locked device, including your Watch.
- **Inherited integrations:** Nightscout, Dexcom sharing, calendar and other saved integrations can share data when configured. Review Settings → Other connections; upgrading does not silently disable an existing user's connections.

Health records are not deleted by disconnecting context. HealthKit read denials can look like missing data, so the app must not claim that no returned samples means no sleep or activity occurred.

## Screenshots and bug reports

Repository screenshots use synthetic simulator data except the explicitly approved real-meal timeline identified in [media notes](media/README.md). Never publish another person's glucose history, meal photos, device/sensor identifiers, API keys or diagnostic logs without their informed permission. Redact reports before posting a public issue. A private security-reporting channel has not been verified for this repository; do not paste secrets into GitHub issues.
