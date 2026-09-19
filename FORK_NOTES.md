# Fork notes

This fork is based on upstream xDrip4iOS 6.3.3 (`69eb8833`) and contains a
personal diagnostic workflow for Libre 2/2+ plus simple meal capture.

## Working checkpoint

- Stable/default branch: `main`
- Original development branch: `debug/libre-pairing`
- Verified on: 2026-09-19
- Sensor: Libre 2 Plus EU 7F
- Verified flow: one activation scan, 60-minute warm-up, one streaming handoff,
  BLE discovery, unlock, and glucose delivery
- The tested replacement sensor connected successfully and the app received
  its first ten glucose samples after the BLE fix.

The Libre diagnostic behavior is compiled only in Debug builds. It prevents
automatic NFC retries during the warm-up, gives distinct completion haptics,
schedules a warm-up notification, records detailed NFC/BLE traces, clears the
previous sensor's CoreBluetooth identifier during handoff, and can recover the
correct 7F sensor from the UID in its manufacturer advertisement.

## Meal capture

The Treatments screen includes a camera/photo meal entry with an optional user
comment. Analysis is sent to OpenAI only after the user taps Analyze. The API
key is stored in the iPhone Keychain, photos and draft data stay local, and
estimated nutrition is written to HealthKit only after confirmation.

## Local signing and build

`xDripConfigOverride.xcconfig` is intentionally ignored. A local copy can set:

```xcconfig
XDRIP_DEVELOPMENT_TEAM = YOUR_TEAM_ID
MAIN_APP_DISPLAY_NAME = Libre Debug
MAIN_APP_BUNDLE_IDENTIFIER = com.example.libredebug
```

Build the workspace rather than the project so Swift Package dependencies are
resolved correctly:

```sh
xcodebuild -workspace xdrip.xcworkspace \
  -scheme xdrip \
  -configuration Debug \
  -destination 'id=YOUR_DEVICE_UDID' \
  -derivedDataPath DerivedData-LibreDebug \
  -allowProvisioningUpdates build
```

Do not commit API keys, signing credentials, device logs, or DerivedData.

This is experimental software and is not a substitute for the manufacturer's
app, a blood glucose meter, or medical advice.

The fork's `master` branch is retained as an upstream 7.x mirror. Porting this
checkpoint to that architecture should happen separately and be revalidated on
real hardware before replacing `main`.
