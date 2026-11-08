import Foundation
import CryptoKit
import CommonCrypto

enum JournalStoragePolicy {
    static let cleanupKey = "GluLibre.storage.automaticCleanup"
    /// Preserve explicit legacy choices; an inherited default isn't user consent to deletion.
    static func removesOldHistory(_ defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: cleanupKey) != nil { return defaults.bool(forKey: cleanupKey) }
        return defaults.object(forKey: "retentionPeriodInDays") != nil
    }
}

/// Portable history, not transmitter state. Restoring this never feeds the live CGM engine.
struct BackupReading: Codable, Equatable {
    let id: String
    let date: Date
    let mgDl: Double
    let sensorID: String?
    let deviceName: String?
    let numericAttributes: [String: Double]
    let flags: [String: Bool]
}

struct BackupPhoto: Codable {
    let data: Data
    let sha256: String

    init(data: Data) {
        self.data = data
        sha256 = Self.digest(data)
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

struct JournalBackupArchive: Codable {
    var version = 1
    let createdAt: Date
    let appVersion: String
    let mealsJSON: Data
    let photos: [String: BackupPhoto]
    let readings: [BackupReading]

    func validate() throws {
        guard version == 1 else { throw JournalBackupError.unsupportedVersion }
        guard createdAt.timeIntervalSince1970.isFinite,
              mealsJSON.count <= 32 * 1024 * 1024,
              photos.count <= 20_000, readings.count <= 2_000_000 else {
            throw JournalBackupError.invalidArchive
        }
        for (name, photo) in photos {
            guard Self.safeFilename(name), !photo.data.isEmpty,
                  photo.data.count <= 25 * 1024 * 1024,
                  photo.sha256 == BackupPhoto.digest(photo.data) else {
                throw JournalBackupError.invalidArchive
            }
        }
        for reading in readings {
            guard !reading.id.isEmpty, reading.id.count <= 512,
                  reading.date.timeIntervalSince1970.isFinite,
                  reading.date >= Date(timeIntervalSince1970: 946684800),
                  reading.date <= Date().addingTimeInterval(300),
                  reading.mgDl.isFinite,
                  reading.numericAttributes.values.allSatisfy({ $0.isFinite }) else {
                throw JournalBackupError.invalidArchive
            }
        }
        guard Set(readings.map(\.id)).count == readings.count else {
            throw JournalBackupError.invalidArchive
        }
    }

    static func safeFilename(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 255 && name != "." && name != ".."
            && !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }

    /// Existing readings win. IDs preserve distinct sensors at the same timestamp.
    static func merging(existing: [BackupReading], incoming: [BackupReading]) -> [BackupReading] {
        var ids = Set(existing.map(\.id))
        return (existing + incoming.filter { ids.insert($0.id).inserted }).sorted { $0.date < $1.date }
    }
}

/// Versioned, authenticated encryption. Fixed KDF cost cannot be attacker-controlled.
/// Header + 16 random salt bytes + AES-256-GCM combined nonce/ciphertext/tag.
enum JournalBackupCipher {
    static let maximumBytes = 256 * 1024 * 1024
    private static let header = Data("GLULIBRE-BACKUP-1\n".utf8)
    private static let iterations: UInt32 = 600_000

    static func seal(_ plaintext: Data, password: String) throws -> Data {
        guard password.count >= 12, password.utf8.count <= 1024 else { throw JournalBackupError.passwordLength }
        guard plaintext.count <= maximumBytes - 1024 else { throw JournalBackupError.tooLarge }
        var salt = Data(count: 16)
        let status = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 16, $0.baseAddress!) }
        guard status == errSecSuccess else { throw JournalBackupError.encryptionFailed }
        let key = try derive(password: password, salt: salt)
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: header + salt)
        guard let combined = box.combined else { throw JournalBackupError.encryptionFailed }
        return header + salt + combined
    }

    static func open(_ encrypted: Data, password: String) throws -> Data {
        guard encrypted.count <= maximumBytes else { throw JournalBackupError.tooLarge }
        guard encrypted.count >= header.count + 16 + 28, encrypted.starts(with: header) else {
            throw JournalBackupError.invalidArchive
        }
        guard !password.isEmpty, password.utf8.count <= 1024 else { throw JournalBackupError.passwordLength }
        let salt = encrypted.subdata(in: header.count..<(header.count + 16))
        let key = try derive(password: password, salt: salt)
        do {
            return try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted.dropFirst(header.count + 16)),
                                    using: key, authenticating: header + salt)
        } catch { throw JournalBackupError.cannotDecrypt }
    }

    private static func derive(password: String, salt: Data) throws -> SymmetricKey {
        let passwordBytes = Array(password.utf8)
        var derived = Data(count: 32)
        let result = derived.withUnsafeMutableBytes { output in
            salt.withUnsafeBytes { saltBytes in
                passwordBytes.withUnsafeBytes { passwordBuffer in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBuffer.baseAddress!.assumingMemoryBound(to: Int8.self), passwordBytes.count,
                        saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations,
                        output.baseAddress!.assumingMemoryBound(to: UInt8.self), 32)
                }
            }
        }
        guard result == kCCSuccess else { throw JournalBackupError.encryptionFailed }
        defer { derived.resetBytes(in: 0..<derived.count) }
        return SymmetricKey(data: derived)
    }
}

enum JournalBackupError: LocalizedError {
    case invalidArchive, unsupportedVersion, tooLarge, cannotDecrypt, passwordLength, encryptionFailed
    case unavailable, incompleteRestore
    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "This backup is incomplete or damaged. Your existing data has not been replaced."
        case .unsupportedVersion: return "This backup needs a newer version of GluLibre."
        case .tooLarge: return "This journal exceeds the 256 MB backup limit. Your data is still on this iPhone."
        case .cannotDecrypt: return "The password is incorrect or the backup is damaged."
        case .passwordLength: return "Use a password of at least 12 characters (up to 1,024 UTF-8 bytes)."
        case .encryptionFailed: return "The backup could not be encrypted. Please try again."
        case .unavailable: return "Your journal is not available yet. Unlock your iPhone and try again."
        case .incompleteRestore: return "Restore did not finish. Existing records are safe. Try the same backup again; duplicates will be skipped."
        }
    }
}
