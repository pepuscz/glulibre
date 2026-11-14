import XCTest
@testable import GlucoseObservationCore

final class GlucoseAdjustmentTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func samples(_ values: [Double] = [99, 100, 101]) -> [GlucoseAdjustment.Sample] {
        values.enumerated().map { .init(date: now.addingTimeInterval(Double($0.offset - values.count + 1) * 300), value: $0.element, sensorID: "A", trendOnly: true) }
    }
    func reference() throws -> GlucoseAdjustment {
        try .make(serial: "synthetic", minute: 720, meter: 110, at: now, samples: samples())
    }
    func testOffsetRequiresConfirmedReferenceAndPreservesOriginals() throws {
        var ref = try reference()
        let old = GlucoseAdjustment.Sample(date: now.addingTimeInterval(-172800), value: 95, sensorID: "A", trendOnly: true)
        XCTAssertNil(ref.adjusted(old))
        ref.accepted = true
        XCTAssertEqual(ref.adjusted(old), 105)
        XCTAssertEqual(old.value, 95)
        XCTAssertEqual(ref.offset, 10)
        XCTAssertTrue(ref.valid)
    }
    func testDoesNotCrossSensorTimeOrCalibrationBoundary() throws {
        var ref = try reference(); ref.accepted = true
        XCTAssertNil(ref.adjusted(.init(date: now, value: 100, sensorID: "B", trendOnly: true)))
        XCTAssertNil(ref.adjusted(.init(date: now.addingTimeInterval(1), value: 100, sensorID: "A", trendOnly: true)))
        XCTAssertNil(ref.adjusted(.init(date: now, value: 100, sensorID: "A", trendOnly: false)))
        XCTAssertNil(ref.adjusted(.init(date: now, value: 395, sensorID: "A", trendOnly: true)))
    }
    func testRejectsUnstableSparseStaleOrMixedSamples() throws {
        for points in [samples([80, 100, 120]), Array(samples().prefix(2)), samples().map {
            GlucoseAdjustment.Sample(date: $0.date.addingTimeInterval(-600), value: $0.value, sensorID: $0.sensorID, trendOnly: true)
        }, samples().enumerated().map {
            GlucoseAdjustment.Sample(date: $0.element.date, value: $0.element.value, sensorID: $0.offset == 1 ? "B" : "A", trendOnly: true)
        }] {
            XCTAssertThrowsError(try GlucoseAdjustment.make(serial: "synthetic", minute: 720, meter: 110, at: now, samples: points))
        }
    }
    func testStoreRoundTripAndIdempotentMerge() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = GlucoseAdjustmentStore(url: folder.appendingPathComponent("references.json"))
        var ref = try reference()
        try store.save(ref)
        ref.accepted = true
        try store.save(ref)
        try store.merge([ref, ref])
        XCTAssertEqual(try store.all(), [ref])
        var invalid = ref; invalid.version = 99
        XCTAssertThrowsError(try store.merge([invalid]))
        XCTAssertEqual(try store.all(), [ref])
    }
    func testFixedOffsetPreservesRiseAndBackupCompatibility() throws {
        var ref = try reference(); ref.accepted = true
        let a = GlucoseAdjustment.Sample(date: now.addingTimeInterval(-3600), value: 100, sensorID: "A", trendOnly: true)
        let b = GlucoseAdjustment.Sample(date: now.addingTimeInterval(-1800), value: 150, sensorID: "A", trendOnly: true)
        XCTAssertEqual(try XCTUnwrap(ref.adjusted(b)) - XCTUnwrap(ref.adjusted(a)), 50)
        let archive = JournalBackupArchive(createdAt: now, appVersion: "test", mealsJSON: Data("[]".utf8), photos: [:], readings: [], adjustments: [ref])
        let data = try JSONEncoder().encode(archive)
        XCTAssertEqual(try JSONDecoder().decode(JournalBackupArchive.self, from: data).adjustments, [ref])
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); old.removeValue(forKey: "adjustments")
        XCTAssertNil(try JSONDecoder().decode(JournalBackupArchive.self, from: JSONSerialization.data(withJSONObject: old)).adjustments)
    }
}

extension GlucoseAdjustmentTests {
    private func historicalSamples() -> [GlucoseAdjustment.Sample] {
        zip([-429.0, -129, 171, 471], [91.0, 93.5, 94.5, 90]).map {
            .init(date: now.addingTimeInterval($0), value: $1, sensorID: "A", trendOnly: true)
        }
    }
    func testHistoricalTimeMatchDoesNotClaimSensorCalibration() throws {
        let ref = try GlucoseAdjustment.historical(serial: "synthetic", minute: 5000, meter: 5.5 * 18.0182, at: now, samples: historicalSamples())
        XCTAssertEqual(ref.baselineMgDl, 93.93, accuracy: 0.000001)
        XCTAssertEqual(ref.offset, 5.1701, accuracy: 0.000001)
        XCTAssertEqual(ref.measuredAt, now)
        XCTAssertFalse(ref.accepted)
        XCTAssertTrue(ref.available)
        XCTAssertTrue(ref.valid)
        XCTAssertEqual(ref.origin, .historicalMeter)
        XCTAssertEqual(ref.adjusted(historicalSamples()[1])!, 98.6701, accuracy: 0.000001)
        XCTAssertNil(ref.adjusted(historicalSamples()[2]))
        XCTAssertEqual(try JSONDecoder().decode(GlucoseAdjustment.self, from: JSONEncoder().encode(ref)), ref)
        var misleading = ref; misleading.accepted = true
        XCTAssertFalse(misleading.valid)
    }
    func testHistoricalReferenceUsesActualOldTimeAndExactSamples() throws {
        let old = now.addingTimeInterval(-86400 * 30)
        let points = samples().map { GlucoseAdjustment.Sample(date: $0.date.addingTimeInterval(-86400 * 30), value: $0.value, sensorID: "A", trendOnly: true) }
        let ref = try GlucoseAdjustment.historical(serial: "synthetic", minute: 5000, meter: 110, at: old, samples: points)
        XCTAssertEqual(ref.measuredAt, old)
        XCTAssertEqual(ref.baselineMgDl, 101)
        XCTAssertTrue(ref.valid)
    }
    func testHistoricalMatchingRejectsExtrapolationGapsAndUnstableWindows() {
        let points = historicalSamples()
        let invalidWindows = [Array(points.prefix(2)), [points[0], points[2], points[3]],
            points.map { GlucoseAdjustment.Sample(date: $0.date, value: $0.value == 94.5 ? 120 : $0.value, sensorID: "A", trendOnly: true) },
            points.enumerated().map { GlucoseAdjustment.Sample(date: $0.element.date, value: $0.element.value, sensorID: $0.offset == 1 ? "B" : "A", trendOnly: true) }]
        for window in invalidWindows {
            XCTAssertThrowsError(try GlucoseAdjustment.historical(serial: "synthetic", minute: 5000, meter: 110, at: now, samples: window))
        }
        XCTAssertThrowsError(try GlucoseAdjustment.historical(serial: "synthetic", minute: 5000, meter: 110, at: now.addingTimeInterval(500), samples: points))
    }
    func testHistoricalAndSensorReferencesCoexistInBackupStore() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = GlucoseAdjustmentStore(url: folder.appendingPathComponent("references.json"))
        let old = try reference()
        let historical = try GlucoseAdjustment.historical(serial: "synthetic", minute: 5000, meter: 110, at: now, samples: historicalSamples())
        try store.save(old); try store.save(historical); try store.merge([historical])
        XCTAssertEqual(try store.all(), [old, historical])
        let archive = JournalBackupArchive(createdAt: now, appVersion: "test", mealsJSON: Data("[]".utf8), photos: [:], readings: [], adjustments: [historical])
        XCTAssertEqual(try JSONDecoder().decode(JournalBackupArchive.self, from: JSONEncoder().encode(archive)).adjustments, [historical])
    }
}
