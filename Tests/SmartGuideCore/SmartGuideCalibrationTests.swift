import XCTest
@testable import SmartGuideCore

final class SmartGuideCalibrationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var start: Date { now.addingTimeInterval(-43_200) }

    private func secured(_ b: [UInt8]) -> Data {
        let c = SmartGuideProtocol.crc(b)
        return Data(b + [UInt8(c & 255), UInt8(c >> 8)])
    }

    func testCapabilitiesAreReadFromSensorNotRetailBatch() throws {
        let supported = try SmartGuideProtocol.capabilities(secured([1, 0x50, 0, 0x29]))
        XCTAssertTrue(supported.usesCRC)
        XCTAssertTrue(supported.calibrationSupported)
        XCTAssertTrue(supported.multipleSessionsSupported)
        // No start/restart command is exposed even if the generic feature bit is present.
        let readOnly = try SmartGuideProtocol.capabilities(Data([0, 0, 0, 0x29, 255, 255]))
        XCTAssertFalse(readOnly.calibrationSupported)
        XCTAssertFalse(readOnly.usesCRC)
        XCTAssertThrowsError(try SmartGuideProtocol.capabilities(Data([1, 0x10, 0, 0x29, 0, 0])))
    }

    func testCalibrationRequiresSensorRequestAndNoFault() {
        XCTAssertFalse(SmartGuideProtocol.Status().permitsCalibration)
        XCTAssertTrue(SmartGuideProtocol.Status(calibration: 4).permitsCalibration)
        XCTAssertTrue(SmartGuideProtocol.Status(calibration: 8).permitsCalibration)
        XCTAssertTrue(SmartGuideProtocol.Status(warning: 2, calibration: 8).permitsCalibration)
        for flag: UInt8 in [1, 2, 16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(calibration: 8 | flag).permitsCalibration)
        }
        for flag: UInt8 in [1, 4, 8, 16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(warning: flag, calibration: 8).permitsCalibration)
        }
        for flag: UInt8 in [16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(calibration: 8, sensor: flag).permitsCalibration)
        }
    }

    func testUnitsRangeFreshnessAndSession() throws {
        let input = try SmartGuideCalibration.Input(value: 5.5, usesMgDl: false, measuredAt: now)
        XCTAssertEqual(input.mgDl, 99)
        XCTAssertEqual(try input.minute(start: start, now: now), 720)
        for value in [Double.nan, .infinity, -.infinity, 0, 2.2, 22.2] {
            XCTAssertThrowsError(try SmartGuideCalibration.Input(value: value, usesMgDl: false, measuredAt: now))
        }
        for value in [0.0, 5.5, 41, 399, 1000] {
            XCTAssertThrowsError(try SmartGuideCalibration.Input(value: value, usesMgDl: true, measuredAt: now))
        }
        XCTAssertNoThrow(try input.minute(start: start, now: now.addingTimeInterval(299)))
        XCTAssertThrowsError(try input.minute(start: start, now: now.addingTimeInterval(300)))
        XCTAssertThrowsError(try input.minute(start: start, now: now.addingTimeInterval(-1)))
        XCTAssertThrowsError(try input.minute(start: now, now: now))
        XCTAssertThrowsError(try input.minute(start: now.addingTimeInterval(-14 * 86400), now: now))
    }

    func testCalibrationWirePayloadUsesFingerAndSensorNextTime() throws {
        let input = try SmartGuideCalibration.Input(value: 100, usesMgDl: true, measuredAt: now)
        let previous = SmartGuideCalibration.Record(mgDl: nil, minute: 0, nextMinute: 900, number: 0, status: 0)
        let expected: [UInt8] = [4, 100, 0, 0xD0, 2, 0x11, 0x84, 3, 0, 0, 0]
        XCTAssertEqual(try SmartGuideCalibration.setValue(input, start: start, now: now, previous: previous, usesCRC: false), Data(expected))
        XCTAssertEqual(try SmartGuideCalibration.setValue(input, start: start, now: now, previous: previous, usesCRC: true), secured(expected))
        XCTAssertEqual(SmartGuideCalibration.lastRecord(usesCRC: false), Data([5, 255, 255]))
        XCTAssertEqual(SmartGuideCalibration.lastRecord(usesCRC: true), secured([5, 255, 255]))
        let pending = SmartGuideCalibration.Record(mgDl: 100, minute: 700, nextMinute: 900, number: 1, status: 4)
        XCTAssertThrowsError(try SmartGuideCalibration.setValue(input, start: start, now: now, previous: pending, usesCRC: true))
    }

    func testResponseValidationAndNoRecordYet() throws {
        XCTAssertEqual(try SmartGuideCalibration.response(secured([28, 4, 1]), usesCRC: true), .acknowledgement(request: 4, result: 1))
        for bad: [UInt8] in [[28, 4], [28, 4, 1, 0], [28, 4, 255], [26]] {
            XCTAssertThrowsError(try SmartGuideCalibration.response(secured(bad), usesCRC: true))
        }
        let empty: [UInt8] = [6, 255, 7, 0, 0, 0, 0, 0, 0, 0, 0]
        guard case .record(let record) = try SmartGuideCalibration.response(secured(empty), usesCRC: true) else { return XCTFail() }
        XCTAssertEqual(record.number, 0)
        XCTAssertNil(record.mgDl)
        var invalid = empty
        invalid[8] = 1
        XCTAssertThrowsError(try SmartGuideCalibration.response(secured(invalid), usesCRC: true))
        var damaged = secured([28, 4, 1])
        damaged[2] = 2
        XCTAssertThrowsError(try SmartGuideCalibration.response(damaged, usesCRC: true))
    }

    func testUnknownOutcomeNeverAllowsRetryEvenAfterRestartOrLongWait() throws {
        var attempt = SmartGuideCalibration.Attempt(submittedAt: now, mgDl: 100, minute: 720, previousRecord: 1)
        let restored = try JSONDecoder().decode(SmartGuideCalibration.Attempt.self, from: JSONEncoder().encode(attempt))
        XCTAssertEqual(restored, attempt)
        XCTAssertThrowsError(try restored.allowsNewAttempt(now: now.addingTimeInterval(86400)))
        for record in [
            SmartGuideCalibration.Record(mgDl: 100, minute: 720, nextMinute: 750, number: 1, status: 0),
            .init(mgDl: 101, minute: 720, nextMinute: 750, number: 2, status: 0),
            .init(mgDl: 100, minute: 721, nextMinute: 750, number: 2, status: 0),
            .init(mgDl: 100, minute: 720, nextMinute: 750, number: 2, status: 4)
        ] {
            attempt.reconcile(record)
            XCTAssertEqual(attempt.outcome, .unconfirmed)
        }
        attempt.reconcile(.init(mgDl: 100, minute: 720, nextMinute: 750, number: 2, status: 0))
        XCTAssertEqual(attempt.outcome, .accepted)
        XCTAssertThrowsError(try attempt.allowsNewAttempt(now: now.addingTimeInterval(1799)))
        XCTAssertNoThrow(try attempt.allowsNewAttempt(now: now.addingTimeInterval(1800)))
    }

    func testRejectedCalibrationCooldownAndPersistence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SmartGuideCalibration.AttemptStore(url: directory.appendingPathComponent("synthetic.json"))
        XCTAssertNil(try store.load())
        var attempt = SmartGuideCalibration.Attempt(submittedAt: now, mgDl: 100, minute: 720, previousRecord: 0)
        try store.save(attempt)
        XCTAssertEqual(try store.load()?.outcome, .unconfirmed)
        attempt.reconcile(.init(mgDl: 100, minute: 720, nextMinute: 750, number: 1, status: 1))
        try store.save(attempt)
        XCTAssertEqual(try store.load()?.outcome, .rejected)
        XCTAssertThrowsError(try attempt.allowsNewAttempt(now: now.addingTimeInterval(899)))
        XCTAssertNoThrow(try attempt.allowsNewAttempt(now: now.addingTimeInterval(900)))
        try Data("corrupt".utf8).write(to: store.url)
        XCTAssertThrowsError(try store.load()) // Never silently discard the replay guard.
    }
}
