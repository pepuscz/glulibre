import SwiftUI

/// The same time scale as the glucose plot. Bars mean recorded steps; gaps do
/// not mean sitting. No activity thresholds or invented posture classification.
struct JournalMovementStrip: View {
    let buckets: [MovementBucket]
    let interval: DateInterval
    var body: some View {
        Canvas { context, size in
            guard interval.duration > 0 else { return }
            let maximum = max(1, buckets.compactMap(\.steps).max() ?? 1)
            for bucket in buckets {
                guard let steps = bucket.steps, steps.isFinite, steps > 0 else { continue }
                let start = max(interval.start, bucket.interval.start)
                let end = min(interval.end, bucket.interval.end)
                let x = start.timeIntervalSince(interval.start) / interval.duration * size.width
                let width = end.timeIntervalSince(start) / interval.duration * size.width
                let height = max(2, steps / maximum * size.height)
                let rect = CGRect(x: x, y: size.height - height, width: max(1, width - 1), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.purple.opacity(0.65)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded steps along the glucose timeline. Gaps do not establish inactivity.")
        .accessibilityIdentifier("movement.timeline")
    }
}

struct JournalMealMovement: View {
    @ObservedObject var health: JournalHealthContext
    let date: Date
    let now: Date
    @State private var minutes = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("After-meal movement", systemImage: "figure.walk").font(.headline)
            if !health.enabled || !health.movementPermissionRequested {
                Text("See everyday movement alongside this meal.").font(.subheadline).foregroundStyle(.secondary)
                Button("Include movement") { health.connect() }.disabled(health.loading)
            } else {
                Picker("Time after eating", selection: $minutes) {
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }.pickerStyle(.segmented).accessibilityIdentifier("movement.window")
                let summary = MealMovement.summary(health.movement, after: date, minutes: minutes, now: now)
                if let error = health.movementError { Text(error).font(.caption).foregroundStyle(.secondary) }
                if let steps = summary.steps {
                    Label("≈\(steps.formatted(.number.precision(.fractionLength(0)))) steps", systemImage: "shoeprints.fill")
                        .font(.headline).accessibilityIdentifier("movement.steps")
                } else if health.loading {
                    ProgressView("Reading movement…")
                } else {
                    Text("Steps unavailable").foregroundStyle(.secondary).accessibilityIdentifier("movement.missing")
                }
                if let standing = summary.standMinutes {
                    Label("≈\(standing.formatted(.number.precision(.fractionLength(0)))) stand min", systemImage: "figure.stand").font(.subheadline)
                }
                if summary.isCollecting {
                    Text(summary.elapsedMinutes == 0 ? "Waiting for activity" : "First \(summary.elapsedMinutes) min so far")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Movement details") {
                    if let metres = summary.distanceMetres {
                        LabeledContent("Distance", value: "≈\(metres.formatted(.number.precision(.fractionLength(0)))) m")
                            .accessibilityIdentifier("movement.distance")
                    }
                    if let energy = summary.activeKilocalories {
                        LabeledContent("Active energy", value: "≈\(energy.formatted(.number.precision(.fractionLength(0)))) kcal")
                    }
                    Text("Recorded values, not proof of complete tracking. Five-minute intervals are estimated at meal boundaries. Watch data can arrive later; missing data doesn’t mean sitting. Stand minutes aren’t an exact posture record.")
                    Button("Review Health access") { health.connect() }.disabled(health.loading)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct JournalMovementContextLabel: View {
    @ObservedObject var health: JournalHealthContext
    let date: Date
    var body: some View {
        let summary = MealMovement.summary(health.movement, after: date, minutes: 60, now: Date())
        if let steps = summary.steps {
            Label("≈\(steps.formatted(.number.precision(.fractionLength(0)))) steps · \(summary.isCollecting ? "\(summary.elapsedMinutes) min so far" : "first hour")", systemImage: "shoeprints.fill")
        } else if health.loading {
            Label("Reading movement…", systemImage: "figure.walk")
        } else {
            Label("Steps unavailable · first hour", systemImage: "figure.walk")
        }
    }
}
