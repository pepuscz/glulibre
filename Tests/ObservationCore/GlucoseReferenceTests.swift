import XCTest
@testable import GlucoseObservationCore

final class GlucoseReferenceTests: XCTestCase {
    func testReferenceAndSafetyBoundaries() {
        XCTAssertEqual(GlucoseReference.position(53.9, stale: false), .veryLow)
        XCTAssertEqual(GlucoseReference.position(54, stale: false), .low)
        XCTAssertEqual(GlucoseReference.position(69.9, stale: false), .low)
        XCTAssertEqual(GlucoseReference.position(70, stale: false), .within)
        XCTAssertEqual(GlucoseReference.position(140, stale: false), .within)
        XCTAssertEqual(GlucoseReference.position(140.1, stale: false), .above)
        XCTAssertEqual(GlucoseReference.position(250, stale: false), .above)
        XCTAssertEqual(GlucoseReference.position(250.1, stale: false), .veryHigh)
    }
    func testMissingStaleAndInvalidAreNeverGreen() {
        for value: Double? in [nil, .nan, .infinity, 0, -1] {
            XCTAssertEqual(GlucoseReference.position(value, stale: false), .unavailable)
        }
        XCTAssertEqual(GlucoseReference.position(100, stale: true), .unavailable)
    }
    func testSlopeUsesRecentSameSensorData() {
        let now = Date()
        let points = (0...5).map { JournalGlucosePoint(date: now.addingTimeInterval(Double($0 - 5) * 60), mgDl: 90 + Double($0 * 2), sensorID: "a") }
        XCTAssertEqual(GlucoseReference.slope(points: points, now: now), 2)
        XCTAssertNil(GlucoseReference.slope(points: Array(points.suffix(2)), now: now))
        XCTAssertNil(GlucoseReference.slope(points: points, now: now.addingTimeInterval(601)))
        let changed = points + [JournalGlucosePoint(date: now.addingTimeInterval(1), mgDl: 103, sensorID: "b")]
        XCTAssertNil(GlucoseReference.slope(points: changed, now: now.addingTimeInterval(1)))
    }
}
