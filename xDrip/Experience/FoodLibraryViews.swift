import SwiftUI
import Charts
import ImageIO

struct FoodLibrarySection: View {
    @ObservedObject var model: JournalModel
    @ObservedObject var health: JournalHealthContext
    let edit: (UUID) -> Void
    let capture: () -> Void
    @State private var largerFirst = false
    private var groups: [FoodResponseGroup] {
        guard largerFirst else { return model.foodGroups }
        return model.foodGroups.sorted { ($0.medianRise ?? -.infinity) > ($1.medianRise ?? -.infinity) }
    }
    var body: some View {
        Section {
            if groups.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "fork.knife.circle").font(.system(size: 48)).foregroundStyle(JournalStyle.accent)
                    Text("Your food. Your response.").font(.title2.bold())
                    Text("Take a meal photo. Your personal food library grows here.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Log a meal", systemImage: "camera.fill", action: capture).buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(.vertical, 32)
            }
            ForEach(groups) { group in
                NavigationLink {
                    FoodResponseDetail(model: model, health: health, groupID: group.id, edit: edit)
                } label: {
                    FoodResponseCard(model: model, group: group, plotDomain: FoodResponsePlot.domain(groups, model: model))
                }.listRowSeparator(.hidden)
            }
        } header: {
            HStack {
                Text("Your foods")
                Spacer()
                Menu {
                    Button("Recently eaten") { largerFirst = false }
                    Button("Larger typical rises") { largerFirst = true }
                } label: { Label(largerFirst ? "Rise" : "Recent", systemImage: "arrow.up.arrow.down") }
            }
        } footer: {
            Text("Last 90 days · Whole meals, not ingredient verdicts.")
        }
    }
}

private struct FoodResponseCard: View {
    @ObservedObject var model: JournalModel
    let group: FoodResponseGroup
    var plotDomain: ClosedRange<Double>?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                FoodPhoto(meal: model.meals.first { $0.id == group.responses.first?.id })
                    .frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.headline).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                    Text("\(group.responses.count) logged · \(group.usable.count) usable").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .center, spacing: 16) {
                FoodResponsePlot(group: group, model: model, compact: true, sharedDomain: plotDomain).frame(height: 60)
                VStack(alignment: .trailing, spacing: 3) {
                    if let rise = group.medianRise {
                        Text(signed(rise, model: model)).font(.title3.bold().monospacedDigit()).foregroundStyle(.orange)
                        Text("\(model.unit) rise").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "circle.dotted").font(.title3).foregroundStyle(JournalStyle.accent)
                        Text(FoodResponseStatus.title(for: group)).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: 130, alignment: .trailing)
            }
        }.padding(.vertical, 8)
    }
}

struct FoodResponseDetail: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: JournalModel
    @ObservedObject var health: JournalHealthContext
    let groupID: String
    let edit: (UUID) -> Void
    @State private var choosingComparison = false
    @State private var updateError: String?
    @State private var editingMeal: MealRecord?
    private var group: FoodResponseGroup? { model.foodGroups.first { $0.id == groupID } }

    var body: some View {
        ScrollView {
            if let group {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        FoodPhoto(meal: model.meals.first { $0.id == group.responses.first?.id })
                            .frame(width: 76, height: 76).clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 5) {
                            Text(group.title).font(.title2.bold())
                            Text("\(group.responses.count) meals · \(group.days) usable days").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    JournalCard {
                        let headerLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                            : AnyLayout(HStackLayout())
                        headerLayout {
                            Text("Your response").font(.headline).fixedSize(horizontal: false, vertical: true)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Text(group.repeated ? "Repeated observations" : FoodResponseStatus.title(for: group))
                                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        FoodResponsePlot(group: group, model: model).frame(height: 200)
                        responseSummary(group)
                        Button { choosingComparison = true } label: {
                            Label("Compare meals", systemImage: "square.split.2x1")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).tint(JournalStyle.accent)
                            .disabled(model.foodGroups.count < 2)
                    }
                    if !group.components.isEmpty {
                        JournalCard {
                            DisclosureGroup("What’s in this meal") {
                                ForEach(Array(group.components.enumerated()), id: \.offset) { _, item in
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).font(.subheadline.bold())
                                        Text(item.portion).font(.caption).foregroundStyle(.secondary)
                                        if let evidence = item.evidence {
                                            Text([evidence.preparation, evidence.brand, evidence.ripeness].compactMap { $0 }.joined(separator: " · "))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
                                }
                            }
                        }
                    }
                    Text("The meals behind it").font(.headline)
                    ForEach(group.responses) { response in
                        if let meal = model.meals.first(where: { $0.id == response.id }) {
                            JournalCard {
                                NavigationLink {
                                    JournalMealDetailContent(model: model, mealID: meal.id, edit: edit)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold()).foregroundStyle(.primary)
                                            if let rise = response.rise { Text(signed(rise, model: model)).foregroundStyle(.orange).font(.headline) }
                                            else { Text(FoodResponseStatus.title(for: response)).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                                    }
                                }
                                FoodMealContext(health: health, date: meal.eatenAt)
                                Menu {
                                    Button("Edit foods & time", systemImage: "pencil") { editingMeal = meal }
                                    Button(meal.keepResponseSeparate == true ? "Allow matching meals" : "Keep this meal separate", systemImage: "rectangle.on.rectangle.slash") {
                                        do {
                                            _ = try MealStore.shared.update(id: meal.id) { $0.keepResponseSeparate = meal.keepResponseSeparate != true }
                                        } catch { updateError = error.localizedDescription }
                                    }
                                    Button("Review nutrition & Health") { edit(meal.id) }
                                } label: { Label("Meal options", systemImage: "ellipsis").font(.caption) }
                            }
                        }
                    }
                    JournalCard {
                        DisclosureGroup("How this comparison works") {
                            Text("Each line is one usable meal, aligned to its pre-meal baseline. Typical rise appears after at least three usable days; it is a median, not proof of a cause. Portions, sleep, activity and sensor variation still matter. Exact food names, portions and preparation are matched together. Use Meal options to separate a mismatch.")
                                .font(.footnote).foregroundStyle(.secondary)
                            if let area = group.medianArea {
                                LabeledContent("Median area above baseline", value: "\(model.formatted(area)) \(model.unit)·min").font(.caption)
                                Text("Positive incremental area over two hours; small within-sensor intervals are interpolated. Not a health score.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.padding(20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack").font(.largeTitle)
                    Text("Meal grouping updated").font(.headline)
                    Text("Return to Your foods to see the updated library.").foregroundStyle(.secondary)
                }.padding(24)
            }
        }.background(JournalStyle.background).navigationTitle("Your food").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $choosingComparison) {
                NavigationStack {
                    List(model.foodGroups.filter { $0.id != groupID }) { other in
                        NavigationLink {
                            FoodComparisonView(model: model, firstID: groupID, secondID: other.id)
                        } label: {
                            FoodResponseCard(model: model, group: other)
                        }
                    }.navigationTitle("Compare with")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingComparison = false } } }
                }
            }
            .sheet(item: $editingMeal) { MealEditView(meal: $0) }
            .alert("Couldn’t update meal", isPresented: Binding(get: { updateError != nil }, set: { if !$0 { updateError = nil } })) {
                Button("OK") { updateError = nil }
            } message: { Text(updateError ?? "") }
    }

    @ViewBuilder private func responseSummary(_ group: FoodResponseGroup) -> some View {
        if let rise = group.medianRise, let range = group.range {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top))
            layout {
                metric("Typical rise", signed(rise, model: model))
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                metric("Observed range", "\(model.formatted(range.lowerBound))–\(model.formatted(range.upperBound))")
            }
        } else {
            if group.components.isEmpty, let id = group.responses.first?.id, let meal = model.meals.first(where: { $0.id == id }) {
                Button("Add foods to find repeats", systemImage: "pencil") { editingMeal = meal }
            } else if group.usable.isEmpty {
                Text(group.responses.first?.limitation ?? "Response unavailable.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label("\(group.days) of 3 usable days", systemImage: "circle.dotted").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title2.bold().monospacedDigit()).fixedSize(horizontal: false, vertical: true)
            Text("\(label) · \(model.unit)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FoodMealContext: View {
    @ObservedObject var health: JournalHealthContext
    let date: Date
    var body: some View {
        let workouts = health.workouts.filter { $0.interval.end > date.addingTimeInterval(-3600) && $0.interval.start < date.addingTimeInterval(7200) }
        VStack(alignment: .leading, spacing: 5) {
            if let sleep = health.sleepBefore(date), health.enabled {
                Label("\(Int(sleep / 3600))h \(Int(sleep.truncatingRemainder(dividingBy: 3600) / 60))m sleep · prior 24h", systemImage: "moon.zzz")
            }
            if health.enabled {
                ForEach(workouts) { workout in
                    Label("\(workout.title) · \(workout.interval.start.formatted(date: .omitted, time: .shortened)) · \(Int(workout.activeDuration / 60)) min", systemImage: "figure.walk")
                }
            }
            if !health.enabled || (workouts.isEmpty && health.sleepBefore(date) == nil) {
                Label("Sleep & activity unavailable", systemImage: "heart.slash")
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}

struct FoodComparisonView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var model: JournalModel
    @ObservedObject private var health = JournalHealthContext.shared
    let firstID: String
    let secondID: String
    var body: some View {
        let groups = [firstID, secondID].compactMap { id in model.foodGroups.first { $0.id == id } }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(groups) { group in
                    JournalCard {
                        HStack {
                            FoodPhoto(meal: model.meals.first { $0.id == group.responses.first?.id }).frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                            Text(group.title).font(.headline)
                        }
                        FoodResponsePlot(group: group, model: model, sharedDomain: FoodResponsePlot.domain(groups, model: model)).frame(height: 170)
                        let metricLayout = dynamicTypeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                            : AnyLayout(HStackLayout())
                        metricLayout {
                            Text(group.medianRise.map { "\(signed($0, model: model)) \(model.unit) typical rise" } ?? FoodResponseStatus.title(for: group))
                                .fixedSize(horizontal: false, vertical: true)
                            if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                            Text("\(group.days) usable days").foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }.font(.subheadline)
                        DisclosureGroup("Portions & context") {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(group.responses) { response in
                                    if let meal = model.meals.first(where: { $0.id == response.id }) {
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.bold())
                                            if !response.usable {
                                                Text(FoodResponseStatus.title(for: response)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            if meal.foodItems.isEmpty {
                                                Text("Foods not added").font(.caption).foregroundStyle(.secondary)
                                            } else {
                                                ForEach(Array(meal.foodItems.enumerated()), id: \.offset) { _, food in
                                                    Text("\(food.name) · \(food.portion)").font(.subheadline)
                                                }
                                            }
                                            FoodMealContext(health: health, date: meal.eatenAt)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }.padding(.top, 8)
                        }
                    }
                }
                Label("Same scale · Different occasions", systemImage: "equal.square").font(.subheadline).foregroundStyle(.secondary)
                Text("Compare the whole meal. This doesn’t isolate an ingredient or account for every difference in sleep, activity or portions.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }.background(JournalStyle.background).navigationTitle("Compare").navigationBarTitleDisplayMode(.inline)
    }
}

private struct FoodResponsePlot: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let group: FoodResponseGroup
    @ObservedObject var model: JournalModel
    var compact = false
    var sharedDomain: ClosedRange<Double>?
    var tint: Color = JournalStyle.accent
    static func domain(_ groups: [FoodResponseGroup], model: JournalModel) -> ClosedRange<Double> {
        let values = groups.flatMap(\.usable).flatMap { response in response.trace.map { model.value($0.mgDl - (response.baseline ?? $0.mgDl)) } }
        return min(model.value(-10), (values.min() ?? 0) - model.value(5))...max(model.value(40), (values.max() ?? 0) + model.value(10))
    }
    var body: some View {
        Chart {
            RuleMark(y: .value("Baseline", 0)).foregroundStyle(.secondary.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ForEach(group.usable) { response in
                ForEach(response.trace) { point in
                    LineMark(x: .value("Minutes after meal", point.date.timeIntervalSince(response.date) / 60),
                             y: .value("Rise", model.value(point.mgDl - (response.baseline ?? point.mgDl))),
                             series: .value("Meal", response.date.formatted(date: .abbreviated, time: .shortened)))
                        .foregroundStyle(tint.opacity(group.usable.count > 1 ? 0.8 : 1))
                        .lineStyle(StrokeStyle(lineWidth: compact ? 2 : 2.5))
                }
            }
        }.chartXScale(domain: -5...125).chartYScale(domain: sharedDomain ?? Self.domain([group], model: model))
            .chartLegend(.hidden)
            .chartXAxis {
                if !compact {
                    AxisMarks(values: dynamicTypeSize.isAccessibilitySize ? [0, 120] : [0, 60, 120]) { value in
                        AxisGridLine()
                        if let minute = value.as(Int.self) {
                            AxisValueLabel(anchor: minute == 0 ? .topLeading : minute == 120 ? .topTrailing : .top) {
                                Text(minute == 0 ? "Meal" : "\(minute)m")
                            }
                        }
                    }
                }
            }
            .chartYAxis { if !compact { AxisMarks(position: .leading) } }
            .overlay { if group.usable.isEmpty { Image(systemName: "waveform.path").foregroundStyle(.secondary.opacity(0.4)).font(.title2) } }
            .accessibilityElement(children: compact ? .ignore : .contain)
            .accessibilityLabel("Glucose change after \(group.title), \(group.usable.count) usable observations, in \(model.unit)")
            .accessibilityValue(group.medianRise.map { "Typical rise \(model.formatted($0))" } ?? FoodResponseStatus.title(for: group))
    }
}

private struct FoodPhoto: View {
    let meal: MealRecord?
    @State private var thumbnail: UIImage?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(JournalStyle.accent.opacity(0.1))
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFill() }
            else { Image(systemName: "fork.knife").foregroundStyle(JournalStyle.accent) }
        }.clipped().accessibilityHidden(true)
            .task(id: meal?.id) {
                thumbnail = nil
                guard let meal else { thumbnail = nil; return }
                thumbnail = await Task.detached(priority: .utility) {
                    guard let data = MealStore.shared.imageData(for: meal),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 240, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil as UIImage? }
                    return UIImage(cgImage: cgImage)
                }.value
            }
    }
}

/// Presentation of the existing analysis result; it does not relax any quality gate.
private enum FoodResponseStatus {
    static func title(for group: FoodResponseGroup) -> String {
        if group.components.isEmpty { return "Add foods" }
        if group.repeated { return "Repeated observations" }
        if !group.usable.isEmpty { return "\(group.days) of 3 usable days" }
        guard let response = group.responses.first else { return "Response unavailable" }
        return title(for: response)
    }

    static func title(for response: FoodResponse) -> String {
        switch response.limitation {
        case "Still collecting the two hours after this meal.":
            return "Collecting 2h response"
        case "Not enough readings just before this meal to estimate a baseline.":
            return "Baseline missing"
        case "A sensor change falls within this window. A comparison would be misleading.":
            return "Sensor changed"
        case "The data source does not identify the sensor. Sensor continuity cannot be checked for this observation.":
            return "Sensor unknown"
        case "Too many missing readings for a reliable two-hour observation.", "More complete readings needed for comparison.":
            return "Readings incomplete"
        case "Another logged meal overlaps this window. The response cannot be separated.":
            return "Meals overlap"
        case "A nearby meal may contribute.":
            return "Nearby meal"
        case .none:
            return response.usable ? "Response available" : "Response unavailable"
        case .some(let limitation):
            return limitation
        }
    }
}

private func signed(_ value: Double, model: JournalModel) -> String {
    "\(value >= 0 ? "+" : "")\(model.formatted(value))"
}
