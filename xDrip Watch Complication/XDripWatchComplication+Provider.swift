//
//  XDripWatchComplication+Provider.swift
//  xDrip Watch Complication Extension
//
//  Created by Paul Plant on 28/2/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import SwiftUI
import WidgetKit
import Foundation

extension XDripWatchComplication {
    struct Provider: TimelineProvider {        
        
        func placeholder(in context: Context) -> Entry {
            .placeholder
        }
        
        func getSnapshot(in context: Context, completion: @escaping (Entry) -> ()) {
            completion(context.isPreview ? .placeholder : Entry(date: .now, widgetState: getWidgetStateFromSharedUserDefaults() ?? .init()))
        }
        
        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
            let now = Date()
            let state = getWidgetStateFromSharedUserDefaults() ?? .init()
            let entries = WatchGlancePolicy.timelineDates(readingDate: state.bgReadingDate, now: now)
                .map { Entry(date: $0, widgetState: state) }
            // A scheduled stale entry retires the value even if the phone stops sending.
            completion(.init(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
        }
    }
}


// MARK: - Helpers

extension XDripWatchComplication.Provider {
    func getWidgetStateFromSharedUserDefaults() -> XDripWatchComplication.Entry.WidgetState? {
        guard let sharedUserDefaults = UserDefaults(suiteName: Bundle.main.appGroupSuiteName) else {return nil}
        
        guard let encodedLatestReadings = sharedUserDefaults.data(forKey: "complicationSharedUserDefaults.\(Bundle.main.mainAppBundleIdentifier)") else {
            return nil
        }
        
        let decoder = JSONDecoder()

        do {
            let data = try decoder.decode(ComplicationSharedUserDefaultsModel.self, from: encodedLatestReadings)
            guard data.bgReadingValues.count == data.bgReadingDatesAsDouble.count,
                  data.bgReadingValues.allSatisfy({ $0.isFinite }),
                  data.bgReadingDatesAsDouble.allSatisfy({ $0.isFinite }) else { return nil }
            
            // because dates aren't Codable we stored them as doubles
            // we need to convert the bgReadingDatesAsDouble key values to an array of real dates
            let bgReadingDates: [Date] = data.bgReadingDatesAsDouble.map { date in
                Date(timeIntervalSince1970: date)
            }
            
            return Entry.WidgetState(bgReadingValues: data.bgReadingValues, bgReadingDates: bgReadingDates, isMgDl: data.isMgDl, slopeOrdinal: data.slopeOrdinal, deltaValueInUserUnit: data.deltaValueInUserUnit, urgentLowLimitInMgDl: data.urgentLowLimitInMgDl, lowLimitInMgDl: data.lowLimitInMgDl, highLimitInMgDl: data.highLimitInMgDl, urgentHighLimitInMgDl: data.urgentHighLimitInMgDl, keepAliveIsDisabled: data.keepAliveIsDisabled, liveDataIsEnabled: data.liveDataIsEnabled)
        } catch {
            print(error.localizedDescription)
        }
              
        return nil
    }
}
