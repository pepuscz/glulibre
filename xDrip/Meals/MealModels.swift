import CryptoKit
import Foundation
import Security
import UIKit

enum MealStatus: String, Codable {
    case draft
    case analyzing
    case estimated
    case confirmed
    case failed

    var displayName: String {
        switch self {
        case .draft: return "Saved"
        case .analyzing: return "Analyzing…"
        case .estimated: return "AI estimate"
        case .confirmed: return "Confirmed"
        case .failed: return "Saved · estimate unavailable"
        }
    }
}

struct MealNutrients: Codable {
    var carbohydratesG: Double?
    var proteinG: Double?
    var fatG: Double?
    var fiberG: Double?
    var sugarG: Double?
    var energyKcal: Double?

    static let empty = MealNutrients(
        carbohydratesG: nil,
        proteinG: nil,
        fatG: nil,
        fiberG: nil,
        sugarG: nil,
        energyKcal: nil
    )

    var hasAnyValue: Bool {
        carbohydratesG != nil || proteinG != nil || fatG != nil || fiberG != nil || sugarG != nil || energyKcal != nil
    }
}

struct MealFoodItem: Codable {
    var name: String
    var portion: String
    var nutrients: MealNutrients
    var confidence: Double
    var evidence: String
    var foodEvidence: FoodEvidence?
}

struct MealAnalysis: Codable {
    var title: String
    var summary: String
    var items: [MealFoodItem]
    var nutrients: MealNutrients
    var overallConfidence: Double
    var assumptions: [String]
    var questions: [String]
    var model: String
    var analyzedAt: Date
}

struct MealRecord: Codable {
    var id: UUID
    var capturedAt: Date
    var eatenAt: Date
    var timeZoneIdentifier: String
    var imageFilename: String
    var imageSHA256: String
    var userComment: String
    var status: MealStatus
    var analysis: MealAnalysis?
    var analysisError: String?
    var healthKitCorrelationUUID: UUID?
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    // Optional for backward-compatible decoding. Only explicitly queued meals are uploaded.
    var analysisRequestID: UUID?
    var analysisAttempts: Int?
    var analysisRetryAfter: Date?
    // Optional, local-only correction. Never changes or re-uploads the original meal.
    var keepResponseSeparate: Bool?
    var userMealName: String?
    var userFoodItems: [MealFoodItem]?

    var foodItems: [MealFoodItem] { userFoodItems ?? analysis?.items ?? [] }

    var responseInput: FoodResponseInput {
        FoodResponseInput(id: id, date: eatenAt, timeZone: timeZoneIdentifier, title: displayTitle,
            components: foodItems.map {
                FoodComponent(name: $0.name, portion: $0.portion, confidence: $0.confidence, evidence: $0.foodEvidence)
            }, separate: keepResponseSeparate == true)
    }

    var displayTitle: String {
        if let name = userMealName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        if let title = analysis?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let trimmedComment = userComment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedComment.isEmpty ? "Meal photo" : trimmedComment
    }

    var captureStatus: String {
        analysisRequestID != nil ? (status == .analyzing ? "Analyzing…" : "Saved · analysis queued") : status.displayName
    }
}

extension Notification.Name {
    static let mealStoreDidChange = Notification.Name("MealStoreDidChange")
}

final class MealStore {
    static let shared = MealStore()

    private let queue = DispatchQueue(label: "LibreDebug.MealStore")
    private let fileManager = FileManager.default
    private let directoryURL: URL
    private let indexURL: URL
    private var records: [MealRecord] = []
    private(set) var loadError: String?

    init(testDirectory: URL? = nil) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = testDirectory ?? applicationSupport.appendingPathComponent("LibreMeals", isDirectory: true)
        indexURL = directoryURL.appendingPathComponent("meals.json")

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: indexURL.path) {
                let data = try Data(contentsOf: indexURL)
                records = try JSONDecoder().decode([MealRecord].self, from: data)
                records = records.map { record in
                    var repaired = record
                    if repaired.status == .analyzing {
                        repaired.status = .failed
                        repaired.analysisError = "Analysis was interrupted. Your photo is saved."
                    }
                    return repaired
                }
            }
        } catch {
            loadError = "Your saved journal could not be opened. It has not been changed. Unlock your iPhone and reopen the app. If this continues, keep the app installed and contact support."
            NSLog("MEAL_CAPTURE failed to initialize store: %@", error.localizedDescription)
        }
    }

    func all() -> [MealRecord] {
        queue.sync {
            records.sorted { $0.eatenAt > $1.eatenAt }
        }
    }

    func record(id: UUID) -> MealRecord? {
        queue.sync { records.first { $0.id == id } }
    }

    func create(image: UIImage, capturedAt: Date = Date(), requestAnalysis: Bool = false, id: UUID = UUID(), eatenAt: Date? = nil) throws -> MealRecord {
        try ensureAvailable()
        guard let imageData = image.mealJPEGData(maxDimension: 2048, compressionQuality: 0.86) else {
            throw MealStoreError.imageEncodingFailed
        }

        let filename = id.uuidString.lowercased() + ".jpg"
        let imageURL = directoryURL.appendingPathComponent(filename)
        try imageData.write(to: imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        let digest = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        let record = MealRecord(
            id: id,
            capturedAt: capturedAt,
            eatenAt: eatenAt ?? capturedAt,
            timeZoneIdentifier: TimeZone.current.identifier,
            imageFilename: filename,
            imageSHA256: digest,
            userComment: "",
            status: .draft,
            analysis: nil,
            analysisError: nil,
            healthKitCorrelationUUID: nil,
            revision: 1,
            createdAt: capturedAt,
            updatedAt: capturedAt,
            analysisRequestID: requestAnalysis ? UUID() : nil
        )

        do {
            try queue.sync {
                let updated = records + [record]
                try persistLocked(updated)
                records = updated
            }
        } catch {
            try? fileManager.removeItem(at: imageURL)
            throw error
        }
        notifyChanged()
        NSLog("MEAL_CAPTURE created meal=%@ imageSHA256=%@", id.uuidString, digest)
        return record
    }

    func save(_ record: MealRecord) throws {
        try ensureAvailable()
        try queue.sync {
            var updated = records
            var updatedRecord = record
            updatedRecord.updatedAt = Date()
            if let index = updated.firstIndex(where: { $0.id == updatedRecord.id }) {
                updated[index] = updatedRecord
            } else {
                updated.append(updatedRecord)
            }
            try persistLocked(updated)
            records = updated
        }
        notifyChanged()
        NSLog("MEAL_CAPTURE saved meal=%@ status=%@ revision=%d", record.id.uuidString, record.status.rawValue, record.revision)
    }

    /// Atomic edit that never recreates a deleted record. Background results use an input token.
    @discardableResult
    func update(id: UUID, matching requestID: UUID? = nil, _ mutation: (inout MealRecord) -> Void) throws -> MealRecord? {
        try ensureAvailable()
        let result: MealRecord? = try queue.sync {
            guard let index = records.firstIndex(where: { $0.id == id }),
                  requestID == nil || records[index].analysisRequestID == requestID else { return nil }
            var updated = records
            mutation(&updated[index])
            updated[index].updatedAt = Date()
            try persistLocked(updated)
            records = updated
            return updated[index]
        }
        if result != nil { notifyChanged() }
        return result
    }

    func delete(id: UUID) throws -> MealRecord? {
        try ensureAvailable()
        let deleted: MealRecord? = try queue.sync {
            guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            var updated = records
            let record = updated.remove(at: index)
            try persistLocked(updated)
            records = updated
            let imageURL = directoryURL.appendingPathComponent(record.imageFilename)
            try? fileManager.removeItem(at: imageURL)
            return record
        }
        notifyChanged()
        return deleted
    }

    func image(for record: MealRecord) -> UIImage? {
        let imageURL = directoryURL.appendingPathComponent(record.imageFilename)
        guard let data = try? Data(contentsOf: imageURL) else { return nil }
        return UIImage(data: data)
    }

    func imageData(for record: MealRecord) -> Data? {
        try? Data(contentsOf: directoryURL.appendingPathComponent(record.imageFilename))
    }

    private func ensureAvailable() throws {
        if let loadError { throw MealStoreError.unavailable(loadError) }
    }

    private func persistLocked(_ updated: [MealRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mealStoreDidChange, object: self)
        }
    }
}

enum MealStoreError: LocalizedError {
    case imageEncodingFailed
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "The meal photo could not be saved."
        case .unavailable(let message): return message
        }
    }
}

#if targetEnvironment(simulator) && DEBUG
extension MealStore {
    static func simulatorMealFixture() throws -> MealRecord {
        if var meal = shared.all().first(where: { $0.userComment.hasPrefix("SIMULATOR FIXTURE") }) {
            // Keep synthetic preview data aligned with the moving synthetic glucose window.
            meal.eatenAt = Date().addingTimeInterval(-3 * 3600)
            try shared.save(meal)
            return meal
        }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 300)).image { context in
            UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
            ("Sample meal\nSimulator only" as NSString).draw(in: CGRect(x: 30, y: 95, width: 340, height: 180), withAttributes: [.font: UIFont.systemFont(ofSize: 32, weight: .bold), .foregroundColor: UIColor.white])
        }
        var meal = try shared.create(image: image, capturedAt: Date().addingTimeInterval(-3 * 3600))
        meal.userComment = "SIMULATOR FIXTURE · Oats, yogurt and berries. Walked after breakfast."
        meal.analysis = MealAnalysis(title: "Oats, yogurt & berries", summary: "Synthetic test estimate", items: [], nutrients: MealNutrients(carbohydratesG: 35, proteinG: 12, fatG: 8, fiberG: 4, sugarG: 9, energyKcal: 260), overallConfidence: 0.5, assumptions: ["Portion is unknown"], questions: [], model: "simulator", analyzedAt: Date())
        meal.status = .estimated
        try shared.save(meal)
        return meal
    }

    /// Exercises the production store against disposable old-format fixtures, never the app's journal.
    static func runPersistenceChecks() {
        do {
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("JournalUpgradeTests-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let index = temporary.appendingPathComponent("meals.json")
            let fixture = """
            [{"id":"03214BEE-F21F-4131-9919-58D8AD67B533","capturedAt":700000000,"eatenAt":700000060,"timeZoneIdentifier":"Europe/Prague","imageFilename":"original.jpg","imageSHA256":"legacy-hash","userComment":"Original note","status":"confirmed","healthKitCorrelationUUID":"A967B7E3-D45D-4FD5-A7DE-AD467283631E","revision":4,"createdAt":700000000,"updatedAt":700000070,"analysis":{"title":"Breakfast","summary":"Reviewed estimate","items":[],"nutrients":{"carbohydratesG":35,"proteinG":12,"fatG":8,"fiberG":4,"sugarG":9,"energyKcal":260},"overallConfidence":0.6,"assumptions":[],"questions":[],"model":"legacy-model","analyzedAt":700000065}}]
            """
            try Data(fixture.utf8).write(to: index)
            let photo = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
            }
            let imageData = photo.jpegData(compressionQuality: 0.8)!
            try imageData.write(to: temporary.appendingPathComponent("original.jpg"))
            let store = MealStore(testDirectory: temporary)
            precondition(store.loadError == nil && store.all().count == 1)
            var original = store.all()[0]
            let id = original.id
            let originalTime = original.eatenAt
            let healthID = original.healthKitCorrelationUUID
            precondition(store.imageData(for: original) == imageData)
            original.userComment = "Edited after upgrade"
            try store.save(original)
            let reloaded = MealStore(testDirectory: temporary)
            let saved = reloaded.record(id: id)!
            precondition(saved.keepResponseSeparate == nil)
            let legacyItem = Data(#"{"name":"Banana","portion":"1 medium","nutrients":{},"confidence":0.9,"evidence":"Visible"}"#.utf8)
            let decodedItem = try JSONDecoder().decode(MealFoodItem.self, from: legacyItem)
            precondition(decodedItem.foodEvidence == nil && decodedItem.name == "Banana")
            var newItem = decodedItem
            newItem.foodEvidence = FoodEvidence(canonicalName: "banana", preparation: "raw", brand: nil, ripeness: "ripe", source: "visible")
            let restoredItem = try JSONDecoder().decode(MealFoodItem.self, from: JSONEncoder().encode(newItem))
            precondition(restoredItem.foodEvidence == newItem.foodEvidence)
            let properties = MealAIClient.responseSchema["properties"] as! [String: Any]
            let items = properties["items"] as! [String: Any]
            let itemSchema = items["items"] as! [String: Any]
            precondition((itemSchema["required"] as! [String]).contains("foodEvidence"))
            precondition(saved.eatenAt == originalTime && saved.healthKitCorrelationUUID == healthID)
            precondition(saved.revision == 4 && saved.analysis?.nutrients.carbohydratesG == 35)
            precondition(saved.imageSHA256 == "legacy-hash" && reloaded.imageData(for: saved) == imageData)
            precondition(saved.userComment == "Edited after upgrade")
            precondition(saved.userMealName == nil && saved.userFoodItems == nil)
            try reloaded.update(id: id) {
                $0.userMealName = "My breakfast"
                $0.userFoodItems = [newItem]
            }
            let corrected = MealStore(testDirectory: temporary).record(id: id)!
            precondition(corrected.displayTitle == "My breakfast" && corrected.foodItems.first?.name == "Banana")
            precondition(corrected.analysis?.title == "Breakfast" && corrected.healthKitCorrelationUUID == healthID)
            precondition(reloaded.imageData(for: corrected) == imageData)
            let photoTime = Date().addingTimeInterval(-7200)
            let imported = try reloaded.create(image: photo, eatenAt: photoTime)
            precondition(MealStore(testDirectory: temporary).record(id: imported.id)?.eatenAt == photoTime)

            let damaged = Data("not valid JSON".utf8)
            try damaged.write(to: index)
            let unavailable = MealStore(testDirectory: temporary)
            precondition(unavailable.loadError != nil)
            do { try unavailable.save(original); preconditionFailure("Corrupt index was writable") } catch {}
            do { _ = try unavailable.create(image: photo); preconditionFailure("Corrupt index accepted photo") } catch {}
            do { _ = try unavailable.delete(id: id); preconditionFailure("Corrupt index was deletable") } catch {}
            let unchanged = try Data(contentsOf: index)
            precondition(unchanged == damaged)

            // A failed disk write must not mutate the in-memory list either.
            try FileManager.default.removeItem(at: index)
            try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
            original.userComment = "Must not survive failed write"
            do { try reloaded.save(original); preconditionFailure("Expected write failure") } catch {}
            precondition(reloaded.record(id: id)?.userComment == "Edited after upgrade")
            NSLog("JOURNAL_UPGRADE_CHECKS PASS legacy decode, manual food overrides, import time, edit/reload, IDs, photo, nutrition, HealthKit reference, corrupt-index write protection, failed-write rollback")
        } catch { preconditionFailure("Journal persistence test failed: \(error)") }
    }
}
#endif

enum MealAISettings {
    static let defaultModel = "gpt-5-mini"
    static var automaticAnalysis: Bool {
        get { UserDefaults.standard.object(forKey: "LibreDebug.MealAI.automatic") == nil || UserDefaults.standard.bool(forKey: "LibreDebug.MealAI.automatic") }
        set { UserDefaults.standard.set(newValue, forKey: "LibreDebug.MealAI.automatic") }
    }
    static var shouldAnalyzeNewMeals: Bool { automaticAnalysis && hasAPIKey }
    private static let modelKey = "LibreDebug.MealAI.model"
    private static let healthKitKey = "LibreDebug.MealAI.writeHealthKit"
    private static let keychainAccount = "openai-api-key"

    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return stored?.isEmpty == false ? stored! : defaultModel
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean.isEmpty ? defaultModel : clean, forKey: modelKey)
        }
    }

    static var writeConfirmedMealsToHealthKit: Bool {
        get {
            guard UserDefaults.standard.object(forKey: healthKitKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: healthKitKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: healthKitKey) }
    }

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else { return nil }
        return value
    }

    static var hasAPIKey: Bool { apiKey != nil }

    static func saveAPIKey(_ value: String) throws {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            try removeAPIKey()
            return
        }

        let data = Data(clean.utf8)
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw MealKeychainError.status(updateStatus) }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw MealKeychainError.status(status) }
    }

    static func removeAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MealKeychainError.status(status)
        }
    }

    private static var keychainService: String {
        (Bundle.main.bundleIdentifier ?? "LibreDebug") + ".MealAI"
    }
}

enum MealKeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            return (SecCopyErrorMessageString(status, nil) as String?) ?? "Keychain error \(status)"
        }
    }
}

extension UIImage {
    func mealJPEGData(maxDimension: CGFloat, compressionQuality: CGFloat) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let targetSize = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.black.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: compressionQuality)
    }
}
