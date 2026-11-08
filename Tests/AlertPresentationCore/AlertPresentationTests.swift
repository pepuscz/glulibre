import XCTest
@testable import AlertPresentationCore

final class AlertPresentationTests: XCTestCase {
    func testAllKindsHaveDistinctPlainTitlesAndUsefulBodies() {
        let copies = (0...9).map { AlertNotificationCopy(kind: $0, reading: "5.4 →", unit: "mmol/L") }
        XCTAssertEqual(Set(copies.map(\.title)).count, 10)
        for copy in copies {
            XCTAssertFalse(copy.body.isEmpty)
            XCTAssertFalse(copy.title.contains("Alarm"))
            XCTAssertNotEqual(copy.title, copy.title.uppercased())
        }
        XCTAssertEqual(copies[1].title, "Low glucose")
        XCTAssertEqual(copies[4].title, "Readings paused")
        XCTAssertTrue(copies[4].body.contains("near the sensor"))
        XCTAssertEqual(copies[9].title, "iPhone battery low")
        XCTAssertEqual(AlertNotificationCopy(kind: 4, reading: "", unit: "", isLocalSensor: false).body,
                       "Open GluLibre to check your reading source.")
        XCTAssertTrue(copies[0].body.contains("mmol/L"))
        XCTAssertEqual(copies[0].body, "5.4 mmol/L →")
        XCTAssertTrue(AlertNotificationCopy(kind: 2, reading: "180 ↑", unit: "mg/dL").body.contains("mg/dL"))
    }

    func testMissingOrInvalidPayloadNeverInventsReadingOrEpochDate() {
        for info: [AnyHashable: Any] in [[:], ["bgReadingValues": [100.0]],
            ["bgReadingValues": [0.0], "bgReadingDatesAsDouble": [100.0]],
            ["bgReadingValues": [Double.nan], "bgReadingDatesAsDouble": [100.0]],
            ["bgReadingValues": [100.0], "bgReadingDatesAsDouble": [0.0]],
            ["bgReadingValues": [100.0], "bgReadingDatesAsDouble": [Double.infinity]]] {
            let model = AlertNotificationPresentation(title: "Readings paused", body: "Keep your iPhone near the sensor.", userInfo: info)
            XCTAssertNil(model.value)
            XCTAssertNil(model.date)
            XCTAssertFalse(model.isFresh(now: Date()))
            XCTAssertFalse(model.bodyContainsReading)
        }
    }

    func testFreshnessExpiresAndFutureDatesAreNotCurrent() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let model = AlertNotificationPresentation(title: "Low glucose", body: "3.5 mmol/L", userInfo: [
            "bgReadingValues": [63.0], "bgReadingDatesAsDouble": [date.timeIntervalSince1970], "isMgDl": false])
        XCTAssertTrue(model.isFresh(now: date.addingTimeInterval(419)))
        XCTAssertFalse(model.isFresh(now: date.addingTimeInterval(420)))
        XCTAssertFalse(model.isFresh(now: date.addingTimeInterval(-1)))
        XCTAssertTrue(model.bodyContainsReading)
        XCTAssertFalse(model.isMgDl)
    }

    func testContentTitleAndBodySurviveWatchDelivery() {
        let model = AlertNotificationPresentation(title: "Readings paused", body: "Open GluLibre if readings don’t resume.", userInfo: ["alertTitle": "MISSED READING"])
        XCTAssertEqual(model.title, "Readings paused")
        XCTAssertEqual(model.body, "Open GluLibre if readings don’t resume.")
    }
}
