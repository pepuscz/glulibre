import UIKit

/// Owns analysis independently of the capture/editor UI. The journal is the durable queue.
@MainActor
final class MealAnalysisService {
    static let shared = MealAnalysisService()
    private let store: MealStore
    private let analyzeImage: (UIImage, String) async throws -> MealAnalysis
    private let hasKey: () -> Bool
    private var worker: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var held = Set<UUID>()
    private var observations: [NSObjectProtocol] = []

    init(store: MealStore = .shared, hasKey: @escaping () -> Bool = { MealAISettings.hasAPIKey },
         analyze: @escaping (UIImage, String) async throws -> MealAnalysis = { try await MealAIClient().analyze(image: $0, userComment: $1) }) {
        self.store = store; self.hasKey = hasKey; self.analyzeImage = analyze
    }

    func start() {
        guard observations.isEmpty else { return }
        for name in [UIApplication.didBecomeActiveNotification, UIApplication.didEnterBackgroundNotification, .mealStoreDidChange] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self else { return }
                    if notification.name == UIApplication.didEnterBackgroundNotification { self.held.removeAll() }
                    self.resume()
                }
            })
        }
        resume()
    }

    func hold(_ id: UUID) { held.insert(id) }
    func cancelPending() throws {
        retry?.cancel(); worker?.cancel()
        for record in store.all() where record.analysisRequestID != nil {
            try store.update(id: record.id) {
                $0.analysisRequestID = nil; $0.analysisRetryAfter = nil
                if $0.status == .analyzing { $0.status = $0.analysis == nil ? .draft : .estimated }
            }
        }
    }
    func release(_ id: UUID) { held.remove(id); resume() }
    func pauseEditing(_ id: UUID) {
        held.insert(id)
        _ = try? store.update(id: id) {
            $0.analysisRequestID = nil
            if $0.status == .analyzing { $0.status = $0.analysis == nil ? .draft : .estimated }
        }
    }

    func enqueue(_ id: UUID) throws {
        guard hasKey() else { return }
        _ = try store.update(id: id) {
            $0.analysisRequestID = UUID(); $0.analysisAttempts = 0; $0.analysisRetryAfter = nil
            $0.analysisError = nil; $0.status = .draft
        }
        resume()
    }

    func resume() {
        guard worker == nil, hasKey() else { return }
        let pending = store.all().filter { $0.analysisRequestID != nil && !held.contains($0.id) }
        guard let next = pending.first(where: { ($0.analysisRetryAfter ?? .distantPast) <= Date() }) else {
            retry?.cancel()
            if let date = pending.compactMap(\.analysisRetryAfter).min() {
                retry = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(1, date.timeIntervalSinceNow) * 1_000_000_000))
                    if !Task.isCancelled { self?.resume() }
                }
            }
            return
        }
        retry?.cancel()
        worker = Task { [weak self] in
            guard let self else { return }
            let canContinue = await self.process(next)
            self.worker = nil
            if canContinue { self.resume() }
        }
    }

    private func process(_ record: MealRecord) async -> Bool {
        guard let token = record.analysisRequestID else { return true }
        var backgroundID: UIBackgroundTaskIdentifier = .invalid
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "Meal estimate") { [weak self] in
            Task { @MainActor in self?.worker?.cancel() }
        }
        defer { if backgroundID != .invalid { UIApplication.shared.endBackgroundTask(backgroundID) } }
        do {
            guard let image = store.image(for: record) else { throw MealAIError.imageEncodingFailed }
            guard let started = try store.update(id: record.id, matching: token, {
                $0.status = .analyzing; $0.analysisAttempts = ($0.analysisAttempts ?? 0) + 1
            }) else { return true }
            let analysis = try await analyzeImage(image, started.userComment)
            try Task.checkCancellation()
            _ = try store.update(id: record.id, matching: token) {
                $0.analysis = analysis; $0.status = .estimated; $0.analysisError = nil
                $0.analysisRequestID = nil; $0.analysisRetryAfter = nil
            }
            return true
        } catch {
            let transient = (error as? URLError).map {
                [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains($0.code)
            } ?? false
            do { _ = try store.update(id: record.id, matching: token) {
                let attempts = $0.analysisAttempts ?? 1
                $0.status = .failed
                $0.analysisError = error.localizedDescription
                if (transient || Task.isCancelled) && attempts < 3 {
                    $0.analysisRetryAfter = Date().addingTimeInterval(attempts == 1 ? 30 : 120)
                } else { $0.analysisRequestID = nil; $0.analysisRetryAfter = nil }
            } } catch { return false }
            return true
        }
    }
}

#if DEBUG && targetEnvironment(simulator)
extension MealAnalysisService {
    static func runCaptureChecks() async {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("QuickMealChecks-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = MealStore(testDirectory: directory)
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            let estimate = MealAnalysis(title: "Test meal", summary: "Fixture", items: [], nutrients: .empty,
                overallConfidence: 0.5, assumptions: [], questions: [], model: "mock", analyzedAt: Date())
            let old = try store.create(image: image)
            let queued = try store.create(image: image, requestAnalysis: true)
            var calls = 0
            let service = MealAnalysisService(store: store, hasKey: { true }) { _, comment in
                calls += 1; precondition(comment == "Rice and beans"); return estimate
            }
            service.hold(queued.id); service.resume()
            precondition(service.worker == nil && calls == 0)
            try store.update(id: queued.id) { $0.userComment = "Rice and beans" }
            service.release(queued.id)
            await service.worker?.value
            precondition(calls == 1 && store.record(id: queued.id)?.status == .estimated)
            precondition(store.record(id: queued.id)?.analysisRequestID == nil)
            precondition(store.record(id: old.id)?.analysis == nil && store.image(for: old) != nil)

            let changed = try store.create(image: image, requestAnalysis: true)
            let staleService = MealAnalysisService(store: store, hasKey: { true }) { _, _ in
                try store.update(id: changed.id) { $0.analysisRequestID = UUID(); $0.userComment = "New note" }
                return estimate
            }
            _ = await staleService.process(changed)
            precondition(store.record(id: changed.id)?.analysis == nil)
            precondition(store.record(id: changed.id)?.userComment == "New note")

            let deleted = try store.create(image: image, requestAnalysis: true)
            let deleteService = MealAnalysisService(store: store, hasKey: { true }) { _, _ in
                _ = try store.delete(id: deleted.id); return estimate
            }
            _ = await deleteService.process(deleted)
            precondition(store.record(id: deleted.id) == nil)

            let interrupted = try store.create(image: image, requestAnalysis: true)
            try store.update(id: interrupted.id) { $0.status = .analyzing }
            let reopened = MealStore(testDirectory: directory)
            let resumed = reopened.record(id: interrupted.id)!
            precondition(resumed.analysisRequestID == interrupted.analysisRequestID)
            let resumeService = MealAnalysisService(store: reopened, hasKey: { true }) { _, _ in estimate }
            _ = await resumeService.process(resumed)
            precondition(reopened.record(id: interrupted.id)?.status == .estimated)

            let offline = try reopened.create(image: image, requestAnalysis: true)
            let offlineService = MealAnalysisService(store: reopened, hasKey: { true }) { _, _ in throw URLError(.notConnectedToInternet) }
            _ = await offlineService.process(offline)
            precondition(reopened.record(id: offline.id)?.analysisRetryAfter != nil)
            precondition(reopened.image(for: offline) != nil)
            for _ in 0..<2 { _ = await offlineService.process(reopened.record(id: offline.id)!) }
            precondition(reopened.record(id: offline.id)?.analysisRequestID == nil)
            precondition(reopened.record(id: offline.id)?.analysisAttempts == 3)

            let denied = try reopened.create(image: image, requestAnalysis: true)
            let noKeyService = MealAnalysisService(store: reopened, hasKey: { false }) { _, _ in preconditionFailure("No key must not upload") }
            noKeyService.resume(); precondition(noKeyService.worker == nil)
            let deniedService = MealAnalysisService(store: reopened, hasKey: { true }) { _, _ in throw MealAIError.api(status: 401, message: "Test denial") }
            _ = await deniedService.process(denied)
            precondition(reopened.record(id: denied.id)?.analysisRequestID == nil)
            precondition(reopened.record(id: denied.id)?.status == .failed)
            let optedOut = try reopened.create(image: image, requestAnalysis: true)
            try reopened.update(id: optedOut.id) { $0.status = .analyzing }
            let cancelService = MealAnalysisService(store: reopened, hasKey: { true }) { _, _ in
                preconditionFailure("Opted-out queue must not upload")
            }
            try cancelService.cancelPending()
            cancelService.resume()
            precondition(cancelService.worker == nil)
            precondition(reopened.record(id: optedOut.id)?.analysisRequestID == nil)
            precondition(reopened.record(id: optedOut.id)?.status == .draft)
            precondition(reopened.image(for: optedOut) != nil)
            NSLog("QUICK_MEAL_CHECKS PASS saved-first, note-before-upload, no historical uploads, stale/deleted-result rejection, restart recovery, bounded offline retries, no-key, API denial, opt-out cancels queue")
        } catch { preconditionFailure("Quick meal checks failed: \(error)") }
    }
}
#endif
