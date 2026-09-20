# Landscape follow-up — build 4239

## Cause and scope

The journal presentation was installed above the original root dashboard, but the
root controller's compact-height transition still inserted a legacy landscape
controller above that host. The storyboard also hid the tab bar in compact height.

The journal now owns both orientations. Legacy landscape entry points are guarded
while the journal coordinator exists, and the tab bar's compact-height hiding rule
is removed. The original controller continues owning its existing services.

Today uses a two-column layout in landscape: reading and meal capture on the left,
chart on the right. Accessibility text sizes retain a scrollable single column.
The chart selection stays in the parent view state across orientation changes.
Existing rotation preferences are respected. Only simulator tests opt into rotation.

No persistence schema, sensor activation, NFC, Bluetooth, credentials, notification
policy, or saved user preference changes are part of this fix.

## Verification

- Simulator and signed iPhone builds succeed; deep code-signature verification passes.
- 53 existing core tests pass (42 glucose/meal/notification and 11 Watch tests).
- Rotation test covers both landscape directions, retained chart duration, opening
  and closing meal capture, Sensor navigation, and returning to portrait.
- Cold-launch test covers landscape launch and all four tabs.
- Both final UI tests pass: `/private/tmp/libre-4239-rotation-verified.xcresult`.
  Full-screen screenshots are exported to `/private/tmp/libre-4239-verified-screens`.
- Build 4239 installed in place and launched successfully on the connected iPhone,
  preserving the bundle identifier `com.652PWHFDA9.libredebug`. No uninstall occurred.
- Pre-update backup: `/private/tmp/libre-4239-upgrade.X39oRG/before` (611 readings).
  Post-update health-data export was denied by the approval reviewer; explicit user
  consent was requested before any retry. A before/after data comparison is therefore
  not yet claimed, nor is a fresh post-install sensor reading verified.
