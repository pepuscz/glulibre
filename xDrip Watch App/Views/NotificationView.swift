import SwiftUI

/// Mirrors the phone alert; never schedules a second notification.
struct NotificationView: View {
    let presentation: AlertNotificationPresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(presentation.title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if presentation.isFresh(now: context.date) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(WatchGlancePolicy.valueText(presentation.value, isMgDl: presentation.isMgDl))
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text(WatchGlancePolicy.trendSymbol(presentation.slope)).font(.title3)
                    }
                    Text(presentation.isMgDl ? "mg/dL" : "mmol/L").font(.caption).foregroundStyle(.secondary)
                } else if presentation.date != nil {
                    Label("Reading out of date", systemImage: "clock.badge.exclamationmark").font(.caption)
                    if presentation.bodyContainsReading {
                        Text("Open GluLibre for your latest reading.").font(.caption)
                    }
                }
                if (!presentation.bodyContainsReading || presentation.date == nil), !presentation.body.isEmpty {
                    Text(presentation.body).font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = presentation.date, date <= context.date {
                    Text("Read at \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.privacySensitive()
        }
    }
}
