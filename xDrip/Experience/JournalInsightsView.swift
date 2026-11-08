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
                        Text("Foods").tag(0)
                        Text("Activity").tag(1)
                    }.pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                if selection == 0 {
                    FoodLibrarySection(model: model, health: health, edit: edit, capture: capture)
                } else {
                    if !health.enabled || !health.movementPermissionRequested {
                        Section {
                            Label("Everyday movement", systemImage: "figure.walk").font(.headline)
                            Text("Steps and standing, without starting a workout.").foregroundStyle(.secondary)
                            Button("Include movement") { health.connect() }.disabled(health.loading)
                        }
                    }
                    if health.enabled && health.movementPermissionRequested {
                        Section("After meals") {
                            if let error = health.movementError { Text(error).foregroundStyle(.secondary) }
                            if model.meals.isEmpty {
                                Text("No meals logged").foregroundStyle(.secondary)
                                Button("Log a meal", systemImage: "camera.fill", action: capture)
                            }
                            ForEach(Array(model.meals.filter { $0.eatenAt <= model.now }.prefix(5)), id: \.id) { meal in
                                NavigationLink {
                                    JournalMealDetailContent(model: model, mealID: meal.id, edit: edit)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(meal.displayTitle).font(.headline)
                                        Text(meal.eatenAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                        JournalMovementContextLabel(health: health, date: model.occasion(for: meal).date).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if health.enabled {
                        Section {
                            if health.loading && health.workouts.isEmpty { ProgressView("Reading workouts…") }
                            if let error = health.error { Text(error).foregroundStyle(.secondary) }
                            if recentWorkouts.isEmpty && !health.loading {
                                Text("No recent workouts").foregroundStyle(.secondary)
                            }
                            ForEach(recentWorkouts) { workout in
                                NavigationLink { JournalWorkoutDetail(model: model, workout: workout) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(workout.title, systemImage: "figure.run").font(.headline)
                                        Text("\(workout.interval.start.formatted(date: .abbreviated, time: .shortened)) · \(Int(workout.activeDuration / 60)) min").font(.subheadline).foregroundStyle(.secondary)
                                    }.padding(.vertical, 4)
                                }
                            }
                        } header: { Text("Workouts · last 14 days") }
                        Section { NavigationLink("Health access", destination: healthAccess) }
                    }
                }
                Section {
                    NavigationLink { JournalPatternsView(model: model, embedded: true) } label: { Label("About readings", systemImage: "info.circle") }
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
                Text("In Health, open your profile → Apps → \(ConstantsHomeView.applicationName) to review access.")
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
            if health.loading && health.workouts.isEmpty && health.movement.isEmpty { ProgressView("Reading Health data…") }
            Button(!health.enabled ? "Connect Apple Health" : (health.movementPermissionRequested ? "Review permissions" : "Include everyday movement")) { health.connect() }.disabled(health.loading)
            if health.enabled {
                Button("Disconnect", role: .destructive) { health.disconnect() }
            }
            if let error = health.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("Movement & sleep") } footer: {
            Text("Steps, distance, stand minutes, active energy, workouts and sleep stay on this iPhone. Disconnecting leaves Health records intact.")
        }
    }
}
