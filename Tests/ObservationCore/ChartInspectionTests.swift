import XCTest
@testable import GlucoseObservationCore

final class ChartInspectionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func point(_ seconds: Double, _ value: Double = 100, sensor: String = "a") -> JournalGlucosePoint {
        JournalGlucosePoint(date: now.addingTimeInterval(seconds), mgDl: value, sensorID: sensor)
    }
    private func inspect(_ seconds: Double, _ points: [JournalGlucosePoint]) -> JournalGlucosePoint? {
        GlucoseObservations.reading(nearest: now.addingTimeInterval(seconds), in: points,
            interval: DateInterval(start: now.addingTimeInterval(-3600), end: now), now: now)
    }
    func testReturnsRecordedValueAndTimestampWithoutInterpolation() {
        let recorded = point(-60, 111.25)
        XCTAssertEqual(inspect(-70, [point(-120, 90), recorded]), recorded)
    }
    func testMissingIntervalDoesNotInventValue() {
        XCTAssertNil(inspect(-1800, [point(-3500), point(-60)]))
    }
    func testIgnoresInvalidAndFutureSamples() {
        XCTAssertNil(inspect(-20, [point(-20, .nan), point(-10, .infinity), point(-30, 0), point(20)]))
        XCTAssertNil(inspect(10, [point(10)]))
    }
    func testDoesNotSelectSamplesOutsideVisibleWindow() {
        XCTAssertNil(inspect(-3550, [point(-3650)]))
        XCTAssertNil(inspect(-3601, [point(-3550)]))
    }
    func testSnappingHasBoundedToleranceAndWorksAtEndpoints() {
        XCTAssertEqual(inspect(-300, [point(0)]), point(0))
        XCTAssertNil(inspect(-301, [point(0)]))
        XCTAssertEqual(inspect(-3600, [point(-3600)]), point(-3600))
    }
    func testUnsortedSamplesAndSensorTransitionKeepActualIdentity() {
        let expected = point(-60, 123, sensor: "new")
        XCTAssertEqual(inspect(-61, [expected, point(-120, 80, sensor: "old")]), expected)
        XCTAssertNil(inspect(-60, []))
    }
}
