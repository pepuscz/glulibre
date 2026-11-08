# Everyday movement · build 4254

Question: how does a meal's observed glucose response differ alongside everyday movement?

## Delivered

- Optional read-only HealthKit steps, walking/running distance, stand minutes and active energy; no workout required. Existing users choose **Include movement** to request the new permissions.
- Last 91 days backfilled as five-minute `HKStatisticsCollectionQuery` cumulative sums. HealthKit merges sources; never add overlapping raw iPhone and Watch records. Quantities remain separate: energy and standing never manufacture steps.
- Steps strip aligned with glucose, 30/60/120-minute meal windows, recorded movement on each occasion in food comparisons, and recent meals in Insights → Activity. Grouped course photos use the same occasion start as their glucose observation.
- Foreground refresh and live Health observer invalidation handle late sync/deletions. Disconnect clears in-memory context; it does not modify Health records. No new Health writes, uploads, notifications, workout sessions, sensor changes or meal schema changes.

## Interpretation

These are recorded totals, not proof of complete wear or tracking. Nil is not zero; HealthKit does not reveal whether absent samples mean denied permission, lack of recording or pending sync. Only completed five-minute bins are used. Boundary bins are proportionally apportioned and totals marked approximate. Window progress means elapsed time, not coverage.

Step-bar heights are relative to the visible interval, not clinical activity zones. Gaps never mean sitting. Stand minutes are Apple's estimate, not a validated sitting/lying/standing classifier. We do not currently collect Core Motion, heart rate or raw accelerometer streams. Health context remains derived and local; no causal food score or automatically inferred movement effect is produced.

## Evidence and API basis

- [2026 review of randomized crossover trials](https://doi.org/10.1111/obr.70152): acute benefits from activity breaks, particularly walking; substantial heterogeneity, not lifespan evidence.
- [Walking versus standing trial](https://pubmed.ncbi.nlm.nih.gov/27633397/): the two must not be treated as equivalent.
- [Apple HealthKit overview and source merging](https://developer.apple.com/videos/play/wwdc2020/10664/).
- [HealthKit statistics](https://developer.apple.com/documentation/healthkit/hkstatistics), [stand time](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applestandtime).

Tests cover unknown/zero, metric independence, window edges, unfinished/future bins, meal-time edits and recomputation. Simulator fixtures are synthetic and cannot verify actual Watch sync, physical permissions or source merging on a user's Health store.

Verification: 106 package tests passed (12 movement tests); simulator build passed. Six targeted UI journeys passed across recorded/missing/upgrade states, empty data, chart-first landing, landscape inspection, workouts and comparisons. The movement journey also passed with accessibility-extra-large text in dark mode; screenshots were inspected. Physical Health access and Watch synchronization still require device validation. No phone installation was performed for this change.
