import Combine
import HealthKit
import UIKit

/// A presentation adapter over existing preferences. Creating it changes nothing.
final class JournalPreferences: ObservableObject {
    @Published private(set) var notificationStatus = "Checking…"
    @Published private(set) var alarmSummaries: [JournalAlarmSummary] = []
    var alarmSummaryProvider: (() -> [JournalAlarmSummary])?
    @Published var message: String?
    private var changes: AnyCancellable?

    init() {
        changes = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var usesMgDl: Bool { UserDefaults.standard.bloodGlucoseUnitIsMgDl }
    func setUsesMgDl(_ value: Bool) { UserDefaults.standard.bloodGlucoseUnitIsMgDl = value; objectWillChange.send() }
    var readingBadge: Bool { UserDefaults.standard.showReadingInAppBadge }
    func setReadingBadge(_ value: Bool) { UserDefaults.standard.showReadingInAppBadge = value; objectWillChange.send() }
    var glucoseToHealth: Bool { UserDefaults.standard.storeReadingsInHealthkit }
    var mealsToHealth: Bool { MealAISettings.writeConfirmedMealsToHealthKit }
    func setMealsToHealth(_ value: Bool) { MealAISettings.writeConfirmedMealsToHealthKit = value; objectWillChange.send() }
    var hasKey: Bool { MealAISettings.hasAPIKey }
    var automaticMealAnalysis: Bool { MealAISettings.automaticAnalysis }
    @MainActor func setAutomaticMealAnalysis(_ enabled: Bool) {
        if !enabled {
            do { try MealAnalysisService.shared.cancelPending() }
            catch { message = "Couldn’t stop pending analysis. Please try again."; return }
        }
        MealAISettings.automaticAnalysis = enabled
        objectWillChange.send()
    }
    var aiModel: String { MealAISettings.model }

    func saveKey(_ key: String) -> Bool {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        do { try MealAISettings.saveAPIKey(key); objectWillChange.send(); return true }
        catch { message = error.localizedDescription; return false }
    }
    func removeKey() {
        do { try MealAISettings.removeAPIKey(); objectWillChange.send() }
        catch { message = error.localizedDescription }
    }
    func setModel(_ value: String) { MealAISettings.model = value; objectWillChange.send() }

    func refreshNotificationStatus() {
        alarmSummaries = alarmSummaryProvider?() ?? []
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral: self?.notificationStatus = "Allowed"
                case .denied: self?.notificationStatus = "Off in iOS Settings"
                case .notDetermined: self?.notificationStatus = "Not enabled yet"
                @unknown default: self?.notificationStatus = "Check iOS Settings"
                }
            }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    static func runNotificationChecks() {
        let suite = "JournalNotificationChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(!defaults.showReadingInNotification)
        defaults.showReadingInNotification = true
        precondition(defaults.showReadingInNotification && !defaults.bool(forKey: "showReadingInNotification"))
        defaults.notificationInterval = 0
        precondition(defaults.notificationInterval == 15)
        defaults.showReadingInNotification = false
        precondition(!defaults.showReadingInNotification)
        precondition(AlertKind.low.defaultAlertValue() == 70)
        precondition(AlertKind.verylow.defaultAlertValue() == 54)
        precondition(AlertKind.high.defaultAlertValue() == 240)
        precondition(AlertKind.missedreading.defaultAlertValue() == 30)
        precondition(AlertKind.low.enabledByDefault && AlertKind.high.enabledByDefault && AlertKind.verylow.enabledByDefault)
        precondition(!AlertKind.fastrise.enabledByDefault && !AlertKind.fastdrop.enabledByDefault)
        NSLog("JOURNAL_NOTIFICATION_CHECKS PASS quiet default, legacy binding, cadence floor, new safety defaults")
    }
    #endif

    func setGlucoseToHealth(_ enabled: Bool) {
        if !enabled {
            UserDefaults.standard.storeReadingsInHealthkit = false
            objectWillChange.send()
            return
        }
        guard HKHealthStore.isHealthDataAvailable(), let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose) else {
            message = "Apple Health is not available on this device."; return
        }
        let store = HKHealthStore()
        store.requestAuthorization(toShare: [type], read: nil) { [weak self] _, error in
            DispatchQueue.main.async {
                let allowed = store.authorizationStatus(for: type) == .sharingAuthorized
                UserDefaults.standard.storeReadingsInHealthkitAuthorized = allowed
                UserDefaults.standard.storeReadingsInHealthkit = allowed
                if !allowed { self?.message = error?.localizedDescription ?? "Allow glucose sharing in the Health app, then try again. Your readings remain saved here." }
                self?.objectWillChange.send()
            }
        }
    }
}

struct JournalAlarmSummary: Identifiable {
    let id: Int
    let title: String
    let value: String
}

struct JournalSensorSnapshot {
    var name = "No sensor selected"
    var deviceName: String?
    var link = "Not configured"
    var startedAt: Date?
    var hasDevice = false
    var connectionEnabled = false
}
