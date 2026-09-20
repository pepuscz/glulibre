# Functional redesign evidence — 19 September 2026

🌐 last30days v3.25.0 · synced 2026-09-19

## What I learned

**Reduce capture effort; do not confuse social enthusiasm with clinical evidence.** The requested last30days run included X, not just web search. Its 17 X posts were largely promotional; the sole Reddit result and much of HN were off-topic. YouTube included older fallback material. These results are weak evidence for modern CGM UX preferences, not a representative user study.

**The useful workflow signal is fewer manual steps.** [AlgomashAI on X](https://x.com/AlgomashAI/status/2099853902590136388) described typing as the bottleneck: “The bottleneck was never the scan. It was typing the number.” This supports reducing entry friction, not validating the post’s glucose-measurement technology. Keep photo capture local-first, optional notes and background analysis.

**Sensor onboarding needs an unmistakable finish signal.** Older comments on [a sensor application demonstration](https://www.youtube.com/watch?v=ULPvZjbdcKo) include @msnelson98: “I’m less intimidated on applying the sensor for the first time.” and @teenasnyder5641: “So easy, not at all uncomfortable, just a ‘thunk’.” These are historical qualitative examples, not recent prevalence estimates. In this app, the stronger evidence is the owner’s repeated difficulty distinguishing detection from completion. Separate activation, warm-up and connection; never use activation as generic reconnect.

**Native navigation follows tasks, not the old controller inventory.** Apple recommends hierarchical navigation for related information and modal presentation for focused tasks. The app now groups everyday controls around Sensor, Notifications, Apple Health and Meal analysis. Lesser-used integrations remain available under Other connections, and historical treatments are a searchable archive rather than a primary tab. [Apple navigation guidance](https://developer.apple.com/videos/play/wwdc2022/10001/), [feature organization](https://developer.apple.com/tutorials/develop-in-swift/organize-your-features?changes=__11_5).

## Life Science Research check

The research-router lane used primary literature after its Entrez helper lacked a required dependency. No clinical database success is claimed for that failed helper.

- **Personal variation is real; ingredient attribution is not automatic.** [PREDICT, Nature Medicine 2020](https://www.nature.com/articles/s41591-020-0934-0) supports variation among people and effects of composition/context. A mixed meal’s response cannot prove which ingredient caused it.
- **Repeatability limits confidence.** [Hengist et al., AJCN 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC11747189/) found low repeatability for duplicate meals in 30 adults without diabetes. Show repeated observations and spread, not a definitive food ranking from one or two meals. Our three-meal/three-day gate is an engineering display rule, not validated clinical confidence.
- **Sleep and activity are useful context.** [Tsereteli et al., Diabetologia 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC8741723/) reports sleep associations with next-morning glucose responses. [DiPietro et al., Diabetes Care 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3781561/) tested post-meal walking in a small, specific at-risk population. Neither establishes an individualized causal effect for any one recorded meal.
- **No established longevity score from these curves.** [Bermingham et al., Nature Communications 2026](https://www.nature.com/articles/s41467-026-70308-3) provides exploratory associations, not proof that eliminating ordinary glucose rises extends life. Preserve meaningful glucose alerts, but do not relabel meal responses as danger grades.

## KEY PATTERNS → product decisions

1. Photograph, optional note, leave. Nutrition review is a separate optional journey, never a capture gate.
2. Compare repeated meals with visible variability and sleep/activity context. Do not infer a cucumber or banana is harmful from one mixed meal.
3. Connection recovery uses saved Bluetooth pairing; new-sensor activation has its own explicit confirmation.
4. Keep notifications actionable. A warm-up notification opens setup; glucose alerts retain existing snooze behavior in a native sheet. [Apple notifications](https://developer.apple.com/design/human-interface-guidelines/notifications/), [alert design](https://developer.apple.com/videos/play/wwdc2017/813/).
5. Remove old presentation routes, not users’ stored data or engine state. Shared alarm profiles must not be changed as a side effect of editing a single period.
6. Be explicit about export scope and destructive retention changes. “All data” was inaccurate; the existing export excludes photos and notes.

## Research limitations

This was not a usability study. Current social retrieval was sparse and noisy; X marketing and older YouTube results are not consensus. Design decisions primarily use Apple platform guidance, observed simulator journeys, the owner’s workflow, and the primary clinical evidence above. Real NFC, notification delivery and background sensor behavior still require physical-device verification.

The following is the research engine’s verbatim run footer; “agents” is its source-worker label:

---
✅ All agents reported back!
├─ 🟠 Reddit: 1 thread │ 1 upvotes │ 1 comments
├─ 🔵 X: 17 posts │ 151 likes │ 52 reposts
├─ 🔴 YouTube: 6 videos │ 964,307 views │ 6/6 with transcripts
├─ 🟡 HN: 16 storys │ 781 points │ 876 comments
├─ 🗣️ Top voices: @Sally_A1c, @ZaveroX, @UpHonestReal │ r/iosapps
├─ 🕒 Recent evidence is thin: only 17 of 40 dated items are from the last 7 days.
└─ 📎 Raw results saved to ~/Documents/personal/xdrip-debug/docs/research/redesign-4237/cgm-app-food-logging-and-ios-usability-raw.md
---
