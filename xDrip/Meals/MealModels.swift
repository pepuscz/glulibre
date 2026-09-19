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
        case .draft: return "Not analyzed"
        case .analyzing: return "Analyzing…"
        case .estimated: return "AI estimate — review needed"
        case .confirmed: return "Confirmed"
        case .failed: return "Analysis failed"
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

    var displayTitle: String {
        if let title = analysis?.title.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let trimmedComment = userComment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedComment.isEmpty ? "Meal photo" : trimmedComment
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

    private init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = applicationSupport.appendingPathComponent("LibreMeals", isDirectory: true)
        indexURL = directoryURL.appendingPathComponent("meals.json")

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if let data = try? Data(contentsOf: indexURL) {
                records = try JSONDecoder().decode([MealRecord].self, from: data)
                records = records.map { record in
                    var repaired = record
                    if repaired.status == .analyzing {
                        repaired.status = .failed
                        repaired.analysisError = "Analysis was interrupted. Tap Analyze to retry."
                    }
                    return repaired
                }
            }
        } catch {
            records = []
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

    func create(image: UIImage, capturedAt: Date = Date()) throws -> MealRecord {
        guard let imageData = image.mealJPEGData(maxDimension: 2048, compressionQuality: 0.86) else {
            throw MealStoreError.imageEncodingFailed
        }

        let id = UUID()
        let filename = id.uuidString.lowercased() + ".jpg"
        let imageURL = directoryURL.appendingPathComponent(filename)
        try imageData.write(to: imageURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])

        let digest = SHA256.hash(data: imageData).map { String(format: "%02x", $0) }.joined()
        let record = MealRecord(
            id: id,
            capturedAt: capturedAt,
            eatenAt: capturedAt,
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
            updatedAt: capturedAt
        )

        try queue.sync {
            records.append(record)
            try persistLocked()
        }
        notifyChanged()
        NSLog("MEAL_CAPTURE created meal=%@ imageSHA256=%@", id.uuidString, digest)
        return record
    }

    func save(_ record: MealRecord) throws {
        try queue.sync {
            var updatedRecord = record
            updatedRecord.updatedAt = Date()
            if let index = records.firstIndex(where: { $0.id == updatedRecord.id }) {
                records[index] = updatedRecord
            } else {
                records.append(updatedRecord)
            }
            try persistLocked()
        }
        notifyChanged()
        NSLog("MEAL_CAPTURE saved meal=%@ status=%@ revision=%d", record.id.uuidString, record.status.rawValue, record.revision)
    }

    func delete(id: UUID) throws -> MealRecord? {
        let deleted: MealRecord? = try queue.sync {
            guard let index = records.firstIndex(where: { $0.id == id }) else { return nil }
            let record = records.remove(at: index)
            try persistLocked()
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

    private func persistLocked() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
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

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed: return "The meal photo could not be saved."
        }
    }
}

enum MealAISettings {
    private static let modelKey = "LibreDebug.MealAI.model"
    private static let healthKitKey = "LibreDebug.MealAI.writeHealthKit"
    private static let keychainAccount = "openai-api-key"

    static var model: String {
        get {
            let stored = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return stored?.isEmpty == false ? stored! : "gpt-5-mini"
        }
        set {
            let clean = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(clean.isEmpty ? "gpt-5-mini" : clean, forKey: modelKey)
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
        SecItemDelete(baseQuery as CFDictionary)

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
