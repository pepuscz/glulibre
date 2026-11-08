import Foundation

/// Derived, read-only HealthKit statistics. Nil means unavailable, never sedentary.
/// Each bucket is already merged by HealthKit; do not sum raw Watch/iPhone samples.
struct MovementBucket: Equatable, Identifiable {
    var id: Date { interval.start }
    let interval: DateInterval
    var steps: Double?
    var distanceMetres: Double?
    var standMinutes: Double?
    var activeKilocalories: Double?

    var hasData: Bool {
        [steps, distanceMetres, standMinutes, activeKilocalories].contains { value in
            value.map { $0.isFinite && $0 >= 0 } ?? false
        }
    }
}

struct MealMovementSummary: Equatable {
    let steps: Double?
    let distanceMetres: Double?
    let standMinutes: Double?
    let activeKilocalories: Double?
    let elapsedMinutes: Int
    let windowMinutes: Int
    var isCollecting: Bool { elapsedMinutes < windowMinutes }
    var hasData: Bool { steps != nil || distanceMetres != nil || standMinutes != nil || activeKilocalories != nil }
}

enum MealMovement {
    static let bucketSeconds: TimeInterval = 300

    /// Only finished buckets are included: a partial current bucket must not imply
    /// knowledge of the future. Boundary buckets are apportioned by elapsed time,
    /// so the UI labels totals as approximate, recorded values, not exact activity.
    static func summary(_ buckets: [MovementBucket], after meal: Date, minutes: Int, now: Date) -> MealMovementSummary {
        let windowMinutes = max(0, minutes)
        let end = min(now, meal.addingTimeInterval(Double(windowMinutes) * 60))
        let relevant = buckets.filter { $0.interval.duration > 0 && $0.interval.end <= now && $0.interval.end > meal && $0.interval.start < end }
        func total(_ key: KeyPath<MovementBucket, Double?>) -> Double? {
            var sum: Double?
            for bucket in relevant {
                guard let value = bucket[keyPath: key], value.isFinite, value >= 0 else { continue }
                let overlap = min(end, bucket.interval.end).timeIntervalSince(max(meal, bucket.interval.start))
                guard overlap > 0 else { continue }
                let updated = (sum ?? 0) + value * (overlap / bucket.interval.duration)
                guard updated.isFinite else { return nil }
                sum = updated
            }
            return sum
        }
        return MealMovementSummary(steps: total(\.steps), distanceMetres: total(\.distanceMetres),
            standMinutes: total(\.standMinutes), activeKilocalories: total(\.activeKilocalories),
            elapsedMinutes: min(windowMinutes, max(0, Int(end.timeIntervalSince(meal) / 60))), windowMinutes: windowMinutes)
    }

    static func visible(_ buckets: [MovementBucket], in interval: DateInterval, now: Date) -> [MovementBucket] {
        buckets.filter { $0.interval.duration > 0 && $0.interval.end <= now && $0.interval.end > interval.start && $0.interval.start < interval.end }
    }
}
