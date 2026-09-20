# Product screenshots

These are actual simulator captures, not design mockups. All meals, glucose and workout data shown are synthetic. No real health data, sensor identifiers or API keys were used.

| File | Screen | Source |
| --- | --- | --- |
| `today.png` | Chart-first Today | Build 4242, iPhone 15, `testTodayChartIsVisibleWithoutScrolling` |
| `food-comparison.png` | Repeated whole-meal comparison | Build 4243, iPhone 17 Pro, `testFoodComparisons` |
| `landscape.png` | Exact-reading chart inspection | Build 4242, iPhone 17 Pro, `testChartInspectionAndLandscapeFocus` |
| `watch.png` | Watch app glucose, trend and taller chart | Build 4244, Apple Watch SE 3 (40mm), `testChartIsReadableWithoutScrolling` |

Captured on 20 September 2026. The product UI is the real app; examples are not evidence that banana, yogurt or activity will produce these responses in any person. Files are kept at capture resolution and sized by HTML in the README, without retouching the UI. The Watch screenshot shows the app, not a watch-face complication.

To refresh: build/install on a simulator, run the corresponding [journey tests](../../Tests/JourneyAudit/README.md), export attachments with `xcrun xcresulttool export attachments`, inspect the images, then replace only these assets. Keep units and sample-data context clear. Do not substitute screenshots from a real user's device without specific consent.
