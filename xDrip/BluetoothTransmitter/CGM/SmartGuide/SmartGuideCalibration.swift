import Foundation

/// CGMS §3.7.2.2 and Roche's Czech calibration instructions. No activation,
/// clock write or guessed next-calibration schedule. Pure logic for fixture tests.
enum SmartGuideCalibration {
    enum Failure: LocalizedError {
        case invalidValue, staleMeasurement, unavailable, recentAttempt, uncertainAttempt
        var errorDescription: String? {
            switch self {
            case .invalidValue: return "Enter a meter reading within 2.3–22.1 mmol/L (42–398 mg/dL)."
            case .staleMeasurement: return "Take a new finger-stick measurement. It must be less than three minutes old."
            case .unavailable: return "The sensor isn’t ready for calibration. Wait for its calibration request."
            case .recentAttempt: return "Wait before calibrating again, then take a new meter reading."
            case .uncertainAttempt: return "The previous calibration is unconfirmed. Check its status before sending another value."
            }
        }
    }

    struct Input: Equatable {
        let mgDl: Int
        let measuredAt: Date

        init(value: Double, usesMgDl: Bool, measuredAt: Date) throws {
            guard value.isFinite, (usesMgDl ? (42...398).contains(value) : (2.3...22.1).contains(value)) else {
                throw Failure.invalidValue
            }
            // Wire units are always mg/dL. Same integer precision as libglupro.
            mgDl = Int((usesMgDl ? value : value * 18.0182).rounded())
            self.measuredAt = measuredAt
        }

        func minute(start: Date, now: Date) throws -> Int {
            guard (0..<180).contains(now.timeIntervalSince(measuredAt)) else { throw Failure.staleMeasurement }
            let elapsed = measuredAt.timeIntervalSince(start)
            guard elapsed >= 3600, elapsed < Double(SmartGuideProtocol.maximumMinutes * 60) else {
                throw Failure.unavailable
            }
            return Int(elapsed / 60)
        }
    }

    struct Record: Equatable {
        let mgDl: Double?
        let minute: Int
        let nextMinute: Int
        let number: Int
        let status: UInt8
        var rejected: Bool { status & 3 != 0 }
        var pending: Bool { status & 4 != 0 }
    }

    enum Response: Equatable {
        case record(Record)
        case acknowledgement(request: UInt8, result: UInt8)
    }

    static func response(_ data: Data, usesCRC: Bool) throws -> Response {
        let bytes = [UInt8](data)
        guard let opcode = bytes.first, opcode == 6 || opcode == 28 else { throw SmartGuideProtocol.Failure.unsupported }
        let b = try SmartGuideProtocol.checked(bytes, payloadSize: opcode == 6 ? 11 : 3, crcRequired: usesCRC)
        if opcode == 28 {
            guard (1...5).contains(b[2]) else { throw SmartGuideProtocol.Failure.unsupported }
            return .acknowledgement(request: b[1], result: b[2])
        }
        guard b[10] & 0xF8 == 0 else { throw SmartGuideProtocol.Failure.unsupported }
        let record = Record(mgDl: SmartGuideProtocol.sfloat(SmartGuideProtocol.uint16(b, 1)),
                            minute: Int(SmartGuideProtocol.uint16(b, 3)),
                            nextMinute: Int(SmartGuideProtocol.uint16(b, 6)),
                            number: Int(SmartGuideProtocol.uint16(b, 8)), status: b[10])
        guard record.number == 0 || (record.mgDl != nil && record.minute <= SmartGuideProtocol.maximumMinutes) else {
            throw SmartGuideProtocol.Failure.malformed
        }
        return .record(record)
    }

    static func lastRecord(usesCRC: Bool) -> Data { packet([5, 255, 255], usesCRC: usesCRC) }

    static func setValue(_ input: Input, start: Date, now: Date, previous: Record, usesCRC: Bool) throws -> Data {
        let minute = try input.minute(start: start, now: now)
        guard !previous.pending, (0...65535).contains(previous.nextMinute) else { throw Failure.unavailable }
        let value = input.mgDl
        // Low nibble = capillary whole blood; high nibble = finger. Nordic's
        // older encoder shifts by eight (losing the location); follow CGMS, not that bug.
        // AccuChekKit CalibratePacket sends zero for next-time and record number.
        // The sensor supplies its schedule in the readback; do not echo it into a write.
        return packet([4, UInt8(value & 255), UInt8(value >> 8), UInt8(minute & 255), UInt8(minute >> 8),
                       0x11, 0, 0, 0, 0, 0], usesCRC: usesCRC)
    }

    /// Either ATT completion or the optional CGMS acknowledgement starts readback.
    /// Neither proves acceptance, and receiving both must not start it twice.
    struct ReadbackGate {
        private var started = false
        mutating func submissionCompleted() -> Bool {
            guard !started else { return false }
            started = true
            return true
        }
    }

    private static func packet(_ bytes: [UInt8], usesCRC: Bool) -> Data {
        guard usesCRC else { return Data(bytes) }
        let crc = SmartGuideProtocol.crc(bytes)
        return Data(bytes + [UInt8(crc & 255), UInt8(crc >> 8)])
    }

    /// Persisted before the irreversible write. An uncertain outcome survives
    /// relaunch and reconnect; no background path is allowed to resend it.
    struct Attempt: Codable, Equatable {
        enum Outcome: String, Codable { case unconfirmed, accepted, rejected }
        let submittedAt: Date
        let mgDl: Int
        let minute: Int
        let previousRecord: Int
        var outcome: Outcome = .unconfirmed

        func allowsNewAttempt(now: Date) throws {
            guard outcome != .unconfirmed else { throw Failure.uncertainAttempt }
            let delay: TimeInterval = outcome == .accepted ? 1800 : 900
            guard now.timeIntervalSince(submittedAt) >= delay else { throw Failure.recentAttempt }
        }

        mutating func reconcile(_ record: Record) {
            guard outcome == .unconfirmed, record.number > previousRecord,
                  record.minute == minute, let value = record.mgDl, abs(value - Double(mgDl)) < 0.1 else { return }
            if record.rejected { outcome = .rejected }
            else if !record.pending { outcome = .accepted }
        }
    }

    struct AttemptStore {
        let url: URL
        func load() throws -> Attempt? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try JSONDecoder().decode(Attempt.self, from: Data(contentsOf: url))
        }
        func save(_ attempt: Attempt) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(attempt)
            #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url, options: .atomic)
            #endif
        }
    }
}
