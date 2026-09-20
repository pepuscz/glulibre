import SwiftUI

struct JournalInsightsView: View {
    @ObservedObject var model: JournalModel
    @ObservedObject var health: JournalHealthContext
    let edit: (UUID) -> Void
    let capture: () -> Void
    @State private var selection = 0
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Explore", selection: $selection) {
                        Text("Your foods").tag(0)
                        Text("Activity").tag(1)
                    }.pickerStyle(.segmented)
                }
                if selection == 0 {
                    FoodLibrarySection(model: model, health: health, edit: edit, capture: capture)
                } else {
                    Section {
                        if !health.enabled {
                            Label("Activity & glucose", systemImage: "figure.run").font(.headline)
                            Text("See Apple Watch workouts alongside your readings.").foregroundStyle(.secondary)
                            Button("Connect Apple Health") { health.connect() }.disabled(health.loading)
                        } else {
                            if health.loading { ProgressView("Reading Health data…") }
                            if let error = health.error { Text(error).foregroundStyle(.secondary) }
                            if recentWorkouts.isEmpty && !health.loading {
                                Text("No workouts available").font(.headline)
                                Text("Workouts may still be syncing, or Health access may be off.").foregroundStyle(.secondary)
                                NavigationLink("Health access", destination: healthAccess)
                            }
                            ForEach(recentWorkouts) { workout in
                                NavigationLink { JournalWorkoutDetail(model: model, workout: workout) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(workout.title, systemImage: "figure.run").font(.headline)
                                        Text("\(workout.interval.start.formatted(date: .abbreviated, time: .shortened)) · \(Int(workout.activeDuration / 60)) min").font(.subheadline).foregroundStyle(.secondary)
                                        Text(workout.source).font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    } header: { Text("Workouts · last 14 days") } footer: { Text("Health data stays on your iPhone.") }
                }
                Section {
                    NavigationLink { JournalPatternsView(model: model, embedded: true) } label: { Label("About your readings", systemImage: "info.circle") }
                }
            }.navigationTitle("Insights")
                .onAppear { health.refresh() }
                .refreshable { model.refresh(); health.refresh() }
        }.tint(JournalStyle.accent)
    }

    private var healthAccess: some View {
        Form {
            JournalHealthContextSettings(health: health)
            Section("Check access & sync") {
                Text("In Health, open your profile → Apps → Libre Debug to review access.")
                Text("Check that your workout appears in Health. Recent Watch workouts may need time to sync.")
            }.foregroundStyle(.secondary)
        }.navigationTitle("Health access").navigationBarTitleDisplayMode(.inline)
    }
    private var recentWorkouts: [JournalWorkout] { health.workouts.filter { $0.interval.end >= model.now.addingTimeInterval(-14 * 86400) } }
}

struct JournalWorkoutDetail: View {
    @ObservedObject var model: JournalModel
    let workout: JournalWorkout
    var body: some View {
        let window = DateInterval(start: workout.interval.start.addingTimeInterval(-30 * 60), end: workout.interval.end.addingTimeInterval(60 * 60))
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                JournalCard {
                    Label(workout.title, systemImage: "figure.run").font(.title2.bold())
                    Text(workout.interval.start.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                    Text("\(Int(workout.activeDuration / 60)) recorded active minutes · \(workout.source)").font(.subheadline)
                }
                JournalCard {
                    Text("Around this activity").font(.headline)
                    Text("30 minutes before · 1 hour after").font(.caption).foregroundStyle(.secondary)
                    JournalGlucoseChart(model: model, points: model.points.filter { window.contains($0.date) }, interval: window, meals: model.meals)
                    JournalChartLegend()
                    if window.end > model.now { Text("Still collecting readings…").font(.subheadline).foregroundStyle(.secondary) }
                    LabeledContent("Glucose coverage", value: "\(Int(GlucoseObservations.coverage(model.points, in: window) * 100))%")
                }
                JournalCard {
                    DisclosureGroup("About this activity") {
                        Text("The purple band includes pauses. This curve shows timing, not proof of cause: food, intensity, and sensor lag also matter. Don’t use it to change medication.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }.padding(20)
        }.background(JournalStyle.background).navigationTitle(workout.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct JournalHealthContextSettings: View {
    @ObservedObject var health: JournalHealthContext
    var body: some View {
        Section {
            if health.loading { ProgressView("Reading Health context…") }
            Text("Workouts & sleep").font(.headline)
            Button(health.enabled ? "Review permissions" : "Connect Apple Health") { health.connect() }.disabled(health.loading)
            if health.enabled {
                LabeledContent("Workouts available", value: "\(health.workouts.count)")
                Button("Disconnect context", role: .destructive) { health.disconnect() }
            }
            if let error = health.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("Understand your day") } footer: {
            Text("Workouts and sleep stay on your iPhone. Disconnecting leaves Health records intact.")
        }
    }
}
