# Notification audit — 20 September 2026

Scope: source review of every local-notification producer found in the iPhone
target, alert scheduling, iPhone expanded notification presentation, Watch
notification presentation, and the Home Screen badge. This is not an inspection
of the user's currently delivered notifications or a live alarm test. No health
data was exported. Existing personal alarm schedules are not changed in build 4240.

## Findings, in priority order

1. **The badge is a glucose display, not an unread count.** It is off when unset,
   but an explicit existing choice remains. The direct path can show mmol/L × 10;
   the routine-notification path supplies a decimal NSNumber instead. Neither
   has a visible unit or age. Freshness clearing relies on the app executing;
   it cannot guarantee timely removal while suspended. A red `62` can therefore
   be mistaken for 62 unread items, and a retained value can look current.
   Recommendation: retire glucose-as-badge in favor of widgets/complications.
   Keep the badge empty unless there is an actual, persistent, unresolved item
   the user can find and dismiss in the app. Do not create fake unread counts.

2. **Frequency is still inherited from an alarm-oriented product.** Routine
   readings are already quiet by default, but enabled immediate alerts use a
   shared five-minute automatic snooze; they may fire again on a later check if
   their condition persists. Missing-reading alerts use repeating timers.
   Operational battery/calibration alerts share much of that alarm machinery.
   Recommendation: separate user-actionable operational events from glucose
   safety alarms. One operational notice per unresolved episode, clear on
   recovery; no repeated success/reconnection notifications. Any change to
   glucose alarm repetition needs explicit policy review and regression tests,
   not a blanket rate limiter or silent migration of saved alarms.

3. **The standard alert uses emoji + uppercase title + value in one title line,
   with no proper body.** This is hard to scan and can truncate. The alert value
   body builder omits the unit. Recommendation: sentence-case event title,
   value/unit/time in the body, one action when required. Do not describe an
   ordinary food response as dangerous or infer its cause from one meal.

4. **iPhone expanded notifications still use the legacy dashboard presentation.**
   Large fixed fonts, heavy colored heading, chart, technical error codes, and
   fallback `LOW ALARM` are not aligned with the redesigned app. There is no
   explicit reading-age display in this view. The Watch view has a freshness
   check, but its title still receives uppercase content from the sender.
   Recommendation: native concise content first; historical values clearly
   timestamped; no alarming fallback when metadata is missing.

5. **Warm-up copy implies a completed sensor state based on a timer.** The body
   is cautious but vague. Suggested title: “Warm-up time has elapsed”; body:
   “Open Libre Debug to check for your first reading.” Do not promise that a
   valid reading has arrived or ask for another NFC scan.

6. **Notification attachment creation uses `try!`.** A missing chart thumbnail
   can crash alert creation. Follow-up should make the attachment optional so
   the essential text notification still delivers. This is separate from any
   change to alert thresholds or frequency.

## Complete producer inventory

| Notification | Current timing / gating | Proposed product treatment |
|---|---|---|
| Routine reading | Off when unset; explicit opt-in retained; passive/background-only; default 30 min, minimum 15; persistent sample deduplication | Keep off by default; prefer native glance surfaces |
| Low / very low / high / very high | Saved schedules; severity groups; five-minute immediate-alert auto-snooze; user snooze and sounds retained | Preserve safety policy pending separate review; concise title + value, unit, timestamp |
| Fast rise / fast fall | Same alert engine; disabled for new schedules, existing choices retained | Remain opt-in; not a food-quality score |
| Missing readings | Scheduled from last reading and saved schedule; repeating; snooze replans repeating timer | One actionable operational notice per episode as a proposed new policy; keep current behavior until approved |
| Sensor/transmitter battery | Threshold-driven; same immediate-alert cooldown | One low-battery episode notice when the hardware supports replacement/charging |
| Phone battery | Threshold-driven; same immediate-alert cooldown | Avoid duplicating iOS battery notices unless monitoring requires a distinct action |
| Calibration reminder | Applicable calibrated sensors only; saved interval | Never surface as a Libre food-journal task; keep support for existing applicable devices |
| Initial calibration | Sensor-driven; fixed identifier; cleared/requested when app returns | Device-specific, actionable only |
| Warm-up timer | One nonrepeating request per sensor, original activation deadline | Distinguish timer elapsed from first valid reading |
| Pairing / sensor not detected / transmitter error | Hardware callbacks; fixed identifiers; pairing timeout 60 sec; no common episode cooldown | Explain user action, no technical error dump; group and deduplicate operational episodes |
| Dexcom reset result | Response to explicit device action | In-app confirmation if foreground; one background completion notice if needed |
| Alarm volume test | Explicit settings action; placeholder text “will not be shown” | Keep testing separate from production copy; verify it cannot leak to visible notifications |
| Meal analysis / food spikes / activity summaries | No notifications scheduled | Keep silent; results belong in the journal |

There is no implemented unread-notification inbox backing an app-icon badge.
The bell in Today opens notification settings, not an inbox. These must not be
presented as if the app has unread messages.

## Evidence

- `RootViewController.createBgReadingNotificationAndSetAppBadge`,
  `ReadingNotificationPolicy`, `UserDefaults.showReadingInAppBadge`.
- `AlertManager.checkAlertAndFire`, `scheduleMissedReadingAlert`, `AlertKind`,
  `ConstantsAlerts.defaultDelayBetweenAlertsOfSameKindInMinutes`.
- `LibreNFC.scheduleDiagnosticWarmupNotification`, Bluetooth transmitter delegate,
  initial calibration / sensor-not-detected / transmitter-error callbacks,
  Dexcom reset result and settings volume-test notification.
- `xDrip Notification Context Extension/NotificationView.swift` and
  `xDrip Watch App/Views/NotificationView.swift`.
- [Apple notification design guidance](https://developer.apple.com/design/human-interface-guidelines/notifications/)
  and [notification management](https://developer.apple.com/design/human-interface-guidelines/managing-notifications).
  Recommendations above are product judgments, not newly established clinical rules.

## Verification boundary

The current routine-notification policy has nine passing unit tests covering
quiet defaults, freshness, deduplication and cadence. This audit does not claim
physical-device validation of Focus, sound overrides, repeated alerts, badge
expiration, or background delivery. No live glucose alarm was induced.
