import Foundation

/// Routine updates only. Clinical and connection alarms never pass through this policy.
enum ReadingNotificationPolicy {
    static let enabledKey = "showReadingInNotification" // Legacy storage is inverted.
    static let intervalKey = "notificationInterval"
    static let sentAtKey = "Journal.readingNotification.sentAt"
    static let readingAtKey = "Journal.readingNotification.readingAt"
    static let defaultIntervalMinutes = 30
    static let minimumIntervalMinutes = 15

    /// An absent legacy preference used to mean on. It now means off; explicit choices survive.
    static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: enabledKey) != nil && !defaults.bool(forKey: enabledKey)
    }

    static func intervalMinutes(in defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: intervalKey) != nil else { return defaultIntervalMinutes }
        return max(minimumIntervalMinutes, defaults.integer(forKey: intervalKey))
    }

    static func shouldSend(enabled: Bool, isBackground: Bool, readingAt: Date,
                           lastReadingAt: Date?, lastSentAt: Date?, now: Date,
                           intervalMinutes: Int) -> Bool {
        guard enabled, isBackground else { return false }
        let age = now.timeIntervalSince(readingAt)
        guard age >= 0, age <= 4.5 * 60 else { return false }
        if let lastReadingAt, readingAt <= lastReadingAt { return false }
        if let lastSentAt,
           now.timeIntervalSince(lastSentAt) < Double(max(minimumIntervalMinutes, intervalMinutes)) * 60 { return false }
        return true
    }

    static func shouldSend(in defaults: UserDefaults, isBackground: Bool,
                           readingAt: Date, now: Date = Date()) -> Bool {
        shouldSend(enabled: isEnabled(in: defaults), isBackground: isBackground,
                   readingAt: readingAt,
                   lastReadingAt: defaults.object(forKey: readingAtKey) as? Date,
                   lastSentAt: defaults.object(forKey: sentAtKey) as? Date,
                   now: now, intervalMinutes: intervalMinutes(in: defaults))
    }

    static func recordSent(in defaults: UserDefaults, readingAt: Date, now: Date = Date()) {
        defaults.set(readingAt, forKey: readingAtKey)
        defaults.set(now, forKey: sentAtKey)
    }
}
