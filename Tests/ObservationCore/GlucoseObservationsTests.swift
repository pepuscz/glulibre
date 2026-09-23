import XCTest
@testable import GlucoseObservationCore

final class GlucoseObservationsTests: XCTestCase {
    func testSleepUnionCountsOverlappingStagesAndSourcesOnce() {
        let start = Date(timeIntervalSince1970: 0)
        let intervals = [DateInterval(start: start, duration: 100), DateInterval(start: start.addingTimeInterval(20), duration: 60), DateInterval(start: start.addingTimeInterval(80), duration: 60)]
        XCTAssertEqual(GlucoseObservations.unionDuration(intervals, in: DateInterval(start: start, duration: 200)), 140)
    }
    func testSleepUnionClipsToWindowAndKeepsAwakeGaps() {
        let start = Date(timeIntervalSince1970: 0)
        let intervals = [DateInterval(start: start.addingTimeInterval(-20), duration: 40), DateInterval(start: start.addingTimeInterval(40), duration: 100)]
        XCTAssertEqual(GlucoseObservations.unionDuration(intervals, in: DateInterval(start: start, duration: 100)), 80)
        XCTAssertEqual(GlucoseObservations.unionDuration([], in: DateInterval(start: start, duration: 100)), 0)
    }
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func point(_ minute: Double, _ glucose: Double = 100, sensor: String? = "a") -> JournalGlucosePoint {
        JournalGlucosePoint(date: start.addingTimeInterval(minute * 60), mgDl: glucose, sensorID: sensor)
    }
    private var complete: [JournalGlucosePoint] { stride(from: -15.0, through: 120, by: 5).map { point($0, $0 == 60 ? 140 : 100) } }
    private func meal(_ points: [JournalGlucosePoint], others: [Date] = [], minutes: Double = 120) -> GlucoseObservations.MealObservation {
        GlucoseObservations.meal(at: start, otherMealDates: others, points: points, now: start.addingTimeInterval(minutes * 60))
    }

    func testValidSortsDeduplicatesAndRejectsInvalidAndFutureValues() {
        let result = GlucoseObservations.valid([point(5), point(0), point(0), point(1, .nan), point(2, .infinity), point(3, 0), point(4, -1), point(9)], now: point(5).date)
        XCTAssertEqual(result.map(\.date), [point(0).date, point(5).date])
    }
    func testSegmentsBreakAtGapAndSensorTransition() {
        let result = GlucoseObservations.segments([point(0), point(5), point(20), point(25, sensor: "b"), point(30, sensor: "b")])
        XCTAssertEqual(result.map(\.count), [2, 1, 2])
    }
    func testCoverageTimeWeightedNotSampleCount() {
        let interval = DateInterval(start: start, duration: 600)
        XCTAssertEqual(GlucoseObservations.coverage([point(0), point(5), point(5), point(10)], in: interval), 1)
        XCTAssertEqual(GlucoseObservations.coverage([point(0), point(10, sensor: "b")], in: interval), 0)
    }
    func testCoverageClipsEdgesAndDoesNotBridgeLargeGap() {
        let interval = DateInterval(start: start, duration: 1200)
        XCTAssertEqual(GlucoseObservations.coverage([point(-5), point(5), point(10), point(25)], in: interval), 0.5)
        XCTAssertEqual(GlucoseObservations.coverage([point(0), point(30)], in: interval), 0)
    }
    func testZeroDurationAndEmptyAreZero() {
        XCTAssertEqual(GlucoseObservations.coverage([], in: DateInterval(start: start, duration: 0)), 0)
        XCTAssertNil(GlucoseObservations.median([]))
    }
    func testMedianOddAndEven() {
        XCTAssertEqual(GlucoseObservations.median([140, 100, 90]), 100)
        XCTAssertEqual(GlucoseObservations.median([140, 100]), 120)
    }
    func testCompleteMealUsesPremealMedianAndObservedPeak() {
        let result = meal(complete)
        XCTAssertNil(result.limitation)
        XCTAssertEqual(result.coverage, 1)
        XCTAssertEqual(result.baseline, 100)
        XCTAssertEqual(result.peak, 140)
        XCTAssertEqual(result.rise, 40)
    }
    func testIncompleteWindowDoesNotPresentRise() {
        let result = meal(complete, minutes: 40)
        XCTAssertNotNil(result.limitation)
        XCTAssertNil(result.rise)
        XCTAssertLessThan(result.coverage, 0.7)
    }
    func testInsufficientBaselineDoesNotPresentRise() {
        XCTAssertNil(meal(complete.filter { $0.date >= start }).rise)
        XCTAssertNil(meal(complete.filter { $0.date < point(-10).date || $0.date > start }).rise)
    }
    func testLowCoverageDoesNotPresentRise() {
        XCTAssertNil(meal(complete.filter { $0.date < point(20).date || $0.date > point(90).date }).rise)
    }
    func testSensorChangeDoesNotPresentRise() {
        let changed = complete.map { JournalGlucosePoint(date: $0.date, mgDl: $0.mgDl, sensorID: $0.date > point(45).date ? "b" : "a") }
        XCTAssertNil(meal(changed).rise)
    }
    func testMissingSensorIdentityDoesNotClaimContinuity() {
        let unknown = complete.map { JournalGlucosePoint(date: $0.date, mgDl: $0.mgDl, sensorID: nil) }
        XCTAssertNil(meal(unknown).rise)
        XCTAssertTrue(meal(unknown).limitation?.contains("continuity") == true)
    }
    func testOverlapIsContextNotMissingObservation() {
        for other in [point(60).date, start, point(-10).date, point(-60).date] {
            let observation = meal(complete, others: [other])
            XCTAssertEqual(observation.rise, 40)
            XCTAssertTrue(observation.hasNearbyMeal)
        }
        XCTAssertFalse(meal(complete, others: [point(121).date]).hasNearbyMeal)
        XCTAssertNotNil(meal(complete, others: [point(121).date]).rise)
    }
    func testMissingFutureSamplesCannotCompleteObservation() {
        let result = meal(complete + [point(240, 900)], minutes: 121)
        XCTAssertEqual(result.peak, 140)
    }
}
