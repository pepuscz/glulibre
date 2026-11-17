import XCTest
@testable import WatchCompanionCore

final class WatchRefreshTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testLifecycleBurstDoesNotChangeDeliveryOrComplicationContent() throws {
        var state = WatchState()
        state.bgReadingValues = [100, 99]
        state.bgReadingDatesAsDouble = [now.timeIntervalSince1970, now.timeIntervalSince1970 - 300]
        state.liveDataIsEnabled = true
        let original = state.complicationContent
        let persisted = try JSONEncoder().encode(original)
        let previous = try JSONDecoder().decode(WatchComplicationContent.self, from: persisted)
        let delivery = WatchState.deliveryContent(try XCTUnwrap(state.asDictionary))
        for i in 0..<100 {
            state.generatedAt = now.timeIntervalSince1970 + Double(i)
            state.sensorAgeInMinutes = Double(i)
            state.remainingComplicationUserInfoTransfers = 50 - i
            XCTAssertEqual(state.complicationContent, previous)
            XCTAssertEqual(WatchState.deliveryContent(try XCTUnwrap(state.asDictionary)), delivery)
        }
        // Another reading with the same value must renew freshness.
        state.bgReadingDatesAsDouble[0] += 300
        XCTAssertNotEqual(state.complicationContent, previous)
    }

    func testMealAndBackfillUpdateAppWithoutReloadingFace() throws {
        var state = WatchState()
        state.bgReadingValues = [100]
        state.bgReadingDatesAsDouble = [now.timeIntervalSince1970]
        let face = state.complicationContent
        let delivery = WatchState.deliveryContent(try XCTUnwrap(state.asDictionary))
        state.lastMeal = WatchMealSnapshot(title: "Lunch", eatenAt: now.timeIntervalSince1970,
            state: "collecting", riseMgDl: nil, detail: "")
        state.bgReadingValues.append(95)
        state.bgReadingDatesAsDouble.append(now.timeIntervalSince1970 - 300)
        XCTAssertEqual(state.complicationContent, face)
        XCTAssertNotEqual(WatchState.deliveryContent(try XCTUnwrap(state.asDictionary)), delivery)
        state.liveDataIsEnabled = true
        XCTAssertNotEqual(state.complicationContent, face)
        let visible = state.complicationContent
        state.isTrendOnly = true
        XCTAssertNotEqual(state.complicationContent, visible)
    }

    func testRoutinePriorityScheduleFitsDailyBudget() {
        var last: Date?
        var sent = 0
        for minute in 0..<1440 {
            let date = now.addingTimeInterval(Double(minute) * 60)
            if WatchComplicationRefreshPolicy.shouldSendPriority(now: date, lastSent: last,
                requestedInterval: 17 * 60, remaining: 50 - sent, active: true, visible: true, forced: false) {
                sent += 1
                last = date
            }
        }
        XCTAssertEqual(sent, 48)
    }

    func testExhaustedInactiveAndHiddenDoNotQueuePriorityTransfers() {
        for remaining in [0, -1] {
            XCTAssertFalse(WatchComplicationRefreshPolicy.shouldSendPriority(now: now, lastSent: nil,
                requestedInterval: 0, remaining: remaining, active: true, visible: true, forced: true))
        }
        XCTAssertFalse(WatchComplicationRefreshPolicy.shouldSendPriority(now: now, lastSent: nil,
            requestedInterval: 0, remaining: 50, active: false, visible: true, forced: true))
        XCTAssertFalse(WatchComplicationRefreshPolicy.shouldSendPriority(now: now, lastSent: nil,
            requestedInterval: 0, remaining: 50, active: true, visible: false, forced: false))
        // A deliberate privacy change can still hide an active complication promptly.
        XCTAssertTrue(WatchComplicationRefreshPolicy.shouldSendPriority(now: now, lastSent: now,
            requestedInterval: 1800, remaining: 1, active: true, visible: false, forced: true))
    }

    func testPersistedSendTimeSurvivesRelaunchAndRespectsSlowerChoice() {
        XCTAssertFalse(WatchComplicationRefreshPolicy.shouldSendPriority(now: now, lastSent: now.addingTimeInterval(-60),
            requestedInterval: 17 * 60, remaining: 50, active: true, visible: true, forced: false))
        XCTAssertFalse(WatchComplicationRefreshPolicy.shouldSendPriority(now: now, lastSent: now.addingTimeInterval(-1800),
            requestedInterval: 3600, remaining: 50, active: true, visible: true, forced: false))
    }
}
