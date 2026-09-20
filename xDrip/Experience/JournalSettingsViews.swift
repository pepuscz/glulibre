import SwiftUI

struct JournalSettingsView: View {
    @ObservedObject var model: JournalModel
    @ObservedObject var preferences: JournalPreferences
    @ObservedObject var management: JournalManagement

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        JournalSensorView(model: model, management: management)
                    } label: {
                        settingsRow("Sensor", subtitle: model.isStale ? "Check reading status" : model.freshness, icon: "sensor.tag.radiowaves.forward", color: JournalStyle.accent)
                    }
                    NavigationLink {
                        JournalNotificationsView(preferences: preferences, management: management)
                    } label: { settingsRow("Notifications", subtitle: "Glucose alerts & visibility", icon: "bell.badge", color: .orange) }
                }
                Section("Connected services") {
                    NavigationLink { JournalHealthSettingsView(preferences: preferences) } label: {
                        settingsRow("Apple Health", subtitle: "Choose what to share", icon: "heart.fill", color: .pink)
                    }
                    NavigationLink { JournalAISettingsView(preferences: preferences) } label: {
                        settingsRow("Meal analysis", subtitle: preferences.hasKey ? "OpenAI key saved" : "Optional photo estimates", icon: "sparkles", color: .indigo)
                    }
                    NavigationLink { connections } label: { Label("Other connections", systemImage: "point.3.connected.trianglepath.dotted") }
                }
                Section {
                    Picker("Glucose units", selection: Binding(get: { preferences.usesMgDl }, set: preferences.setUsesMgDl)) {
                        Text("mmol/L").tag(false)
                        Text("mg/dL").tag(true)
                    }
                    NavigationLink { JournalPrivacyView(management: management) } label: { Label("Privacy & data", systemImage: "hand.raised") }
                } header: { Text("Preferences") }
                Section {
                    NavigationLink { JournalSavedRecordsView(management: management) } label: { Label("Saved records", systemImage: "archivebox") }
                    NavigationLink { support } label: { Label("Help & sensor care", systemImage: "questionmark.circle") }
                    NavigationLink { JournalLegalView() } label: { Label("About & licenses", systemImage: "info.circle") }
                } footer: {
                    Text("\(ConstantsHomeView.applicationName) · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")")
                        .frame(maxWidth: .infinity).padding(.top, 16)
                }
            }.navigationTitle("Settings")
        }.tint(JournalStyle.accent)
    }

    private var connections: some View {
        List {
            Section {
                ForEach([JournalService.nightscout, .dexcom, .watch]) { service in serviceLink(service) }
            } header: { Text("Share readings") } footer: { Text("Existing connections keep working. Opening a service doesn’t enable sharing.") }
            Section("Accessibility & displays") {
                ForEach([JournalService.speech, .calendar, .contact]) { service in serviceLink(service) }
            }
            Section { serviceLink(.source) } footer: { Text("Changing the reading source can interrupt your sensor connection.") }
        }.navigationTitle("Connections").navigationBarTitleDisplayMode(.inline)
    }
    @ViewBuilder private func serviceLink(_ service: JournalService) -> some View {
        if let adapter = management.settingsProvider(service) {
            NavigationLink(service.rawValue) { JournalServiceView(title: service.rawValue, model: adapter) }
        }
    }
    private var support: some View {
        List {
            Section {
                NavigationLink("Sensor connection") { JournalSensorView(model: model, management: management) }
                NavigationLink("Saved devices") { JournalDeviceDetailsView(management: management) }
            }
            Section {
                DisclosureGroup("Missing readings") { Text("Keep your phone nearby with Bluetooth on. Leave the app running in the background. A brief gap doesn’t require a new NFC scan.") }
                DisclosureGroup("Replacing a sensor") { Text("Use Start a new sensor only for a newly applied, unused sensor. Keep the app installed to preserve your history and connection settings.") }
                DisclosureGroup("A reading doesn’t feel right") { Text("If readings don’t match how you feel, check with a finger-stick meter. Seek medical advice for persistent unusual readings or symptoms.") }
                DisclosureGroup("About food responses") { Text("Compare repeated meals, portions, activity and sleep. A single response can’t identify a harmful ingredient, and a flatter curve is not a proven longevity outcome.") }
            }
        }.navigationTitle("Help").navigationBarTitleDisplayMode(.inline)
    }

    private func settingsRow(_ title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
    }
}

/// Keep upstream notices discoverable after replacing the original Settings UI.
private struct JournalLegalView: View {
    var body: some View {
        List {
            Section(ConstantsHomeView.applicationName) {
                Text("An experimental meal and glucose journal, built on xDrip4iOS.")
                Text("Modified fork · 24 August–20 September 2026").font(.subheadline).foregroundStyle(.secondary)
                Link("Source code", destination: URL(string: ConstantsHomeView.gitHubURL)!)
                Link("Upstream xDrip4iOS", destination: URL(string: "https://github.com/JohanDegraeve/xdripswift")!)
            }
            Section("Free software") {
                Text("Copyright © Johan Degraeve and the other authors credited in the source. Original copyright notices are retained.")
                Text("You may redistribute and modify this app under the GNU GPL, version 3 or later. It comes without any warranty, including merchantability or fitness for a particular purpose.")
                NavigationLink("GNU GPL v3") { JournalLegalText(title: "GNU GPL v3", resource: "GPL-3.0") }
                NavigationLink("Third-party notices") { JournalLegalText(title: "Third-party notices", resource: "ThirdPartyNotices") }
                Link("Legacy icons by Icons8", destination: URL(string: "https://icons8.com/")!)
            }
        }.navigationTitle("About & licenses").navigationBarTitleDisplayMode(.inline)
    }
}

private struct JournalLegalText: View {
    let title: String
    let resource: String
    private var contents: String? {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt", subdirectory: "Legal") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
    var body: some View {
        ScrollView {
            Text(contents ?? "The license text is missing from this build. Please check the source repository.")
                .font(.footnote).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding()
                .accessibilityIdentifier("journal.legal.text")
        }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

struct JournalSensorView: View {
    @ObservedObject var model: JournalModel
    @ObservedObject var management: JournalManagement
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "sensor.tag.radiowaves.forward").font(.largeTitle).foregroundStyle(JournalStyle.accent).accessibilityHidden(true)
                    Text(model.sensor.name).font(.title2.bold())
                    Label(management.isWarmingUp ? "Warming up" : model.latest == nil ? "Waiting for readings" : model.isStale ? "Readings are delayed" : "Receiving readings", systemImage: model.isStale ? "clock" : "checkmark.circle")
                        .foregroundStyle(model.isStale ? Color.secondary : JournalStyle.accent)
                    Text(model.freshness).font(.subheadline).foregroundStyle(.secondary)
                    if management.isWarmingUp, let end = management.warmupEnd { Text(end, style: .timer).font(.title.monospacedDigit()) }
                }.padding(.vertical, 8)
            }
            Section("Connection") {
                LabeledContent("Bluetooth", value: model.sensor.link)
                if let device = model.sensor.deviceName { LabeledContent("Device", value: device) }
                if let started = model.sensor.startedAt {
                    LabeledContent("Sensor started", value: started.formatted(date: .abbreviated, time: .shortened))
                }
                if model.sensor.hasDevice {
                    LabeledContent("Automatic reconnection", value: model.sensor.connectionEnabled ? "Enabled" : "Disabled")
                }
            }
            Section {
                Text(management.isWarmingUp ? "We’ll notify you when warm-up finishes. No scanning needed now." : model.isStale
                     ? "Keep your phone nearby with Bluetooth on. Don’t re-pair to fix a brief delay."
                     : "Readings continue in the background. Don’t force-quit the app.")
                    .foregroundStyle(.secondary)
            } header: { Text(model.isStale ? "Check connection" : "Connected") }
            Section {
                if model.isStale && model.sensor.hasDevice && !management.isWarmingUp {
                    Button("Reconnect Bluetooth", systemImage: "arrow.clockwise") { management.reconnect() }.disabled(!model.isReady)
                }
                NavigationLink(model.sensor.hasDevice ? "Replace or finish sensor setup" : "Set up a sensor") { JournalSensorSetupView(model: model, management: management) }
                    .disabled(!model.isReady)
                NavigationLink("Device details") { JournalDeviceDetailsView(management: management) }
            }
        }.navigationTitle("Sensor").navigationBarTitleDisplayMode(.inline)
            .onAppear { model.refreshSensor(); management.refresh() }
            .refreshable { model.refresh(); model.refreshSensor() }
            .journalManagementMessage(management)
    }
}

struct JournalNotificationsView: View {
    @ObservedObject var preferences: JournalPreferences
    @ObservedObject var management: JournalManagement
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Form {
            Section {
                LabeledContent("iOS permission", value: preferences.notificationStatus)
                Button("Open iOS notification settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Section("When it matters") {
                ForEach(preferences.alarmSummaries) { alarm in
                    LabeledContent(alarm.title, value: alarm.value)
                }
                Label("Warm-up finished", systemImage: "timer")
            }
            Section {
                NavigationLink("Customize alarms") { JournalAlarmList(management: management) }
            } footer: { Text("Uses your saved alarms. iOS notification permission is required.") }
            Section("At a glance") {
                Toggle("Glucose on app badge", isOn: Binding(get: { preferences.readingBadge }, set: preferences.setReadingBadge))
            }
        }.navigationTitle("Notifications").navigationBarTitleDisplayMode(.inline)
            .onAppear { preferences.refreshNotificationStatus() }
            .onChange(of: scenePhase) { phase in if phase == .active { preferences.refreshNotificationStatus() } }
    }
}

struct JournalHealthSettingsView: View {
    @ObservedObject var preferences: JournalPreferences
    @ObservedObject private var health = JournalHealthContext.shared
    var body: some View {
        Form {
            JournalHealthContextSettings(health: health)
            Section {
                Toggle("Share glucose readings", isOn: Binding(get: { preferences.glucoseToHealth }, set: preferences.setGlucoseToHealth))
                Toggle("Export confirmed meals", isOn: Binding(get: { preferences.mealsToHealth }, set: preferences.setMealsToHealth))
            } header: { Text("Apple Health") } footer: {
                Text("Confirmed nutrition only. Photos and notes stay out of Health.")
            }
            Section("Your permissions") {
                Text("Manage access in Health → your profile → Apps → \(ConstantsHomeView.applicationName).")
                    .foregroundStyle(.secondary)
            }
        }.navigationTitle("Apple Health").navigationBarTitleDisplayMode(.inline)
            .alert("Apple Health", isPresented: Binding(get: { preferences.message != nil }, set: { if !$0 { preferences.message = nil } })) {
                Button("OK") { preferences.message = nil }
            } message: { Text(preferences.message ?? "") }
    }
}

struct JournalAISettingsView: View {
    @ObservedObject var preferences: JournalPreferences
    @State private var key = ""
    @State private var modelName = ""
    @State private var editingKey = false
    @State private var removeKey = false
    @State private var saved = false
    var body: some View {
        Form {
            Section {
                Label(preferences.hasKey ? "API key saved" : "Use your own API key", systemImage: preferences.hasKey ? "checkmark.shield" : "key")
                Button(preferences.hasKey ? "Replace API key" : "Add OpenAI API key") { editingKey = true }
            } footer: { Text("Photos and notes work without AI. Your key is stored in Keychain. OpenAI usage may incur charges.") }
            Section {
                Toggle("Automatic meal analysis", isOn: Binding(get: { preferences.automaticMealAnalysis }, set: preferences.setAutomaticMealAnalysis))
                if !preferences.hasKey {
                    Text("Add a key to analyze meal photos.").font(.subheadline).foregroundStyle(.secondary)
                }
            } footer: {
                Text("When on, new photos and notes are sent to OpenAI with your key. Older meals aren’t sent automatically. Review estimates before Health export.")
            }
            Section {
                TextField("Model ID", text: $modelName)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("Model ID").accessibilityIdentifier("journal.ai.model")
                Button("Save model") {
                    preferences.setModel(modelName)
                    modelName = preferences.aiModel
                    saved = true
                }
                .disabled(modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || modelName.trimmingCharacters(in: .whitespacesAndNewlines) == preferences.aiModel)
                .accessibilityIdentifier("journal.ai.saveModel")
                if saved { Label("Model saved", systemImage: "checkmark.circle").font(.subheadline).foregroundStyle(.secondary) }
            } header: { Text("AI model") } footer: {
                Text("Enter an OpenAI model ID. It must support images and structured outputs through the Responses API. Changes apply to the next analysis; saved meals stay unchanged.")
            }
            if preferences.hasKey {
                Section {
                    Button("Remove API key", role: .destructive) { removeKey = true }
                }
            }
        }.navigationTitle("Meal analysis").navigationBarTitleDisplayMode(.inline)
            .onAppear { modelName = preferences.aiModel }
            .onChange(of: modelName) { value in
                if value.trimmingCharacters(in: .whitespacesAndNewlines) != preferences.aiModel { saved = false }
            }
            .sheet(isPresented: $editingKey, onDismiss: { key = "" }) {
                NavigationStack {
                    Form {
                        Section {
                            SecureField("Paste API key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        } footer: { Text("The existing key is kept until a replacement is saved successfully.") }
                    }.navigationTitle("OpenAI key").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { editingKey = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("Save") {
                                if preferences.saveKey(key) { key = ""; editingKey = false }
                            }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
                        }
                        .alert("Couldn’t save key", isPresented: Binding(get: { preferences.message != nil }, set: { if !$0 { preferences.message = nil } })) {
                            Button("OK") { preferences.message = nil }
                        } message: { Text(preferences.message ?? "") }
                }.tint(JournalStyle.accent)
            }
            .confirmationDialog("Remove your API key?", isPresented: $removeKey, titleVisibility: .visible) {
                Button("Remove key", role: .destructive) { preferences.removeKey() }
            } message: { Text("Your meals and photos stay saved. You can add a key again later.") }
            .overlay(alignment: .bottom) {
                if !editingKey, let message = preferences.message {
                    Text(message).font(.footnote).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).padding()
                }
            }
    }
}

struct JournalPrivacyView: View {
    @ObservedObject var management: JournalManagement
    var body: some View {
        List {
            Section("On this iPhone") {
                Label("Glucose history, meal photos & notes", systemImage: "iphone")
                Text("Stored locally. App updates preserve your data; uninstalling can remove it.").foregroundStyle(.secondary)
            }
            Section("Sharing you control") {
                Label("OpenAI: photos and notes you analyze", systemImage: "sparkles")
                Text("New meals are sent automatically when enabled in Meal analysis. Your older journal isn’t sent automatically.").foregroundStyle(.secondary)
                Label("Apple Health: when enabled & authorized", systemImage: "heart")
                Text("Workouts and sleep stay on this iPhone and aren’t sent to OpenAI.").foregroundStyle(.secondary)
                Text("Review other sharing in Settings → Other connections.").foregroundStyle(.secondary)
            }
            Section {
                if let adapter = management.settingsProvider(.data) {
                    NavigationLink("Storage & export") { JournalStorageView(model: adapter) }
                }
            }
            Section("About your observations") {
                Text("A glucose curve is context, not a diagnosis or a food grade. Missing readings, sensor variation, activity, sleep, and meal timing can affect the picture.").foregroundStyle(.secondary)
            }
        }.navigationTitle("Privacy & data").navigationBarTitleDisplayMode(.inline)
    }
}
