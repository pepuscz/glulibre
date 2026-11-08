import Foundation
import CoreData
import Combine
import UIKit

/// Restored samples are read-only journal history. Never imported into sensor, alarm,
/// calibration, HealthKit-writing or transmitter databases.
final class JournalRecoveredHistory {
    static let shared = JournalRecoveredHistory()
    private let queue = DispatchQueue(label: "GluLibre.RecoveredHistory")
    private let url: URL
    private var cache: [BackupReading]?

    init(directory: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = (directory ?? support.appendingPathComponent("GluLibreRecovery", isDirectory: true))
            .appendingPathComponent("readings.json")
    }

    func all() throws -> [BackupReading] { try queue.sync { try loadLocked() } }

    private func loadLocked() throws -> [BackupReading] {
        if let cache { return cache }
        let values: [BackupReading]
        if FileManager.default.fileExists(atPath: url.path) {
            values = try JSONDecoder().decode([BackupReading].self, from: Data(contentsOf: url))
        } else { values = [] }
        cache = values
        return values
    }

    @discardableResult func merge(_ incoming: [BackupReading]) throws -> Int {
        try queue.sync {
            let old = try loadLocked()
            let merged = JournalBackupArchive.merging(existing: old, incoming: incoming)
            guard merged.count != old.count else { return 0 }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(merged).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            cache = merged
            return merged.count - old.count
        }
    }
}

struct JournalRestorePreview {
    let archive: JournalBackupArchive
    let meals: [MealRecord]
}

/// UI state and orchestration only; costly file IO and cryptography stay off the main thread.
@MainActor
final class JournalBackupController: ObservableObject {
    @Published private(set) var busy = false
    @Published var message: String?
    @Published var document: JournalBackupDocument?
    @Published var preview: JournalRestorePreview?
    @Published var showExporter = false
    @Published var lastExport = UserDefaults.standard.object(forKey: "GluLibre.backup.lastExport") as? Date

    func export(password: String, context: NSManagedObjectContext?) {
        guard !busy else { return }
        guard let context else { message = JournalBackupError.unavailable.localizedDescription; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let readings = try await Self.readings(context: context)
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
                let encrypted = try await Task.detached(priority: .userInitiated) {
                    let (meals, photos) = try MealStore.shared.backupSnapshot()
                    let all = JournalBackupArchive.merging(existing: readings, incoming: try JournalRecoveredHistory.shared.all())
                    let archive = JournalBackupArchive(createdAt: Date(), appVersion: version, mealsJSON: meals, photos: photos, readings: all)
                    try archive.validate()
                    return try JournalBackupCipher.seal(JSONEncoder().encode(archive), password: password)
                }.value
                document = JournalBackupDocument(data: encrypted)
                showExporter = true
            } catch { message = error.localizedDescription }
        }
    }

    func inspect(url: URL, password: String) {
        guard !busy else { return }
        busy = true
        preview = nil
        Task {
            defer { busy = false }
            do {
                preview = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    // Coordinate with Files providers (including downloaded documents).
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var result: Result<JournalRestorePreview, Error>?
                    coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { accessible in
                        result = Result {
                            let size = try accessible.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                            guard size <= JournalBackupCipher.maximumBytes else { throw JournalBackupError.tooLarge }
                            let encrypted = try Data(contentsOf: accessible)
                            let data = try JournalBackupCipher.open(encrypted, password: password)
                            let archive = try JSONDecoder().decode(JournalBackupArchive.self, from: data)
                            try archive.validate()
                            let meals = try Self.validatedMeals(archive)
                            return JournalRestorePreview(archive: archive, meals: meals)
                        }
                    }
                    if let coordinationError { throw coordinationError }
                    guard let result else { throw JournalBackupError.unavailable }
                    return try result.get()
                }.value
            } catch { message = error.localizedDescription }
        }
    }

    func restore(context: NSManagedObjectContext?) {
        guard !busy, let preview else { return }
        guard let context else { message = JournalBackupError.unavailable.localizedDescription; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let liveIDs = Set(try await Self.readings(context: context).map(\.id))
                let counts = try await Task.detached(priority: .userInitiated) {
                    // Validate everything before the first durable write. Both merges are idempotent:
                    // a process interruption between stores can safely be retried without duplicates.
                    try preview.archive.validate()
                    _ = try Self.validatedMeals(preview.archive)
                    guard MealStore.shared.loadError == nil else { throw JournalBackupError.unavailable }
                    let readings = try JournalRecoveredHistory.shared.merge(preview.archive.readings.filter { !liveIDs.contains($0.id) })
                    let meals = try MealStore.shared.restoreMissing(preview.meals, photos: preview.archive.photos)
                    return (meals, readings)
                }.value
                self.preview = nil
                JournalModel.shared.refresh()
                message = "Restored \(counts.0) meals and \(counts.1) readings. Existing records and sensor pairing were kept."
            } catch {
                JournalModel.shared.refresh()
                message = JournalBackupError.incompleteRestore.localizedDescription
            }
        }
    }

    func exportFinished(_ result: Result<URL, Error>) {
        document = nil
        switch result {
        case .success:
            lastExport = Date()
            UserDefaults.standard.set(lastExport, forKey: "GluLibre.backup.lastExport")
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { message = error.localizedDescription }
        }
    }

    nonisolated static func validatedMeals(_ archive: JournalBackupArchive) throws -> [MealRecord] {
        let meals = try JSONDecoder().decode([MealRecord].self, from: archive.mealsJSON)
        guard Set(meals.map(\.id)).count == meals.count,
              Set(meals.map(\.imageFilename)).count == meals.count,
              Set(meals.map(\.imageFilename)) == Set(archive.photos.keys) else { throw JournalBackupError.invalidArchive }
        for meal in meals {
            guard JournalBackupArchive.safeFilename(meal.imageFilename),
                  let photo = archive.photos[meal.imageFilename],
                  UIImage(data: photo.data) != nil,
                  meal.capturedAt.timeIntervalSince1970.isFinite,
                  meal.eatenAt.timeIntervalSince1970.isFinite else { throw JournalBackupError.invalidArchive }
            if meal.imageSHA256.count == 64, meal.imageSHA256.lowercased() != photo.sha256 {
                throw JournalBackupError.invalidArchive
            }
        }
        return meals
    }

    private static func readings(context: NSManagedObjectContext) async throws -> [BackupReading] {
        try await context.perform {
            let request = BgReading.fetchRequest()
            request.fetchBatchSize = 1_000
            return try context.fetch(request).map { reading in
                BackupReading(id: reading.id, date: reading.timeStamp, mgDl: reading.calculatedValue,
                    sensorID: reading.sensor?.id, deviceName: reading.deviceName,
                    numericAttributes: ["rawData": reading.rawData, "ageAdjustedRawValue": reading.ageAdjustedRawValue,
                        "calculatedValueSlope": reading.calculatedValueSlope, "a": reading.a, "b": reading.b,
                        "c": reading.c, "ra": reading.ra, "rb": reading.rb, "rc": reading.rc],
                    flags: ["calibrationFlag": reading.calibrationFlag, "hideSlope": reading.hideSlope])
            }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Disposable fixtures only; never touches the live journal, Health or sensor state.
    static func runSimulatorChecks() {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BackupChecks-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let source = MealStore(testDirectory: directory.appendingPathComponent("source"))
            let target = MealStore(testDirectory: directory.appendingPathComponent("target"))
            let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
            }
            var original = try source.create(image: image, requestAnalysis: true)
            original.userComment = "Original private note"
            try source.save(original)
            let (index, photos) = try source.backupSnapshot()
            let reading = BackupReading(id: "sample", date: Date().addingTimeInterval(-86400), mgDl: 103,
                sensorID: "historic", deviceName: "fixture", numericAttributes: ["rawData": 102], flags: [:])
            let archive = JournalBackupArchive(createdAt: Date(), appVersion: "test", mealsJSON: index, photos: photos, readings: [reading])
            let encrypted = try JournalBackupCipher.seal(JSONEncoder().encode(archive), password: "synthetic test password")
            let decoded = try JSONDecoder().decode(JournalBackupArchive.self,
                from: JournalBackupCipher.open(encrypted, password: "synthetic test password"))
            try decoded.validate()
            let meals = try validatedMeals(decoded)
            let firstRestore = try target.restoreMissing(meals, photos: decoded.photos)
            let repeatedRestore = try target.restoreMissing(meals, photos: decoded.photos)
            precondition(firstRestore == 1 && repeatedRestore == 0)
            var restored = target.record(id: original.id)!
            precondition(restored.analysisRequestID == nil && restored.userComment == original.userComment)
            precondition(restored.eatenAt == original.eatenAt && restored.imageSHA256 == original.imageSHA256)
            precondition(target.imageData(for: restored) == source.imageData(for: original))
            restored.userComment = "Newer local edit"
            try target.save(restored)
            let editedRestore = try target.restoreMissing(meals, photos: decoded.photos)
            precondition(editedRestore == 0)
            precondition(target.record(id: original.id)?.userComment == "Newer local edit")
            let history = JournalRecoveredHistory(directory: directory.appendingPathComponent("history"))
            let firstHistory = try history.merge([reading])
            let repeatedHistory = try history.merge([reading])
            let reopened = try JournalRecoveredHistory(directory: directory.appendingPathComponent("history")).all()
            precondition(firstHistory == 1 && repeatedHistory == 0 && reopened == [reading])
            precondition(MealStore(testDirectory: directory.appendingPathComponent("target")).all().count == 1)
            let invalid = JournalBackupArchive(createdAt: Date(), appVersion: "test", mealsJSON: index, photos: [:], readings: [])
            do { _ = try validatedMeals(invalid); preconditionFailure("Missing photo accepted") } catch {}
            NSLog("JOURNAL_BACKUP_CHECKS PASS encrypted roundtrip, photo bytes, metadata, no reupload, repeat restore, existing edit, durable history, missing photo")
        } catch { preconditionFailure("Backup checks failed: \(error)") }
    }
    #endif
}
