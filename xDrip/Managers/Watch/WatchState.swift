//
//  WatchState.swift
//  xdrip
//
//  Created by Paul Plant on 21/2/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import Foundation

/// model of the data we'll use to manage the watch views
struct WatchState: Codable {
    var bgReadingValues: [Double] = []
    var bgReadingDatesAsDouble: [Double] = []
    var bgReadingSensorIDs: [String]?
    var isMgDl: Bool?
    var slopeOrdinal: Int?
    var deltaValueInUserUnit: Double?
    var urgentLowLimitInMgDl: Double?
    var lowLimitInMgDl: Double?
    var highLimitInMgDl: Double?
    var urgentHighLimitInMgDl: Double?
    var updatedDate: Date?
    var activeSensorDescription: String?
    var sensorAgeInMinutes: Double?
    var sensorMaxAgeInMinutes: Double?
    var isMaster: Bool?
    var followerDataSourceTypeRawValue: Int?
    var followerBackgroundKeepAliveTypeRawValue: Int?
    var timeStampOfLastFollowerConnection: Double?
    var secondsUntilFollowerDisconnectWarning: Int?
    var timeStampOfLastHeartBeat: Double?
    var secondsUntilHeartBeatDisconnectWarning: Int?
    var keepAliveIsDisabled: Bool?
    var liveDataIsEnabled: Bool?
    var remainingComplicationUserInfoTransfers: Int?
    // Optional additions keep the phone/watch upgrade order backward compatible.
    var generatedAt: Double?
    var lastMeal: WatchMealSnapshot?
    
    // use this to track the AID/looping status if sent
    var deviceStatusCreatedAt: Double?
    var deviceStatusLastLoopDate: Double?
    var deviceStatusIOB: Double?
    var deviceStatusCOB: Double?
    
    var asDictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}

/// A read-only observation produced by the phone's existing meal analysis.
/// No photo or API key is transferred to the watch.
struct WatchMealSnapshot: Codable, Equatable {
    let title: String
    let eatenAt: Double
    let state: String
    let riseMgDl: Double?
    let detail: String
}

/// Shared by the app and complication. Freshness is based on the reading, not sync time.
enum WatchGlancePolicy {
    static let freshInterval: TimeInterval = 7 * 60

    static func timelineDates(readingDate: Date?, now: Date) -> [Date] {
        guard let readingDate, readingDate.timeIntervalSince1970.isFinite, readingDate <= now else { return [now] }
        let expiry = readingDate.addingTimeInterval(freshInterval)
        return expiry > now ? [now, expiry] : [now]
    }

    static func isFresh(value: Double?, date: Date?, now: Date) -> Bool {
        guard let value, value.isFinite, value > 12, let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < freshInterval
    }

    static func valueText(_ value: Double?, isMgDl: Bool) -> String {
        guard let value, value.isFinite, value > 12 else { return "—" }
        if value < 40 { return "LOW" }
        if value >= 400 { return "HIGH" }
        return String(format: isMgDl ? "%.0f" : "%.1f", locale: Locale.current,
                      isMgDl ? value : value / 18.0182)
    }

    static func ageText(date: Date?, now: Date) -> String {
        guard let date, date <= now else { return "No reading" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "Just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        if minutes < 1440 { return "\(minutes / 60)h ago" }
        return "\(minutes / 1440)d ago"
    }

    static func valueTextForRise(_ value: Double, isMgDl: Bool) -> String {
        guard value.isFinite else { return "—" }
        return String(format: isMgDl ? "%.0f" : "%.1f", locale: Locale.current,
                      isMgDl ? value : value / 18.0182)
    }

    static func trendSymbol(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: return "↑↑"
        case 2: return "↑"
        case 3: return "↗"
        case 4: return "→"
        case 5: return "↘"
        case 6: return "↓"
        case 7: return "↓↓"
        default: return ""
        }
    }

    static func trendDescription(_ ordinal: Int) -> String {
        switch ordinal {
        case 1: return "Rising quickly"
        case 2, 3: return "Rising"
        case 4: return "Steady"
        case 5, 6: return "Falling"
        case 7: return "Falling quickly"
        default: return "Trend unavailable"
        }
    }

    /// Newer snapshots can clear deleted meals or an empty data source. Old queued
    /// deliveries must never overwrite more recent settings/history.
    static func accepts(generatedAt: Double?, lastAccepted: Double, readingDate: Double?, currentReadingDate: Double?) -> Bool {
        if let generatedAt {
            return generatedAt.isFinite && generatedAt > lastAccepted
        }
        guard lastAccepted == 0 else { return false }
        guard let readingDate, readingDate.isFinite else { return currentReadingDate == nil }
        return readingDate >= (currentReadingDate ?? 0)
    }
}
