import Combine
import HealthKit
import UIKit

struct JournalWorkout: Identifiable {
    let id: UUID
    let title: String
    let interval: DateInterval
    let activeDuration: TimeInterval
    let source: String
}

/// Optional, read-only context. No Health records, routes, or identifiers are uploaded to AI.
final class JournalHealthContext: ObservableObject {
    static let shared = JournalHealthContext()
    private static let enabledKey = "LibreDebug.Journal.healthContextEnabled"
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var loading = false
    @Published private(set) var workouts: [JournalWorkout] = []
    @Published private(set) var sleep: [DateInterval] = []
    @Published private(set) var error: String?
    private let store = HKHealthStore()
    private var foreground: AnyCancellable?
    private var generation = UUID()
    private var preview = false

    private init() {
        foreground = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
    }

    func connect() {
        guard !loading, HKHealthStore.isHealthDataAvailable(), let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            error = "Health data is unavailable right now."; return
        }
        loading = true
        error = nil
        let requestID = UUID()
        generation = requestID
        // Completion says whether the request was processed, not whether read access was granted.
        store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), sleepType]) { [weak self] success, failure in
            DispatchQueue.main.async {
                guard let self, self.generation == requestID else { return }
                self.loading = false
                if let failure { self.error = failure.localizedDescription; return }
                guard success else { self.error = "The Health request could not be completed. You can try again."; return }
                self.enabled = true
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                self.refresh()
            }
        }
    }

    func disconnect() {
        generation = UUID()
        enabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        workouts = []; sleep = []; error = nil; loading = false
    }

    func refresh() {
        guard !preview, enabled, !loading, HKHealthStore.isHealthDataAvailable(), let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        loading = true
        error = nil
        let requestID = UUID()
        generation = requestID
        let end = Date()
        let start = end.addingTimeInterval(-91 * 86400)
        Task { [weak self] in
            guard let self else { return }
            do {
                async let workoutSamples = self.samples(type: HKObjectType.workoutType(), start: start, end: end)
                async let sleepSamples = self.samples(type: sleepType, start: start, end: end)
                let (activity, rest) = try await (workoutSamples, sleepSamples)
                let workouts = activity.compactMap { $0 as? HKWorkout }.filter { $0.endDate > $0.startDate }.map {
                    JournalWorkout(id: $0.uuid, title: Self.title($0.workoutActivityType), interval: DateInterval(start: $0.startDate, end: $0.endDate), activeDuration: $0.duration, source: $0.sourceRevision.source.name)
                }
                let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                let sleep = rest.compactMap { $0 as? HKCategorySample }.filter { asleepValues.contains($0.value) && $0.endDate > $0.startDate }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
                await MainActor.run {
                    guard self.enabled, self.generation == requestID else { return }
                    self.workouts = workouts
                    self.sleep = sleep
                    self.loading = false
                }
            } catch {
                await MainActor.run {
                    guard self.generation == requestID else { return }
                    self.workouts = []; self.sleep = []
                    self.error = "Health context could not be refreshed. \(error.localizedDescription)"
                    self.loading = false
                }
            }
        }
    }

    func sleepBefore(_ date: Date) -> TimeInterval? {
        let seconds = GlucoseObservations.unionDuration(sleep, in: DateInterval(start: date.addingTimeInterval(-86400), end: date))
        return seconds > 0 ? seconds : nil
    }

    private func samples(type: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end), limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    private static func title(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Cycling"
        case .swimming: return "Swim"
        case .hiking: return "Hike"
        case .yoga: return "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength training"
        case .highIntensityIntervalTraining: return "Interval training"
        case .pilates: return "Pilates"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .dance: return "Dance"
        default: return "Workout"
        }
    }

    #if targetEnvironment(simulator) && DEBUG
    func useSimulatorPreview() {
        preview = true
        enabled = true
        let now = Date()
        workouts = [JournalWorkout(id: UUID(), title: "Sample run", interval: DateInterval(start: now.addingTimeInterval(-7200), duration: 2400), activeDuration: 2100, source: "Simulator sample—not Health data")]
        sleep = [DateInterval(start: now.addingTimeInterval(-14 * 3600), duration: 7 * 3600)]
        if ProcessInfo.processInfo.arguments.contains("--journal-empty") { workouts = []; sleep = [] }
    }
    #endif
}
