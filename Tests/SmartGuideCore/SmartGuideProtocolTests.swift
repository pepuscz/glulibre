import XCTest
// Includes a CGMS fixture from Nordic Semiconductor (2018), BSD-3-Clause.
// Full notice: docs/licenses/Nordic-BLE.txt. Swift tests added 2026-10-15.
@testable import SmartGuideCore

final class SmartGuideProtocolTests: XCTestCase {
    func testTrendModeRetainsFaultGates() throws {
        let observed = try SmartGuideProtocol.sensorStatus(Data([0x41, 0, 0, 0x0a, 0, 0x9e, 7]), crcRequired: true)
        XCTAssertTrue(observed.status.calibrationRequired)
        XCTAssertTrue(observed.status.permitsReading)
        for bit: UInt8 in [1, 16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(calibration: 0x0a | bit).permitsReading)
        }
        for bit: UInt8 in [1, 4, 8, 16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(warning: bit, calibration: 0x0a).permitsReading)
        }
        for bit: UInt8 in [64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(calibration: 0x0a, sensor: bit).permitsReading)
        }
    }

    func testObservedSmartGuideUTCUnknownDSTResponse() throws {
        let packet = Data([0xea, 0x07, 0x0b, 0x08, 0x07, 0x27, 0x33, 0, 0xff, 0x6d, 0x3a])
        let start = try SmartGuideProtocol.sessionDate(packet, crcRequired: true)
        let formatter = ISO8601DateFormatter()
        XCTAssertEqual(start, formatter.date(from: "2026-11-08T07:39:51Z"))
        let statusAt = try XCTUnwrap(formatter.date(from: "2026-11-08T07:48:53Z"))
        let attempt = try XCTUnwrap(formatter.date(from: "2026-11-08T07:45:39Z"))
        XCTAssertEqual(try SmartGuideProtocol.verifiedInitializationStart(reported: start, minutes: 9,
            statusAt: statusAt, attemptedAt: attempt, now: statusAt.addingTimeInterval(3)), start)
        let status = try SmartGuideProtocol.sensorStatus(Data([9, 0, 8, 2, 0, 0x9e, 0x94]), crcRequired: true)
        XCTAssertEqual(status.status.calibration & 1, 0)
        XCTAssertThrowsError(try SmartGuideProtocol.sessionDate(secured([0xea, 7, 11, 8, 7, 39, 51, 4, 255]), crcRequired: true))
        XCTAssertThrowsError(try SmartGuideProtocol.sessionDate(secured([0xea, 7, 11, 8, 7, 39, 51, 0, 9]), crcRequired: true))
    }

    func testInitializationRequiresFreshUnsetSession() {
        let fresh = SmartGuideProtocol.Status(warning: 8, calibration: 3, sensor: 0)
        func permits(_ status: SmartGuideProtocol.Status = .init(warning: 8, calibration: 3), minutes: Int = 0, saved: Date? = nil, reported: Date? = nil, attempted: Bool = false) -> Bool {
            SmartGuideProtocol.initializationAllowed(status: status, minutes: minutes, saved: saved, reported: reported, attempted: attempted)
        }
        XCTAssertTrue(permits(fresh))
        XCTAssertTrue(permits(minutes: 60))
        XCTAssertTrue(permits(minutes: 61))
        XCTAssertFalse(permits(minutes: SmartGuideProtocol.maximumMinutes))
        XCTAssertFalse(permits(minutes: -1))
        XCTAssertFalse(permits(saved: Date()))
        XCTAssertTrue(permits(reported: Date())) // synchronization flag, not date syntax, controls initialization
        XCTAssertFalse(permits(attempted: true))
        XCTAssertFalse(permits(.init()))
        XCTAssertFalse(permits(.init(warning: 1, calibration: 1)))
        XCTAssertFalse(permits(.init(warning: 32, calibration: 1)))
        XCTAssertFalse(permits(.init(calibration: 17)))
        XCTAssertFalse(permits(.init(calibration: 1, sensor: 128)))
    }

    func testInitializationReadbackUsesSensorElapsedOffset() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for minutes in [0, 1, 10, 61, 720] {
            let start = now.addingTimeInterval(-Double(minutes) * 60)
            XCTAssertEqual(try SmartGuideProtocol.verifiedInitializationStart(reported: start, minutes: minutes,
                statusAt: now, attemptedAt: now.addingTimeInterval(-2), now: now.addingTimeInterval(1)), start)
        }
        // Reconnect much later: the saved attempt time is not the expected session start.
        let start = now.addingTimeInterval(-7200)
        XCTAssertEqual(try SmartGuideProtocol.verifiedInitializationStart(reported: start, minutes: 120,
            statusAt: now, attemptedAt: now.addingTimeInterval(-6600), now: now), start)
        // An echo of NOW is wrong for a sensor whose offset is ten minutes.
        XCTAssertThrowsError(try SmartGuideProtocol.verifiedInitializationStart(reported: now, minutes: 10,
            statusAt: now, attemptedAt: now, now: now))
        XCTAssertThrowsError(try SmartGuideProtocol.verifiedInitializationStart(reported: nil, minutes: 0,
            statusAt: now, attemptedAt: now, now: now))
        XCTAssertThrowsError(try SmartGuideProtocol.verifiedInitializationStart(reported: now, minutes: 0,
            statusAt: now, attemptedAt: now, now: now.addingTimeInterval(31)))
        XCTAssertThrowsError(try SmartGuideProtocol.verifiedInitializationStart(reported: now, minutes: 0,
            statusAt: now, attemptedAt: now.addingTimeInterval(1), now: now))
    }

    func testInitializationDateEncodingAndCRC() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-08T12:34:56Z"))
        let plain = try SmartGuideProtocol.initializationPacket(date: date, usesCRC: false)
        XCTAssertEqual(Array(plain), [0xEA, 7, 11, 8, 12, 34, 56, 0, 0])
        let secured = try SmartGuideProtocol.initializationPacket(date: date, usesCRC: true)
        XCTAssertEqual(secured.count, 11)
        XCTAssertEqual(try SmartGuideProtocol.sessionDate(secured, crcRequired: true), date)
        var corrupt = secured
        corrupt[3] ^= 1
        XCTAssertThrowsError(try SmartGuideProtocol.sessionDate(corrupt, crcRequired: true))
        XCTAssertThrowsError(try SmartGuideProtocol.initializationPacket(date: Date(timeIntervalSince1970: 0), usesCRC: true))
    }

    private func secured(_ bytes: [UInt8]) -> Data {
        let crc = SmartGuideProtocol.crc(bytes)
        return Data(bytes + [UInt8(crc & 255), UInt8(crc >> 8)])
    }

    func testCRCAndNordicReferenceVector() throws {
        XCTAssertEqual(SmartGuideProtocol.crc(Array("123456789".utf8)), 0x6F91)
        // Nordic ContinuousGlucoseMeasurementDataCallbackTest, full record fixture.
        let record = Data([15, 0xE3, 0xD2, 0xE4, 5, 0, 2, 0x14, 0xFF, 2, 0xF0, 0xE5, 0xF3, 0x8E, 0x3F])
        let result = try XCTUnwrap(SmartGuideProtocol.measurements(record, crcRequired: true).first)
        XCTAssertEqual(result.mgDl!, 12.34, accuracy: 0.001)
        XCTAssertEqual(result.trend!, 0.2, accuracy: 0.001)
        XCTAssertEqual(result.quality!, 99.7, accuracy: 0.001)
        XCTAssertEqual(result.minutes, 5)
        XCTAssertEqual(result.warning, 2)
        XCTAssertFalse(result.status(fallback: .init()).permitsReading)
    }

    func testPackedRecordsAndStrictCRCPolicy() throws {
        let first = secured([8, 0, 120, 0, 60, 0])
        let second = secured([8, 0, 123, 0, 65, 0])
        let records = try SmartGuideProtocol.measurements(first + second, crcRequired: true)
        XCTAssertEqual(records.map(\.minutes), [60, 65])
        XCTAssertEqual(records.map(\.mgDl), [120, 123])
        XCTAssertThrowsError(try SmartGuideProtocol.measurements(Data(first.dropLast()), crcRequired: true))
        XCTAssertThrowsError(try SmartGuideProtocol.measurements(Data([6, 0, 120, 0, 60, 0]), crcRequired: true))
        XCTAssertThrowsError(try SmartGuideProtocol.measurements(first, crcRequired: false))
        var damaged = second
        damaged[2] ^= 1
        XCTAssertThrowsError(try SmartGuideProtocol.measurements(first + damaged, crcRequired: true))
        XCTAssertThrowsError(try SmartGuideProtocol.measurements(secured([8, 4, 120, 0, 60, 0]), crcRequired: true))
    }

    func testFeatureAndStatus() throws {
        XCTAssertTrue(try SmartGuideProtocol.features(secured([1, 0x10, 0, 0])))
        XCTAssertFalse(try SmartGuideProtocol.features(Data([1, 0, 0, 0, 255, 255])))
        XCTAssertThrowsError(try SmartGuideProtocol.features(Data([1, 0x10, 0, 0, 255, 255])))
        let status = try SmartGuideProtocol.sensorStatus(secured([120, 0, 0, 8, 0]), crcRequired: true)
        XCTAssertEqual(status.minutes, 120)
        XCTAssertTrue(status.status.calibrationRequired)
        XCTAssertTrue(status.status.permitsReading)
        XCTAssertEqual(status.status.message, "Trend mode · Not calibrated")
        XCTAssertTrue(SmartGuideProtocol.Status(warning: 2, calibration: 4, sensor: 0x3F).permitsReading)
        for warning: UInt8 in [1, 4, 8, 16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(warning: warning).permitsReading)
        }
        for calibration: UInt8 in [1, 16, 32, 64, 128] {
            XCTAssertFalse(SmartGuideProtocol.Status(calibration: calibration).permitsReading)
        }
    }

    func testSFLOATSpecialsAndSignedExponent() {
        for value: UInt16 in [0x07FE, 0x07FF, 0x0800, 0x0801, 0x0802] {
            XCTAssertNil(SmartGuideProtocol.sfloat(value))
        }
        XCTAssertEqual(SmartGuideProtocol.sfloat(0xF064), 10)
        XCTAssertEqual(SmartGuideProtocol.sfloat(0xFFF6), -1)
        XCTAssertEqual(SmartGuideProtocol.sfloat(0x100C), 120)
    }

    func testClockAndReconnectIdentity() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let start = try SmartGuideProtocol.anchor(minutes: 120, now: now, saved: nil, reported: nil)
        let again = try SmartGuideProtocol.anchor(minutes: 125, now: now.addingTimeInterval(310), saved: start, reported: nil)
        XCTAssertEqual(start, again)
        XCTAssertThrowsError(try SmartGuideProtocol.anchor(minutes: 0, now: now, saved: start, reported: nil))
        XCTAssertThrowsError(try SmartGuideProtocol.anchor(minutes: 65535, now: now, saved: nil, reported: nil))
        let utc = try SmartGuideProtocol.sessionDate(secured([0xEA, 7, 10, 15, 12, 0, 0, 0, 0]), crcRequired: true)
        let prague = try SmartGuideProtocol.sessionDate(secured([0xEA, 7, 10, 15, 14, 0, 0, 4, 4]), crcRequired: true)
        XCTAssertEqual(utc, prague)
        XCTAssertThrowsError(try SmartGuideProtocol.sessionDate(secured([0xEA, 7, 2, 31, 12, 0, 0, 0, 0]), crcRequired: true))
        XCTAssertThrowsError(try SmartGuideProtocol.sessionDate(secured([0xEA, 7, 10, 15, 12, 0, 0, 128, 0]), crcRequired: true))
    }

    func testOnlyUsableReadingsPass() throws {
        let now = Date()
        let start = now.addingTimeInterval(-7200)
        func record(_ value: UInt16 = 120, minute: Int = 120, calibration: UInt8 = 0) throws -> SmartGuideProtocol.Measurement {
            try XCTUnwrap(SmartGuideProtocol.measurements(secured([9, 0x40, UInt8(value & 255), UInt8(value >> 8), UInt8(minute & 255), UInt8(minute >> 8), calibration]), crcRequired: true).first)
        }
        XCTAssertTrue(SmartGuideProtocol.usable(try record(), status: .init(), start: start, now: now))
        for value: UInt16 in [0, 39, 401, 0x7FF, 0x802] {
            XCTAssertFalse(SmartGuideProtocol.usable(try record(value), status: .init(), start: start, now: now))
        }
        XCTAssertFalse(SmartGuideProtocol.usable(try record(minute: 59), status: .init(), start: start, now: now))
        XCTAssertFalse(SmartGuideProtocol.usable(try record(minute: 130), status: .init(), start: start, now: now))
        XCTAssertTrue(SmartGuideProtocol.usable(try record(calibration: 8), status: .init(), start: start, now: now))
        XCTAssertFalse(SmartGuideProtocol.usable(try record(), status: .init(warning: 8), start: start, now: now))
    }

    func testExactDeviceSelectionAndReadOnlyHistoryRequest() {
        XCTAssertTrue(SmartGuideProtocol.matches(name: "AC-12345678", serial: "12345678"))
        XCTAssertFalse(SmartGuideProtocol.matches(name: "AC-0012345678", serial: "12345678"))
        XCTAssertFalse(SmartGuideProtocol.matches(name: "OTHER12345678", serial: "12345678"))
        XCTAssertFalse(SmartGuideProtocol.validSerial(""))
        XCTAssertFalse(SmartGuideProtocol.validSerial("123 45678"))
        XCTAssertEqual(SmartGuideProtocol.history(from: 60), Data([1, 3, 1, 60, 0]))
        XCTAssertEqual(SmartGuideProtocol.history(from: 300), Data([1, 3, 1, 44, 1]))
    }
}
