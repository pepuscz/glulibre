// Copyright © 2024 Johan Degraeve. All rights reserved.
import SwiftUI

struct NotificationView: View {
    let presentation: AlertNotificationPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 12) {
                Text(presentation.title).font(.headline)
                if presentation.isFresh(now: context.date), let value = presentation.value {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(value < 40 ? "LOW" : value >= 400 ? "HIGH" : value.mgDlToMmolAndToString(mgDl: presentation.isMgDl))
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text(trend).font(.title2)
                        Text(presentation.isMgDl ? "mg/dL" : "mmol/L").foregroundStyle(.secondary)
                    }
                    if presentation.isTrendOnly {
                        Label("Not calibrated", systemImage: "exclamationmark.circle")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else if presentation.date != nil {
                    Label("Reading out of date", systemImage: "clock.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    if presentation.bodyContainsReading {
                        Text("Open GluLibre for your latest reading.").font(.subheadline)
                    }
                }
                if (!presentation.bodyContainsReading || presentation.date == nil), !presentation.body.isEmpty {
                    Text(presentation.body).font(.subheadline)
                }
                if let date = presentation.date, date <= context.date {
                    Text("Read at \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding()
                .fixedSize(horizontal: false, vertical: true).privacySensitive()
        }
    }

    private var trend: String {
        [1: "↑↑", 2: "↑", 3: "↗", 4: "→", 5: "↘", 6: "↓", 7: "↓↓"][presentation.slope] ?? ""
    }
}
