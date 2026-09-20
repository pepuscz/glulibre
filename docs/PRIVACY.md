# Data and sharing

## On the iPhone

Meal photos, notes, timestamps, AI estimates and glucose history are stored locally. API credentials use the iOS Keychain. Updating in place is intended to preserve data; uninstalling can remove it. Local storage does not mean exclusion from device backups or immunity to device compromise.

## Optional services

- **OpenAI:** with a key and automatic meal analysis enabled, new meal photos and notes are sent for analysis. Older meals are not automatically resubmitted. Manual analysis also sends the selected meal. The request uses `store: false`; that is not a guarantee of zero provider retention. Your account terms, data controls and usage charges apply. Changing the model does not itself upload anything.
- **Apple Health:** read access provides workouts and recorded sleep. Sleep is the union of asleep intervals in the 24 hours before a meal, not a sleep-quality score. Glucose sharing is separate; estimated meal nutrition is exported only after the user's confirmation. Workouts and sleep are not included in the meal AI request.
- **Watch, widgets and Live Activities:** selected readings or meal context can appear outside the app when enabled. Consider visibility on a locked device.
- **Inherited integrations:** Nightscout, Dexcom sharing, calendar and other saved integrations can share data when configured. Review Settings → Other connections; upgrading does not silently disable an existing user's connections.

Health records are not deleted by disconnecting context. HealthKit read denials can look like missing data, so the app must not claim that no returned samples means no sleep or activity occurred.

## Screenshots and bug reports

Repository screenshots use synthetic simulator data. Never publish another person's glucose history, meal photos, device/sensor identifiers, API keys or diagnostic logs without their informed permission. Redact reports before posting a public issue. A private security-reporting channel has not been verified for this repository; do not paste secrets into GitHub issues.
