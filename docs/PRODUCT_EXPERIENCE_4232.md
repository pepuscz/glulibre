# Everyday product experience — build 4232

## Product decisions, not claims of research consensus

This app's primary job is understanding food, movement, and glucose in context.
The new navigation is Today, Journal, Insights, Settings. Treatments are no longer
a top-level tab. Existing treatment records and specialist controls remain under
Settings → Advanced; nothing was deleted or reinterpreted. This hierarchy is a
product judgment for the requested workflow, not a finding that research mandates
a particular tab bar.

The old Settings and Bluetooth lists are not the everyday entry points anymore.
Native settings pages cover Sensor, Notifications, Apple Health, Meal analysis,
units, and Privacy. The Sensor page distinguishes connection state from fresh
glucose, reads the existing transmitter passively, and never pairs or restarts it.
Advanced explicitly opens the original configuration, pairing/diagnostic,
treatment, and alert editors. Those specialist editors have not been rewritten.

The existing root controller still owns CGM services. The coordinator retains the
original navigation controllers outside the tab bar, injects their existing
dependencies, and presents them only on request. There is no new sensor manager,
Core Data schema, glucose store, meal schema, or credential namespace.

## Apple Watch / Apple Health context

Implemented optional read-only workout and sleep context through HealthKit:

- Explicit opt-in in Settings → Apple Health or Insights → Activity.
- Only workout and sleep-analysis read permissions; no location, workout routes,
  heart rate, or broad health-library authorization.
- Last 14 days, refreshed on foreground entry and manually, kept in memory.
- Workouts listed with source, actual start/end interval, and recorded duration.
  Purple chart bands show elapsed intervals including pauses; active minutes
  remain a separate number.
- Workout detail shows 30 minutes before through one hour after, with glucose
  gaps, logged meals, coverage, and no causal/dosing claims.
- Meal detail shows nearby workouts and recorded asleep time in the preceding
  24 hours. In-bed/awake segments are excluded; overlapping sleep stages/sources
  are merged before summing. Missing sleep is not displayed as zero sleep.
- Stopping context display clears memory and disables reads. It does not delete
  Health records or revoke system permission. In-flight results cannot repopulate
  the view after disconnect.
- Empty reads are described as missing/unsynced records or unavailable permission,
  never as proof that the person was inactive or permission was granted.
- This data is not passed to the OpenAI meal client. Existing meal analysis still
  sends only its explicit photo/comment request after Analyze.

### Evidence basis and limits

[Yao et al. (2024)](https://pmc.ncbi.nlm.nih.gov/articles/PMC11658231/) observed
11,333 meals in 789 adults without diabetes. Post-meal activity and sleep duration
were associated with glucose response. This supports collecting context, not
declaring causation for a particular meal or prescribing an activity intervention.
[The PREDICT sleep study](https://pmc.ncbi.nlm.nih.gov/articles/PMC8741723/)
likewise supports examining sleep alongside meal responses. Neither validates a
longevity score. The prior X research informs current discussion and design, not
these clinical conclusions.

Permissions and data shapes follow Apple's
[HKWorkout](https://developer.apple.com/documentation/healthkit/hkworkout) and
[HealthKit privacy](https://developer.apple.com/documentation/healthkit/protecting-user-privacy)
model. Receiving an authorization callback is not treated as evidence of read
permission.

## Checks and remaining acceptance

- Simulator and signed iPhone builds pass; signature verified.
- 16 pure tests pass, including overlapping/clipped sleep duration and glucose
  continuity/coverage/meal-window limitations.
- Existing meal upgrade checks and HealthKit correlation-permission regression
  checks pass in the simulator.
- Rendered light/dark Settings, Sensor empty state, Insights meal observations,
  workout chart with clearly labeled simulated data, and Health opt-in screen.
- Original alert and treatment routes render after being removed from the tabs.
- New data and settings pages use native controls, Dynamic Type, semantic colors,
  and accessible labels. Interactive VoiceOver and every navigation gesture still
  require hands-on acceptance; routed screenshots are not end-to-end UI tests.
- Real Watch data cannot be claimed verified until the user opts in on device and
  Health returns records. Simulator sample workouts are DEBUG/simulator-only and
  never enter the phone's storage.

The previous photo crash correction is retained: food correlations are excluded
from Health authorization sets; only constituent nutrients are requested.
