import Foundation

/// Bluetooth CGMS 1.0.2 wire format, kept independent of CoreBluetooth and storage.
/// Reference implementations: xDrip/libglupro (JamOrHam, GPL-3.0) and Nordic
/// Android BLE Library (2018 Nordic Semiconductor, BSD-3-Clause). See
/// docs/SMARTGUIDE.md and docs/licenses/Nordic-BLE.txt for provenance/notices.
enum SmartGuideProtocol {
    static let service = "181F"
    static let measurement = "2AA7"
    static let feature = "2AA8"
    static let status = "2AA9"
    static let sessionStart = "2AAA"
    static let recordAccess = "2A52"
    static let controlPoint = "2AAC"
    static let maximumMinutes = 14 * 24 * 60

    enum Failure: Error { case malformed, checksum, unsupported, invalidClock }

    /// Restored CBService objects may already contain cached characteristics.
    /// Only fresh discovery callbacks establish that our own map is complete.
    struct Discovery {
        enum Result: Equatable { case waiting, ready, unsupported }
        static let services: Set<String> = ["180A", SmartGuideProtocol.service]
        static let required: Set<String> = ["2A29", "2A24", "2A25", feature, status, sessionStart, measurement, recordAccess]
        private var completed = Set<String>()
        private var found = Set<String>()
        private var finished = false

        mutating func received(service: String, characteristics: Set<String>) -> Result {
            guard !finished, Self.services.contains(service) else { return .waiting }
            completed.insert(service)
            found.formUnion(characteristics)
            guard Self.services.isSubset(of: completed) else { return .waiting }
            finished = true
            return Self.required.isSubset(of: found) ? .ready : .unsupported
        }
    }

    /// One outstanding status request. A completed/cancelled request must never
    /// let an old watchdog interrupt a later connection or a newer read.
    struct StatusRead {
        private var token: UUID?
        mutating func begin() -> UUID? {
            guard token == nil else { return nil }
            let next = UUID()
            token = next
            return next
        }
        mutating func complete() { token = nil }
        mutating func expire(_ candidate: UUID) -> Bool {
            guard token == candidate else { return false }
            token = nil
            return true
        }
    }

    // Independent CGMS date-time encoder. Reference behavior: AccuChekKit
    // 4f8c3a8, PairingAdapter.getSensorStatus; no upstream code is incorporated.
    static func initializationAllowed(status: Status, minutes: Int, saved: Date?, reported: Date?, attempted: Bool) -> Bool {
        status.calibration & 1 != 0 && status.calibration & 0xFC == 0
            && status.warning & 0xF7 == 0 && status.sensor == 0
            && (0..<maximumMinutes).contains(minutes) && saved == nil && !attempted
    }

    /// CGMS 3.4.1: the client writes NOW; the sensor returns NOW minus its
    /// elapsed session offset, not an echo of the write. Use fresh status time
    /// so read latency/reconnect does not move the session anchor.
    static func verifiedInitializationStart(reported: Date?, minutes: Int, statusAt: Date,
                                            attemptedAt: Date, now: Date) throws -> Date {
        guard let reported, (0..<maximumMinutes).contains(minutes),
              (0...30).contains(now.timeIntervalSince(statusAt)),
              attemptedAt <= now, reported <= attemptedAt.addingTimeInterval(120),
              abs(reported.addingTimeInterval(Double(minutes) * 60).timeIntervalSince(statusAt)) <= 120
        else { throw Failure.invalidClock }
        return reported
    }

    static func initializationPacket(date: Date, usesCRC: Bool) throws -> Data {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = c.year, (2020...2099).contains(year) else { throw Failure.invalidClock }
        var bytes: [UInt8] = [UInt8(year & 255), UInt8(year >> 8), UInt8(c.month!), UInt8(c.day!), UInt8(c.hour!), UInt8(c.minute!), UInt8(c.second!), 0, 0]
        if usesCRC { let checksum = crc(bytes); bytes += [UInt8(checksum & 255), UInt8(checksum >> 8)] }
        return Data(bytes)
    }

    struct Status: Equatable {
        var warning: UInt8 = 0
        var calibration: UInt8 = 0
        var sensor: UInt8 = 0
        var stopped: Bool { warning & 1 != 0 }
        var calibrationRequired: Bool { calibration & 8 != 0 }
        var requestsCalibration: Bool { calibration & 0x0C != 0 }
        var permitsCalibration: Bool {
            requestsCalibration && warning & 0xFD == 0 && calibration & 0xF3 == 0 && sensor & 0xF0 == 0
        }
        var permitsReading: Bool {
            // Keep low/high and rate alerts: these are real readings, not faults.
            // Unknown/reserved flags fail closed rather than becoming believable glucose.
            warning & 0xFD == 0 && calibration & 0xF1 == 0 && sensor & 0xC0 == 0
        }
        var message: String? {
            if stopped { return "Sensor stopped" }
            if warning & 0xFC != 0 { return "Sensor needs attention in mySugr" }
            if calibration & 0x30 != 0 { return "Sensor temperature outside range" }
            if calibration & 0xC1 != 0 { return "Sensor clock needs attention in mySugr" }
            if sensor & 0xC0 != 0 { return "Glucose outside sensor measuring range" }
            if calibrationRequired { return "Trend mode · Not calibrated" }
            if calibration & 4 != 0 { return "Calibration recommended" }
            return nil
        }
    }

    struct Measurement: Equatable {
        let minutes: Int
        let mgDl: Double?
        let trend: Double?
        let quality: Double?
        let warning: UInt8?
        let calibration: UInt8?
        let sensor: UInt8?
        func status(fallback: Status) -> Status {
            Status(warning: warning ?? fallback.warning,
                   calibration: calibration ?? fallback.calibration,
                   sensor: sensor ?? fallback.sensor)
        }
    }

    static func validSerial(_ text: String) -> Bool {
        // Cap serial, not the six-digit pairing PIN. Do not accept partial matches.
        (6...32).contains(text.count) && text.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0)
        }
    }

    static func matches(name: String, serial: String) -> Bool {
        let name = name.uppercased()
        return validSerial(serial) && name == "AC-" + serial
    }

    static func crc(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0xFFFF
        for byte in bytes {
            value ^= UInt16(byte)
            for _ in 0..<8 { value = value & 1 == 0 ? value >> 1 : (value >> 1) ^ 0x8408 }
        }
        return value
    }

    static func checked(_ bytes: [UInt8], payloadSize: Int, crcRequired: Bool) throws -> [UInt8] {
        guard bytes.count == payloadSize + (crcRequired ? 2 : 0) else { throw Failure.malformed }
        let payload = Array(bytes.prefix(payloadSize))
        if crcRequired, crc(payload) != uint16(bytes, payloadSize) { throw Failure.checksum }
        return payload
    }

    static func uint16(_ bytes: [UInt8], _ index: Int) -> UInt16 {
        UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
    }

    /// IEEE 11073 SFLOAT is a signed decimal mantissa/exponent, not an integer.
    static func sfloat(_ value: UInt16) -> Double? {
        let rawMantissa = Int(value & 0x0FFF)
        guard ![0x07FE, 0x07FF, 0x0800, 0x0801, 0x0802].contains(rawMantissa) else { return nil }
        let mantissa = rawMantissa >= 0x800 ? rawMantissa - 0x1000 : rawMantissa
        let rawExponent = Int(value >> 12)
        let exponent = rawExponent >= 8 ? rawExponent - 16 : rawExponent
        return Double(mantissa) * pow(10, Double(exponent))
    }

    static func features(_ data: Data) throws -> Bool {
        try capabilities(data).usesCRC
    }

    struct Capabilities: Equatable {
        let usesCRC: Bool
        let calibrationSupported: Bool
        let multipleSessionsSupported: Bool
    }

    static func capabilities(_ data: Data) throws -> Capabilities {
        let bytes = [UInt8](data)
        guard bytes.count == 6 else { throw Failure.malformed }
        let usesCRC = bytes[1] & 0x10 != 0
        if usesCRC {
            _ = try checked(bytes, payloadSize: 4, crcRequired: true)
        } else if uint16(bytes, 4) != 0xFFFF { throw Failure.malformed }
        return Capabilities(usesCRC: usesCRC, calibrationSupported: bytes[0] & 1 != 0,
                            multipleSessionsSupported: bytes[1] & 0x40 != 0)
    }

    static func sensorStatus(_ data: Data, crcRequired: Bool) throws -> (minutes: Int, status: Status) {
        let bytes = try checked([UInt8](data), payloadSize: 5, crcRequired: crcRequired)
        return (Int(uint16(bytes, 0)), Status(warning: bytes[2], calibration: bytes[3], sensor: bytes[4]))
    }

    static func measurements(_ data: Data, crcRequired: Bool) throws -> [Measurement] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty, bytes.count <= 4096 else { throw Failure.malformed }
        var offset = 0
        var result: [Measurement] = []
        while offset < bytes.count {
            let size = Int(bytes[offset])
            guard size >= 6, offset + size <= bytes.count else { throw Failure.malformed }
            let flags = bytes[offset + 1]
            guard flags & 0x1C == 0 else { throw Failure.unsupported }
            let expected = 6 + (flags & 1 != 0 ? 2 : 0) + (flags & 2 != 0 ? 2 : 0)
                + (flags & 0x20 != 0 ? 1 : 0) + (flags & 0x40 != 0 ? 1 : 0) + (flags & 0x80 != 0 ? 1 : 0)
            let packet = try checked(Array(bytes[offset..<(offset + size)]), payloadSize: expected, crcRequired: crcRequired)
            var index = 6
            func octet(_ flag: UInt8) -> UInt8? {
                guard flags & flag != 0 else { return nil }
                defer { index += 1 }
                return packet[index]
            }
            let warning = octet(0x20), calibration = octet(0x40), sensor = octet(0x80)
            func optionalFloat(_ flag: UInt8) -> Double? {
                guard flags & flag != 0 else { return nil }
                defer { index += 2 }
                return sfloat(uint16(packet, index))
            }
            let trend = optionalFloat(1), quality = optionalFloat(2)
            result.append(Measurement(minutes: Int(uint16(packet, 4)), mgDl: sfloat(uint16(packet, 2)),
                                      trend: trend, quality: quality, warning: warning, calibration: calibration, sensor: sensor))
            offset += size
        }
        return result // No partial delivery if any record in the notification was corrupt.
    }

    static func sessionDate(_ data: Data, crcRequired: Bool) throws -> Date {
        let b = try checked([UInt8](data), payloadSize: 9, crcRequired: crcRequired)
        let zone = Int(Int8(bitPattern: b[7]))
        // SmartGuide returns UTC with DST=255 (unknown), including after a
        // successful time write. AccuChekKit's CgmStartTime ignores DST.
        // Accept that observed UTC case; do not guess an unknown local offset.
        let unknownUTCOffset = zone == 0 && b[8] == 255
        guard (-48...56).contains(zone), [0, 2, 4, 8].contains(b[8]) || unknownUTCOffset else { throw Failure.invalidClock }
        let daylightMinutes = unknownUTCOffset ? 0 : Int(b[8]) * 15
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: zone * 900 + daylightMinutes * 60)!
        let components = DateComponents(year: Int(uint16(b, 0)), month: Int(b[2]), day: Int(b[3]),
                                        hour: Int(b[4]), minute: Int(b[5]), second: Int(b[6]))
        guard let date = calendar.date(from: components), components.year! >= 2020,
              calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date) == components
        else { throw Failure.invalidClock }
        return date
    }

    /// Session age anchors the clock even when the manufacturer's session-date field
    /// is unset. Reuse a consistent anchor across reconnects; never rewrite sensor time.
    static func anchor(minutes: Int, now: Date, saved: Date?, reported: Date?) throws -> Date {
        guard (0...maximumMinutes).contains(minutes) else { throw Failure.invalidClock }
        let estimate = now.addingTimeInterval(-Double(minutes) * 60)
        if let saved {
            guard abs(saved.timeIntervalSince(estimate)) <= 120 else { throw Failure.invalidClock }
            return saved
        }
        if let reported, abs(reported.timeIntervalSince(estimate)) <= 120 { return reported }
        return estimate
    }

    static func usable(_ record: Measurement, status: Status, start: Date, now: Date) -> Bool {
        guard record.minutes >= 60, record.minutes <= maximumMinutes,
              record.status(fallback: status).permitsReading,
              let value = record.mgDl, value.isFinite, (40...400).contains(value) else { return false }
        return start.addingTimeInterval(Double(record.minutes) * 60) <= now
    }

    /// RACP report records >= session-minute offset (CGMS uses time offset, not glucose sequence IDs).
    static func history(from minute: Int) -> Data {
        let value = UInt16(clamping: minute)
        return Data([1, 3, 1, UInt8(value & 255), UInt8(value >> 8)])
    }
}
