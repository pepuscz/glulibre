# Meal model settings — 4241

The existing default is `gpt-5-mini`; the choice was cost-oriented, not a demonstrated winner on a meal-recognition evaluation. The OpenAI Docs skill was used to verify image input, Responses API and structured-output support against the official model page: https://developers.openai.com/api/docs/models/gpt-5-mini (2026-09-20).

## Changes

- Expose the existing free-text model preference directly in Settings → Meal analysis → AI model, instead of hiding it inside “Model & key management”.
- Accept arbitrary model IDs without a compiled model allowlist. Trim whitespace; disable empty and unchanged saves. This does not guarantee compatibility with future API protocol changes: the selected model must support image input and strict JSON-schema output through Responses, and be available to the user's API project.
- Preserve the existing preference key and selected model. Centralize the unchanged fallback default. Saving does not contact OpenAI, validate account access, reanalyze old meals or change the API key.
- Capture the requested model once for each request and its saved analysis metadata. Changing settings during an in-flight request no longer mislabels that result. The recorded ID is the requested ID, not necessarily an alias's resolved snapshot.
- Correct the missing-key error's Settings destination; align the legacy editor's capability guidance.

## Verification

- Build 4241 for iOS Simulator; existing 59 package tests.
- UI journey `testEditableMealModelPersistsWithoutAPIRequest` covers visible editing, empty rejection, an arbitrary future ID, whitespace trimming, save feedback and persistence across relaunch. It restores the simulator's previous selection and makes no API calls.
- No database or sensor changes. No physical-device deployment in this change.
