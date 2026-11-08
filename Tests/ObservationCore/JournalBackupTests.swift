import XCTest
@testable import GlucoseObservationCore

final class JournalBackupTests: XCTestCase {
    private let password = "a long test-only password"
    func testRetentionDefaultsAndExplicitLegacyChoice() {
        let name = "BackupPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertFalse(JournalStoragePolicy.removesOldHistory(defaults))
        defaults.set(180, forKey: "retentionPeriodInDays")
        XCTAssertTrue(JournalStoragePolicy.removesOldHistory(defaults))
        defaults.set(false, forKey: JournalStoragePolicy.cleanupKey)
        XCTAssertFalse(JournalStoragePolicy.removesOldHistory(defaults))
    }
    func testEncryptedRoundTripAndRandomization() throws {
        let original = Data("private photo and glucose".utf8)
        let first = try JournalBackupCipher.seal(original, password: password)
        let second = try JournalBackupCipher.seal(original, password: password)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try JournalBackupCipher.open(first, password: password), original)
        XCTAssertNil(first.range(of: original))
    }
    func testWrongPasswordAndTamperingAreRejected() throws {
        var data = try JournalBackupCipher.seal(Data("journal".utf8), password: password)
        XCTAssertThrowsError(try JournalBackupCipher.open(data, password: "wrong password"))
        data[data.count - 1] ^= 1
        XCTAssertThrowsError(try JournalBackupCipher.open(data, password: password))
        XCTAssertThrowsError(try JournalBackupCipher.open(Data("not a backup".utf8), password: password))
        XCTAssertThrowsError(try JournalBackupCipher.seal(Data(), password: "short"))
    }
    func testUnicodePasswordRoundTrip() throws {
        let secret = "příliš žluťoučký kůň 🔑"
        let data = try JournalBackupCipher.seal(Data([1, 2, 3]), password: secret)
        XCTAssertEqual(try JournalBackupCipher.open(data, password: secret), Data([1, 2, 3]))
    }
    func testManifestAndPhotoValidation() throws {
        var archive = JournalBackupArchive(createdAt: Date(), appVersion: "test", mealsJSON: Data("[]".utf8),
            photos: ["photo.jpg": BackupPhoto(data: Data([1, 2]))], readings: [])
        try archive.validate()
        archive.version = 2
        XCTAssertThrowsError(try archive.validate())
        for filename in ["../photo", "/photo", "a/b", "a\\b", ".", "..", "", "a\0b"] {
            XCTAssertFalse(JournalBackupArchive.safeFilename(filename))
        }
        XCTAssertTrue(JournalBackupArchive.safeFilename("original.jpg"))
        let damaged = try JSONDecoder().decode(BackupPhoto.self, from: Data(#"{"data":"AQI=","sha256":"wrong"}"#.utf8))
        let bad = JournalBackupArchive(createdAt: Date(), appVersion: "test", mealsJSON: Data(), photos: ["p.jpg": damaged], readings: [])
        XCTAssertThrowsError(try bad.validate())
    }
    func testRestoreMergeIsIdempotentAndKeepsExistingValues() {
        let date = Date()
        let existing = BackupReading(id: "a", date: date, mgDl: 100, sensorID: "s", deviceName: nil, numericAttributes: [:], flags: [:])
        let conflicting = BackupReading(id: "a", date: date, mgDl: 200, sensorID: "s", deviceName: nil, numericAttributes: [:], flags: [:])
        let other = BackupReading(id: "b", date: date, mgDl: 105, sensorID: "another", deviceName: nil, numericAttributes: [:], flags: [:])
        let once = JournalBackupArchive.merging(existing: [existing], incoming: [conflicting, other])
        XCTAssertEqual(once.count, 2)
        XCTAssertEqual(once.first(where: { $0.id == "a" })?.mgDl, 100)
        XCTAssertEqual(JournalBackupArchive.merging(existing: once, incoming: [conflicting, other]), once)
    }
}
