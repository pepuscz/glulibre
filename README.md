# Libre Debug

### Your meals. Your glucose. Your patterns.

An experimental, open-source iPhone app for people curious about how their everyday meals relate to their glucose. Take a food photo, add a note if you want, and come back to the measured response—not another carbohydrate calculator.

[Get started](#try-it) · [How it works](#from-a-photo-to-a-pattern) · [Build from source](docs/DEVELOPMENT.md) · [Privacy](docs/PRIVACY.md) · [License & credits](NOTICE.md)

<p>
  <img src="docs/media/today.png" width="265" alt="Today: glucose value and a fully visible interactive chart, with meal capture below">
  <img src="docs/media/food-comparison.png" width="265" alt="Compare repeated meal responses in Insights">
</p>

*Real simulator captures using synthetic meals, workouts and glucose—not someone's health records. [Screenshot details](docs/media/README.md).*

## What does it solve?

A glucose curve alone doesn't tell you what you ate. A food diary alone doesn't show what happened afterwards. Libre Debug brings them together so you can ask:

- Which of my repeated meals are followed by a larger glucose rise?
- How do the observed responses to a banana alone and a banana with yogurt compare?
- Was there a workout nearby, or less recorded sleep beforehand?

It compares **whole meals and repeated observations**. It cannot identify a guilty ingredient from one sandwich or prove that a meal caused a change.

## Why try it if you don't have diabetes?

For curiosity and feedback—not because everyone needs a glucose sensor. Watching a familiar breakfast alongside your own readings can make an otherwise abstract pattern tangible. The PREDICT study found substantial differences between people's glucose responses to identical meals, supporting the idea that your own observations can be informative. [Berry et al., Nature Medicine](https://www.nature.com/articles/s41591-020-0934-0).

David Sinclair discusses food, metabolism and CGMs in *Lifespan*. If that longevity-minded curiosity brought you here, this app gives it a practical outlet: record, repeat, compare. It is **not a Sinclair protocol**; no affiliation or endorsement is claimed. [Original podcast episode](https://www.lifespanpodcast.com/what-to-eat-when-to-eat-for-longevity/), CGM segment at 33:26.

The limit matters: a flatter curve is not a proven longer life. A 2026 systematic review found no appreciable glycemic benefit in healthy normoglycemic participants, despite some encouraging findings in other non-diabetic groups. This is a learning tool, not a promise of disease prevention or longevity. [Review](https://pubmed.ncbi.nlm.nih.gov/41588451/).

## From a photo to a pattern

1. **Capture and go.** Photograph your meal or choose a photo. A note can clarify ingredients, portion or preparation. Saving doesn't wait for AI.
2. **Let the sensor measure.** See current glucose, a trend arrow and the recent curve. Rotate for a wider chart; touch it for a recorded value and time.
3. **Add context, optionally.** Your OpenAI key enables food identification from the photo and note. Apple Health adds workouts and sleep duration before the meal.
4. **Compare familiar meals.** Insights groups matching meal descriptions and portions. A typical rise appears only after usable observations across at least three days. You can correct a food description or separate a mismatched meal.

<img src="docs/media/landscape.png" width="850" alt="Landscape glucose chart with crosshairs and the selected reading's value and timestamp">

Also included: an Apple Watch companion, complications, iPhone widgets and Live Activity support. Availability depends on device, permissions and configuration. Sleep is currently displayed as context; automated sleep–glucose analysis is not implemented.

## Try it

This is a **self-built experimental fork**, not a public, medically validated release.

- Start with the [build and installation guide](docs/DEVELOPMENT.md).
- The fork-specific sensor path has been exercised with **Libre 2 Plus EU** on a physical iPhone. Other inherited integrations are not a promise of tested compatibility; check the exact sensor generation and region before buying anything.
- In Settings, connect Apple Health if you want sleep and workout context.
- Meal photos and notes work without AI. To enable analysis, add your own OpenAI API key in **Settings → Meal analysis**. The model ID is editable; there is no fixed model picker. API usage costs extra.
- Keep the same signing identity and bundle identifiers when updating. **Do not uninstall a working installation** just to upgrade: it can remove local data and connection state.

AI identifies foods; **the sensor supplies the glucose measurements**. Nutrition estimates need review. The app is not intended to diagnose a condition, guide medication or replace prescribed monitoring. Don't treat a single excursion or the chart's reference band as a diagnosis or an individual treatment target.

## Your data

Photos, notes and glucose history are stored on the iPhone. If automatic meal analysis is enabled and a key is present, new meal photos and notes are sent to OpenAI. The key is stored in Keychain. Sleep and workout context is not sent to the meal AI. Apple Health sharing and inherited external integrations are separate choices. Device backups and any services you enable have their own data handling. [Privacy details](docs/PRIVACY.md).

## Building on open source

Libre Debug is a **modified fork of [xDrip4iOS / xdripswift](https://github.com/JohanDegraeve/xdripswift)** by Johan Degraeve and its contributors, based on the 6.3.3 source checkpoint. Fork changes dated **24 August–20 September 2026** focus on meal capture, personal food-response comparisons, native iPhone/Watch presentation and Libre diagnostics.

The app remains **GPL-3.0-or-later**, with no warranty. Original copyright notices are retained. This product includes software developed by the "Marcin Krzyzanowski" (http://krzyzanowskim.com/). Legacy icons include work from [Icons8](https://icons8.com/). See [LICENSE](LICENSE), [attribution and dependency notices](NOTICE.md), and the [distribution checklist](docs/LICENSING.md).

This fork is independent of the upstream maintainers, Abbott, Apple, OpenAI and David Sinclair. Please report fork-specific issues [here](https://github.com/pepuscz/xdripswift/issues), not to upstream support.

[Contributing](CONTRIBUTING.md) · [Repository map](docs/README.md) · [Fork history](FORK_NOTES.md)
