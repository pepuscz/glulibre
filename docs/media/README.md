# Product screenshots

These are actual app captures, not design mockups. `real-meal-timeline.png` shows real meal photos and a glucose timeline from a physical iPhone, reviewed and explicitly approved for public README publication by the user on 20 September 2026. All other captures use synthetic data. No sensor identifiers or API keys are shown.

| File | Screen | Source |
| --- | --- | --- |
| `real-meal-timeline.png` | Real meals and glucose timeline | Physical iPhone 15; exact user-approved screenshot |
| `today.png` | Chart-first Today | Build 4242, iPhone 15, `testTodayChartIsVisibleWithoutScrolling` |
| `food-comparison.png` | Repeated whole-meal comparison | Build 4243, iPhone 17 Pro, `testFoodComparisons` |
| `landscape.png` | Exact-reading chart inspection | Build 4242, iPhone 17 Pro, `testChartInspectionAndLandscapeFocus` |
| `watch.png` | Watch app glucose, trend and taller chart | Build 4244, Apple Watch SE 3 (40mm), `testChartIsReadableWithoutScrolling` |

Captured on 20 September 2026. These examples are not evidence that a pictured food caused a response or predicts anyone else's response. Files are kept at capture resolution and sized by HTML in the README, without retouching the UI. The Watch screenshot shows the app, not a watch-face complication.

Permission covers this exact real-data screenshot only—not other photos, raw health records or future captures. The published PNG is byte-for-byte identical to the approved private preview.

To refresh: build/install on a simulator, run the corresponding [journey tests](../../Tests/JourneyAudit/README.md), export attachments with `xcrun xcresulttool export attachments`, inspect the images, then replace only these assets. Keep units and sample-data context clear. Do not substitute screenshots from a real user's device without specific consent.
