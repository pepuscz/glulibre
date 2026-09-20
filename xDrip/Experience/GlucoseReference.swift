import Foundation

/// Descriptive research reference, not a treatment target or food score.
enum GlucoseReference {
    static let lower = 70.0
    static let upper = 140.0
    enum Position { case unavailable, veryLow, low, within, above, veryHigh }

    static func position(_ value: Double?, stale: Bool) -> Position {
        guard !stale, let value, value.isFinite, value > 0 else { return .unavailable }
        if value < 54 { return .veryLow }
        if value < lower { return .low }
        if value <= upper { return .within }
        if value > 250 { return .veryHigh }
        return .above
    }

    /// Observed slope, never a prediction. Require enough recent points from one sensor.
    static func slope(points: [JournalGlucosePoint], now: Date) -> Double? {
        let recent = GlucoseObservations.valid(points, now: now).filter { now.timeIntervalSince($0.date) <= 10 * 60 }
        guard recent.count >= 3, let last = recent.last, now.timeIntervalSince(last.date) <= 3 * 60,
              let first = recent.first(where: { last.date.timeIntervalSince($0.date) >= 3 * 60 }),
              let sensor = last.sensorID, recent.allSatisfy({ $0.sensorID == sensor }) else { return nil }
        return (last.mgDl - first.mgDl) / (last.date.timeIntervalSince(first.date) / 60)
    }
}
