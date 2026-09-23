import XCTest
@testable import GlucoseObservationCore

final class MissingReadingPolicyTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testOnlyNewReadingRearmsAfterOutageOrRelaunch() {
        XCTAssertTrue(MissingReadingPolicy.shouldArm(readingAt: now, armedAt: nil, now: now, isMaster: true, hasActiveSensor: true))
        for date in [now, now.addingTimeInterval(-60)] {
            XCTAssertFalse(MissingReadingPolicy.shouldArm(readingAt: date, armedAt: now, now: now.addingTimeInterval(86400), isMaster: true, hasActiveSensor: true))
        }
        XCTAssertTrue(MissingReadingPolicy.shouldArm(readingAt: now.addingTimeInterval(60), armedAt: now, now: now.addingTimeInterval(60), isMaster: true, hasActiveSensor: true))
    }
    func testStoppedDirectSensorDoesNotDisableFollowerMonitoring() {
        XCTAssertFalse(MissingReadingPolicy.shouldArm(readingAt: now, armedAt: nil, now: now, isMaster: true, hasActiveSensor: false))
        XCTAssertTrue(MissingReadingPolicy.shouldArm(readingAt: now, armedAt: nil, now: now, isMaster: false, hasActiveSensor: false))
        XCTAssertFalse(MissingReadingPolicy.shouldArm(readingAt: now.addingTimeInterval(60), armedAt: nil, now: now, isMaster: true, hasActiveSensor: true))
    }
    func testUpgradeCancelsAlreadyDeliveredLoopAndPreservesUnsentReminder() {
        XCTAssertNil(MissingReadingPolicy.legacyDelay(alreadyDelivered: true, nextFire: now.addingTimeInterval(1800), now: now))
        XCTAssertEqual(MissingReadingPolicy.legacyDelay(alreadyDelivered: false, nextFire: now.addingTimeInterval(123), now: now), 123)
        XCTAssertEqual(MissingReadingPolicy.legacyDelay(alreadyDelivered: false, nextFire: now.addingTimeInterval(-1), now: now), 1)
        XCTAssertNil(MissingReadingPolicy.legacyDelay(alreadyDelivered: false, nextFire: nil, now: now))
    }
}
