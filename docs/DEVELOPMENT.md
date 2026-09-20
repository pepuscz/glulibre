# Build and maintain Libre Debug

## Local build

Use macOS, Xcode with the required iOS/watchOS SDKs, and Swift Package Manager. Physical-device installation requires your own Apple signing setup. Local development has been exercised with Xcode 27 and iOS/watchOS 26.5; older toolchains and every device combination are not validated.

1. Clone this fork and select the branch you intend to build.
2. Copy `xDripConfigOverride.xcconfig.example` to `xDripConfigOverride.xcconfig`. Add your team ID and unique bundle identifier. The real override is ignored by Git.
3. Open `xdrip.xcworkspace`, select the `xdrip` scheme and your device, and resolve package dependencies.
4. Build **Debug** for the current fork-specific Libre diagnostic flow. A successful Release archive is not a substitute for checking its different sensor behavior.

```sh
xcodebuild -workspace xdrip.xcworkspace \
  -scheme xdrip -configuration Debug \
  -destination 'id=YOUR_DEVICE_UDID' \
  -derivedDataPath DerivedData-LibreDebug \
  -allowProvisioningUpdates build
```

For an existing installation, keep its bundle identifiers, signing team, app groups and Keychain access unchanged. Install an update in place; do not uninstall to fix a build error. Never reactivate or re-pair a working sensor just to test UI changes.

The Watch companion has its own target and provisioning requirements. Follow [Watch notes](WATCH_COMPANION_4238.md); don't assume an iPhone provisioning profile also covers the Watch.

## Tests

```sh
swift test
```

The package runs pure observation, notification-policy and Watch-state tests without sensors, Health access or credentials. UI tests use a separate generated project: [iPhone journeys](../Tests/JourneyAudit/README.md), [Watch journeys](../Tests/WatchJourneyAudit/README.md).

Debug simulator arguments provide synthetic fixtures. **Never run those fixture arguments on a user's phone.** Do not spend API credits, upload real food photos or change Health records as an incidental test.

## Architecture

| Area | Responsibility |
| --- | --- |
| `xDrip/Experience/` | Native screens, presentation adapters and pure observation/comparison rules |
| `xDrip/Meals/` | Durable meal records/photos, background AI and confirmed Health export |
| `xDrip/Managers/Watch/` | Shared Watch payload and freshness policy |
| `xDrip Watch App/` / `xDrip Watch Complication/` | Watch UI and glance surfaces |
| Existing managers, Bluetooth code and Core Data | Inherited engine, persistence and saved integrations |
| `Tests/` | Pure regression tests and simulator journeys |

Keep presentation separate from sensor ownership and persistence. New screens should adapt the existing engine, not create a second Bluetooth manager. Study [contribution boundaries](../CONTRIBUTING.md) before removing inherited functionality.

## Source and releases

Keep the workspace's `Package.resolved` committed; inspect dependency updates together with their licenses. Do not change the model ID into a compiled list: requests read the user's saved setting.

Upstream synchronization is manual. The inherited signed-build workflow is manual too, builds the selected fork ref, and uploads to TestFlight only when explicitly selected. Its Release path and signing setup need independent validation; documentation work does not certify public distribution. Other inherited certificate/identifier workflows remain maintainer-only tools. Never run certificate revocation as cleanup.

Before distributing a build: review the full diff, run relevant tests, preserve upgrade identifiers, attach matching source and notices, and complete [LICENSING.md](LICENSING.md). Do not tag a dirty working tree as a reproducible release. [Screenshot instructions](media/README.md).
