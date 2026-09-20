# Build 4233 — attention for events, not every sample

## Shipped behavior

- Unset routine-reading notification preference now means **off**, including the
  user's current installation. An explicit legacy preference keeps its meaning.
- The everyday Notifications screen has no routine-update switch or interval
  chooser. It summarizes actual currently applicable saved low/high and missing-
  reading schedules; customization is collapsed, not a required setup task.
- For users who deliberately enable the legacy advanced routine-update feature,
  updates are passive, background-only, and rate-limited (30 minutes when unset;
  minimum 15 minutes). Reading identity and send time persist across launches.
  Stale/future readings, repeated samples, and overlapping submissions are rejected.
- Turning routine updates off clears only their pending/delivered identifier.
  Startup does the same for the new quiet default, even before a reading arrives.
- Clinical alerts do not pass through the routine-update policy. Existing alarm
  thresholds, sounds, schedules, repeat behavior and snoozes remain unchanged.
- Warm-up uses one non-repeating request per sensor and the original activation
  deadline. The wording distinguishes the timer finishing from valid readings.
  No activation, NFC, Bluetooth protocol or sensor-state changes.
- No meal-peak, food-grade, activity-summary or engagement notifications.
- Today, Journal, Insights, Health and Sensor screens lose repeated explanatory
  paragraphs. Charts use a compact icon legend, meal observations use labeled
  values, and interpretation details live behind About/Disclosure controls.
  Missing-data and stale-reading warnings stay visible where relevant.

## Meaningful defaults without overwriting personal care settings

When an alarm schedule is created for the first time: low 70 mg/dL, very low
54 mg/dL, high 240 mg/dL; existing very-high 250 mg/dL and 30-minute missing-reading
defaults remain. Fast-rise/fall alerts are specialist opt-ins for new schedules.
Existing schedule rows are **not** migrated or guessed to be unmodified defaults.
The existing user's 50/70/170/250 schedules therefore remain as saved, not silently
replaced with the new-install defaults. The screen displays the saved values.

These thresholds are a safety-oriented product starting point, not an optimal
range for healthy people, a diagnosis, or a clinically validated alarm system.
This fork is not an approved replacement for a medical monitoring system.

## Evidence and judgment

Life Science Research's research-router and Entrez instructions were used to
frame this as clinical safety versus non-diabetic observational evidence. The
Entrez helper could not run because `requests` is absent; official sources were
retrieved directly instead. No research result was inferred from that failed call.

- [Abbott Libre alarm guidance](https://www.freestyle.abbott/sa-en/discover-freestyle-libre/getting-started-with-freestyle-libre/optional-glucose-alarms.html)
  gives 70/240 mg/dL low/high alarm defaults for the described Libre system.
- [ADA Standards 2026](https://diabetesjournals.org/care/article/49/Supplement_1/S132/163927/6-Glycemic-Goals-Hypoglycemia-and-Hyperglycemic)
  defines level-1 hypoglycemia below 70 and level-2 below 54 mg/dL in diabetes.
  This is not a universal wellness target.
- [Shah et al. healthy-participant study](https://academic.oup.com/jcem/article/104/10/4356/5479355)
  reports glucose excursions in 153 healthy participants; it describes reference
  distributions, not thresholds for labeling each food or excursion harmful.
- Quiet-by-default notifications, disclosure placement, the cadence guard and
  retaining existing personal schedules are product/engineering decisions, not
  clinical findings. Existing alarm repeat behavior is deliberately not replaced
  by a new, unvalidated episode-suppression algorithm.

## Verification

- 25 pure Swift tests: 16 observation and 9 notification-policy cases.
- Simulator checks cover legacy preference binding and new default thresholds,
  plus the existing meal persistence and Health authorization regressions.
- Simulator and signed-device builds, visual inspection and in-place upgrade
  receipt recorded after deployment below. No live low/high event is induced.

### Device upgrade receipt — 19 September 2026

- Signed build 4233 installed in place as `com.652PWHFDA9.libredebug` and launched.
- Private pre/post backups: `/private/tmp/libre-4233-upgrade.ugXBgy` (not in Git).
- Glucose rows increased from 190 to 191; first verified post-upgrade reading at
  15:50:28 local time. Zero missing/changed prior readings or sensor records.
- Alarm entries and alarm types unchanged in the database; meal JSON and photos
  byte-identical. No re-pairing or sensor activation.
- The device routine-reading preference is still absent, now interpreted as off.
- Visual checks: Today and Notifications; simulator fixture data clearly labeled.
- Live low/high alarm delivery, Focus modes, and prolonged background operation
  were not provoked/tested on the user's real sensor. No claim of clinical validation.
