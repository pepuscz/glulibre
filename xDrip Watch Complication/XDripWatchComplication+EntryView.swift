//
//  XDripWatchComplication+EntryView.swift
//  xDrip Watch Complication Extension
//
//  Created by Paul Plant on 28/2/24.
//  Copyright © 2024 Johan Degraeve. All rights reserved.
//

import SwiftUI
import Foundation

extension XDripWatchComplication {
    // main complication view body
    struct EntryView : View {
        // get the widget's family so that we can show the correct view
        @Environment(\.widgetFamily) private var widgetFamily
        
        var entry: Entry

        private var fresh: Bool {
            entry.widgetState.liveDataIsEnabled && WatchGlancePolicy.isFresh(value: entry.widgetState.bgValueInMgDl,
                date: entry.widgetState.bgReadingDate, now: entry.date)
        }
        private var value: String {
            fresh ? WatchGlancePolicy.valueText(entry.widgetState.bgValueInMgDl, isMgDl: entry.widgetState.isMgDl) : "—"
        }
        private var status: String {
            if !entry.widgetState.liveDataIsEnabled { return "Hidden on watch face" }
            if entry.widgetState.bgReadingDate == nil { return "Waiting for data" }
            return fresh ? entry.widgetState.bgUnitString : "Out of date"
        }
        private var arrow: String { fresh ? WatchGlancePolicy.trendSymbol(entry.widgetState.slopeOrdinal) : "" }
        private var unavailableLabel: String {
            WatchGlancePolicy.unavailableLabel(enabled: entry.widgetState.liveDataIsEnabled,
                value: entry.widgetState.bgValueInMgDl, date: entry.widgetState.bgReadingDate, now: entry.date)
        }
        private var statusSymbol: String {
            !entry.widgetState.liveDataIsEnabled ? "eye.slash" : fresh ? "drop.fill" : "clock.badge.exclamationmark"
        }
        
        var body: some View {
            Group {
                switch widgetFamily {
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                            Text(arrow).font(.title3)
                            Spacer(minLength: 0)
                            Image(systemName: statusSymbol)
                                .widgetAccentable()
                        }
                        Text(status).font(.caption)
                        if let date = entry.widgetState.bgReadingDate, entry.widgetState.liveDataIsEnabled {
                            Text("Read at \(date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                case .accessoryCircular:
                    VStack(spacing: 0) {
                        Image(systemName: statusSymbol).font(.caption2).widgetAccentable()
                        Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).minimumScaleFactor(0.7)
                        Text(fresh ? arrow : unavailableLabel).font(.caption2)
                    }
                case .accessoryCorner:
                    Text(value).font(.title3.weight(.semibold))
                        .widgetCurvesContent()
                        .widgetLabel { Text(fresh ? "\(entry.widgetState.bgUnitString) \(arrow)" : status) }
                case .accessoryInline:
                    Text(fresh ? "\(value) \(arrow) \(entry.widgetState.bgUnitString)" : "Glucose · \(status)")
                default:
                    Image(systemName: "drop.fill")
                }
            }
            .privacySensitive()
            .containerBackground(.clear, for: .widget)
            .accessibilityLabel(fresh ? "Glucose \(value) \(entry.widgetState.bgUnitString). \(WatchGlancePolicy.trendDescription(entry.widgetState.slopeOrdinal))" : "Glucose. \(status)")
        }
    }
}
