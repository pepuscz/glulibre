# License, origin and credits

**This is a modified fork, not the original xDrip4iOS release.**

Libre Debug is based on [JohanDegraeve/xdripswift](https://github.com/JohanDegraeve/xdripswift), upstream version 6.3.3, commit `69eb8833`. Copyright belongs to Johan Degraeve and the other authors credited in the source and Git history. Those notices have not been replaced by this fork's branding.

Fork changes dated **2026-08-24 through 2026-09-20** cover Libre diagnostics, meal capture and analysis, personal food-response observations, Apple Health context, iPhone/Watch UI, testing and repository documentation. [Fork history](FORK_NOTES.md) describes the changes; individual commits and retained headers establish their provenance.

The app is free software under the **GNU General Public License, version 3 or any later version**, as stated by upstream's in-app notice (`xDrip/Texts/TextsHomeView.swift`). A complete copy of version 3 is in [LICENSE](LICENSE). You may redistribute and modify the app under those terms. It is provided **without warranty**, including the implied warranties of merchantability or fitness for a particular purpose. No health or longevity outcome is promised.

## Included dependencies and assets

Full notices are bundled for offline reading in [ThirdPartyNotices.txt](xDrip/Resources/Legal/ThirdPartyNotices.txt), alongside [the GPL text](xDrip/Resources/Legal/GPL-3.0.txt), and exposed in Settings → About & licenses. Dependency revisions are pinned in the workspace's [Package.resolved](xdrip.xcworkspace/xcshareddata/swiftpm/Package.resolved).

| Component | Origin | License / notice |
| --- | --- | --- |
| ActionClosurable | [Yoshitaka Seki](https://github.com/takasek/ActionClosurable) | MIT |
| CryptoSwift | [Marcin Krzyżanowski](https://github.com/krzyzanowskim/CryptoSwift) | Upstream attribution license; retained verbatim in bundled notices |
| PieCharts | [Ivan Schütz; paulplant fork](https://github.com/paulplant/PieCharts) | Apache-2.0 |
| SwiftCharts | [Ivan Schütz](https://github.com/ivanschuetz/SwiftCharts) | Apache-2.0 |
| Legacy icon assets | [Icons8](https://icons8.com/) | Original attribution retained; audit asset-specific rights before changing or redistributing assets separately |

This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/).

Imported source files also credit authors including Nathan Racklyeft, Pete Schwamb, LoopKit authors, Faifly, Uwe Petersen, Bjørn Inge Berg and DiaBox. This summary does not replace their file-level notices or claim that every asset has one uniform license. Preserve those notices and review additional dependencies whenever the build changes.

Apple platform symbols, product names and third-party trademarks remain their owners' property. Neither the GPL nor this notice grants endorsement or trademark rights. No affiliation with or endorsement by Abbott, Apple, OpenAI, David Sinclair or the upstream project is claimed.

Before distributing binaries, follow the [source and notices checklist](docs/LICENSING.md). This inventory is maintenance documentation, not a legal opinion or a certification of regulatory compliance.
