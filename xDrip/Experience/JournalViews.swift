import SwiftUI
import Charts
import UIKit

enum JournalStyle {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.27, green: 0.82, blue: 0.72, alpha: 1)
            : UIColor(red: 0.05, green: 0.48, blue: 0.44, alpha: 1)
    })
    static let background = Color(uiColor: .systemGroupedBackground)
}

struct JournalCard<Content: View>: View {
    var spacing: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct JournalTodayView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject var model: JournalModel
    let capture: () -> Void
    let sensor: () -> Void
    let advanced: () -> Void
    let insights: () -> Void
    let alerts: () -> Void
    let edit: (UUID) -> Void
    @State private var hours = 6
    @State private var showLimits = false
    @State private var showReadingInfo = false
    @State private var selectedMeal: MealRecord?
    private var wideLayout: Bool { verticalSizeClass == .compact && !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            Group {
                if wideLayout {
                    GeometryReader { geometry in
                        VStack(spacing: 6) {
                            HStack(spacing: 16) {
                                Text(model.unit).font(.caption).foregroundStyle(.secondary)
                                durationPicker.frame(maxWidth: 360)
                                Spacer(minLength: 0)
                                chartOptions
                            }
                            JournalGlucoseChart(model: model, points: visiblePoints,
                                interval: chartInterval, meals: model.meals, showLimits: showLimits,
                                chartHeight: max(100, geometry.size.height - 66))
                        }
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("journal.today.landscape")
                    }
                } else {
                    portraitDashboard
                }
            }
            .background(JournalStyle.background)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Notifications", systemImage: "bell", action: alerts).disabled(!model.isReady)
                        Button("Sensor & connection", systemImage: "sensor.tag.radiowaves.forward", action: sensor).disabled(!model.isReady)
                        Button("Settings & integrations", systemImage: "gearshape", action: advanced)
                    } label: { Image(systemName: "ellipsis.circle").accessibilityLabel("More glucose options") }
                }
            }
            .toolbar(wideLayout ? .hidden : .visible, for: .navigationBar)
            .sheet(item: $selectedMeal) { meal in JournalMealDetail(model: model, mealID: meal.id, edit: edit) }
            .sheet(isPresented: $showReadingInfo) { JournalPatternsView(model: model) }
        }.tint(JournalStyle.accent)
    }

    private var todayMeals: [MealRecord] { model.meals.filter { Calendar.current.isDate($0.eatenAt, inSameDayAs: model.now) } }
    private var visiblePoints: [JournalGlucosePoint] { model.points.filter { $0.date >= model.now.addingTimeInterval(-Double(hours) * 3600) } }
    private var chartInterval: DateInterval { DateInterval(start: model.now.addingTimeInterval(-Double(hours) * 3600), end: model.now) }

    private var portraitDashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                #if targetEnvironment(simulator) && DEBUG
                if ProcessInfo.processInfo.arguments.contains("--journal-demo") {
                    Label("Simulator preview · sample glucose", systemImage: "testtube.2").font(.caption).foregroundStyle(.orange)
                }
                #endif
                chartCard
                captureButton
                HStack {
                    Text("Your journal").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("Today").font(.subheadline).foregroundStyle(.secondary)
                }
                if let issue = model.storageIssue {
                    JournalCard { Label("Journal unavailable", systemImage: "exclamationmark.triangle"); Text(issue).font(.footnote) }
                } else if todayMeals.isEmpty {
                    JournalCard {
                        Label("Start with your next meal", systemImage: "fork.knife").font(.headline)
                        Text("Take a photo. Add a note if you like.").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(todayMeals, id: \.id) { meal in
                        Button { selectedMeal = meal } label: { JournalMealRow(meal: meal) }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 20)
        }
    }

    private var durationPicker: some View {
        Picker("Chart duration", selection: $hours) {
            ForEach([3, 6, 12, 24], id: \.self) { Text("\($0)h").tag($0) }
        }.pickerStyle(.segmented)
    }

    private var chartOptions: some View {
        Menu {
            Toggle("Display limits", isOn: $showLimits)
            Button("About readings", systemImage: "info.circle") { showReadingInfo = true }
        } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44).accessibilityLabel("Chart options") }
    }

    private var captureButton: some View {
        Button(action: capture) {
            Label("Log a meal", systemImage: "camera.fill")
                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 2)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
        .accessibilityIdentifier("journal.capture")
    }

    private var glucoseSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.isStale, model.latest != nil {
                        Text("Past reading").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    }
                    if let latest = model.latest {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                reading(latest)
                                Text(model.unit).font(.subheadline).foregroundStyle(.secondary)
                                readingTrend
                            }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 4) {
                                reading(latest)
                                HStack { Text(model.unit).foregroundStyle(.secondary); readingTrend }
                            }
                        }
                    } else {
                        Text("No readings yet").font(.title2.bold())
                    }
                    if !model.isStale, model.latest != nil {
                        Text(referenceTitle).font(.caption).foregroundStyle(referenceColor)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                chartOptions
            }
            if model.isStale {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(model.freshness).font(.caption).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        sensorButton
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.freshness).font(.caption).foregroundStyle(.secondary)
                        sensorButton
                    }
                }
            }
        }
    }

    private var sensorButton: some View {
        Button(model.isReady ? "Check sensor" : "Opening your data…", action: sensor)
            .font(.subheadline).frame(minHeight: 44).disabled(!model.isReady)
    }

    private func reading(_ point: JournalGlucosePoint) -> some View {
        Text(model.formatted(point.mgDl))
            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).fontWidth(.expanded)
            .foregroundStyle(model.isStale ? Color.secondary : referenceColor)
            .accessibilityLabel("\(model.isStale ? "Past reading" : "Latest glucose") \(model.formatted(point.mgDl)) \(model.unit)")
    }

    private var position: GlucoseReference.Position { GlucoseReference.position(model.latest?.mgDl, stale: model.isStale) }
    private var referenceColor: Color {
        switch position {
        case .within: return JournalStyle.accent
        case .low, .above: return .orange
        case .veryLow, .veryHigh: return .red
        case .unavailable: return .secondary
        }
    }
    private var referenceTitle: String {
        switch position {
        case .within: return "Within reference"
        case .above: return "Above reference"
        case .low: return "Low"
        case .veryLow: return "Very low"
        case .veryHigh: return "Very high"
        case .unavailable: return "Reading unavailable"
        }
    }
    @ViewBuilder private var readingTrend: some View {
        if !model.isStale, let slope = GlucoseReference.slope(points: model.points, now: model.now) {
            Image(systemName: slope > 1 ? "arrow.up.right" : slope < -1 ? "arrow.down.right" : "arrow.right")
                .font(.title2).foregroundStyle(referenceColor)
                .accessibilityLabel(slope > 1 ? "Rising" : slope < -1 ? "Falling" : "Steady")
        }
    }

    private var chartCard: some View {
        JournalCard(spacing: 12) {
            glucoseSummary
            durationPicker
            if visiblePoints.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line").font(.largeTitle).foregroundStyle(JournalStyle.accent)
                    Text("Waiting for readings").font(.headline)
                }.multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 160)
            } else {
                JournalGlucoseChart(model: model, points: visiblePoints,
                    interval: DateInterval(start: model.now.addingTimeInterval(-Double(hours) * 3600), end: model.now),
                    meals: model.meals, showLimits: showLimits, chartHeight: 250)
                Button { showReadingInfo = true } label: {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(JournalStyle.accent.opacity(0.25)).frame(width: 16, height: 10)
                        Text("Reference \(model.formatted(GlucoseReference.lower))–\(model.formatted(GlucoseReference.upper)) \(model.unit)")
                        Image(systemName: "info.circle")
                    }.font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain)
                JournalChartLegend()
            }
            if showLimits {
                Text("Display limits: \(model.formatted(model.low))–\(model.formatted(model.high)) \(model.unit)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

extension MealRecord: Identifiable {}

struct JournalChartLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            Label("Meals", systemImage: "fork.knife").foregroundStyle(.orange)
            Label("Activity", systemImage: "figure.run").foregroundStyle(.purple)
        }.font(.caption)
    }
}

struct JournalMealSparkline: View {
    let points: [JournalGlucosePoint]
    let baseline: Double
    var body: some View {
        Chart {
            RuleMark(y: .value("Before meal", baseline)).foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(dash: [3, 3]))
            ForEach(Array(GlucoseObservations.segments(points).enumerated()), id: \.offset) { index, segment in
                ForEach(segment) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Glucose", point.mgDl), series: .value("Segment", index))
                        .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
        }
        .chartYScale(domain: min(70, points.map(\.mgDl).min() ?? 70)...max(160, points.map(\.mgDl).max() ?? 160))
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(width: 100, height: 48)
        .accessibilityLabel("Glucose response after this meal; dashed line is the pre-meal baseline")
    }
}

struct JournalGlucoseChart: View {
    @ObservedObject var model: JournalModel
    @ObservedObject private var health = JournalHealthContext.shared
    let points: [JournalGlucosePoint]
    let interval: DateInterval
    let meals: [MealRecord]
    var showLimits = false
    var mealBaseline: Double?
    var mealPeak: JournalGlucosePoint?
    var chartHeight: CGFloat = 200
    @State private var inspectedDate: Date?

    private var inspectedPoint: JournalGlucosePoint? {
        guard let inspectedDate else { return nil }
        return GlucoseObservations.reading(nearest: inspectedDate, in: points, interval: interval, now: model.now)
    }

    private var inspectionLabel: String {
        guard let inspectedDate else { return "" }
        guard let point = inspectedPoint else {
            return "\(inspectedDate.formatted(.dateTime.hour().minute())) · No reading"
        }
        return "\(point.date.formatted(.dateTime.month(.abbreviated).day().hour().minute().second())) · \(model.formatted(point.mgDl)) \(model.unit)"
    }

    var body: some View {
        let segments = GlucoseObservations.segments(points)
        Chart {
            RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("End", interval.end),
                          yStart: .value("Reference lower", model.value(GlucoseReference.lower)), yEnd: .value("Reference upper", model.value(GlucoseReference.upper)))
                .foregroundStyle(JournalStyle.accent.opacity(0.10)).accessibilityLabel("Research reference band, 70 to 140 milligrams per deciliter; not a treatment target")
            if yDomain.upperBound > model.value(GlucoseReference.upper) {
                RectangleMark(xStart: .value("Start", interval.start), xEnd: .value("End", interval.end),
                              yStart: .value("Above reference", model.value(GlucoseReference.upper)), yEnd: .value("Upper edge", yDomain.upperBound))
                    .foregroundStyle(Color.orange.opacity(0.06)).accessibilityHidden(true)
            }
            ForEach(health.workouts.filter { $0.interval.start < interval.end && $0.interval.end > interval.start }) { workout in
                RectangleMark(xStart: .value("Activity start", max(workout.interval.start, interval.start)), xEnd: .value("Activity end", min(workout.interval.end, interval.end)))
                    .foregroundStyle(Color.purple.opacity(0.13))
                    .accessibilityLabel("Recorded \(workout.title)")
            }
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment) { point in
                    LineMark(x: .value("Time", point.date), y: .value(model.unit, model.value(point.mgDl)), series: .value("Readings", index))
                        .foregroundStyle(JournalStyle.accent).lineStyle(StrokeStyle(lineWidth: 2.5))
                    if segment.count == 1 {
                        PointMark(x: .value("Time", point.date), y: .value(model.unit, model.value(point.mgDl)))
                            .foregroundStyle(JournalStyle.accent)
                    }
                }
            }
            ForEach(meals.filter { interval.contains($0.eatenAt) }, id: \.id) { meal in
                RuleMark(x: .value("Meal", meal.eatenAt))
                    .foregroundStyle(Color.orange.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .accessibilityLabel("Meal: \(meal.displayTitle)")
                    .accessibilityValue(meal.eatenAt.formatted(date: .omitted, time: .shortened))
            }
            if showLimits, model.low > 0, model.high > model.low {
                RuleMark(y: .value("Lower display limit", model.value(model.low))).lineStyle(StrokeStyle(dash: [4, 4])).foregroundStyle(Color.secondary)
                RuleMark(y: .value("Upper display limit", model.value(model.high))).lineStyle(StrokeStyle(dash: [4, 4])).foregroundStyle(Color.secondary)
            }
            if let baseline = mealBaseline {
                RuleMark(y: .value("Before meal", model.value(baseline)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4])).foregroundStyle(Color.secondary)
            }
            if let peak = mealPeak, let baseline = mealBaseline {
                RuleMark(x: .value("Peak time", peak.date), yStart: .value("Baseline", model.value(baseline)), yEnd: .value("Peak", model.value(peak.mgDl)))
                    .foregroundStyle(Color.orange).lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Observed peak", peak.date), y: .value("Glucose", model.value(peak.mgDl)))
                    .foregroundStyle(Color.orange).symbolSize(60)
                    .annotation(position: .top) { Text("\(peak.mgDl >= baseline ? "+" : "")\(model.formatted(peak.mgDl - baseline))").font(.caption.bold()).foregroundStyle(.orange) }
            }
            if let point = inspectedPoint {
                RuleMark(x: .value("Selected time", point.date))
                    .foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("Selected glucose", model.value(point.mgDl)))
                    .foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Selected time", point.date), y: .value("Selected glucose", model.value(point.mgDl)))
                    .foregroundStyle(JournalStyle.accent).symbolSize(65)
            } else if let inspectedDate {
                RuleMark(x: .value("Inspected time", inspectedDate))
                    .foregroundStyle(Color.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute(), anchor: .topTrailing)
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                let plot = geometry[proxy.plotAreaFrame]
                ChartInspectionSurface { location in
                    inspectedDate = proxy.value(atX: min(max(0, location.x), plot.width), as: Date.self)
                }
                    .frame(width: plot.width, height: plot.height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Inspect glucose chart")
                    .accessibilityValue(inspectionLabel)
                    .accessibilityHint("Swipe up or down to inspect recorded readings")
                    .accessibilityAdjustableAction { direction in
                        let readings = GlucoseObservations.valid(points, now: model.now)
                            .filter { $0.date >= interval.start && $0.date <= interval.end }
                        guard !readings.isEmpty else { return }
                        let index = inspectedPoint.flatMap { readings.firstIndex(of: $0) } ?? (readings.count - 1)
                        switch direction {
                        case .increment: inspectedDate = readings[min(index + 1, readings.count - 1)].date
                        case .decrement: inspectedDate = readings[max(index - 1, 0)].date
                        @unknown default: break
                        }
                    }
                    .accessibilityIdentifier("journal.chart.plot")
                    .position(x: plot.midX, y: plot.midY)
            }
        }
        .frame(height: max(60, chartHeight))
        .accessibilityLabel("Glucose chart. \(points.count) readings. \(max(0, segments.count - 1)) breaks. Units \(model.unit).")
        .overlay(alignment: .topLeading) {
            if inspectedDate != nil {
                HStack(spacing: 4) {
                    Text(inspectionLabel).font(.caption.monospacedDigit())
                        .foregroundStyle(inspectedPoint == nil ? Color.secondary : JournalStyle.accent)
                        .padding(.leading, 10)
                        .accessibilityIdentifier("journal.chart.readout")
                    Button { inspectedDate = nil } label: {
                        Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel("Clear selected reading")
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onChange(of: interval.duration) { _ in inspectedDate = nil }
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.mgDl) + [GlucoseReference.lower, GlucoseReference.upper]
        if showLimits, model.low > 0, model.high > model.low { values += [model.low, model.high] }
        return model.value(max(0, (values.min() ?? 70) - 15))...model.value((values.max() ?? 140) + 15)
    }
}

/// Reject vertical drags before recognition, so the enclosing native scroll view
/// can handle them. Filtering inside SwiftUI's onChanged is too late: it has
/// already claimed the gesture and prevents the page from scrolling on iOS.
private struct ChartInspectionSurface: UIViewRepresentable {
    let inspect: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(inspect: inspect) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.panned(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.inspect = inspect }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var inspect: (CGPoint) -> Void
        init(inspect: @escaping (CGPoint) -> Void) { self.inspect = inspect }

        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            inspect(gesture.location(in: gesture.view))
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began || gesture.state == .changed || gesture.state == .ended {
                inspect(gesture.location(in: gesture.view))
            }
        }
    }
}

struct JournalMealRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let meal: MealRecord
    var body: some View {
        JournalCard {
            HStack(alignment: .top, spacing: 14) {
                if !dynamicTypeSize.isAccessibilitySize { Group {
                    if let image = MealStore.shared.image(for: meal) {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else { Image(systemName: "fork.knife").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity).background(JournalStyle.background) }
                }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityHidden(true) }
                VStack(alignment: .leading, spacing: 5) {
                    Text(meal.displayTitle).font(.headline).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    Text(meal.status == .confirmed ? "Reviewed nutrition estimate" : meal.captureStatus).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct JournalListView: View {
    @ObservedObject var model: JournalModel
    let capture: () -> Void
    let edit: (UUID) -> Void
    @State private var query = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let issue = model.storageIssue { Text(issue).foregroundStyle(.orange) }
                    if filtered.isEmpty {
                        JournalCard {
                            Image(systemName: query.isEmpty ? "camera.on.rectangle" : "magnifyingglass").font(.largeTitle).foregroundStyle(JournalStyle.accent)
                            Text(query.isEmpty ? "Your food story starts here" : "No matching meals").font(.title2.bold())
                            Text(query.isEmpty ? "Your meals and notes appear here." : "Try another name or note.").foregroundStyle(.secondary)
                            if query.isEmpty { Button("Log your first meal", action: capture).buttonStyle(.borderedProminent) }
                        }
                    }
                    ForEach(filtered, id: \.id) { meal in
                        NavigationLink { JournalMealDetailContent(model: model, mealID: meal.id, edit: edit) } label: { JournalMealRow(meal: meal) }.buttonStyle(.plain)
                    }
                }.padding(20)
            }.background(JournalStyle.background)
                .navigationTitle("Journal")
                .searchable(text: $query, prompt: "Meal name or note")
                .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button(action: capture) { Label("Log meal", systemImage: "camera.fill") } } }
        }.tint(JournalStyle.accent)
    }
    private var filtered: [MealRecord] {
        model.meals.filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) || $0.userComment.localizedCaseInsensitiveContains(query) }
    }
}

struct JournalMealDetail: View {
    @ObservedObject var model: JournalModel
    let mealID: UUID
    let edit: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            JournalMealDetailContent(model: model, mealID: mealID, edit: edit)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Done") { dismiss() } } }
        }.tint(JournalStyle.accent)
    }
}

struct JournalMealDetailContent: View {
    @ObservedObject var model: JournalModel
    @ObservedObject private var health = JournalHealthContext.shared
    let mealID: UUID
    let edit: (UUID) -> Void
    @State private var editingMeal = false
    @State private var analysisSettings = false
    @State private var analysisError: String?
    var body: some View {
        ScrollView {
            if let meal = model.meals.first(where: { $0.id == mealID }) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        if let image = MealStore.shared.image(for: meal) {
                            Image(uiImage: image).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meal.displayTitle).font(.title2.bold())
                            Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    response(meal)
                    if !meal.userComment.isEmpty { JournalCard { Label("Your note", systemImage: "text.bubble").font(.headline); Text(meal.userComment) } }
                    if health.enabled {
                        JournalCard {
                            Label("Health context", systemImage: "heart.text.clipboard").font(.headline)
                            if let duration = health.sleepBefore(meal.eatenAt) {
                                LabeledContent("Sleep · prior 24h", value: "\(Int(duration / 3600))h \(Int(duration.truncatingRemainder(dividingBy: 3600) / 60))m")
                            } else { Text("Sleep unavailable · prior 24h").foregroundStyle(.secondary) }
                            let nearby = health.workouts.filter { $0.interval.end > meal.eatenAt.addingTimeInterval(-3600) && $0.interval.start < meal.eatenAt.addingTimeInterval(7200) }
                            ForEach(nearby) { workout in
                                NavigationLink { JournalWorkoutDetail(model: model, workout: workout) } label: {
                                    Label("\(workout.title) · \(workout.interval.start.formatted(date: .omitted, time: .shortened))", systemImage: "figure.run")
                                }
                            }
                        }
                    }
                    JournalCard {
                        HStack { Text("Foods & portions").font(.headline); Spacer(); Button("Edit") { editingMeal = true } }
                        if meal.foodItems.isEmpty {
                            Text("Add foods to find repeated meals.").foregroundStyle(.secondary)
                        }
                        ForEach(Array(meal.foodItems.enumerated()), id: \.offset) { _, food in
                            LabeledContent(food.name, value: food.portion).font(.subheadline)
                        }
                        if meal.analysisRequestID != nil {
                            Label("Identifying food…", systemImage: "sparkles").font(.subheadline).foregroundStyle(.secondary)
                        } else if meal.analysis == nil || meal.status == .failed {
                            Button(meal.status == .failed ? "Retry photo analysis" : "Identify food from photo", action: analyzePhoto)
                        }
                    }
                    JournalCard {
                        DisclosureGroup("Nutrition & Apple Health") {
                            if let nutrients = meal.analysis?.nutrients {
                                Text("\(nutrients.carbohydratesG.map { String(format: "%.0f g", $0) } ?? "Unknown") carbohydrates · estimate").font(.subheadline)
                            }
                            Button("Review nutrition & Health") { edit(mealID) }
                            Button("Analyze photo again", action: analyzePhoto).disabled(meal.analysisRequestID != nil)
                        }
                    }
                }.padding(20)
            } else { Text("This meal is no longer available.").padding() }
        }.background(JournalStyle.background).navigationTitle("Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Edit meal") { editingMeal = true } } }
            .sheet(isPresented: $editingMeal) {
                if let meal = model.meals.first(where: { $0.id == mealID }) { MealEditView(meal: meal) }
            }
            .sheet(isPresented: $analysisSettings) {
                JournalNavigationSheet(content: JournalAISettingsView(preferences: JournalPreferences()))
            }
            .alert("Couldn’t start analysis", isPresented: Binding(get: { analysisError != nil }, set: { if !$0 { analysisError = nil } })) {
                Button("OK") { analysisError = nil }
            } message: { Text(analysisError ?? "") }
    }

    private func analyzePhoto() {
        guard MealAISettings.hasAPIKey else { analysisSettings = true; return }
        do { try MealAnalysisService.shared.enqueue(mealID) }
        catch { analysisError = error.localizedDescription }
    }

    private func response(_ meal: MealRecord) -> some View {
        let observation = model.observation(for: meal)
        let occasion = model.occasion(for: meal)
        let window = DateInterval(start: observation.interval.start.addingTimeInterval(-15 * 60), end: observation.interval.end)
        return JournalCard {
            Label(occasion.meals.count > 1 ? "Together at this meal" : "After this meal", systemImage: "waveform.path").font(.headline)
            if occasion.meals.count > 1 {
                ForEach(occasion.meals) { capture in
                    if let original = model.meals.first(where: { $0.id == capture.id }) {
                        HStack {
                            FoodPhoto(meal: original).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(original.displayTitle).font(.subheadline).lineLimit(2)
                            Spacer()
                            Text(original.eatenAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("15 minutes before · 2 hours after").font(.caption).foregroundStyle(.secondary)
            if meal.eatenAt < model.now.addingTimeInterval(-90 * 86400) {
                Text("This meal is outside the 90-day comparison window. Your original records are still saved.").font(.footnote).foregroundStyle(.secondary)
            }
            JournalGlucoseChart(model: model, points: model.mealPoints(for: meal), interval: window, meals: model.meals,
                mealBaseline: observation.limitation == nil ? observation.baseline : nil,
                mealPeak: observation.limitation == nil ? model.mealPoints(for: meal).filter { observation.interval.contains($0.date) }.max(by: { $0.mgDl < $1.mgDl }) : nil)
            LabeledContent("Glucose coverage", value: "\(Int(observation.coverage * 100))%")
            if observation.hasNearbyMeal {
                Label("Overlapping meals", systemImage: "fork.knife").font(.caption).foregroundStyle(.secondary)
            }
            if let limitation = observation.limitation {
                Label(limitation, systemImage: "info.circle").font(.subheadline).foregroundStyle(.secondary)
            } else if let baseline = observation.baseline, let peak = observation.peak {
                HStack {
                    VStack(alignment: .leading) { Text("Before meal").font(.caption).foregroundStyle(.secondary); Text(model.formatted(baseline)).font(.title2.bold()) }
                    Spacer()
                    VStack(alignment: .trailing) { Text("Observed peak").font(.caption).foregroundStyle(.secondary); Text("\(model.formatted(peak)) \(model.unit)").font(.title2.bold()) }
                }
            }
            DisclosureGroup("About this observation") {
                Text("Photos within 30 minutes of the first share one window. Other nearby meals stay on the chart; their effects cannot be separated. This is an observed curve, not a food score.").font(.footnote).foregroundStyle(.secondary)
                Button(meal.keepResponseSeparate == true ? "Group with nearby photos" : "Keep this photo separate") {
                    do {
                        _ = try MealStore.shared.update(id: meal.id) { $0.keepResponseSeparate = meal.keepResponseSeparate != true }
                    } catch { analysisError = error.localizedDescription }
                }
            }
        }
    }
}

struct JournalPatternsView: View {
    @ObservedObject var model: JournalModel
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder
    var body: some View {
        if embedded { content }
        else {
            NavigationStack {
                content.toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
            }.tint(JournalStyle.accent)
        }
    }
    @ViewBuilder private var content: some View {
        let interval = DateInterval(start: model.now.addingTimeInterval(-14 * 86400), end: model.now)
        let coverage = GlucoseObservations.coverage(model.points, in: interval)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    JournalCard {
                        Label("About sensor readings", systemImage: "info.circle").font(.headline)
                        Text("CGM measures interstitial glucose. If a reading doesn’t match how you feel, follow your sensor’s instructions and confirm as directed.")
                        Text("The shaded 70–140 mg/dL (3.9–7.8 mmol/L) band is a research reference from healthy participants, not a recommended target for everyone. Meal peaks can rise above it. The orange marker shows the observed rise from the pre-meal baseline, not proof that one food caused it or a longevity score.").foregroundStyle(.secondary)
                        Text("Chart gaps mean missing readings or a sensor change. Display limits are your chart settings, not a universal healthy range. They do not change alarms.").foregroundStyle(.secondary)
                    }
                    JournalCard {
                        Label("The last 14 days", systemImage: "calendar").font(.headline)
                        Text("\(Int(coverage * 100))% coverage").font(.largeTitle.bold())
                        ProgressView(value: coverage).tint(JournalStyle.accent)
                        Text("Meals logged: \(model.meals.filter { interval.contains($0.eatenAt) }.count)").font(.subheadline)
                        Text(coverage < 0.7 ? "Your picture is still forming. Missing readings stay missing; they are never filled with guesses." : "You have useful coverage to explore. Repeated, comparable meals matter more than one peak.").foregroundStyle(.secondary)
                    }
                    JournalCard {
                        Label("Compare like with like", systemImage: "square.on.square").font(.headline)
                        Text("Try logging a familiar meal again. Include the portion, eating time, and anything different: a walk, sleep, stress, illness, or alcohol.")
                        Text("The journal shows two-hour observations, not a causal explanation or a prediction of future health.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    JournalCard {
                        Label("No universal perfect curve", systemImage: "heart.text.clipboard").font(.headline)
                        Text("Clinical glucose targets depend on the person and their care plan. A lower meal response doesn’t necessarily make a food healthier, and CGM alone cannot diagnose diabetes or measure longevity.")
                        Text("Fourteen days and 70% coverage are common clinical reporting benchmarks, not a validated longevity test.").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }.background(JournalStyle.background).navigationTitle("About readings").navigationBarTitleDisplayMode(.inline)
    }
}
