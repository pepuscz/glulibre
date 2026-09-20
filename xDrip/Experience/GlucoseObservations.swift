import Foundation

/// Presentation-only values. Never writes, calibrates or feeds values back to the sensor.
struct JournalGlucosePoint: Identifiable, Equatable {
    let date: Date
    let mgDl: Double
    let sensorID: String?
    var id: Date { date }
}

enum GlucoseObservations {
    static let maximumGap: TimeInterval = 10 * 60

    /// Inspect an actual recorded sample, never an interpolated glucose value.
    /// Do not snap across missing data, outside the visible window, or into the future.
    static func reading(nearest date: Date, in points: [JournalGlucosePoint],
                        interval: DateInterval, now: Date) -> JournalGlucosePoint? {
        guard date >= interval.start, date <= interval.end, date <= now else { return nil }
        let samples = valid(points, now: now).filter { $0.date >= interval.start && $0.date <= interval.end }
        guard let point = samples.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
              abs(point.date.timeIntervalSince(date)) <= maximumGap / 2 else { return nil }
        return point
    }

    /// Clips and merges overlapping sleep segments, including duplicate sources/stages.
    static func unionDuration(_ intervals: [DateInterval], in window: DateInterval) -> TimeInterval {
        let clipped = intervals.compactMap { interval -> DateInterval? in
            let start = max(interval.start, window.start), end = min(interval.end, window.end)
            return end > start ? DateInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var current: DateInterval?
        for interval in clipped {
            if let previous = current, interval.start <= previous.end {
                current = DateInterval(start: previous.start, end: max(previous.end, interval.end))
            } else {
                total += current?.duration ?? 0
                current = interval
            }
        }
        return total + (current?.duration ?? 0)
    }

    static func valid(_ points: [JournalGlucosePoint], now: Date) -> [JournalGlucosePoint] {
        var seen = Set<Date>()
        return points.filter { $0.mgDl.isFinite && $0.mgDl > 0 && $0.date <= now }
            .sorted { $0.date < $1.date }.filter { seen.insert($0.date).inserted }
    }

    /// Break both sensor transitions and missing intervals instead of inventing a continuous trace.
    static func segments(_ points: [JournalGlucosePoint]) -> [[JournalGlucosePoint]] {
        var result: [[JournalGlucosePoint]] = []
        for point in points {
            if let last = result.last?.last,
               point.date.timeIntervalSince(last.date) <= maximumGap,
               point.sensorID == last.sensorID {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    /// Time covered by adjacent readings, not sample count; duplicates never inflate coverage.
    static func coverage(_ points: [JournalGlucosePoint], in interval: DateInterval) -> Double {
        guard interval.duration > 0 else { return 0 }
        let sorted = valid(points, now: interval.end.addingTimeInterval(maximumGap))
        var seconds: TimeInterval = 0
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.sensorID == b.sensorID {
            let gap = b.date.timeIntervalSince(a.date)
            guard gap > 0, gap <= maximumGap else { continue }
            seconds += max(0, min(b.date, interval.end).timeIntervalSince(max(a.date, interval.start)))
        }
        return min(1, seconds / interval.duration)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    struct MealObservation {
        let interval: DateInterval
        let coverage: Double
        let baseline: Double?
        let peak: Double?
        let limitation: String?
        var rise: Double? {
            guard limitation == nil, let baseline, let peak else { return nil }
            return peak - baseline
        }
    }

    static func meal(at date: Date, otherMealDates: [Date], points: [JournalGlucosePoint], now: Date) -> MealObservation {
        let interval = DateInterval(start: date, duration: 2 * 3600)
        let clean = valid(points, now: now)
        let before = clean.filter { $0.date >= date.addingTimeInterval(-15 * 60) && $0.date <= date }
        let after = clean.filter { $0.date >= date && $0.date <= interval.end }
        let coverage = coverage(clean, in: interval)
        let baseline = median(before.map(\.mgDl))
        let peak = after.map(\.mgDl).max()
        let sensorIDs = Set((before + after).map { $0.sensorID ?? "unknown" })
        let limitation: String?
        if now < interval.end {
            limitation = "Still collecting the two hours after this meal."
        } else if before.count < 2 || before.last.map({ date.timeIntervalSince($0.date) > maximumGap }) != false {
            limitation = "Not enough readings just before this meal to estimate a baseline."
        } else if sensorIDs.count > 1 {
            limitation = "A sensor change falls within this window. A comparison would be misleading."
        } else if (before + after).contains(where: { $0.sensorID == nil }) {
            limitation = "The data source does not identify the sensor. Sensor continuity cannot be checked for this observation."
        } else if coverage < 0.7 {
            limitation = "Too many missing readings for a reliable two-hour observation."
        } else if otherMealDates.contains(where: { $0 >= date.addingTimeInterval(-15 * 60) && $0 <= interval.end }) {
            limitation = "Another logged meal overlaps this window. The response cannot be separated."
        } else {
            limitation = nil
        }
        return MealObservation(interval: interval, coverage: coverage, baseline: baseline, peak: peak, limitation: limitation)
    }
}
