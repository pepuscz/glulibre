# Watch scrolling, 4247

The Watch is a glance at glucose and a meal response, not a connection dashboard.

- Removed the Connection page, manual Refresh button and obsolete setup instructions.
- Replaced vertically paged, separately scrolling views with one native ScrollView:
  glucose and chart, followed by the last meal. No custom Crown acceleration or
  touch gestures override the system's scrolling.
- Kept automatic updates on launch, foregrounding, wrist wake, connection changes
  and the existing foreground timer. Background delivery and complication behavior
  are unchanged.
- Missing/stale readings show a brief recovery hint on the glucose view, not a
  separate screen. Fresh readings have no connection instructions.
- Preserved installation identifiers, saved data, sensor ownership and pairing.

## Regression coverage

The initial paged layout failed Crown traversal and touch return-to-glucose tests.
The single-scroll layout passed all five Watch journeys on the 49 mm Ultra 3
simulator, including forward/reverse Crown input with long meal text and large
accessibility type. The suite also checks chart visibility, touch navigation,
missing/stale data and dimmed privacy.

- Original Ultra (Watch6,18, 49 mm): Crown forward/reverse and chart checks passed.
- SE 3 (40 mm): four layout, touch, state and privacy journeys passed.
- All 61 pure regression tests passed; signed iPhone and Watch builds passed.
- iPhone 4247 installed in place. Private before/after checks retained meal files,
  all existing glucose records and sensor identity/start/end dates.
- After device reachability was restored, physical Watch 4247 installed and
  launched in place; installed bundle metadata confirmed the version. Hardware
  Crown feel still needs a hands-on check, separate from simulator navigation tests.

Tests use Apple's [Digital Crown automation API](https://developer.apple.com/documentation/xcuiautomation/xcuidevice/rotatedigitalcrown(delta:velocity:)),
not swipe gestures presented as Crown tests. The [test guide](../Tests/WatchJourneyAudit/README.md)
describes how to repeat them. Simulator events do not certify the tactile feel of
a physical Crown.

Only synthetic simulator fixtures are used in automated journeys. Device backups
and private screenshots stay outside the repository.
