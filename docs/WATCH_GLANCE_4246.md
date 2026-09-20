# Watch face and settings, 4246

The complication showed “Sync” when its display preference was unset. That
looked like a connection problem even when the Watch had valid readings.

- Settings → Apple Watch is now a direct, always-available destination.
- An unset Show glucose preference defaults on; an explicitly saved off choice
  survives upgrades. Adding the complication is enough to display fresh data.
- Fresh data shows glucose and trend. Hidden data shows Off, missing data a dash,
  and stale data its age without a misleading glucose value.
- Watch connection changes rebuild the payload from current readings and settings.
- No bundle IDs, storage keys, signing identities or sensor activation paths changed.

## Verified

- 61 pure tests passed, including default/off preservation and unavailable states.
- Three iPhone simulator journeys passed: Watch settings and relaunch persistence,
  offline GluLibre branding/licenses, and chart-first landing.
- Two small-screen Watch journeys passed: chart readability in both units and
  empty/stale/meal states.
- Signed iPhone and Watch builds installed in place as GluLibre 4246. The physical
  Watch face displayed a real glucose reading and trend instead of Sync.
- Private before/after checks retained meal files and existing glucose history;
  readings continued arriving after the update.

App and extension display names are GluLibre. Internal target/product names remain
unchanged for compatibility. A system screen with a cached old label is not proof
that an old binary is installed; check installed build metadata before suggesting
reinstallation. Never uninstall to refresh branding.

Personal screenshots, backups and raw readings are not included in this repository.
