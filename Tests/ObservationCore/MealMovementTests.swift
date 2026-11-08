import XCTest
@testable import GlucoseObservationCore

final class MealMovementTests: XCTestCase {
    let meal = Date(timeIntervalSince1970: 1_800_000_000)
    func bucket(_ minute: Double, steps: Double? = nil, stand: Double? = nil) -> MovementBucket {
        MovementBucket(interval: DateInterval(start: meal.addingTimeInterval(minute * 60), duration: 300), steps: steps, standMinutes: stand)
    }
    func summary(_ buckets: [MovementBucket], minutes: Int = 60, now: Double = 180) -> MealMovementSummary {
        MealMovement.summary(buckets, after: meal, minutes: minutes, now: meal.addingTimeInterval(now * 60))
    }

    func testAbsentDataIsNotZero() {
        let result = summary([])
        XCTAssertNil(result.steps)
        XCTAssertNil(result.standMinutes)
        XCTAssertFalse(result.hasData)
        XCTAssertFalse(result.isCollecting)
    }

    func testExplicitRecordedZeroIsDistinctFromMissing() {
        XCTAssertEqual(summary([bucket(0, steps: 0)]).steps, 0)
        XCTAssertNil(summary([bucket(0, stand: 3)]).steps)
        XCTAssertEqual(summary([bucket(0, stand: 3)]).standMinutes, 3)
    }

    func testThirtySixtyAndOneTwentyMinuteWindows() {
        let values = [bucket(-5, steps: 999), bucket(0, steps: 100), bucket(30, steps: 200), bucket(60, steps: 300), bucket(120, steps: 999)]
        XCTAssertEqual(summary(values, minutes: 30).steps, 100)
        XCTAssertEqual(summary(values, minutes: 60).steps, 300)
        XCTAssertEqual(summary(values, minutes: 120).steps, 600)
    }

    func testBoundaryBinsAreApportionedNotCreditedInFull() {
        XCTAssertEqual(summary([bucket(-2.5, steps: 100), bucket(57.5, steps: 100)]).steps, 100)
    }

    func testUnfinishedAndFutureBinsAreNeverUsed() {
        let result = summary([bucket(0, steps: 50), bucket(5, steps: 100), bucket(20, steps: 200)], now: 7)
        XCTAssertEqual(result.steps, 50)
        XCTAssertEqual(result.elapsedMinutes, 7)
        XCTAssertTrue(result.isCollecting)
    }

    func testFutureMealIsWaitingNotInactive() {
        let result = summary([bucket(0, steps: 100)], now: -5)
        XCTAssertNil(result.steps)
        XCTAssertEqual(result.elapsedMinutes, 0)
        XCTAssertTrue(result.isCollecting)
    }

    func testInvalidValuesAreMissingAndMetricsRemainIndependent() {
        let result = summary([bucket(0, steps: .nan, stand: 2), bucket(5, steps: -.infinity), bucket(10, steps: -1)])
        XCTAssertNil(result.steps)
        XCTAssertEqual(result.standMinutes, 2)
    }

    func testLateSyncAndDeletionRecomputeWithoutPersistedMealChanges() {
        XCTAssertNil(summary([]).steps)
        XCTAssertEqual(summary([bucket(5, steps: 100)]).steps, 100)
        XCTAssertNil(summary([]).steps)
    }

    func testEditingMealTimeChangesContext() {
        let values = [bucket(0, steps: 100), bucket(30, steps: 300)]
        let result = MealMovement.summary(values, after: meal.addingTimeInterval(1800), minutes: 60, now: meal.addingTimeInterval(10800))
        XCTAssertEqual(result.steps, 300)
    }

    func testTimelineClipsAndExcludesFuture() {
        let window = DateInterval(start: meal, duration: 3600)
        let result = MealMovement.visible([bucket(-5, steps: 100), bucket(0, steps: 50), bucket(5, steps: 100)], in: window, now: meal.addingTimeInterval(420))
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.steps, 50)
    }

    func testDistanceEnergyAndStandingDoNotInventStepsOrPosture() {
        let value = MovementBucket(interval: DateInterval(start: meal, duration: 300), distanceMetres: 20, standMinutes: 2, activeKilocalories: 8)
        let result = summary([value])
        XCTAssertNil(result.steps)
        XCTAssertEqual(result.distanceMetres, 20)
        XCTAssertEqual(result.activeKilocalories, 8)
        XCTAssertTrue(result.hasData)
    }

    func testOverflowDoesNotBecomeADisplayableTotal() {
        XCTAssertNil(summary([bucket(0, steps: .greatestFiniteMagnitude), bucket(5, steps: .greatestFiniteMagnitude)]).steps)
    }
}
