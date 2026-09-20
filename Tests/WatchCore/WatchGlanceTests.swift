import XCTest
@testable import WatchCompanionCore

final class WatchGlanceTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshnessUsesReadingAndExpiresAtSevenMinutes() {
        XCTAssertTrue(WatchGlancePolicy.isFresh(value: 100, date: now.addingTimeInterval(-419), now: now))
        XCTAssertFalse(WatchGlancePolicy.isFresh(value: 100, date: now.addingTimeInterval(-420), now: now))
        XCTAssertFalse(WatchGlancePolicy.isFresh(value: 100, date: now.addingTimeInterval(-86400), now: now))
    }
    func testTimelineSchedulesExpiryWithoutAnotherPhoneMessage() {
        let reading = now.addingTimeInterval(-120)
        let dates = WatchGlancePolicy.timelineDates(readingDate: reading, now: now)
        XCTAssertEqual(dates, [now, reading.addingTimeInterval(420)])
        XCTAssertFalse(WatchGlancePolicy.isFresh(value: 100, date: reading, now: dates[1]))
        XCTAssertEqual(WatchGlancePolicy.timelineDates(readingDate: now.addingTimeInterval(-420), now: now), [now])
        XCTAssertEqual(WatchGlancePolicy.timelineDates(readingDate: nil, now: now), [now])
        XCTAssertEqual(WatchGlancePolicy.timelineDates(readingDate: now.addingTimeInterval(10), now: now), [now])
    }
    func testMissingInvalidAndFutureReadingsAreNotLive() {
        for value in [Double.nan, .infinity, -1, 0, 1, 12] {
            XCTAssertFalse(WatchGlancePolicy.isFresh(value: value, date: now, now: now))
            XCTAssertEqual(WatchGlancePolicy.valueText(value, isMgDl: true), "—")
        }
        XCTAssertFalse(WatchGlancePolicy.isFresh(value: nil, date: now, now: now))
        XCTAssertFalse(WatchGlancePolicy.isFresh(value: 100, date: nil, now: now))
        XCTAssertFalse(WatchGlancePolicy.isFresh(value: 100, date: now.addingTimeInterval(1), now: now))
    }
    func testExtremeValuesAreNotClampedToNormal() {
        XCTAssertEqual(WatchGlancePolicy.valueText(39, isMgDl: false), "LOW")
        XCTAssertEqual(WatchGlancePolicy.valueText(400, isMgDl: false), "HIGH")
        XCTAssertEqual(WatchGlancePolicy.valueText(100, isMgDl: true), "100")
    }
    func testRiseIsNotTreatedAsAbsoluteLowGlucose() {
        XCTAssertEqual(WatchGlancePolicy.valueTextForRise(0, isMgDl: true), "0")
        XCTAssertEqual(WatchGlancePolicy.valueTextForRise(30, isMgDl: true), "30")
        XCTAssertFalse(WatchGlancePolicy.valueTextForRise(30, isMgDl: false).contains("LOW"))
    }
    func testAgeLabels() {
        XCTAssertEqual(WatchGlancePolicy.ageText(date: nil, now: now), "No reading")
        XCTAssertEqual(WatchGlancePolicy.ageText(date: now.addingTimeInterval(2), now: now), "No reading")
        XCTAssertEqual(WatchGlancePolicy.ageText(date: now, now: now), "Just now")
        XCTAssertEqual(WatchGlancePolicy.ageText(date: now.addingTimeInterval(-120), now: now), "2m ago")
        XCTAssertEqual(WatchGlancePolicy.ageText(date: now.addingTimeInterval(-7200), now: now), "2h ago")
        XCTAssertEqual(WatchGlancePolicy.ageText(date: now.addingTimeInterval(-86400), now: now), "1d ago")
    }
    func testQueueCannotRevertNewerState() {
        XCTAssertFalse(WatchGlancePolicy.accepts(generatedAt: 99, lastAccepted: 100, readingDate: 200, currentReadingDate: 190))
        XCTAssertTrue(WatchGlancePolicy.accepts(generatedAt: 101, lastAccepted: 100, readingDate: nil, currentReadingDate: 190))
        XCTAssertFalse(WatchGlancePolicy.accepts(generatedAt: .nan, lastAccepted: 100, readingDate: 200, currentReadingDate: nil))
        XCTAssertFalse(WatchGlancePolicy.accepts(generatedAt: 100, lastAccepted: 100, readingDate: 200, currentReadingDate: 200))
        XCTAssertFalse(WatchGlancePolicy.accepts(generatedAt: nil, lastAccepted: 100, readingDate: 200, currentReadingDate: 200))
    }
    func testLegacyMessagesUseReadingOrder() {
        XCTAssertFalse(WatchGlancePolicy.accepts(generatedAt: nil, lastAccepted: 0, readingDate: 100, currentReadingDate: 101))
        XCTAssertTrue(WatchGlancePolicy.accepts(generatedAt: nil, lastAccepted: 0, readingDate: 101, currentReadingDate: 100))
    }
    func testOldPhonePayloadStillDecodes() throws {
        let data = Data(#"{"bgReadingValues":[100],"bgReadingDatesAsDouble":[1800000000],"isMgDl":true}"#.utf8)
        let state = try JSONDecoder().decode(WatchState.self, from: data)
        XCTAssertNil(state.lastMeal)
        XCTAssertNil(state.generatedAt)
        XCTAssertEqual(state.bgReadingValues, [100])
    }
    func testNewSnapshotRoundTripAndMealRemoval() throws {
        var state = WatchState()
        state.generatedAt = now.timeIntervalSince1970
        state.lastMeal = WatchMealSnapshot(title: "Toast", eatenAt: now.timeIntervalSince1970 - 7200,
            state: "ready", riseMgDl: 25, detail: "Observed after this meal")
        var copy = try JSONDecoder().decode(WatchState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(copy.lastMeal, state.lastMeal)
        XCTAssertNotNil(state.asDictionary?["lastMeal"])
        state.lastMeal = nil
        copy = try JSONDecoder().decode(WatchState.self, from: JSONEncoder().encode(state))
        XCTAssertNil(copy.lastMeal)
    }
    func testUnknownTrendIsNotInvented() {
        XCTAssertEqual(WatchGlancePolicy.trendSymbol(0), "")
        XCTAssertEqual(WatchGlancePolicy.trendDescription(0), "Trend unavailable")
        XCTAssertEqual(WatchGlancePolicy.trendSymbol(4), "→")
    }
}
