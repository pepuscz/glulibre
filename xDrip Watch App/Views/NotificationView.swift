import SwiftUI

/// Mirrors the phone's existing alert. This view does not schedule additional alerts.
struct NotificationView: View {
    var alertTitle: String?
    var bgReadingValues: [Double]?
    var bgReadingDates: [Date]?
    var isMgDl: Bool?
    var slopeOrdinal: Int?
    var deltaValueInUserUnit: Double?
    var urgentLowLimitInMgDl: Double?
    var lowLimitInMgDl: Double?
    var highLimitInMgDl: Double?
    var urgentHighLimitInMgDl: Double?
    var alertUrgencyType: AlertUrgencyType?
    var bgUnitString: String?
    var bgValueInMgDl: Double?
    var bgReadingDate: Date?
    var bgValueStringInUserChosenUnit: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let fresh = WatchGlancePolicy.isFresh(value: bgValueInMgDl, date: bgReadingDate, now: context.date)
            VStack(alignment: .leading, spacing: 8) {
                Text(alertTitle?.isEmpty == false ? alertTitle! : "Glucose update")
                    .font(.headline).fixedSize(horizontal: false, vertical: true)
                if fresh {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(WatchGlancePolicy.valueText(bgValueInMgDl, isMgDl: isMgDl ?? true))
                            .font(.system(.largeTitle, design: .rounded).weight(.semibold)).monospacedDigit()
                        Text(WatchGlancePolicy.trendSymbol(slopeOrdinal ?? 0)).font(.title3)
                    }
                    Text(bgUnitString ?? "").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Check latest reading", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                }
                if let date = bgReadingDate, date <= context.date {
                    Text("Read at \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.privacySensitive()
        }
    }
}
