//
//  AlertNotificationDictionary.swift
//  xdrip
//
//  Created by Paul Plant on 11/5/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import Foundation

/// model of the data we'll send to the notification content extension as userInfo for alerts
struct AlertNotificationDictionary: Codable {
    var alertTitle: String?
    var bgReadingValues: [Double]?
    var bgReadingDatesAsDouble: [Double]?
    var isMgDl: Bool?
    var slopeOrdinal: Int?
    var deltaValueInUserUnit: Double?
    var urgentLowLimitInMgDl: Double?
    var lowLimitInMgDl: Double?
    var highLimitInMgDl: Double?
    var urgentHighLimitInMgDl: Double?
    var alertUrgencyTypeRawValue: Int?
    
    var asDictionary: [String: Any]? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: .allowFragments)).flatMap { $0 as? [String: Any] }
    }
}

/// Copy shared by the banner, phone expansion and Watch. Kind numbers are the
/// persisted AlertKind identifiers; never reorder them to change presentation.
struct AlertNotificationCopy {
    let title: String
    let body: String

    init(kind: Int, reading: String, unit: String, isLocalSensor: Bool = true) {
        switch kind {
        case 0: title = "Very low glucose"
        case 1: title = "Low glucose"
        case 2: title = "High glucose"
        case 3: title = "Very high glucose"
        case 4: title = "Readings paused"
        case 5: title = "Calibration reminder"
        case 6: title = "Sensor battery low"
        case 7: title = "Glucose falling quickly"
        case 8: title = "Glucose rising quickly"
        case 9: title = "iPhone battery low"
        default: title = "Glucose update"
        }
        switch kind {
        case 0...3, 7, 8:
            let parts = reading.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            if let value = parts.first {
                body = "\(value) \(unit)" + (parts.count > 1 ? " \(parts[1])" : "")
            } else {
                body = "Open GluLibre to check your latest reading."
            }
        case 4: body = isLocalSensor
            ? "Keep your iPhone near the sensor. Open GluLibre if readings don’t resume."
            : "Open GluLibre to check your reading source."
        case 5: body = "Open GluLibre to review your sensor’s calibration status."
        case 6: body = "Open GluLibre to check your sensor’s battery status."
        case 9: body = "Charge your iPhone to keep receiving readings."
        default: body = "Open GluLibre to check your latest reading."
        }
    }
}

/// Never invent a reading or timestamp when an older notification lacks data.
struct AlertNotificationPresentation {
    let title: String
    let body: String
    let value: Double?
    let date: Date?
    let isMgDl: Bool
    let slope: Int

    var bodyContainsReading: Bool { body.contains("mg/dL") || body.contains("mmol/L") }

    init(title: String, body: String, userInfo: [AnyHashable: Any]) {
        self.title = title.isEmpty ? (userInfo["alertTitle"] as? String ?? "Glucose update") : title
        self.body = body
        isMgDl = userInfo["isMgDl"] as? Bool ?? true
        slope = userInfo["slopeOrdinal"] as? Int ?? 0
        let values = userInfo["bgReadingValues"] as? [Double] ?? []
        let dates = userInfo["bgReadingDatesAsDouble"] as? [Double] ?? []
        if let first = values.first, first.isFinite, first > 12,
           let timestamp = dates.first, timestamp.isFinite, timestamp > 0 {
            value = first
            date = Date(timeIntervalSince1970: timestamp)
        } else {
            value = nil
            date = nil
        }
    }

    func isFresh(now: Date) -> Bool {
        guard value != nil, let date else { return false }
        let age = now.timeIntervalSince(date)
        return age >= 0 && age < 7 * 60
    }

    #if DEBUG && targetEnvironment(simulator)
    static func preview(mode: String) -> Self {
        let paused = mode == "stale" || mode == "missing"
        let copy = AlertNotificationCopy(kind: paused ? 4 : 1, reading: "3.5 ↘", unit: "mmol/L")
        let info: [AnyHashable: Any] = mode == "missing" ? [:] : [
            "bgReadingValues": [63.0], "isMgDl": false, "slopeOrdinal": 5,
            "bgReadingDatesAsDouble": [Date().addingTimeInterval(paused ? -900 : -30).timeIntervalSince1970]]
        return Self(title: copy.title, body: copy.body, userInfo: info)
    }
    #endif
}
