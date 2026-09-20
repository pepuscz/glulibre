import Foundation

/// Optional extraction evidence. Never used as evidence that a food caused a response.
struct FoodEvidence: Codable, Equatable {
    var canonicalName: String
    var preparation: String?
    var brand: String?
    var ripeness: String?
    var source: String
}

struct FoodComponent: Equatable {
    var name: String
    var portion: String
    var confidence: Double
    var evidence: FoodEvidence?
}

struct FoodResponseInput {
    let id: UUID
    let date: Date
    let timeZone: String
    let title: String
    let components: [FoodComponent]
    let separate: Bool
}

struct FoodResponse: Identifiable {
    let id: UUID
    let date: Date
    let day: String
    let baseline: Double?
    let rise: Double?
    /// Positive incremental trapezoidal area, mg/dL × minutes. Never bridged over gaps.
    let area: Double?
    let trace: [JournalGlucosePoint]
    let limitation: String?
    var usable: Bool { limitation == nil && rise != nil && area != nil }
}

struct FoodResponseGroup: Identifiable {
    let id: String
    let title: String
    let components: [FoodComponent]
    var responses: [FoodResponse]
    var usable: [FoodResponse] { responses.filter(\.usable) }
    var days: Int { Set(usable.map(\.day)).count }
    // A display safeguard, not a clinical confidence threshold or causal conclusion.
    var repeated: Bool { usable.count >= 3 && days >= 3 }
    var medianRise: Double? { repeated ? GlucoseObservations.median(usable.compactMap(\.rise)) : nil }
    var medianArea: Double? { repeated ? GlucoseObservations.median(usable.compactMap(\.area)) : nil }
    var range: ClosedRange<Double>? {
        let values = usable.compactMap(\.rise)
        guard let min = values.min(), let max = values.max() else { return nil }
        return min...max
    }
}

enum FoodResponseCore {
    static func normalized(_ text: String) -> String {
        text.lowercased(with: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Exact whole-composition matching. No substring matches or ingredient attribution.
    /// JSON encoding makes boundaries unambiguous, even when a name contains punctuation.
    static func key(for meal: FoodResponseInput) -> String {
        guard !meal.separate, !meal.components.isEmpty,
              meal.components.allSatisfy({ $0.confidence.isFinite && $0.confidence >= 0.75 && !normalized($0.name).isEmpty && portionKnown($0.portion) }) else {
            return meal.id.uuidString
        }
        let parts = meal.components.map { component -> [String] in
            // Preserve raw identity too: a model's generic canonical name must not erase a distinction.
            [normalized(component.name), normalized(component.portion),
             normalized(component.evidence?.preparation ?? ""),
             normalized(component.evidence?.brand ?? ""),
             normalized(component.evidence?.ripeness ?? "")]
        }.sorted { $0.lexicographicallyPrecedes($1) }
        return String(data: (try? JSONEncoder().encode(parts)) ?? Data(), encoding: .utf8) ?? meal.id.uuidString
    }

    static func groups(meals: [FoodResponseInput], points: [JournalGlucosePoint], now: Date) -> [FoodResponseGroup] {
        let clean = GlucoseObservations.valid(points, now: now)
        let eligible = meals.filter { $0.date <= now && $0.date >= now.addingTimeInterval(-90 * 86400) }
        var grouped: [String: FoodResponseGroup] = [:]
        for meal in eligible.sorted(by: { $0.date > $1.date }) {
            let window = DateInterval(start: meal.date.addingTimeInterval(-15 * 60), end: meal.date.addingTimeInterval(7200))
            let samples = slice(clean, from: window.start, through: window.end.addingTimeInterval(GlucoseObservations.maximumGap))
            let observation = GlucoseObservations.meal(at: meal.date,
                otherMealDates: meals.filter { $0.id != meal.id }.map(\.date), points: samples, now: now)
            // Use a wider prior-meal exclusion for cross-meal comparisons than the single-meal view.
            let nearbyMeal = meals.contains { $0.id != meal.id && $0.date > meal.date.addingTimeInterval(-7200) && $0.date <= window.end }
            let baseline = observation.baseline
            let after = boundedTrace(samples, start: meal.date, end: window.end)
            let edgeMissing = after.first?.date != meal.date
            let endMissing = after.last?.date != window.end
            let gap = zip(after, after.dropFirst()).contains { $1.date.timeIntervalSince($0.date) > GlucoseObservations.maximumGap }
            let limitation = observation.limitation ?? (nearbyMeal ? "A nearby meal may contribute." :
                observation.coverage < 0.9 || edgeMissing || endMissing || gap ? "More complete readings needed for comparison." : nil)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: meal.timeZone) ?? TimeZone(secondsFromGMT: 0)!
            let day = calendar.dateComponents([.year, .month, .day], from: meal.date)
            let response = FoodResponse(id: meal.id, date: meal.date,
                day: "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)", baseline: baseline,
                rise: limitation == nil ? observation.rise : nil,
                area: limitation == nil ? baseline.map { positiveArea(after, baseline: $0) } : nil,
                trace: after, limitation: limitation)
            let key = key(for: meal)
            if grouped[key] != nil { grouped[key]?.responses.append(response) }
            else { grouped[key] = FoodResponseGroup(id: key, title: meal.title, components: meal.components, responses: [response]) }
        }
        return grouped.values.sorted {
            if $0.repeated != $1.repeated { return $0.repeated }
            return ($0.responses.first?.date ?? .distantPast) > ($1.responses.first?.date ?? .distantPast)
        }
    }

    static func portionKnown(_ text: String) -> Bool {
        let value = normalized(text)
        return !value.isEmpty && !["unknown", "unclear", "unspecified", "not known", "not visible"].contains(where: value.contains)
    }

    /// Interpolate only bracketed boundaries inside short, identified same-sensor intervals.
    static func boundedTrace(_ points: [JournalGlucosePoint], start: Date, end: Date) -> [JournalGlucosePoint] {
        func boundary(_ date: Date) -> JournalGlucosePoint? {
            if let exact = points.first(where: { $0.date == date }) { return exact }
            guard let before = points.last(where: { $0.date < date }), let after = points.first(where: { $0.date > date }),
                  before.sensorID != nil, before.sensorID == after.sensorID,
                  after.date.timeIntervalSince(before.date) <= GlucoseObservations.maximumGap else { return nil }
            let fraction = date.timeIntervalSince(before.date) / after.date.timeIntervalSince(before.date)
            return JournalGlucosePoint(date: date, mgDl: before.mgDl + fraction * (after.mgDl - before.mgDl), sensorID: before.sensorID)
        }
        return [boundary(start)].compactMap { $0 } + points.filter { $0.date > start && $0.date < end } + [boundary(end)].compactMap { $0 }
    }

    /// Binary bounds avoid scanning three months of readings for every meal.
    static func slice(_ sorted: [JournalGlucosePoint], from start: Date, through end: Date) -> [JournalGlucosePoint] {
        func bound(_ date: Date, upper: Bool) -> Int {
            var low = 0, high = sorted.count
            while low < high {
                let middle = (low + high) / 2
                if sorted[middle].date < date || (upper && sorted[middle].date == date) { low = middle + 1 }
                else { high = middle }
            }
            return low
        }
        return Array(sorted[bound(start, upper: false)..<bound(end, upper: true)])
    }

    static func positiveArea(_ points: [JournalGlucosePoint], baseline: Double) -> Double {
        zip(points, points.dropFirst()).reduce(0) { result, pair in
            let (a, b) = pair
            let minutes = b.date.timeIntervalSince(a.date) / 60
            guard minutes > 0, minutes <= GlucoseObservations.maximumGap / 60, a.sensorID == b.sensorID else { return result }
            let y0 = a.mgDl - baseline, y1 = b.mgDl - baseline
            if y0 >= 0 && y1 >= 0 { return result + (y0 + y1) * minutes / 2 }
            if y0 <= 0 && y1 <= 0 { return result }
            // Integrate only the portion above baseline when a segment crosses it.
            let positive = max(y0, y1)
            return result + positive * positive / abs(y1 - y0) * minutes / 2
        }
    }
}
