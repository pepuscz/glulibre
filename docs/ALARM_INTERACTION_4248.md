# Alarm interaction, 4248

Removed the automatic Low Alarm / Select Snooze Time sheet.

- Foreground alarms use native banners and Notification Center, with their existing sound configuration.
- Tapping an alarm selects Today without changing its snooze state or dismissing an unfinished meal editor.
- The explicit notification Snooze action still applies the configured duration. Dismissal and missed-reading rescheduling are unchanged.
- Thresholds, alarm eligibility, repeat intervals, mute overrides, sensor pairing and stored data are unchanged.

The obsolete SwiftUI alarm sheet is deleted. Manual legacy snooze controls remain separate from notification delivery.

## Verification

- All 61 pure tests passed.
- Three iPhone simulator journeys passed: alarm tap opens the chart, foreground handling leaves meal capture usable, and the landing chart stays visible.
- Simulator-only checks exercise the production response/presentation methods for every alarm kind, verify default taps do not alter snooze state, and verify the explicit Snooze action still does. These are routing checks, not an end-to-end certification of iOS sound delivery.
- Signed iPhone and Watch builds passed. iPhone 4248 installed and launched in place; installed metadata confirmed the version.
- Private before/after checks found no lost glucose rows, unchanged sensor identifiers/start/end dates, and identical contents for all 14 meal files. Device screenshots and backups are not published.
- Initial direct Watch installation hit a device tunnel timeout. After the Watch became reachable, build 4248 installed and launched in place; installed metadata confirmed the version. Watch code is unchanged from 4247; this fix is in the iPhone notification handler.
