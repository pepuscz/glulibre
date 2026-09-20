import XCTest
@testable import GlucoseObservationCore

final class ReadingNotificationPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func withDefaults(_ test: (UserDefaults) -> Void) {
        let name = "ReadingNotificationPolicyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        test(defaults)
    }

    func testFreshAndInheritedDefaultsAreQuietWithoutWritingPreferences() {
        withDefaults { defaults in
            XCTAssertFalse(ReadingNotificationPolicy.isEnabled(in: defaults))
            XCTAssertEqual(ReadingNotificationPolicy.intervalMinutes(in: defaults), 30)
            XCTAssertNil(defaults.object(forKey: ReadingNotificationPolicy.enabledKey))
        }
    }

    func testExplicitLegacyChoicesKeepTheirMeaning() {
        withDefaults { defaults in
            defaults.set(false, forKey: ReadingNotificationPolicy.enabledKey)
            XCTAssertTrue(ReadingNotificationPolicy.isEnabled(in: defaults))
            defaults.set(true, forKey: ReadingNotificationPolicy.enabledKey)
            XCTAssertFalse(ReadingNotificationPolicy.isEnabled(in: defaults))
        }
    }

    func testLegacyZeroAndNegativeIntervalCannotSpam() {
        withDefaults { defaults in
            for value in [0, -1, 1, 14] {
                defaults.set(value, forKey: ReadingNotificationPolicy.intervalKey)
                XCTAssertEqual(ReadingNotificationPolicy.intervalMinutes(in: defaults), 15)
            }
            defaults.set(90, forKey: ReadingNotificationPolicy.intervalKey)
            XCTAssertEqual(ReadingNotificationPolicy.intervalMinutes(in: defaults), 90)
        }
    }

    private func eligible(enabled: Bool = true, background: Bool = true, age: Double = 0,
                          priorReading: Date? = nil, priorSend: Date? = nil, interval: Int = 30) -> Bool {
        ReadingNotificationPolicy.shouldSend(enabled: enabled, isBackground: background,
            readingAt: now.addingTimeInterval(-age), lastReadingAt: priorReading,
            lastSentAt: priorSend, now: now, intervalMinutes: interval)
    }

    func testDisabledAndForegroundNeverNotify() {
        XCTAssertFalse(eligible(enabled: false))
        XCTAssertFalse(eligible(background: false))
        XCTAssertTrue(eligible())
    }
    func testRejectsStaleAndFutureReadings() {
        XCTAssertFalse(eligible(age: 271))
        XCTAssertFalse(eligible(age: -1))
        XCTAssertTrue(eligible(age: 270))
    }
    func testDoesNotRepeatSameOrOlderReading() {
        XCTAssertFalse(eligible(priorReading: now))
        XCTAssertFalse(eligible(priorReading: now.addingTimeInterval(1)))
        XCTAssertTrue(eligible(priorReading: now.addingTimeInterval(-1)))
    }
    func testRateLimitAndExactBoundary() {
        XCTAssertFalse(eligible(priorSend: now.addingTimeInterval(-1799)))
        XCTAssertTrue(eligible(priorSend: now.addingTimeInterval(-1800)))
        XCTAssertFalse(eligible(priorSend: now.addingTimeInterval(-60), interval: 0))
    }
    func testClockRollbackDoesNotBypassCadence() {
        XCTAssertFalse(eligible(priorSend: now.addingTimeInterval(60)))
    }
    func testDeliveryStatePersistsAndDoesNotMutateOtherPreferences() {
        withDefaults { defaults in
            defaults.set(false, forKey: ReadingNotificationPolicy.enabledKey)
            defaults.set("unchanged", forKey: "safetyAlertSentinel")
            ReadingNotificationPolicy.recordSent(in: defaults, readingAt: now, now: now)
            XCTAssertFalse(ReadingNotificationPolicy.shouldSend(in: defaults, isBackground: true,
                readingAt: now.addingTimeInterval(60), now: now.addingTimeInterval(60)))
            XCTAssertEqual(defaults.object(forKey: ReadingNotificationPolicy.readingAtKey) as? Date, now)
            XCTAssertEqual(defaults.string(forKey: "safetyAlertSentinel"), "unchanged")
            XCTAssertTrue(ReadingNotificationPolicy.shouldSend(in: defaults, isBackground: true,
                readingAt: now.addingTimeInterval(1800), now: now.addingTimeInterval(1800)))
        }
    }
}
