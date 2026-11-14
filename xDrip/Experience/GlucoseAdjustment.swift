import Foundation

/// A reversible historical estimate, independent of the sensor/alert pipelines.
struct GlucoseAdjustment: Codable, Identifiable, Equatable {
    let id: String
    let sensorID: String
    let serial: String
    let measuredAt: Date
    let sensorMinute: Int
    let meterMgDl: Double
    let baselineMgDl: Double
    let sampleDates: [Date]
    let sampleValues: [Double]
    var accepted = false
    var version = 1
    enum Origin: String, Codable { case historicalMeter }
    var origin: Origin?
    var available: Bool { version == 2 && origin == .historicalMeter || version == 1 && accepted }
    var offset: Double { meterMgDl - baselineMgDl }

    struct Sample: Codable {
        let date: Date
        let value: Double
        let sensorID: String
        let trendOnly: Bool
    }

    enum Failure: LocalizedError {
        case unstable, invalid, insufficientHistory
        var errorDescription: String? {
            switch self {
            case .unstable: return "Glucose was changing too quickly near this time to estimate an adjustment."
            case .invalid: return "Check the meter value and measurement time."
            case .insufficientHistory: return "Not enough sensor readings around this time."
            }
        }
    }

    /// Local history only: match the actual meter time using nearby sensor samples.
    /// No sensor calibration command, current-time substitution or acceptance claim.
    static func historical(serial: String, minute: Int, meter: Double, at date: Date, samples: [Sample]) throws -> Self {
        guard (42...398).contains(meter), date.timeIntervalSince1970.isFinite,
              (60...20160).contains(minute) else { throw Failure.invalid }
        let window = samples.filter { abs($0.date.timeIntervalSince(date)) <= 600 }.sorted { $0.date < $1.date }
        guard window.count >= 3, let first = window.first, let last = window.last,
              last.date.timeIntervalSince(first.date) >= 600,
              let before = window.last(where: { $0.date <= date }),
              let after = window.first(where: { $0.date >= date }),
              after.date.timeIntervalSince(before.date) <= 360,
              !first.sensorID.isEmpty,
              window.allSatisfy({ $0.sensorID == first.sensorID && $0.trendOnly && (40...400).contains($0.value) })
        else { throw Failure.insufficientHistory }
        for (a, b) in zip(window, window.dropFirst()) {
            let seconds = b.date.timeIntervalSince(a.date)
            guard seconds > 0, seconds <= 360 else { throw Failure.insufficientHistory }
            guard abs(b.value - a.value) / (seconds / 60) <= 1 else { throw Failure.unstable }
        }
        let values = window.map(\.value)
        guard values.max()! - values.min()! <= 10 else { throw Failure.unstable }
        let interval = after.date.timeIntervalSince(before.date)
        let baseline = interval == 0 ? before.value : before.value +
            (after.value - before.value) * date.timeIntervalSince(before.date) / interval
        var reference = Self(id: "\(serial):historical:\(date.timeIntervalSince1970):\(meter)",
            sensorID: first.sensorID, serial: serial, measuredAt: date, sensorMinute: minute,
            meterMgDl: meter, baselineMgDl: baseline, sampleDates: window.map(\.date), sampleValues: values)
        reference.version = 2
        reference.origin = .historicalMeter
        return reference
    }

    static func make(serial: String, minute: Int, meter: Double, at date: Date, samples: [Sample]) throws -> Self {
        guard (42...398).contains(meter), date.timeIntervalSince1970.isFinite, minute >= 60 else { throw Failure.invalid }
        let window = samples.filter { $0.date <= date && date.timeIntervalSince($0.date) <= 900 }.sorted { $0.date < $1.date }
        guard window.count >= 3, let first = window.first, let last = window.last,
              !last.sensorID.isEmpty, date.timeIntervalSince(last.date) <= 300,
              last.date.timeIntervalSince(first.date) >= 600,
              window.allSatisfy({ $0.sensorID == last.sensorID && $0.trendOnly && (40...400).contains($0.value) }) else { throw Failure.unstable }
        for (a, b) in zip(window, window.dropFirst()) {
            let seconds = b.date.timeIntervalSince(a.date)
            guard seconds > 0, seconds <= 360, abs(b.value - a.value) / (seconds / 60) <= 1 else { throw Failure.unstable }
        }
        let values = window.map(\.value).sorted()
        guard values.last! - values.first! <= 10 else { throw Failure.unstable }
        // Stable-window median avoids fitting a slope from one or two meter values.
        let baseline = values.count % 2 == 0 ? (values[values.count / 2 - 1] + values[values.count / 2]) / 2 : values[values.count / 2]
        return Self(id: "\(serial):\(minute):\(Int(meter))", sensorID: last.sensorID, serial: serial,
                    measuredAt: date, sensorMinute: minute, meterMgDl: meter, baselineMgDl: baseline,
                    sampleDates: window.map(\.date), sampleValues: window.map(\.value))
    }

    func adjusted(_ sample: Sample) -> Double? {
        guard available, sample.sensorID == sensorID, sample.trendOnly,
              sample.date <= measuredAt, (40...400).contains(sample.value), offset.isFinite else { return nil }
        let value = sample.value + offset
        // Do not clamp an out-of-range estimate into a plausible reading.
        return (40...400).contains(value) ? value : nil
    }

    var valid: Bool {
        guard (1...2).contains(version), !sensorID.isEmpty, sensorID.count <= 512, !serial.isEmpty, serial.count <= 32,
              sampleDates.count <= 64, sampleDates.count == sampleValues.count else { return false }
        let samples = zip(sampleDates, sampleValues).map { Sample(date: $0, value: $1, sensorID: sensorID, trendOnly: true) }
        let rebuilt: Self?
        if version == 2 {
            guard origin == .historicalMeter, !accepted else { return false }
            rebuilt = try? Self.historical(serial: serial, minute: sensorMinute, meter: meterMgDl, at: measuredAt, samples: samples)
        } else {
            guard origin == nil else { return false }
            rebuilt = try? Self.make(serial: serial, minute: sensorMinute, meter: meterMgDl, at: measuredAt, samples: samples)
        }
        guard let rebuilt else { return false }
        return rebuilt.id == id && rebuilt.baselineMgDl == baselineMgDl
    }
}

final class GlucoseAdjustmentStore: @unchecked Sendable {
    static let shared = GlucoseAdjustmentStore(url: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GlucoseAdjustments.json"))
    private let url: URL
    private let lock = NSRecursiveLock()
    init(url: URL) { self.url = url }
    func all() throws -> [GlucoseAdjustment] {
        lock.lock(); defer { lock.unlock() }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let records = try JSONDecoder().decode([GlucoseAdjustment].self, from: Data(contentsOf: url))
        guard records.allSatisfy(\.valid) else { throw GlucoseAdjustment.Failure.invalid }
        return records
    }
    func save(_ reference: GlucoseAdjustment) throws {
        try merge([reference], replace: true)
    }
    func merge(_ incoming: [GlucoseAdjustment], replace: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        guard incoming.allSatisfy(\.valid) else { throw GlucoseAdjustment.Failure.invalid }
        var records = try all()
        for record in incoming {
            if let index = records.firstIndex(where: { $0.id == record.id }) {
                if replace { records[index] = record }
            } else { records.append(record) }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}
