import Foundation

enum MealPhotoTime {
    /// EXIF is a proposed eating time, never silently a future timestamp.
    static func date(_ original: String?, offset: String?, now: Date) -> Date? {
        guard let original else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.isLenient = false
        formatter.timeZone = .current
        if let offset {
            guard offset.range(of: #"^[+-](0[0-9]|1[0-4]):[0-5][0-9]$"#, options: .regularExpression) != nil else { return nil }
            let parts = offset.dropFirst().split(separator: ":")
            let seconds = ((Int(parts[0]) ?? 0) * 3600 + (Int(parts[1]) ?? 0) * 60) * (offset.first == "-" ? -1 : 1)
            formatter.timeZone = TimeZone(secondsFromGMT: seconds)
        }
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        guard let result = formatter.date(from: original), result <= now, result.timeIntervalSince1970 > 0 else { return nil }
        return result
    }
}
