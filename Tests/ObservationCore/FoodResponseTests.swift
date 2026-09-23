import XCTest
@testable import GlucoseObservationCore

final class FoodResponseTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    func meal(_ name: String = "Banana", portion: String = "1 medium", at: Date? = nil, confidence: Double = 0.9, separate: Bool = false) -> FoodResponseInput {
        FoodResponseInput(id: UUID(), date: at ?? date, timeZone: "Europe/Prague", title: name,
            components: [FoodComponent(name: name, portion: portion, confidence: confidence)], separate: separate)
    }
    func points(at start: Date? = nil, rise: Double = 40) -> [JournalGlucosePoint] {
        let start = start ?? date
        return stride(from: -15, through: 120, by: 5).map { minute in
            let delta = minute < 0 ? 0 : max(0, 1 - abs(Double(minute) - 45) / 45) * rise
            return JournalGlucosePoint(date: start.addingTimeInterval(Double(minute * 60)), mgDl: 95 + delta, sensorID: "sensor")
        }
    }
    func testExactCompositionAndPortionNotSubstrings() {
        XCTAssertEqual(FoodResponseCore.key(for: meal(" BANANA ")), FoodResponseCore.key(for: meal("banana")))
        XCTAssertNotEqual(FoodResponseCore.key(for: meal()), FoodResponseCore.key(for: meal("Banana bread")))
        XCTAssertNotEqual(FoodResponseCore.key(for: meal()), FoodResponseCore.key(for: meal(portion: "2 medium")))
    }
    func testUncertainFoodAndUserSeparationNeverMerge() {
        XCTAssertNotEqual(FoodResponseCore.key(for: meal(confidence: 0.3)), FoodResponseCore.key(for: meal(confidence: 0.3)))
        XCTAssertNotEqual(FoodResponseCore.key(for: meal(separate: true)), FoodResponseCore.key(for: meal()))
    }
    func testMixedMealIsNotAssignedToEachIngredient() {
        let banana = meal()
        let mixed = FoodResponseInput(id: UUID(), date: date, timeZone: "UTC", title: "Banana & yogurt",
            components: banana.components + [FoodComponent(name: "Yogurt", portion: "100g", confidence: 0.9)], separate: false)
        XCTAssertNotEqual(FoodResponseCore.key(for: banana), FoodResponseCore.key(for: mixed))
        let reversed = FoodResponseInput(id: UUID(), date: date, timeZone: "UTC", title: "Yogurt & banana", components: mixed.components.reversed(), separate: false)
        XCTAssertEqual(FoodResponseCore.key(for: mixed), FoodResponseCore.key(for: reversed))
    }
    func testThreeSeparateDaysRequiredForTypicalResponse() {
        let meals = (0..<3).map { meal(at: date.addingTimeInterval(Double(-$0 * 86400))) }
        let samples = meals.flatMap { points(at: $0.date) }
        let groups = FoodResponseCore.groups(meals: meals, points: samples, now: date.addingTimeInterval(8000))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].days, 3)
        XCTAssertEqual(groups[0].medianRise, 40)
        XCTAssertEqual(groups[0].medianArea, 1800)
        let single = FoodResponseCore.groups(meals: [meals[0]], points: samples, now: date.addingTimeInterval(8000))[0]
        XCTAssertNil(single.medianRise)
        XCTAssertEqual(single.usable.count, 1)
    }
    func testSameDayDoesNotBecomeRepeatedPattern() {
        let meals = (0..<3).map { meal(at: date.addingTimeInterval(Double(-$0 * 10800))) }
        let group = FoodResponseCore.groups(meals: meals, points: meals.flatMap { points(at: $0.date) }, now: date.addingTimeInterval(8000))[0]
        XCTAssertFalse(group.repeated)
    }
    func testOverlappingMealAndPriorMealExcluded() {
        for offset in [-3600.0, 3600] {
            let meals = [meal(), meal("Toast", at: date.addingTimeInterval(offset))]
            let responses = FoodResponseCore.groups(meals: meals, points: points(), now: date.addingTimeInterval(9000)).flatMap(\.responses)
            XCTAssertTrue(responses.allSatisfy { !$0.usable })
        }
    }
    func testSparseChangedSensorAndUnfinishedExcluded() {
        let meal = meal()
        let cases = [Array(points().prefix(15)), points().enumerated().map { index, point in
            JournalGlucosePoint(date: point.date, mgDl: point.mgDl, sensorID: index > 10 ? "other" : "sensor")
        }]
        for samples in cases {
            XCTAssertFalse(FoodResponseCore.groups(meals: [meal], points: samples, now: date.addingTimeInterval(9000))[0].responses[0].usable)
        }
        XCTAssertFalse(FoodResponseCore.groups(meals: [meal], points: points(), now: date.addingTimeInterval(1000))[0].responses[0].usable)
    }
    func testAreaCrossingBaselineAndGaps() {
        let samples = [JournalGlucosePoint(date: date, mgDl: 90, sensorID: "s"), JournalGlucosePoint(date: date.addingTimeInterval(600), mgDl: 110, sensorID: "s")]
        XCTAssertEqual(FoodResponseCore.positiveArea(samples, baseline: 100), 25)
        let gap = [samples[0], JournalGlucosePoint(date: date.addingTimeInterval(1200), mgDl: 110, sensorID: "s")]
        XCTAssertEqual(FoodResponseCore.positiveArea(gap, baseline: 100), 0)
    }
    func testDeletionAndFutureMealsDoNotProduceGhostGroups() {
        XCTAssertTrue(FoodResponseCore.groups(meals: [], points: points(), now: date).isEmpty)
        XCTAssertTrue(FoodResponseCore.groups(meals: [meal(at: date.addingTimeInterval(100))], points: points(), now: date).isEmpty)
    }
    func testOptionalEvidenceDecodingAndRoundtrip() throws {
        let evidence = FoodEvidence(canonicalName: "banana", preparation: "raw", brand: nil, ripeness: nil, source: "visible")
        XCTAssertEqual(try JSONDecoder().decode(FoodEvidence.self, from: JSONEncoder().encode(evidence)), evidence)
    }
    func testBoundaryInterpolationHasExactWindowAndNoExtrapolation() {
        let samples = stride(from: -2, through: 123, by: 5).map { minute in
            JournalGlucosePoint(date: date.addingTimeInterval(Double(minute * 60)), mgDl: 100, sensorID: "s")
        }
        let trace = FoodResponseCore.boundedTrace(samples, start: date, end: date.addingTimeInterval(7200))
        XCTAssertEqual(trace.first?.date, date)
        XCTAssertEqual(trace.last?.date, date.addingTimeInterval(7200))
        XCTAssertEqual(FoodResponseCore.positiveArea(trace, baseline: 90), 1200)
        XCTAssertNotEqual(FoodResponseCore.boundedTrace(Array(samples.dropFirst()), start: date, end: date.addingTimeInterval(7200)).first?.date, date)
    }
    func testUnknownPortionNotGrouped() {
        XCTAssertNotEqual(FoodResponseCore.key(for: meal(portion: "unknown")), FoodResponseCore.key(for: meal(portion: "unknown")))
    }

    func testCoursesShareFirstWindowAndFullComposition() {
        let first = meal("Toast")
        let second = meal("Yogurt", at: date.addingTimeInterval(15 * 60))
        let meals = [second, first]
        let occasions = FoodResponseCore.occasions(meals: meals, now: date.addingTimeInterval(9000))
        XCTAssertEqual(occasions.count, 1)
        XCTAssertEqual(occasions[0].date, date)
        XCTAssertEqual(occasions[0].meals.map(\.id), [first.id, second.id])
        XCTAssertEqual(occasions[0].input.components.count, 2)
        let groups = FoodResponseCore.groups(meals: meals, points: points(), now: date.addingTimeInterval(9000))
        XCTAssertEqual(groups.count, 1)
        XCTAssertTrue(groups[0].responses[0].usable)
        XCTAssertEqual(groups[0].responses[0].mealIDs, [first.id, second.id])
        XCTAssertNotEqual(groups[0].id, FoodResponseCore.key(for: first))
    }

    func testOccasionWindowIsBoundedAndDoesNotChainSnacks() {
        let captures = [0.0, 20, 30, 40, 60, 80].map { meal(at: date.addingTimeInterval($0 * 60)) }
        let occasions = FoodResponseCore.occasions(meals: captures, now: date.addingTimeInterval(9000))
        XCTAssertEqual(occasions.map { $0.meals.count }, [3, 2, 1])
        XCTAssertEqual(occasions.flatMap(\.meals).count, captures.count)
    }

    func testSeparationCorrectionDeletionAndFutureCapture() {
        let first = meal("Toast")
        let separate = meal("Yogurt", at: date.addingTimeInterval(60), separate: true)
        XCTAssertEqual(FoodResponseCore.occasions(meals: [first, separate], now: date.addingTimeInterval(9000)).count, 2)
        let later = meal("Yogurt", at: date.addingTimeInterval(60))
        XCTAssertEqual(FoodResponseCore.occasions(meals: [first, later], now: date).count, 1)
        XCTAssertEqual(FoodResponseCore.occasions(meals: [later], now: date.addingTimeInterval(9000)).first?.date, later.date)
    }

    func testOverlapRetainsObservationButNotFoodAttribution() {
        let first = meal("Toast")
        let next = meal("Yogurt", at: date.addingTimeInterval(3600))
        let result = FoodResponseCore.groups(meals: [first, next], points: points(), now: date.addingTimeInterval(9000))
            .flatMap(\.responses).first { $0.id == first.id }!
        XCTAssertEqual(result.observedRise, 40)
        XCTAssertFalse(result.usable)
        XCTAssertNil(result.rise)
        XCTAssertNil(result.area)
        XCTAssertFalse(result.trace.isEmpty)
    }

    func testUnknownCourseCannotDisappearFromComposition() {
        let first = meal("Toast")
        let unknown = FoodResponseInput(id: UUID(), date: date.addingTimeInterval(60), timeZone: "UTC", title: "Photo", components: [], separate: false)
        let combined = FoodResponseCore.occasions(meals: [first, unknown], now: date.addingTimeInterval(9000))[0].input
        XCTAssertTrue(combined.components.isEmpty)
        XCTAssertEqual(FoodResponseCore.key(for: combined), first.id.uuidString)
    }

    func testRepeatedMultiCourseMealCountsOccasionsNotPhotos() {
        let firsts = (0..<3).map { meal("Toast", at: date.addingTimeInterval(Double(-$0 * 86400))) }
        let courses = firsts.map { meal("Yogurt", at: $0.date.addingTimeInterval(600)) }
        let groups = FoodResponseCore.groups(meals: firsts + courses, points: firsts.flatMap { points(at: $0.date) }, now: date.addingTimeInterval(9000))
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].responses.count, 3)
        XCTAssertEqual(groups[0].days, 3)
        XCTAssertEqual(groups[0].medianRise, 40)
    }
}
