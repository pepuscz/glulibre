import AVFoundation
import Foundation
import OSLog
import UserNotifications

#if canImport(CoreNFC)
@preconcurrency import CoreNFC

// source : https://github.com/gui-dos/DiaBLE/tree/master/DiaBLE

fileprivate struct NFCCommand {
    let code: UInt8
    let parameters: Data
}

// source : https://github.com/gui-dos/DiaBLE/tree/master/DiaBLE class Sensor
fileprivate enum Subcommand: UInt8, CustomStringConvertible {
    case activate = 0x1B
    case enableStreaming = 0x1E
    case unknown0x1a = 0x1A
    case unknown0x1c = 0x1C
    case unknown0x1d = 0x1D
    case unknown0x1f = 0x1F
    
    var description: String {
        switch self {
        case .activate: return "activate"
        case .enableStreaming: return "enable BLE streaming"
        default: return "[unknown: 0x\(String(format: "%x", rawValue))]"
        }
    }
}

#if DEBUG
/// Diagnostic Libre 2 NFC operations are deliberately split so an activation
/// scan can never fall through into the normal BLE handoff in the same session.
enum LibreDebugNFCSessionMode {
    case activationOnly
    case enableStreamingOnly
}
#endif

// MARK: - Async CoreNFC helpers (avoid capturing self inside SDK callbacks)

fileprivate func customCommandAsync(tag: NFCISO15693Tag, requestFlags: NFCISO15693RequestFlag = .highDataRate, code: Int, params: Data) async throws -> Data {
    try await withCheckedThrowingContinuation { cont in
        tag.customCommand(requestFlags: requestFlags, customCommandCode: code, customRequestParameters: params) { response, error in
            if let error = error {
                cont.resume(throwing: error)
            } else {
                cont.resume(returning: response)
            }
        }
    }
}

fileprivate func readMultipleBlocksAsync(tag: NFCISO15693Tag, requestFlags: NFCISO15693RequestFlag = [.highDataRate, .address], blockRange: NSRange) async throws -> [Data] {
    try await withCheckedThrowingContinuation { cont in
        tag.readMultipleBlocks(requestFlags: requestFlags, blockRange: blockRange) { blockArray, error in
            if let error = error {
                cont.resume(throwing: error)
            } else {
                cont.resume(returning: blockArray)
            }
        }
    }
}

fileprivate func extendedWriteSingleBlockAsync(tag: NFCISO15693Tag, blockNumber: Int, dataBlock: Data) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        tag.extendedWriteSingleBlock(requestFlags: .highDataRate, blockNumber: blockNumber, dataBlock: dataBlock) { error in
            if let error = error {
                cont.resume(throwing: error)
            } else {
                cont.resume(returning: ())
            }
        }
    }
}

fileprivate func writeMultipleBlocksAsync(tag: NFCISO15693Tag, blockRange: NSRange, dataBlocks: [Data]) async throws {
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        tag.writeMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: blockRange, dataBlocks: dataBlocks) { error in
            if let error = error {
                cont.resume(throwing: error)
            } else {
                cont.resume(returning: ())
            }
        }
    }
}

// Wrapper to allow capturing the ISO15693 tag inside @Sendable closures
private final class NFCISO15693TagWrapper: @unchecked Sendable {
    let tag: NFCISO15693Tag
    init(_ tag: NFCISO15693Tag) { self.tag = tag }
}

class LibreNFC: NSObject, NFCTagReaderSessionDelegate {
    // MARK: - properties
    
    /// for trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryLibreNFC)
    static let diagnosticWarmupNotificationIdentifierPrefix = "LibreDebugWarmupComplete."
    
    /// will be used to pass back info like sensorUid , patchInfo to delegate
    private(set) weak var libreNFCDelegate: LibreNFCDelegate?
    
    /// fixed unlock code to use
    private let unlockCode: UInt32 = 42
    
    /// use to keep track of if a successful NFC scan has happened
    private var nfcScanSuccessful: Bool = false

#if DEBUG
    /// A fresh sensor activation and a BLE streaming handoff are separate,
    /// explicit operations. This mirrors DiaBLE's Activate / RePair controls
    /// and prevents an automatic fall-through after A1 1B.
    private let diagnosticMode: LibreDebugNFCSessionMode

    /// A successful activation-only session is not a completed BLE handoff.
    /// Keep it separate from nfcScanSuccessful so invalidation never starts a
    /// Bluetooth scan.
    private var activationOnlySucceeded = false

    static let diagnosticWarmupSeconds: TimeInterval = 60 * 60
    private static func diagnosticActivationAttemptKey(sensorUID: Data) -> String {
        // v3 is the first attempt that mirrors DiaBLE's complete activation
        // transaction, including its immediate 43-block FRAM reread.
        "LibreDebugUpstreamDiaBLEActivationAttemptIssued.v3." + sensorUID.toHexString()
    }

    private static func diagnosticActivationAcceptedAtKey(sensorUID: Data) -> String {
        "LibreDebugDiaBLEActivationAcceptedAt." + sensorUID.toHexString()
    }

    static func diagnosticActivationAcceptedAt(sensorUID: Data) -> Date? {
        let timestamp = UserDefaults.standard.double(forKey: diagnosticActivationAcceptedAtKey(sensorUID: sensorUID))
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    static func diagnosticActivationAttemptIssued(sensorUID: Data) -> Bool {
        UserDefaults.standard.bool(forKey: diagnosticActivationAttemptKey(sensorUID: sensorUID))
    }

    static func diagnosticWarmupSecondsRemaining(sensorUID: Data, now: Date = Date()) -> TimeInterval? {
        guard let acceptedAt = diagnosticActivationAcceptedAt(sensorUID: sensorUID) else { return nil }
        return max(0, diagnosticWarmupSeconds - now.timeIntervalSince(acceptedAt))
    }

    static func scheduleDiagnosticWarmupNotification(sensorUID: Data) {
        guard let acceptedAt = diagnosticActivationAcceptedAt(sensorUID: sensorUID) else { return }

        let readyAt = acceptedAt.addingTimeInterval(diagnosticWarmupSeconds)
        let delay = readyAt.timeIntervalSinceNow
        guard delay > 0 else { return }

        let center = UNUserNotificationCenter.current()
        let identifier = diagnosticWarmupNotificationIdentifierPrefix + sensorUID.toHexString()

        let schedule = {
            // Permission may have taken time; never restart the countdown from its old delay.
            let remaining = readyAt.timeIntervalSinceNow
            guard remaining > 0 else { return }
            let content = UNMutableNotificationContent()
            content.title = "Sensor warm-up finished"
            content.body = "Open \(ConstantsHomeView.applicationName) to check your sensor and finish setup if needed."
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, remaining), repeats: false)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            // The same sensor identifier replaces its pending request; never queue a second timer.
            center.add(request) { error in
                let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryLibreNFC)
                if let error {
                    xdrip.trace("LIBRE_DIAG failed to schedule warm-up notification: %{public}@", log: log, category: ConstantsLog.categoryLibreNFC, type: .error, error.localizedDescription)
                } else {
                    xdrip.trace("LIBRE_DIAG scheduled warm-up notification readyAt=%{public}@ delaySeconds=%{public}@", log: log, category: ConstantsLog.categoryLibreNFC, type: .info, readyAt.description, Int(delay).description)
                }
            }
        }

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule()
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { schedule() }
                }
            case .denied:
                let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryLibreNFC)
                xdrip.trace("LIBRE_DIAG warm-up notification not scheduled because notifications are denied", log: log, category: ConstantsLog.categoryLibreNFC, type: .error)
            @unknown default:
                break
            }
        }
    }
#endif
    
    /// use to keep track of the sensor serial number so that we can pass it back to the delegate
    private var serialNumber: String = ""
    
    /// use to keep track of the sensor mac address so that we can pass it back to the delegate (for new Libre 2 Plus)
    private var macAddress: String = ""
    
    // MARK: - initalizer
    
    #if DEBUG
    init(libreNFCDelegate: LibreNFCDelegate, diagnosticMode: LibreDebugNFCSessionMode = .enableStreamingOnly) {
        self.libreNFCDelegate = libreNFCDelegate
        self.diagnosticMode = diagnosticMode
    }
    #else
    init(libreNFCDelegate: LibreNFCDelegate) {
        self.libreNFCDelegate = libreNFCDelegate
    }
    #endif
    
    // MARK: - public functions
    
    public func startSession() {
        guard NFCTagReaderSession.readingAvailable else {
            xdrip.trace("NFC: NFC is not available@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
            
            return
        }
        
        if let tagSession = NFCTagReaderSession(pollingOption: [.iso15693], delegate: self, queue: .main) {
            // make sure the this is (re)set to false before we start scanning
            self.nfcScanSuccessful = false
            
#if DEBUG
            switch diagnosticMode {
            case .activationOnly:
                tagSession.alertMessage = "Hold the top of the iPhone near the sensor until activation is confirmed."
            case .enableStreamingOnly:
                tagSession.alertMessage = "Keep the iPhone's top edge on the sensor until TWO strong completion vibrations."
            }
#else
            tagSession.alertMessage = TextsLibreNFC.holdTopOfIphoneNearSensor
#endif
            
            tagSession.begin()
        }
    }
    
    // MARK: - NFCTagReaderSessionDelegate functions
    
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        xdrip.trace("NFC: tag reader session did become active. Waiting to detect tag/sensor.", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        xdrip.trace("LIBRE_DIAG NFC session invalidated successful=%{public}@ domain=%{public}@ code=%{public}@ error=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, self.nfcScanSuccessful.description, (error as NSError).domain, (error as NSError).code.description, error.localizedDescription)
        if let readerError = error as? NFCReaderError {
            switch readerError.code {
            case .readerSessionInvalidationErrorSessionTimeout:
                
                xdrip.trace("NFC: scan time-out error", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                
            case .readerSessionInvalidationErrorUserCanceled:

                xdrip.trace("NFC: user cancelled the NFC scan", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                
            default:
                
                var debugInfo = "NFC: scan error code: " + readerError.errorCode.description
                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                
                debugInfo = "NFC: scan error message: " + readerError.localizedDescription
                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
            }
            
#if DEBUG
            if self.activationOnlySucceeded {
                xdrip.trace("LIBRE_DIAG activation-only NFC session completed; deliberately not starting BLE or another NFC scan", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                self.libreNFCDelegate?.activationCompleted()
                return
            }
#endif
            // if we have generated a successful NFC scan and been able to correctly parse out the needed data, then inform the user and start BLE scanning. If not, inform the user and offer to scan again
            if self.nfcScanSuccessful {
                xdrip.trace("NFC: passing NFC scan successful to the delegate and starting BLE scanning", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                
                self.libreNFCDelegate?.nfcScanResult(successful: true)
                
                self.libreNFCDelegate?.nfcScanExpectedDevice(serialNumber: self.serialNumber, macAddress: self.macAddress)
                
                self.libreNFCDelegate?.startBLEScanning()
                
            } else {
                xdrip.trace("NFC: passing NFC scan error to the delegate", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                
                // In the diagnostic handoff build, vibration has one meaning:
                // the six-byte streaming response was received successfully.
#if !DEBUG
                AudioServicesPlaySystemSound(1107)
#endif
                
                self.libreNFCDelegate?.nfcScanResult(successful: false)
            }
        }
    }
    
    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        xdrip.trace("NFC: did detect tags", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)

        guard let firstTag = tags.first else { return }
        guard case .iso15693(let tag) = firstTag else { return }

        Task { @MainActor in
            session.alertMessage = "Sensor found. Keep holding while its state is verified."
            let blocks = 43
            let requestBlocks = 3
            let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
            let remainder = blocks % requestBlocks
            var dataArray = [Data](repeating: Data(), count: blocks)

            var patchInfo = Data()
            var systemInfo: NFCISO15693SystemInfo!

            let retries = ConstantsLibre.retryAttemptsForLibre2NFCScans
            var requestedRetry = 0

            // Connect with retries
            while true {
                do {
                    if requestedRetry > 0 {
                        let debugInfo = "NFC: connecting to tag, retry attempt # \(requestedRetry)/\(retries)"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                        let alertMessage = TextsLibreNFC.nfcErrorMessageScanErrorRetrying + requestedRetry.description + "/" + retries.description
                        session.alertMessage = alertMessage

                        self.scanRepeatHapticFeedback()
                        try await Task.sleep(nanoseconds: 200000000)
                    } else {
                        xdrip.trace("NFC: connecting to tag", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                    }

                    try await session.connect(to: firstTag)
                    break
                } catch {
                    xdrip.trace("NFC:       error: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, error.localizedDescription)

                    if requestedRetry >= retries {
                        let debugInfo = "NFC:       fatal error: stopped trying to connect after \(requestedRetry) attempts: \(error.localizedDescription)"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                        session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
                        return
                    }

                    requestedRetry += 1
                }
            }

            xdrip.trace("NFC:     - tag response OK, now let's get systemInfo and patchInfo", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
            requestedRetry = 0

            // Get systemInfo + patchInfo with retries
            while true {
                do {
                    // Libre 3 workaround: call A1 before systemInfo
                    patchInfo = try await customCommandAsync(tag: tag, code: 0xA1, params: Data())
                    if requestedRetry == 0 {
                        xdrip.trace("NFC:     calling 0xA1 before getting sytemInfo", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                    } else {
                        let debugInfo = "NFC:     calling 0xA1 before getting sytemInfo - retry attempt # \(requestedRetry)/\(retries)"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    }

                    systemInfo = try await tag.systemInfo(requestFlags: .highDataRate)
                    if requestedRetry == 0 {
                        xdrip.trace("NFC:     getting tag sytemInfo", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                    } else {
                        let debugInfo = "NFC:     getting tag sytemInfo, retry attempt # \(requestedRetry)/\(retries)"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                    }

                    self.scanRepeatHapticFeedback()
                    break
                } catch {
                    let debugInfo = "NFC:     - error while getting tag info: \(error.localizedDescription)"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                    if requestedRetry >= retries {
                        let debugInfo = "NFC:     fatal error: stopped retrying to get tag systemInfo after \(requestedRetry) attempts"
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                        session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
                        return
                    }

                    requestedRetry += 1
                }
            }

            // Best-effort refresh
            do {
                patchInfo = try await customCommandAsync(tag: tag, code: 0xA1, params: Data())
            } catch {
                // keep previous patchInfo if this fails
            }

            xdrip.trace("NFC:     systemInfo and patchInfo retrieved. Let's try and process them.", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)

            // Read FRAM blocks
            for i in 0 ..< requests {
                let start = UInt8(i * requestBlocks)
                let end = UInt8(i * requestBlocks + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0))
                var blockRetry = 0

                while true {
                    do {
                        let blocks = try await readMultipleBlocksAsync(tag: tag, blockRange: NSRange(start ... end))
                        for j in 0 ..< blocks.count {
                            dataArray[i * requestBlocks + j] = blocks[j]
                        }
                        break
                    } catch {
                        let debugInfo = "NFC: error while reading multiple blocks (#\(start) - #\(end)), retry \(blockRetry)/\(retries): " + error.localizedDescription
                        xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                        guard blockRetry < retries else {
                            session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
                            return
                        }

                        blockRetry += 1
                        session.alertMessage = TextsLibreNFC.holdTopOfIphoneNearSensor
                        try? await Task.sleep(nanoseconds: 150_000_000)

                        // A transient ISO15693 field drop invalidates the tag
                        // connection but not necessarily the reader session.
                        // Reconnect to the same detected tag and retry only the
                        // missing chunk instead of discarding all prior blocks.
                        do {
                            try await session.connect(to: firstTag)
                            xdrip.trace("NFC: reconnected to tag for blocks #%{public}@ - #%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, start.description, end.description)
                        } catch {
                            xdrip.trace("NFC: reconnect attempt for blocks #%{public}@ - #%{public}@ failed: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, start.description, end.description, error.localizedDescription)
                        }
                    }
                }
            }

            var fram = Data()
            var msg = ""
            for (n, data) in dataArray.enumerated() {
                if data.count > 0 {
                    fram.append(data)
                    msg += "NFC: block #\(String(format: "%02d", n))  \(data.reduce("") { $0 + String(format: "%02X", $1) + " " }.dropLast())\n"
                }
            }
            if !msg.isEmpty {
                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, String(msg.dropLast()))
            }

            self.traceICIdentifier(tag: tag)
            self.traceICManufacturer(tag: tag)
            self.traceICSerialNumber(tag: tag)
            self.traceROM(tag: tag)
            self.traceICReference(systemInfo: systemInfo)
            self.traceApplicationFamilyIdentifier(systemInfo: systemInfo)
            self.traceDataStorageFormatIdentifier(systemInfo: systemInfo)
            self.traceMemorySize(systemInfo: systemInfo)
            self.traceBlockSize(systemInfo: systemInfo)

            let sensorUID = Data(tag.identifier.reversed())
            guard patchInfo.count >= 6 else {
                xdrip.trace("NFC: received patchInfo has length < 6", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info)
                session.invalidate(errorMessage: TextsLibreNFC.nfcErrorMessageScanFailed)
                return
            }

            let sensorType = LibreSensorType.type(patchInfo: patchInfo.toHexString())
            xdrip.trace("LIBRE_DIAG NFC payload sensorType=%{public}@ sensorUID=%{public}@ patchInfo=%{public}@ framBytes=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, sensorType?.description ?? "unknown", sensorUID.toHexString(), patchInfo.toHexString(), fram.count.description)

            self.libreNFCDelegate?.received(sensorUID: sensorUID, patchInfo: patchInfo)
            self.traceSensorUID(sensorUID: sensorUID)
            self.tracePatchInfo(patchInfo: patchInfo)

#if DEBUG
            // Decode the sensor state before issuing any state-changing
            // command. A fresh Libre reports state 0x01 and age 0; enabling
            // streaming alone does not activate it or start BLE broadcasts.
            func decodedStateAndAge(_ encryptedFram: Data) -> (state: LibreSensorState, age: Int, stateByte: UInt8, decodingPatchInfo: Data)? {
                guard let sensorType,
                      encryptedFram.count >= 318
                else { return nil }

                // A Libre 2's current NFC patch info can differ from the
                // value captured when streaming was enabled. Try both, but
                // never trust state/age unless all three FRAM CRCs validate.
                var candidatePatchInfos = [patchInfo]
                if let initialPatchInfo = UserDefaults.standard.libreInitialPatchInfo,
                   initialPatchInfo.count >= 6,
                   initialPatchInfo != patchInfo {
                    candidatePatchInfos.append(initialPatchInfo)
                }

                for candidatePatchInfo in candidatePatchInfos {
                    var decodedFram = encryptedFram
                    guard sensorType.decryptIfPossibleAndNeeded(rxBuffer: &decodedFram, headerLength: 0, log: nil, patchInfo: candidatePatchInfo.toHexString(), uid: Array(sensorUID)),
                          decodedFram.count >= 318
                    else { continue }

                    var crcBuffer = decodedFram
                    let crcValid = sensorType.crcIsOk(rxBuffer: &crcBuffer, headerLength: 0, log: nil)
                    xdrip.trace("LIBRE_DIAG FRAM candidate patch=%{public}@ crcValid=%{public}@ stateByte=%{public}@ ageMinutes=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: crcValid ? .info : .error, candidatePatchInfo.toHexString(), crcValid.description, String(format: "0x%02X", decodedFram[4]), (Int(decodedFram[316]) + (Int(decodedFram[317]) << 8)).description)
                    guard crcValid else { continue }

                    let stateByte = decodedFram[4]
                    let state = LibreSensorState(stateByte: stateByte)
                    let age = Int(decodedFram[316]) + (Int(decodedFram[317]) << 8)
                    return (state, age, stateByte, candidatePatchInfo)
                }

                return nil
            }

            guard let decodedStatus = decodedStateAndAge(fram) else {
                xdrip.trace("LIBRE_DIAG refusing sensor command: unable to decode state/age", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error)
                session.invalidate(errorMessage: "Unable to verify the sensor state.")
                return
            }

            xdrip.trace("LIBRE_DIAG CRC-validated NFC state=%{public}@ stateByte=%{public}@ ageMinutes=%{public}@ decodingPatch=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, decodedStatus.state.description, String(format: "0x%02X", decodedStatus.stateByte), decodedStatus.age.description, decodedStatus.decodingPatchInfo.toHexString())

            switch diagnosticMode {
            case .activationOnly:
                // DiaBLE classifies both C6 and 7F 0E 31 01 as non-Gen2
                // European Libre 2 Plus sensors. They share the legacy Libre 2
                // A1/1B activation path; 7F differs later by advertising the
                // MAC address returned by A1/1E instead of ABBOTT + serial.
                guard sensorType == .libre2C6 || sensorType == .libre27F else {
                    xdrip.trace("LIBRE_DIAG refusing activation-only command for unsupported sensor type %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, sensorType?.description ?? "unknown")
                    session.invalidate(errorMessage: "This diagnostic activation supports only Libre 2 Plus C6 and 7F.")
                    return
                }

                if decodedStatus.state == .notYetStarted {
                    guard decodedStatus.age == 0 else {
                        xdrip.trace("LIBRE_DIAG refusing activation: not-started sensor has nonzero age %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, decodedStatus.age.description)
                        session.invalidate(errorMessage: "The sensor state is inconsistent and was not changed.")
                        return
                    }

                    // This is a new, explicitly authorized test of the current
                    // upstream DiaBLE activation path. Persist both the lock and
                    // one-shot consumption before A1 1B so CoreBluetooth cannot
                    // race the NFC transaction and relaunching cannot repeat it.
                    let activationAttemptKey = Self.diagnosticActivationAttemptKey(sensorUID: sensorUID)
                    guard !UserDefaults.standard.bool(forKey: activationAttemptKey) else {
                        xdrip.trace("LIBRE_DIAG refusing activation: the upstream DiaBLE v3 attempt for sensor %{public}@ was already issued", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, sensorUID.toHexString())
                        session.invalidate(errorMessage: "This activation attempt was already used.")
                        return
                    }

                    let provisionalAcceptedAt = Date()
                    UserDefaults.standard.set(provisionalAcceptedAt.timeIntervalSince1970, forKey: Self.diagnosticActivationAcceptedAtKey(sensorUID: sensorUID))
                    UserDefaults.standard.set(true, forKey: activationAttemptKey)

                    let activationCommand = self.nfcCommand(.activate, unlockCode: self.unlockCode, patchInfo: patchInfo, sensorUID: sensorUID)
                    xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 activation command=0x%{public}@ parameters=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, String(format: "%02X", activationCommand.code), activationCommand.parameters.toHexString())

                    var activationAcknowledged = false
                    var framToPersist = fram
                    do {
                        let activationResponse = try await customCommandAsync(tag: tag, code: Int(activationCommand.code), params: activationCommand.parameters)
                        xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 activation response bytes=%{public}@ data=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, activationResponse.count.description, activationResponse.toHexString())

                        guard activationResponse.count == 4,
                              activationResponse.prefix(2) == patchInfo.prefix(2),
                              activationResponse.suffix(2) == Data([0x10, 0x00])
                        else {
                            xdrip.trace("LIBRE_DIAG activation-only response failed validation", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error)
                            session.invalidate(errorMessage: "The sensor rejected activation.")
                            return
                        }
                        activationAcknowledged = true

                        // DiaBLE immediately rereads all 43 FRAM blocks after
                        // A1 1B using only .highDataRate, three blocks per
                        // request, five global retries, and a 250 ms retry
                        // delay. Keep this deliberately separate from xDrip's
                        // normal chunk reader so the comparison is exact.
                        var postActivationFram = Data()
                        var remainingBlocks = 43
                        var requestedBlocks = 3
                        var readRetry = 0
                        let upstreamReadRetries = 5

                        while remainingBlocks > 0 && readRetry <= upstreamReadRetries {
                            let blockToRead = postActivationFram.count / 8

                            do {
                                let blockData = try await readMultipleBlocksAsync(
                                    tag: tag,
                                    requestFlags: .highDataRate,
                                    blockRange: NSRange(location: blockToRead, length: requestedBlocks)
                                )
                                for block in blockData {
                                    postActivationFram += block
                                }
                                remainingBlocks -= requestedBlocks
                                if remainingBlocks != 0 && remainingBlocks < requestedBlocks {
                                    requestedBlocks = remainingBlocks
                                }
                            } catch {
                                xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 post-activation FRAM read error block=%{public}@ retry=%{public}@/%{public}@ error=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, blockToRead.description, readRetry.description, upstreamReadRetries.description, error.localizedDescription)
                                readRetry += 1
                                if readRetry <= upstreamReadRetries {
                                    self.scanRepeatHapticFeedback()
                                    try await Task.sleep(nanoseconds: 250_000_000)
                                } else {
                                    throw error
                                }
                            }
                        }

                        if postActivationFram.count == 43 * 8,
                           let postActivationStatus = decodedStateAndAge(postActivationFram) {
                            xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 immediate state=%{public}@ stateByte=%{public}@ ageMinutes=%{public}@ framBytes=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, postActivationStatus.state.description, String(format: "0x%02X", postActivationStatus.stateByte), postActivationStatus.age.description, postActivationFram.count.description)
                            framToPersist = postActivationFram
                        } else {
                            xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 immediate FRAM reread incompleteOrUndecodable bytes=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, postActivationFram.count.description)
                        }
                    } catch {
                        let nsError = error as NSError
                        xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 activation/post-read ended domain=%{public}@ code=%{public}@ error=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, nsError.domain, nsError.code.description, error.localizedDescription)
                        guard activationAcknowledged else {
                            session.invalidate(errorMessage: "Sensor activation failed and was not retried.")
                            return
                        }
                    }

                    let acceptedAt = Date()
                    UserDefaults.standard.set(acceptedAt.timeIntervalSince1970, forKey: Self.diagnosticActivationAcceptedAtKey(sensorUID: sensorUID))
                    Self.scheduleDiagnosticWarmupNotification(sensorUID: sensorUID)
                    UserDefaults.standard.removeObject(forKey: "LibreDebugActivationVerified")
                    UserDefaults.standard.libreInitialPatchInfo = nil
                    UserDefaults.standard.libreActiveSensorUnlockCount = 0
                    self.libreNFCDelegate?.received(fram: framToPersist)

                    xdrip.trace("LIBRE_DIAG upstream DiaBLE v3 transaction ended at %{public}@; entering hard 60-minute NFC/BLE lockout", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, acceptedAt.description)
                    session.alertMessage = "DiaBLE activation test complete. Move the phone away and do not scan for 60 minutes."
                    self.commandCompletionHapticFeedback()
                    self.activationOnlySucceeded = true
                    session.invalidate()
                    return
                }

                // If a prior activation took effect before this deliberately
                // isolated scan, record its approximate start and still stop.
                if decodedStatus.state == .starting || decodedStatus.state == .ready {
                    let acceptedAt = Date().addingTimeInterval(-TimeInterval(decodedStatus.age * 60))
                    if Self.diagnosticActivationAcceptedAt(sensorUID: sensorUID) == nil {
                        UserDefaults.standard.set(acceptedAt.timeIntervalSince1970, forKey: Self.diagnosticActivationAcceptedAtKey(sensorUID: sensorUID))
                    }
                    self.libreNFCDelegate?.received(fram: fram)
                    xdrip.trace("LIBRE_DIAG activation-only scan found sensor already %{public}@ age=%{public}@; no command sent", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, decodedStatus.state.description, decodedStatus.age.description)
                    session.alertMessage = "Sensor is already warming or active. No command was sent."
                    self.activationOnlySucceeded = true
                    session.invalidate()
                    return
                }

                xdrip.trace("LIBRE_DIAG refusing activation-only command for sensor state %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, decodedStatus.state.description)
                session.invalidate(errorMessage: "The sensor is not in an activatable state.")
                return

            case .enableStreamingOnly:
                guard let secondsRemaining = Self.diagnosticWarmupSecondsRemaining(sensorUID: sensorUID) else {
                    xdrip.trace("LIBRE_DIAG refusing streaming: no successful activation-only timestamp exists for sensor %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, sensorUID.toHexString())
                    session.invalidate(errorMessage: "Activate this sensor with the diagnostic activation scan first.")
                    return
                }

                guard secondsRemaining <= 0 else {
                    let minutesRemaining = Int(ceil(secondsRemaining / 60))
                    xdrip.trace("LIBRE_DIAG hard warm-up lockout refused streaming with %{public}@ seconds remaining", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, Int(secondsRemaining).description)
                    session.invalidate(errorMessage: "Warm-up lock: wait another \(minutesRemaining) minute(s). No command was sent.")
                    return
                }

                guard decodedStatus.state == .ready else {
                    xdrip.trace("LIBRE_DIAG refusing streaming after lockout: CRC-validated sensor state is %{public}@ age=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, decodedStatus.state.description, decodedStatus.age.description)
                    session.invalidate(errorMessage: "The sensor is not ready. No streaming command was sent.")
                    return
                }

                UserDefaults.standard.set(true, forKey: "LibreDebugActivationVerified")
                session.alertMessage = "Sensor is ready. Enabling Bluetooth—keep holding."
            }
#endif

            self.libreNFCDelegate?.received(fram: fram)

            // Enable streaming
            let subCmd: Subcommand = .enableStreaming
            let cmd = self.nfcCommand(subCmd, unlockCode: self.unlockCode, patchInfo: patchInfo, sensorUID: sensorUID)
            let info = "NFC: sending Libre 2 command to " + subCmd.description + " : code: 0x" + String(format: "%0X", cmd.code) + ", parameters: 0x" + cmd.parameters.toHexString() + "unlock code: " + self.unlockCode.description
            xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, info)

            var streamingRetry = 0
            var streamingSucceeded = false

            while true {
                do {
                    let response = try await customCommandAsync(tag: tag, code: Int(cmd.code), params: cmd.parameters)
                    let respLog = "NFC: '" + subCmd.description + " command response " + response.count.description + " bytes : 0x" + response.toHexString() + ", error: nil"
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, respLog)

                    guard response.count == 6 else {
                        xdrip.trace("LIBRE_DIAG enable-streaming rejected unexpectedResponseLength=%{public}@ response=%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .error, response.count.description, response.toHexString())
                        break
                    }

                    self.serialNumber = LibreSensorSerialNumber(withUID: sensorUID, with: LibreSensorType.type(patchInfo: patchInfo.toHexString()))?.serialNumber ?? "unknown"
                    self.macAddress = Data(response.reversed()).hexEncodedString().uppercased()

                    let ok = "NFC: successfully enabled BLE streaming on Libre 2 " + self.serialNumber + " unlock code: " + self.unlockCode.description + " MAC address: " + self.macAddress
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, ok)

                    session.alertMessage = "Bluetooth streaming enabled. You may move the phone away."
                    self.nfcScanSuccessful = true
                    streamingSucceeded = true
                    self.commandCompletionHapticFeedback()
                    break
                } catch {
                    let nsError = error as NSError
                    let respLog = "NFC: '" + subCmd.description + " command error on attempt " + streamingRetry.description + "/" + retries.description + ": " + error.localizedDescription + " domain: " + nsError.domain + " code: " + nsError.code.description
                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, respLog)

                    guard streamingRetry < retries else { break }
                    streamingRetry += 1
                    session.alertMessage = TextsLibreNFC.holdTopOfIphoneNearSensor
                    try? await Task.sleep(nanoseconds: 150_000_000)

                    do {
                        try await session.connect(to: firstTag)
                        xdrip.trace("NFC: reconnected to tag for enable-streaming attempt %{public}@/%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, streamingRetry.description, retries.description)
                    } catch {
                        xdrip.trace("NFC: reconnect before enable-streaming attempt %{public}@/%{public}@ failed: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, streamingRetry.description, retries.description, error.localizedDescription)
                    }
                }
            }

            self.libreNFCDelegate?.streamingEnabled(successful: streamingSucceeded)

            session.invalidate()
        }
    }
    
    // MARK: - helper functions

    func readRaw(_ address: UInt16, _ bytes: Int, buffer: Data = Data(), tag: NFCISO15693Tag, handler: @escaping (UInt16, Data, Error?) -> Void) {
        let tagWrapper = NFCISO15693TagWrapper(tag)
        var buffer = buffer
        let addressToRead = address + UInt16(buffer.count)
        
        var remainingBytes = bytes
        let bytesToRead = remainingBytes > 24 ? 24 : bytes
        
        var remainingWords = bytes / 2
        if bytes % 2 == 1 || (bytes % 2 == 0 && addressToRead % 2 == 1) { remainingWords += 1 }
        let wordsToRead = UInt8(remainingWords > 12 ? 12 : remainingWords) // real limit is 15
        
        // this is for libre 2 only, ignoring other libre types
        let readRawCommand = NFCCommand(code: 0xB3, parameters: Data([UInt8(addressToRead & 0x00FF), UInt8(addressToRead >> 8), wordsToRead]))
        
        if buffer.count == 0 {
            xdrip.trace("NFC: sending 0x%{public}@ 0x07 0x%{public}@ command (%{public}@ read raw)", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, readRawCommand.code.description, readRawCommand.parameters.toHexString(), "libre 2")
        }

        tagWrapper.tag.customCommand(requestFlags: .highDataRate, customCommandCode: Int(readRawCommand.code), customRequestParameters: readRawCommand.parameters) {
            response, error in
            
            var data = response
            
            if error != nil {
                xdrip.trace("NFC: error while reading %{public}@ words at raw memory 0x%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, wordsToRead.description, addressToRead.description)

                remainingBytes = 0
                
            } else {
                if addressToRead % 2 == 1 { data = data.subdata(in: 1 ..< data.count) }
                if data.count - Int(bytesToRead) == 1 { data = data.subdata(in: 0 ..< data.count - 1) }
            }
            
            buffer += data
            remainingBytes -= data.count
            
            if remainingBytes == 0 {
                handler(address, buffer, error)
            } else {
                self.readRaw(address, remainingBytes, buffer: buffer, tag: tagWrapper.tag) { address, data, error in handler(address, data, error) }
            }
        }
    }

    func writeRaw(_ address: UInt16, _ data: Data, tag: NFCISO15693Tag, handler: @escaping (UInt16, Data, Error?) -> Void) {
        let tagWrapper = NFCISO15693TagWrapper(tag)
        let backdoor = [UInt8]([0xDE, 0xAD, 0xBE, 0xEF]) // "deadbeef".bytes
        
        // Unlock
        xdrip.trace("NFC: sending 0xa4 0x07 0x%{public}@ command (%{public}@ unlock)", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, Data(backdoor).toHexString(), "libre 2")

        tagWrapper.tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA4, customRequestParameters: Data(backdoor)) {
            response, error in
            
            xdrip.trace("NFC: unlock command response: 0x%{public}@, error: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, response.toHexString(), error?.localizedDescription ?? "none")
            
            let addressToRead = (address / 8) * 8
            let startOffset = Int(address % 8)
            let endAddressToRead = ((Int(address) + data.count - 1) / 8) * 8 + 7
            let blocksToRead = (endAddressToRead - Int(addressToRead)) / 8 + 1
            
            self.readRaw(addressToRead, blocksToRead * 8, tag: tagWrapper.tag) { readAddress, readData, error in

                var msg = error?.localizedDescription ?? readData.hexDump(address: Int(readAddress), header: "NFC: blocks to overwrite:")
                
                if error != nil {
                    handler(address, data, error)
                    return
                }
                
                var bytesToWrite = readData
                bytesToWrite.replaceSubrange(startOffset ..< startOffset + data.count, with: data)
                msg += "\(bytesToWrite.hexDump(address: Int(addressToRead), header: "\nwith blocks:"))"
                
                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, msg)
                
                let startBlock = Int(addressToRead / 8)
                let blocks = bytesToWrite.count / 8
                
                if address < 0xF860 { // lower than FRAM blocks
                    for i in 0 ..< blocks {
                        let blockToWrite = bytesToWrite[i * 8 ... i * 8 + 7]
                        
                        // FIXME: doesn't work as the custom commands C1 or A5 for other chips
                        tagWrapper.tag.extendedWriteSingleBlock(requestFlags: .highDataRate, blockNumber: startBlock + i, dataBlock: blockToWrite) { error in

                            var debugInfo = String(format: "%X", startBlock + i) + " " + Int(i + 1).description + " of " + blocks.description + " " + blockToWrite.toHexString() + " at 0x" + String(format: "%X", Int((startBlock + i) * 8))
                            
                            if let error = error {
                                debugInfo = "NFC: error while writing block 0x" + debugInfo + " : " + error.localizedDescription
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)

                                if i != blocks - 1 { return }
                                
                            } else {
                                debugInfo = "NFC: wrote block 0x" + debugInfo
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                            }
                            
                            if i == blocks - 1 {
                                // Lock
                                tagWrapper.tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA2, customRequestParameters: Data(backdoor)) { response, error in
                                    
                                    xdrip.trace("NFC: lock command response: 0x%{public}@, error: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, response.toHexString(), error?.localizedDescription ?? "none")
                                    
                                    handler(address, data, error)
                                }
                            }
                        }
                    }
                    
                } else { // address >= 0xF860: write to FRAM blocks
                    let requestBlocks = 2 // 3 doesn't work
                    
                    let requests = Int(ceil(Double(blocks) / Double(requestBlocks)))
                    let remainder = blocks % requestBlocks
                    var blocksToWrite = [Data](repeating: Data(), count: blocks)
                    
                    for i in 0 ..< blocks {
                        blocksToWrite[i] = Data(bytesToWrite[i * 8 ... i * 8 + 7])
                    }
                    
                    for i in 0 ..< requests {
                        let startIndex = startBlock - 0xF860 / 8 + i * requestBlocks
                        let endIndex = startIndex + (i == requests - 1 ? (remainder == 0 ? requestBlocks : remainder) : requestBlocks) - (requestBlocks > 1 ? 1 : 0)
                        let blockRange = NSRange(UInt8(startIndex) ... UInt8(endIndex))
                        
                        var dataBlocks = [Data]()
                        for j in startIndex ... endIndex {
                            dataBlocks.append(blocksToWrite[j - startIndex])
                        }
                        
                        // snapshot to avoid mutation-after-capture compiler warning
                        let dataBlocksSnapshot = dataBlocks
                        
                        // TODO: write to 16-bit addresses as the custom cummand C4 for other chips
                        tagWrapper.tag.writeMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: blockRange, dataBlocks: dataBlocksSnapshot) {
                            error in // TEST

                            var debugInfo = String(format: "%X", startIndex) + " - 0x" + String(format: "%X", endIndex) + dataBlocksSnapshot.reduce("") { $0 + $1.toHexString() } + " at 0x" + String(format: "%X", (startBlock + i * requestBlocks) * 8)

                            if error != nil {
                                debugInfo = "NFC: error while writing multiple blocks 0x" + debugInfo + " : " + error!.localizedDescription
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                
                                if i != requests - 1 { return }
                                
                            } else {
                                debugInfo = "NFC: wrote blocks 0x" + debugInfo
                                
                                xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                            }
                            
                            if i == requests - 1 {
                                // Lock
                                tagWrapper.tag.customCommand(requestFlags: .highDataRate, customCommandCode: 0xA2, customRequestParameters: Data(backdoor)) {
                                    response, error in
                                    
                                    let debugInfo = "NFC: lock command response: 0x" + response.toHexString() + "error: " + (error?.localizedDescription ?? "none")
                                    
                                    xdrip.trace("%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, debugInfo)
                                    
                                    handler(address, data, error)
                                }
                            }
                        } // TEST writeMultipleBlocks
                    }
                }
            }
        }
    }

    private func trace(systemError: Error?, ownErrorString: String, session: NFCTagReaderSession) {
        if let systemError = systemError {
            xdrip.trace("NFC: error : %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemError.localizedDescription)
        }
    }
    
    private func traceICIdentifier(tag: NFCISO15693Tag) {
        xdrip.trace("NFC: IC identifier: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, tag.identifier.toHexString())
    }
   
    private func traceICManufacturer(tag: NFCISO15693Tag) {
        var manufacturer = String(tag.icManufacturerCode)
        if manufacturer == "7" {
            manufacturer.append(" (Texas Instruments)")
        } else if manufacturer == "122" {
            manufacturer.append(" (Abbott Diabetes Care)")
        }

        xdrip.trace("NFC: IC manufacturer code: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, manufacturer)
    }
    
    private func traceICSerialNumber(tag: NFCISO15693Tag) {
        xdrip.trace("NFC: IC serial number: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, tag.icSerialNumber.toHexString())
    }

    private func traceROM(tag: NFCISO15693Tag) {
        var rom = "RF430"
        switch tag.identifier[2] {
        case 0xA0: rom += "TAL152H Libre 1 A0"
        case 0xA4: rom += "TAL160H Libre 2 A4"
        default: rom = String(tag.identifier[2])
        }

        xdrip.trace("NFC: %{public}@ ROM", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, rom)
    }
    
    private func traceICReference(systemInfo: NFCISO15693SystemInfo) {
        xdrip.trace("NFC: IC reference: 0x%{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.icReference.description)
    }
    
    private func traceApplicationFamilyIdentifier(systemInfo: NFCISO15693SystemInfo) {
        if systemInfo.applicationFamilyIdentifier != -1 {
            xdrip.trace("NFC: application family id (AFI): %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.applicationFamilyIdentifier.description)
        }
    }

    private func traceDataStorageFormatIdentifier(systemInfo: NFCISO15693SystemInfo) {
        if systemInfo.dataStorageFormatIdentifier != -1 {
            xdrip.trace("NFC: data storage format id: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.dataStorageFormatIdentifier.description)
        }
    }
    
    private func traceMemorySize(systemInfo: NFCISO15693SystemInfo) {
        xdrip.trace("NFC: memory size: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.totalBlocks.description)
    }
    
    private func traceBlockSize(systemInfo: NFCISO15693SystemInfo) {
        xdrip.trace("NFC: block size: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, systemInfo.blockSize.description)
    }
    
    private func traceSensorUID(sensorUID: Data) {
        xdrip.trace("NFC: sensorUID: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, sensorUID.toHexString())
    }
    
    private func tracePatchInfo(patchInfo: Data) {
        xdrip.trace("NFC: patchInfo: %{public}@", log: self.log, category: ConstantsLog.categoryLibreNFC, type: .info, patchInfo.toHexString())
    }
    
    private func nfcCommand(_ code: Subcommand, unlockCode: UInt32, patchInfo: Data, sensorUID: Data) -> NFCCommand {
        var b: [UInt8] = []
        var y: UInt16
        
        if code == .enableStreaming {
            // Enables Bluetooth on Libre 2. Returns peripheral MAC address to connect to.
            // unlockCode could be any 32 bit value. The unlockCode and sensor Uid / patchInfo
            // will have also to be provided to the login function when connecting to peripheral.
            
            b = [
                UInt8(unlockCode & 0xFF),
                UInt8((unlockCode >> 8) & 0xFF),
                UInt8((unlockCode >> 16) & 0xFF),
                UInt8((unlockCode >> 24) & 0xFF)
            ]
            
            y = UInt16(patchInfo[4 ... 5]) ^ UInt16(b[1], b[0])
            
        } else {
            y = 0x1B6A
        }
        
        let d = PreLibre2.usefulFunction(sensorUID: sensorUID, x: UInt16(code.rawValue), y: y)
        
        var parameters = Data([code.rawValue])
        
        if code == .enableStreaming {
            parameters += b
        }
        
        parameters += d
        
        return NFCCommand(code: 0xA1, parameters: parameters)
    }
    
    /// this just centralises the system sound that we will fire every time we scan the sensor in each loop.
    private func scanRepeatHapticFeedback() {
        // Intermediate/retry haptics are intentionally silent in the debug
        // handoff build: a vibration must mean the NFC command is complete.
#if !DEBUG
        AudioServicesPlaySystemSound(1519)
#endif
    }

    /// A recognizable completion signal, distinct from iOS's own NFC tag
    /// detection vibration. Both pulses occur only after the sensor has
    /// returned a validated activation or enable-streaming response.
    private func commandCompletionHapticFeedback() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }
}

#endif
