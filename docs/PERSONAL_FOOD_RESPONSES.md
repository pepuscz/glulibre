# Product direction: your food, your response

Research and design decision · 19 September 2026

Status: research-led design specification. The first food-library/comparison release is now installed as build 4235; see `FOOD_RESPONSES_4235.md` for delivered scope, tests and remaining limits. Automated experiments and validated causal/predictive models remain future work. Sensor activation and existing alerts are unchanged.

## The job

Help a generally healthy, longevity-interested adult answer: **Which foods and meal combinations repeatedly produce larger glucose responses for me, and under what conditions?**

Capture remains photo → optional note → leave. Learning happens later. Grams of carbohydrate are useful explanatory data, not the product's organizing principle. The primary experience is a personal food-response library, not a diabetes treatment console or a generic calorie tracker.

## Evidence and its limits

This is a targeted primary-literature review, not a systematic review. Life Science Research's routing framework was used to separate individual variation, measurement reliability, and health outcomes. The Entrez helper could not run because its Python dependency was unavailable; primary publications and their PubMed records were retrieved through web search instead.

### Individual variation: supported

Zeevi and colleagues followed 800 people and 46,898 meals, validating a personalized prediction model in another 100 people. Responses to identical meals differed substantially across participants. Their model used food and person-level information; it was not a claim that carbohydrate content does not matter or that a photograph alone can predict response. The study population was not uniformly metabolically healthy. [Cell, 2015](https://pubmed.ncbi.nlm.nih.gov/26590418/)

PREDICT1 studied 1,002 UK adults and validated findings in 100 US adults. It also found large between-person differences. Meal macronutrients explained more glycemic variance than the reported person-specific factors in that analysis: 15.4% versus 6.0%. Personalization should therefore add to food composition, not discard it. [Nature Medicine, 2020](https://pmc.ncbi.nlm.nih.gov/articles/8265154/)

### Repeatability: mixed, requiring careful comparison

A 2025 NIH analysis of 30 adults without diabetes included 1,189 responses to duplicate presented meals across inpatient studies. Within-person reliability was low (ICC 0.28 for Abbott and 0.17 for Dexcom). The authors recommended aggregating repeated measurements. This argues against labeling a food from one trace; it does not prove that all personal food patterns are unknowable. Devices and study conditions differ from our app. [American Journal of Clinical Nutrition, 2025](https://pubmed.ncbi.nlm.nih.gov/39755436/)

A separate 2025 study in 176 young, healthy Chinese participants found consistent individualized glycemic sensitivity under standardized conditions, with a second study in 30 participants. Its sensitivity index showed temporal consistency. That supports studying repeatable personal tendencies, but a standardized person-level index is not equivalent to identifying a culprit ingredient in an uncontrolled mixed meal. [American Journal of Clinical Nutrition, 2025](https://www.sciencedirect.com/science/article/pii/S0002916525002011)

**Synthesis:** between-person variation and within-person noise coexist. Repeated observations, comparable conditions, and uncertainty are product requirements, not optional disclaimers.

### Context and combinations matter

An intensive longitudinal study of adults without diabetes assessed food, physical activity, and sleep in relation to free-living post-meal responses. Its associations support collecting context, not asserting that a specific workout or night's sleep caused an individual's change. [Yao et al., 2024](https://pmc.ncbi.nlm.nih.gov/articles/PMC11658231/)

A small crossover experiment in 25 healthy people found lower two-hour glucose after a Mediterranean-type meal with added extra-virgin olive oil. It does not establish an effect for every person, dose, or meal. It does show why an ingredient may modify a combined response rather than independently act as a glucose source. [Nutrition & Diabetes, 2015](https://pmc.ncbi.nlm.nih.gov/articles/PMC4521177/)

For bread + cucumber + oil, a glucose curve belongs initially to **that combination**. It cannot identify cucumber, bread, or oil separately. “Individual” does not mean every ingredient is an equally plausible direct cause. A banana eaten alone is easier to study than a banana smoothie with several other ingredients, but serving, preparation, timing, and context still matter.

### Longevity: do not turn a surrogate into a promise

An 18-week randomized trial of 347 adults tested a multi-component personalized nutrition program. It improved some cardiometabolic outcomes, including triglycerides and several secondary measures; LDL change was not significant. It combined several biological inputs and dietary guidance, so it did not isolate the effect of suppressing glucose peaks. It did not measure lifespan. [Nature Medicine, 2024](https://www.nature.com/articles/s41591-024-02951-6)

These findings justify a learning product, not a claim that removing every normal glucose rise extends life. A smaller curve is not, by itself, proof of a healthier food. We must not reward skipping meals, avoiding nutritious fruit, or adding fat merely to flatten a curve.

## What the current code actually does

- `MealModels.swift` already preserves the original photo, note, timestamps, ingredient names, portion text, nutrient estimates, and AI confidence. We are not losing all food identity today.
- `MealAIClient.swift` is predominantly a nutrient-estimation prompt. Ingredient identity, preparation, and evidence provenance are not sufficiently structured for reliable longitudinal matching.
- `GlucoseObservations.swift` calculates a two-hour, per-meal baseline and peak with useful quality gates. It does not learn repeat-food patterns.
- `JournalInsightsView.swift` lists individual meals from the latest 14 days. It does not answer “which foods for me?”
- Apple Health workout and sleep context is available on-device, but currently transient. Missing context is not evidence of no activity or good sleep.

The next release should build on these working foundations. It should not touch sensor activation or replace the storage/connection stack.

## The experience

### Today

Keep the current glucose curve and prominent camera action. Add at most one genuinely new personal-pattern card, with meal photos and a small comparison curve. Do not turn every post-meal increase into an interruption. Clinical safety alerts remain separate and preserved.

### Your foods

Make food responses the first Insights destination:

- Photo-led cards for recognizable foods and recurring meal combinations.
- Small overlaid response curves aligned to meal time; show individual traces and a typical curve only when the group is sufficiently comparable.
- Number of usable observations and visible spread. No opaque 0–100 food score.
- A food appears after its first observation, but as “Learning,” without a confident ranking.
- Sortable exploration of observed responses, not a permanent good/bad-food hierarchy.
- A tap opens the exact meals contributing to the result, so users can inspect or correct grouping.

Color represents relative response magnitude within an explained comparison, not danger or food morality. Shape, position, and accessible labels carry the same meaning; color is never the only signal. The main surfaces stay visual and concise. Method details live one level deeper.

### Compare

Show comparable repeats side by side: usual toast alone versus the same toast with a different accompaniment, or a similar meal with versus without a recorded walk. Display differences as observations, not causal facts.

Support a lightweight “Try again” action that reuses a meal identity, asks for no mandatory form, and can suggest changing one component on a future occasion. Do not ask users to consume excessive sugar, stop exercise, or change medication. More controlled repeated comparisons strengthen an inference; the app must not claim randomized-trial certainty from casual logging.

## Capture the right data without more work

Keep originals permanently unless the user deletes them. Add versioned, optional metadata rather than replacing existing fields:

| Layer | Needed information | Rule |
| --- | --- | --- |
| Capture | Original photo/note, captured time, actual eating time and timing confidence | Default to capture time; make correction quick. A photo is not proof that the entire visible serving was eaten. |
| Food identity | Canonical food concept plus original wording; full meal composition | Preserve combinations. “Banana” and “banana bread” must never merge by substring. |
| Variation | Portion and unit when known; preparation, ripeness, brand, sauces, drinks | Preserve unknowns; do not invent invisible oil, quantities, or ripeness from a photo. |
| Provenance | User-stated, visually observed, inferred; extraction model/schema version | AI identification confidence is not statistical confidence in a glucose effect. |
| Context | Meal timing, earlier logged meals, available sleep and activity | Mark unavailable/denied/missing separately. Keep Health context on-device and revocation-aware. |
| Response | Source readings, sensor identity, baseline, whole curve, coverage and exclusions | Recompute derived metrics after meal-time edits or late sensor data. |

Nutrients remain contextual features. Do not divide the response by uncertain photo-estimated carbohydrate grams and present the quotient as a personal biological constant.

Historical meals must continue to decode unchanged. Their free-text ingredients can seed conservative local grouping. Do not upload old photos automatically; any re-analysis must be explicitly initiated. User corrections must survive future model upgrades.

## Analysis architecture and rules

Separate five responsibilities:

1. **Meal evidence extraction:** AI describes the meal from its photo and note; it does not decide what caused a measured glucose response.
2. **Food identity/grouping:** a local, versioned, inspectable index relates food instances and meal combinations. Ambiguous items remain separate; mappings can be corrected.
3. **Response computation:** deterministic, tested processing derives observations from actual CGM readings.
4. **Comparison eligibility:** checks meal/context comparability and data quality before aggregation.
5. **Presentation:** renders the evidence available without upgrading association into causation.

Keep these services independent of SwiftUI, Bluetooth, and the AI request lifecycle. Reuse the durable meal store, read-only glucose bridge, and existing background analysis service. Derived indexes are rebuildable; raw records remain the source of truth.

Compute and retain more than the maximum point: baseline-relative peak, incremental area over a defined interval, peak timing, and the observed trajectory. Specify the area convention and units explicitly. Return-to-baseline measures need a tested tolerance and sustained-duration definition; “not observed” is distinct from recovery.

Use fixed, comparable windows for aggregate metrics. A two-hour view can be the compact default, with longer context visible where data permits. Do not claim two hours captures every mixed-meal response. If another meal intervenes, show that overlap; do not silently truncate and compare unequal windows as equivalent.

Before suggesting a recurring pattern, require multiple usable repeats on separate occasions, adequate coverage and baseline, and credible meal matching. Count alone is insufficient. A minimum repeat count is an engineering safeguard, not a clinically validated certainty threshold. Show the number and spread instead of fabricated “95% confidence.” Missing logging, changing sensors, portion uncertainty, and different activity/sleep remain potential confounders.

A food's association across unrelated mixed meals must not become an ingredient-specific causal verdict. Initially aggregate closely matched meals and explicitly observed single-food occasions. More ambitious ingredient attribution requires a separately validated statistical design, not an LLM explanation layered over correlations.

## Release sequence and acceptance gates

1. **Evidence capture:** backward-compatible food identity/provenance fields, preservation of originals and corrections, strict-schema parsing tests, and no extra capture steps.
2. **Personal library:** conservative meal grouping, repeat curves, visible spread/count, drill-down to source observations. No causal ingredient ranking.
3. **Comparisons:** explicit eligibility and comparable windows; optional contextual comparisons and simple repeat experiments.

Before shipping:

- Old meal JSON decodes and round-trips; photos, glucose history, sensor state, credentials, preferences, and alerts are preserved.
- One spiky mixed meal cannot blacklist each ingredient. Two nearly identical names with materially different foods do not merge automatically.
- Repeated identical meals with inconsistent responses show variability, not a confident verdict.
- Sparse, overlapping, incomplete, future-dated, or cross-sensor windows do not produce misleading ranked results.
- Portion/preparation differences and missing Health context remain visible in comparison eligibility.
- Editing a meal or receiving delayed CGM data invalidates affected derived results. Deletion removes the meal from every aggregate.
- No retrospective photo upload or new Health-data upload occurs as a side effect of upgrade.
- VoiceOver conveys response and uncertainty without relying on color; Dynamic Type and compact native layouts are visually tested.
- Source-derived computations get unit tests; extraction/grouping gets a labeled fixture set before effectiveness claims.

**Success is answering a personal food question with traceable repeated evidence, while keeping capture effortless. It is not reducing all of eating to a flatter line.**
