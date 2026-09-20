import XCTest
@testable import GlucoseObservationCore

final class MealPhotoTimeTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testEXIFOffsetPreservesActualPhotoTime() {
        let date = MealPhotoTime.date("2026:09:19 12:30:00", offset: "+02:00", now: now)
        XCTAssertEqual(date, ISO8601DateFormatter().date(from: "2026-09-19T10:30:00Z"))
    }
    func testFutureAndInvalidMetadataAreNotUsed() {
        XCTAssertNil(MealPhotoTime.date("2030:01:01 12:00:00", offset: "+02:00", now: now))
        XCTAssertNil(MealPhotoTime.date("not a date", offset: nil, now: now))
        XCTAssertNil(MealPhotoTime.date("2026:09:19 12:00:00", offset: "+99:99", now: now))
        XCTAssertNil(MealPhotoTime.date(nil, offset: nil, now: now))
    }
}
