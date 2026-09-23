# Connection-loss alerts and meal occasions — 4249

## Quiet outages

Missed-reading alerts now schedule one notification per last-reading timestamp,
persisted across relaunches. A newer reading clears the previous episode and
re-arms the configured delay. Dismissal does not schedule another reminder;
explicit Snooze requests one additional reminder. Stopping a direct sensor
cancels pending and delivered missed-reading alerts. Follower monitoring does
not require a local active sensor.

On upgrade, an old repeating request is removed. If its notice is already
delivered, nothing replaces it; otherwise its next fire time becomes a one-shot.
A generation check prevents migration from replacing a newer reading's request.
Low/high alerts, thresholds, sounds and saved schedules are unchanged. Missing
readings alone do not prove expiry and never automatically stop or reset a sensor.

## Observe everyday meals

Photos within 30 minutes of the first form a derived eating occasion. The window
does not chain indefinitely through snacks. All original photos, notes, times and
corrections remain intact; grouping is recalculated after edits/deletion. “Keep
this photo separate” opts an entry out. This reuses the existing separation flag,
so no storage migration or historical AI upload is required.

Each occasion shares the first capture's baseline and two-hour window. Its full
composition—not each course independently—is used for matching. An unidentified
course prevents confident composition matching. Occasions count once, not once
per photo. Thirty minutes is a product heuristic, not a physiological threshold.

Nearby meals no longer hide an otherwise complete observed curve, baseline or
peak. The phone and Watch label overlap; comparison plots use dashed lines for
observations excluded from aggregation. Missing readings, sensor changes and
incomplete windows still withhold unsupported metrics. Strict whole-meal
comparisons and repeated-day requirements remain; observing a rise does not
attribute it to a particular food. The two-hour observation is not a claim that
every meal response ends at two hours.

## Verification

- 70 pure tests passed, including bounded grouping, composition preservation,
  repeated occasions, separation, deletion, overlap and outage/migration policy.
- Five iPhone simulator journeys passed, including multi-course observations,
  existing comparisons, chart-first landing and alarm interaction regressions.
- Two original-Ultra simulator journeys passed, including overlap with a visible
  observed rise and navigation through the single scrolling view.
- Signed iPhone and Watch builds succeeded. iPhone 4249 installed and launched
  in place. Its private device log confirmed removal of the repeating request
  with no further reminder for the already-delivered episode.
- Private before/after checks preserved meal files, glucose history, sensor
  identity/start/end dates and saved alert entries/profiles. No private data or
  device screenshots are included in this release note.
- Direct Watch deployment remains blocked by unavailable developer connectivity,
  despite an unlocked Watch. Simulator success is not physical installation.
