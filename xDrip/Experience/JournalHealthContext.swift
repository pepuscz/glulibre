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
    private static let movementPermissionKey = "GluLibre.Health.movementPermissionRequested.v1"
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: enabledKey)
    @Published private(set) var movementPermissionRequested = UserDefaults.standard.bool(forKey: movementPermissionKey)
    @Published private(set) var loading = false
    @Published private(set) var workouts: [JournalWorkout] = []
    @Published private(set) var sleep: [DateInterval] = []
    @Published private(set) var movement: [MovementBucket] = []
    @Published private(set) var movementError: String?
    @Published private(set) var error: String?
    private let store = HKHealthStore()
    private var foreground: AnyCancellable?
    private var generation = UUID()
    private var preview = false
    private var observers: [HKObserverQuery] = []
    private var pendingRefresh: DispatchWorkItem?
    private var refreshAgain = false

    private static var movementTypes: [(HKQuantityTypeIdentifier, HKUnit)] {
        [(.stepCount, .count()), (.distanceWalkingRunning, .meter()),
         (.appleStandTime, .minute()), (.activeEnergyBurned, .kilocalorie())]
    }

    private init() {
        foreground = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refresh() }
    }

    func connect() {
        guard !preview else { return }
        guard !loading, HKHealthStore.isHealthDataAvailable(), let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            error = "Health data is unavailable right now."; return
        }
        loading = true
        error = nil
        let requestID = UUID()
        generation = requestID
        // Completion says whether the request was processed, not whether read access was granted.
        var read: Set<HKObjectType> = [HKObjectType.workoutType(), sleepType]
        read.formUnion(Self.movementTypes.compactMap { HKObjectType.quantityType(forIdentifier: $0.0) })
        store.requestAuthorization(toShare: [], read: read) { [weak self] success, failure in
            DispatchQueue.main.async {
                guard let self, self.generation == requestID else { return }
                self.loading = false
                if let failure { self.error = failure.localizedDescription; return }
                guard success else { self.error = "The Health request could not be completed. You can try again."; return }
                self.enabled = true
                self.movementPermissionRequested = true // Requested, not proof of read authorization.
                UserDefaults.standard.set(true, forKey: Self.movementPermissionKey)
                UserDefaults.standard.set(true, forKey: Self.enabledKey)
                self.refresh()
            }
        }
    }

    func disconnect() {
        generation = UUID()
        enabled = false
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        observers.forEach { store.stop($0) }; observers = []
        pendingRefresh?.cancel(); pendingRefresh = nil; refreshAgain = false
        workouts = []; sleep = []; movement = []; movementError = nil; error = nil; loading = false
    }

    func refresh() {
        guard !preview, enabled, HKHealthStore.isHealthDataAvailable(), let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        guard !loading else { refreshAgain = true; return }
        loading = true
        error = nil
        movementError = nil
        // Keep the current snapshot visible while refreshing to avoid disappearing
        // chart bands and jumping sections. Replace it even when the query returns
        // empty (revoked/deleted records); failures and disconnect still clear it.
        startObservingMovement()
        let requestID = UUID()
        generation = requestID
        let end = Date()
        let start = end.addingTimeInterval(-91 * 86400)
        Task { [weak self] in
            guard let self else { return }
            do {
                async let workoutSamples = self.samples(type: HKObjectType.workoutType(), start: start, end: end)
                async let sleepSamples = self.samples(type: sleepType, start: start, end: end)
                async let movementResult = self.loadMovement(start: start, end: end)
                let (activity, rest) = try await (workoutSamples, sleepSamples)
                let (movement, movementFailed) = await movementResult
                let workouts = activity.compactMap { $0 as? HKWorkout }.filter { $0.endDate > $0.startDate }.map {
                    JournalWorkout(id: $0.uuid, title: Self.title($0.workoutActivityType), interval: DateInterval(start: $0.startDate, end: $0.endDate), activeDuration: $0.duration, source: $0.sourceRevision.source.name)
                }
                let asleepValues: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
                let sleep = rest.compactMap { $0 as? HKCategorySample }.filter { asleepValues.contains($0.value) && $0.endDate > $0.startDate }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
                await MainActor.run {
                    guard self.enabled, self.generation == requestID else { return }
                    self.workouts = workouts
                    self.sleep = sleep
                    self.movement = movement
                    self.movementError = movementFailed ? "Some movement data couldn’t be refreshed." : nil
                    self.loading = false
                    self.finishRefresh()
                }
            } catch {
                await MainActor.run {
                    guard self.generation == requestID else { return }
                    self.workouts = []; self.sleep = []; self.movement = []
                    self.error = "Health context could not be refreshed. \(error.localizedDescription)"
                    self.loading = false
                    self.finishRefresh()
                }
            }
        }
    }

    private func finishRefresh() {
        if refreshAgain {
            refreshAgain = false
            refresh()
        }
    }

    /// Live invalidation while the app is running. Apple Health remains the source
    /// of truth; collection doesn't depend on our app being open or a workout.
    /// No background workout, alerts, cloud upload, or new Health writes.
    private func startObservingMovement() {
        guard observers.isEmpty, movementPermissionRequested else { return }
        for (identifier, _) in Self.movementTypes {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                completion()
                DispatchQueue.main.async {
                    guard let self, self.enabled else { return }
                    self.pendingRefresh?.cancel()
                    let work = DispatchWorkItem { [weak self] in self?.refresh() }
                    self.pendingRefresh = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
                }
            }
            observers.append(query)
            store.execute(query)
        }
    }

    private func loadMovement(start: Date, end: Date) async -> ([MovementBucket], Bool) {
        guard movementPermissionRequested else { return ([], false) }
        return await withTaskGroup(of: (Int, [MovementStatistic], Bool).self) { group in
            for (index, metric) in Self.movementTypes.enumerated() {
                group.addTask {
                    do { return (index, try await self.movementStatistics(metric.0, unit: metric.1, start: start, end: end), false) }
                    catch { return (index, [], true) }
                }
            }
            var combined: [Date: MovementBucket] = [:]
            var failed = false
            for await (index, values, error) in group {
                failed = failed || error
                for value in values {
                    var bucket = combined[value.interval.start] ?? MovementBucket(interval: value.interval)
                    switch index {
                    case 0: bucket.steps = value.value
                    case 1: bucket.distanceMetres = value.value
                    case 2: bucket.standMinutes = value.value
                    default: bucket.activeKilocalories = value.value
                    }
                    combined[value.interval.start] = bucket
                }
            }
            return (combined.values.sorted { $0.id < $1.id }, failed)
        }
    }

    private struct MovementStatistic {
        let interval: DateInterval
        let value: Double
    }

    private func movementStatistics(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async throws -> [MovementStatistic] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            // Apple's merged statistics avoid adding overlapping Watch + phone steps.
            // Query full aligned bins; apportion meal boundaries only in the pure core.
            let alignedStart = Date(timeIntervalSince1970: floor(start.timeIntervalSince1970 / MealMovement.bucketSeconds) * MealMovement.bucketSeconds)
            let predicate = HKQuery.predicateForSamples(withStart: alignedStart, end: end)
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: Date(timeIntervalSince1970: 0), intervalComponents: DateComponents(minute: 5))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                var values: [MovementStatistic] = []
                collection?.enumerateStatistics(from: alignedStart, to: end) { statistics, _ in
                    guard statistics.endDate <= end, let quantity = statistics.sumQuantity() else { return }
                    let value = quantity.doubleValue(for: unit)
                    guard value.isFinite, value >= 0 else { return }
                    values.append(MovementStatistic(interval: DateInterval(start: statistics.startDate, end: statistics.endDate), value: value))
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
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
        movementPermissionRequested = true
        let now = Date()
        workouts = [JournalWorkout(id: UUID(), title: "Sample run", interval: DateInterval(start: now.addingTimeInterval(-7200), duration: 2400), activeDuration: 2100, source: "Simulator sample—not Health data")]
        sleep = [DateInterval(start: now.addingTimeInterval(-14 * 3600), duration: 7 * 3600)]
        let anchor = floor(now.timeIntervalSince1970 / 300) * 300
        movement = (1...288).compactMap { index in
            guard index % 12 < 4 else { return nil } // Deliberate gaps, not fabricated zeros.
            return MovementBucket(interval: DateInterval(start: Date(timeIntervalSince1970: anchor - Double(index) * 300), duration: 300),
                steps: Double(20 + index % 4 * 90), distanceMetres: Double(index % 4 * 60), standMinutes: 3, activeKilocalories: 8)
        }.sorted { $0.id < $1.id }
        if ProcessInfo.processInfo.arguments.contains("--journal-empty") { workouts = []; sleep = []; movement = [] }
        if ProcessInfo.processInfo.arguments.contains("--movement-missing") { movement = [] }
        if ProcessInfo.processInfo.arguments.contains("--movement-upgrade") { movement = []; movementPermissionRequested = false }
        if ProcessInfo.processInfo.arguments.contains("--movement-refreshing") { loading = true }
        if ProcessInfo.processInfo.arguments.contains("--health-disconnected") {
            enabled = false; movementPermissionRequested = false
            workouts = []; sleep = []; movement = []
        }
    }
    #endif
}
