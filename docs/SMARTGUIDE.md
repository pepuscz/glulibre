# Accu-Chek SmartGuide — experimental collector

Updated 11 November 2026 (4267). **Experimental. Direct setup, reconnect, background status reception and trend-mode history ingestion have been observed on one Czech-market sensor; meter calibration remains hardware-unverified.** Target: the current Accu-Chek SmartGuide family sold in Czech stores. No box photo, manufacture-date gate or firmware allowlist is required. Model, firmware and capabilities are read over Bluetooth; unknown/incompatible packets fail closed. This is not a claim that every retail batch has been tested.

## Use

Settings → Sensor → Sensor setup → Accu-Chek SmartGuide. Enter the complete serial on the blue applicator cap; enter the six-digit PIN only in the iPhone's system Bluetooth dialog. No NFC.

**First initialization is now offered explicitly after connection when eligible.** The user confirms a newly applied, unused sensor. The collector rereads status and session time before any write. Eligibility requires time-synchronization requested, no saved anchor, no previous attempt, an offset within the supported sensor lifetime, and no disallowed status flags. Existing sessions are never synchronized or restarted by this path. Keep mySugr as a fallback when eligibility cannot be established. Do not remove an app or unpair a sensor just to experiment. To hand over collection, prevent the other app from competing for Bluetooth.

An atomic protected file is written before the single session-time write; failure to save blocks the write. The attempt survives reconnect/relaunch and is never automatically retried. Success requires a clear synchronization flag and session-time readback consistent with the fresh status offset before collection: CGMS stores current time minus elapsed sensor minutes, not an echo of the written time. A dedicated 30-second confirmation timeout covers the status read, write and readback; uncertain writes are never retried automatically. Uncertain outcomes require review, not another activation. No physical initialization is performed by installation or opening setup.

Behavioral reference: [AccuChekKit PairingAdapter](https://github.com/loopandlearn/AccuChekKit/blob/4f8c3a8cb50e68a979bdbed2e207aca00e4b35e0/AccuChekKit/Pairing/PairingAdapter.swift), which conditionally sets session time on the synchronization flag; [Trio PR 1310](https://github.com/nightscout/Trio/pull/1310) reports real-sensor use of that driver. No AccuChekKit source/assets are copied or linked (no clear license grant found). Our encoder and gating are independently implemented. Advanced-security/ACS support is not added by this change.

Calibration can be submitted here when the connected sensor advertises calibration support and requests it. Enter a fresh finger-stick meter reading, verify its units, and confirm. A matching accepted stored record is required before reporting acceptance; an ATT completion or optional CGMS acknowledgement alone is insufficient. An uncertain result is never resent automatically. Use **Check calibration status** to reconcile it. This flow is hardware-unverified; keep Roche's app available as a fallback. GluLibre never changes reporting intervals or sends start/restart/stop commands. The only session-time write is the explicitly confirmed first-initialization path above.

This is not a replacement for the manufacturer's validated app or a treatment-decision system. The implementation-boundary and initial research notes below describe 4252 unless superseded by the 4257 initialization section above.

## Implementation boundary

- Reuses `BluetoothTransmitter` and `BluetoothPeripheralManager`; no second sensor manager. Background reconnect uses inherited CoreBluetooth restoration.
- Exact advertised `AC-<serial>` selection; reads Roche manufacturer, matching serial, model, firmware and CGM Feature before adoption. iOS handles bonding. Never stores the PIN.
- Bluetooth CGMS service `181F`: Feature `2AA8`, Status `2AA9`, Session Start `2AAA`, Measurement `2AA7`, RACP `2A52`, Specific Ops `2AAC`.
- Validates lengths, feature-declared CRC16-MCRF4XX, packed records, SFLOAT special values, clock continuity and status. Unknown/reserved flags fail closed. Warm-up, stopped/expired, fault, temperature and out-of-range records do not enter the glucose pipeline. Calibration-required readings are accepted as explicitly marked trend-mode observations (4261). Low/high alert bits are **not** discarded as faults.
- Session minutes anchor timestamps across reconnects. Uses the reported start date when consistent. Apart from the explicitly confirmed first-initialization path above, never rewrites the sensor clock. A contradictory clock stops collection instead of silently relabeling history.
- Automatic characteristic writes only request stored readings. History is buffered and sorted for the existing ingestion engine. That engine appends newer readings; this is reconnect catch-up, **not** a general importer for old gaps before the latest saved reading.
- Explicit calibration: read fresh status → get last calibration → durably record attempt → set calibration → read back matching record. No fabricated readings, implicit calibration or guessed 12-hour next-time field: outgoing next-time and record fields are zero, matching AccuChekKit. The sample-location byte is `0x11` per CGMS (correcting the older Nordic encoder's eight-bit-shift issue). Pending, rejected and unconfirmed are distinct from accepted. The local attempt journal survives app relaunch; corrupt/unreadable journals block writes. It is sensor-specific operational state, not imported by portable meal/history backups.
- Calibration is gated by sensor capability, request, temperature/fault/rate status, session age, fresh meter measurement (<3 min), confirmation and a connected active collector. After rejection, wait ≥15 minutes; after acceptance, ≥30 minutes and a new sensor request. Unconfirmed attempts remain blocked until a matching record resolves them. No retries after timeout, pause or disconnect. Never test this by submitting made-up values.
- A namespaced discriminator in existing `BLEPeripheral.transmitterId` persists identity without a Core Data migration. Existing Libre/Dexcom entities, IDs, readings and meals are untouched. Do not downgrade a SmartGuide setup to old builds: their orphan cleanup cannot recognize this new discriminator.
- Uses the existing calibrated-value path, excluding Libre smoothing/deletion. An inactive collector cannot deliver queued data into another sensor session.
- Watch uses the normal iPhone payload, not a direct sensor connection.
- No claims of Bluetooth qualification, medical-device certification or vendor endorsement.

## Sources inspected

- [Czech Roche transition to mySugr](https://www.accu-chek.cz/prechod-na-aplikaci-mysugr), retrieved 15 October 2026. This app transition is not proof of a changed BLE protocol.
- [Current Czech official shop](https://shop.accu-chek.cz/accu-chek-r-smart-guide), checked 15 October 2026: one listed SmartGuide family, up to 14 days. The public listing does not enumerate firmware revisions; compatibility is negotiated, not inferred from purchase date.
- [Roche Czech calibration guidance](https://www.accu-chek.cz/treninkove-centrum/cgm/senzor-kalibrace-doba-zahrivani): fresh meter input, stable glucose, two-stage calibration and irreversible wrong values. GluLibre does not invent its own calibration schedule.
- [Roche Czech pairing](https://www.accu-chek.cz/treninkove-centrum/cgm/jak-sparovat-senzor-s-aplikaci).
- [xDrip SmartGuide setup](https://navid200.github.io/xDrip/docs/Accu-Chek/SmartGuide.html).
- [xDrip libglupro](https://github.com/NightscoutFoundation/xDrip/tree/366c97a8de5fe644b20910ab008da98a07391c7b/libglupro), JamOrHam, GPL-3.0. Inspected bonding, notifications, status, history and session-clock handling. We intentionally do **not** copy its automatic clock write.
- [Juggluco FAQ-083](https://www.juggluco.nl/Juggluco/faq.html): official activation first, no repeated activation for an active sensor. Also inspected `Common/src/dex/java/tk/glucodata/AccuGattCallback.java` for UUIDs and `AC-` names.
- [Juggluco activation issue #372](https://github.com/j-kaltes/Juggluco/issues/372): maintainer still directs official activation in June 2026. The generic CGMS Start Session opcode alone is not a validated fresh-SmartGuide startup sequence. `libglupro` implements calibration but no explicit Start Session operation was found in the inspected revision.
- [Bluetooth CGMS 1.0.2](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/CGMS_v1.0.2/out/en/index-en.html): packet layout, SFLOAT, CRC and RACP time-offset filters.
- [Nordic Android BLE Library](https://github.com/NordicSemiconductor/Android-BLE-Library/tree/da698f297c75784ca3932bc19777cde93ec7c975/ble-common), BSD-3-Clause: parser behavior and independent full-record test vector. [License](licenses/Nordic-BLE.txt) also bundled in About → Third-party notices.

## Verification / release gate

### Initial standalone activation recheck — 8 November 2026 (superseded by AccuChekKit finding above)

No verified fresh-sensor activation sequence was found in these inspected paths:

- Juggluco `afe6539f1e48aa0b6aeb1a34741752323858a5ad`, `Common/src/dex/java/tk/glucodata/AccuGattCallback.java`: collection/control queries, not a validated activation implementation. Current FAQ-083 still explicitly requires official activation first.
- xDrip `98d4171ecfe512d7a54150c3e0511aca7b3a3a75`, `libglupro/src/main/java/lwld/glucose/profile/GluProBle.java` and `packet/Packet.java`: session-time adjustment exists, but is not evidence of successful first activation. Do not port that write as an activation fix.
- JugglucoNG `f740f0e556fdf4f6bc92efc22a89d74d42fd1b00`, `Common/src/dex/java/tk/glucodata/AccuGattCallback.java`: the inspected control writes likewise do not establish a fresh-sensor startup sequence.

This is a bounded source review, not proof that standalone activation is impossible.
Implementation remains blocked on a demonstrated startup sequence: either a working
reference with fresh-sensor evidence or a Bluetooth trace of successful official
activation, including requests, responses and timing. Capturing that trace requires
planning before the one-time activation; do not activate/reset the user's sensor as
an incidental diagnostic. No activation commands or phone changes were made in this
recheck. Existing tests do not certify activation.

4252: 90 package tests passed (14 SmartGuide, 63 observation/storage, 13 Watch); three iPhone simulator journeys passed and screenshots were inspected. Debug simulator and signed iPhone builds succeeded. These results do not verify physical SmartGuide reception or calibration.

`swift test` covers CRC/reference fixture, packed records, truncation/tampering, capabilities, SFLOAT, status suppression, timezone validation, reconnect anchors, exact selection, history requests, calibration encoding, units/freshness, acknowledgement decoding, record reconciliation and durable replay prevention. Simulator journeys cover saved peripheral recognition without migration, setup input gating and calibration review/cancel. A build or fixture is **not** a hardware test.

Before calling this verified: capture model/firmware automatically from the device; pair with the cap PIN; compare timestamps/readings against Roche's app sequentially; verify five-minute readings, background/locked-phone reception, relaunch, disconnect/catch-up, duplicates, real requested calibration and ended behavior. Build 4257 includes conservative first initialization, still hardware-unverified. Never repeat activation as a connection test. Keep private logs/serials/PINs out of the public repository.

## First physical initialization diagnostic (4259)

A Czech-market sensor cleared time-synchronization-required after the single session-time write. Reconnection read a valid CRC-protected UTC session timestamp with DST byte `0xFF` (unknown), which our parser previously rejected. AccuChekKit `CgmStartTime.swift` at `4f8c3a8cb50e68a979bdbed2e207aca00e4b35e0` ignores the DST byte. We independently accept this observed UTC/unknown-DST combination while retaining CRC, calendar and elapsed-offset verification; unknown non-UTC offsets remain rejected. A regression test uses the observed session/status packets without sensor identifiers or PINs. No new initialization is needed to read the existing session. This establishes the response to the time write, not yet valid glucose reception, calibration or full hardware validation.

## Trend mode (4261)

Calibration-required alone does not make SmartGuide trend readings invalid. Roche documents trend-mode glucose after warm-up, before calibration, unsuitable for treatment decisions. The collector accepts this flag while retaining CRC, timestamp, warm-up, range and fault gates. Each accepted uncalibrated reading retains a ` · Trend mode` source suffix in the existing reading deviceName field (also preserved by backups); Today labels the latest such reading “Trend mode · Not calibrated”. No schema migration or sensor write is involved. Tests cover the observed post-warm-up status and combined fault flags. Source: https://www.accu-chek.cz/produktova-podpora/smartguide-cgm

## Calibration access and retrospective research (4262, 11 November 2026)

Settings → Sensor now exposes Calibrate with meter for the active saved SmartGuide. It remains reachable when disconnected; the form explains blockers and offers reconnection. Setup no longer hides the control based on transient Bluetooth capabilities. SD CodeFree readings are manually entered with explicit units; no Bluetooth meter integration is claimed. The meter-value freshness limit is three minutes, matching Roche’s manual. Confirmation, sensor eligibility, durable attempt storage and acknowledgement/readback remain required. Device transport capabilities are logged without meter values or credentials. The physical calibration path remains unverified.

Two simulator journeys passed: direct Sensor entry with invalid-value/unit-change/confirmation checks, and visible disconnected entry with sending disabled. Signed device build succeeded; installation was deferred because the user’s phone was unavailable.

### What retrospective correction can mean

- Our current `SmartGuideProtocol.measurements` decodes CGMS `2AA7` glucose concentration, time offset, status, trend and quality. The inherited `glucoseLevelRaw` name does not establish access to electrode-current samples. AccuChekKit’s `CgmMeasurement` decodes the same concentration field. This is a statement about these drivers, not proof that no other sensor channel exists.
- Roche-affiliated researchers reprocessed raw study signals using an improved algorithm: [2026 paper](https://pmc.ncbi.nlm.nih.gov/articles/PMC13624188/), and [2024 pivotal study](https://doi.org/10.1177/19322968241267774). These papers do not supply a retail Bluetooth raw-signal extraction method or a reproducible algorithm for our saved concentration series.
- Separately, [Juggluco’s calibration documentation](https://www.juggluco.nl/Jugglucohelp/calibrationhelp.html) explicitly supports “Apply to past”: applying the latest meter-derived calibration to all readings of the same sensor, with offset-only or slope-plus-offset models. Thus processed glucose values CAN be retrospectively adjusted. This is a concrete alternative to raw-signal reprocessing, not evidence that a later calibration reconstructs the true earlier curve.
- Whether SmartGuide itself returns revised old records after a sensor calibration is still unverified. A safe future experiment is a read-only history comparison before/after a confirmed real calibration, preserving original records and comparing values at identical sensor offsets. Reconnecting alone does not establish this: our ingestion deliberately deduplicates older readings.
- A local retrospective estimate should be a separate, labelled, reversible series with stored meter references, stable-glucose eligibility, model/version and uncertainty; it must not overwrite originals or silently enter alert/Health pipelines. This research pass did not implement or claim a validated retrospective correction.

Sources: [SD BIOSENSOR CodeFree specifications](https://www.sdbiosensor.co.in/product-sd-codefree-3.php) (plasma-calibrated meter results); [Roche calibration manual](https://www.accu-chek.com/sites/g/files/papvje226/files/document/dms/Czech/User%20Manual%20Accu-Chek%20SmartGuide%20App/SmartGuide-app-man-html-cs_2024-11/index/kalibracesen/kalibracesen.html).

## Earlier-readings estimate (4263)

Settings → Sensor → Earlier readings compares **Original / Adjusted** after a confirmed meter calibration. This independently implemented offset-only estimate follows the general approach documented by Juggluco; it does not reproduce Roche’s raw-signal algorithm or claim clinically validated retrospective accuracy.

Before sending a calibration, the app saves an eligible meter reference and the preceding stable window. Eligibility requires at least three same-session trend-mode samples over at least ten minutes within the preceding fifteen minutes, a latest sample no more than five minutes old, gaps no longer than six minutes, rates no greater than 1 mg/dL/min and a total spread no greater than 10 mg/dL. These are conservative app rules, not a validated clinical stability detector. The sensor still enforces its own calibration eligibility. An ineligible history window does not block sensor calibration.

After sensor confirmation, the estimate adds `meter − window median` only to earlier uncalibrated samples from that session. Estimates outside 40–400 mg/dL are omitted, not clamped. Originals, live readings, alerts, meal metrics, Watch and Health exports remain untouched. A fixed offset does not change meal-to-baseline rises. Accuracy further back is unknown. Pending/rejected references never produce an adjusted curve.

Meter references, supporting samples and method version are protected local records and included in encrypted journal backups. Restore is idempotent and never sends a calibration. The UI uses short native controls with limitations behind “About this estimate,” following [Apple’s writing guidance](https://developer.apple.com/design/human-interface-guidelines/writing).

Verification: 116 package tests and three simulator journeys passed (original/adjusted history, calibration review/cancel and disconnected calibration). Screenshots were inspected; a sheet-presentation failure discovered during the audit was fixed. The signed 4263 device build succeeds. Installation and real calibration remain pending because the phone was unavailable; simulator acceptance is not sensor validation.

## Cached-service restoration (4264)

After installing 4263, a restored connection was incorrectly rejected as unsupported: `CBService.characteristics` was already populated from iOS's cache, while the collector's own characteristic map contained only the first discovery callback. The collector now waits for fresh callbacks from both Device Information and CGMS, ignores unrelated services, and starts validation once. Missing required characteristics still reject the profile after discovery completes. Regression tests cover both callback orders, duplicate callbacks, unrelated services and incomplete profiles. This changes discovery only; activation, pairing identity, calibration writes and saved readings are preserved.

118 package tests passed; signed build 4264 was installed in place. Physical reconnection completed both service callbacks, validated the existing session, enabled calibration indications and received 96 trend-mode history records. This verifies renewed collection on the same sensor, not successful meter calibration.

4265 keeps calibration-status progress and the result inline in the calibration sheet, avoiding competing shared alerts in the presenting screen. The read-only status operation reports completion through its caller; it never submits a meter value. Diagnostics record record number/status and completion without logging meter values or credentials. The simulator journey checks that status feedback is visible after cancelling a calibration review.

The 4265 update reproduced iOS's connected-peripheral restoration on the physical phone and passed both discovery callbacks, session validation and subscriptions. A new live reading had arrived on 4264 after history recovery; the local database gained all 55 records from the outage. No sensor activation or calibration write was used to restore collection.

## Calibration reference audit (4266)

Before another finger-stick, an audit against AccuChekKit `4f8c3a8` identified two mismatches: its `CalibratePacket` sends zero next-time/record fields, and `calibrateSensor` explicitly continues to readback even if Set Calibration receives no CGMS response. Both paths are corrected. Successful ATT completion now starts readback without claiming acceptance; late optional acknowledgements do not interrupt it. Old/pending records are polled read-only under the existing 45-second deadline. No path resends the meter value. ATT completions are associated with queued opcodes so completion of a preceding Get cannot masquerade as Set completion.

An offline executable compiled the unmodified reference packet encoder and CRC alongside our encoder: 36 combinations of values, elapsed offsets and previous next-times matched byte for byte. A reference-generated packet and documented acknowledgement are pinned in regression tests. This establishes encoding compatibility, not real-sensor acceptance. The read-only record query has succeeded on the user's sensor; an actual meter submission remains hardware-unverified. No calibration was sent as part of this audit.

4267 removes the misleading dismissal label “Done.” The form now has Cancel and a primary Calibrate toolbar action, followed by the explicit Send calibration confirmation. After feedback, dismissal is labelled Close. The action remains visible with the decimal keyboard open. The simulator journey exercises both cancellation and the actual Send action against a confirmed transmitter-free fixture; it verifies visible feedback and cleared input without a radio write.

## Timestamp-matched meter references (4268)

Earlier readings → **+** now accepts a meter value and its actual measurement date/time, independently of sensor calibration. Historical entries never send a Bluetooth command, rewrite their time to now, or mark sensor calibration accepted. The three-minute requirement still applies to the separate firmware-calibration workflow.

The version-2 method linearly interpolates the same-session trend samples bracketing the meter timestamp. It requires at least three samples spanning ten minutes within ±10 minutes, gaps at most six minutes, rates at most 1 mg/dL/min, and spread at most 10 mg/dL. These are app quality checks, not clinically validated accuracy guarantees. It adds `meter − interpolated sensor value` to earlier trend readings only. Future readings, originals, alerts, Health, Watch and meal metrics remain unchanged. One reference estimates an offset, not historical sensor drift or a correction to the size of meal rises.

The saved record contains the actual measurement time/value, supporting sample times/values, session identity and method provenance. Historical references coexist with version-1 sensor-confirmed references and survive encrypted backup/restore. Tests cover timestamp interpolation, old and exact-time references, gaps, changing glucose, session boundaries, serialization and idempotent storage. The UI uses a native value/date form and keeps method details collapsed.

4268 verification: package tests and the simulator history/form journey passed; screenshots were inspected. The signed build was installed and launched on the connected iPhone. A timestamp-matched historical reference was generated from that phone's saved readings using the production implementation, saved as a separate adjustment record, and read back byte-for-byte. No original glucose record was changed and no sensor calibration command was sent.

## Automatic timeout recovery (4269)

The physical log audit found that ordinary radio disconnects recovered automatically, but a status-read timeout called the permanent failure path and disabled all reconnects until user action. The next connection retrieved only the available history, leaving an older gap.

Status timeouts now discard unverified pending packets and reconnect through the existing CoreBluetooth connection engine. Setup timeouts do the same for a sensor with a saved session. They do not leave the collector blocked or depend on an app timer to re-enable it after suspension. Initial pairing, unsupported profiles and invalid packets still fail closed. Session identity, history, calibration attempts and explicit pause behavior are preserved; calibration and initialization commands are never replayed.

A request-scoped watchdog prevents an old timeout from interrupting a completed request, a later request, or a disconnected/paused session. Regression tests cover timeout-to-retry and stale watchdog cancellation. No notification policy or glucose calculation changed.

4269 validation: all 125 package tests passed, including status-timeout retry and watchdog cancellation. The signed iPhone build installed in place. After the phone was unlocked, physical reconnection validated the unchanged session, enabled notifications, retrieved 96 history records and subsequently received and saved a new live reading. This verifies post-update collection and catch-up; the timeout itself was not deliberately reproduced on the physical sensor.
