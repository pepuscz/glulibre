import CoreBluetooth
import Foundation
import os

/// SmartGuide collector using the inherited connection/restoration engine.
/// Calibration and first initialization require explicit confirmation. No stop/restart writes.
final class CGMSmartGuideTransmitter: BluetoothTransmitter, CGMTransmitter {
    let serial: String
    private weak var receiver: CGMTransmitterDelegate?
    private var characteristics: [String: CBCharacteristic] = [:]
    private weak var connectedPeripheral: CBPeripheral?
    private var usesCRC: Bool?
    private var capabilities: SmartGuideProtocol.Capabilities?
    private var modelName = ""
    private var firmware = ""
    private var statusReceivedAt: Date?
    private enum CalibrationPhase { case idle, status, previousRecord, acknowledgement, confirmation }
    private var calibrationPhase = CalibrationPhase.idle
    private var calibrationInput: SmartGuideCalibration.Input?
    private var calibrationCompletion: ((String) -> Void)?
    private var calibrationToken = UUID()
    private var status = SmartGuideProtocol.Status()
    private var start: Date?
    private var currentMinutes = 0
    private var pending: [SmartGuideProtocol.Measurement] = []
    private var seen = Set<Int>()
    private var enabledNotifications = Set<String>()
    private var adopted = false
    private var blocked = false
    private var reportedStop = false
    private var historyRequested = false
    private var collectingHistory = false
    private var statusReadPending = false
    private var statusReadToken = UUID()
    private var generation = UUID()
    private var initializationRequested = false
    private var awaitingInitialization = false
    private var initializationToken: UUID?
    private let log = Logger(subsystem: ConstantsLog.subSystem, category: "SmartGuide")
    private let diagnosticLog = OSLog(subsystem: ConstantsLog.subSystem, category: "SmartGuide")

    private func diagnostic(_ message: String) {
        trace("%{public}@", log: diagnosticLog, category: "SmartGuide", type: .info, message)
    }

    init(address: String?, name: String?, serial: String, bluetoothDelegate: BluetoothTransmitterDelegate,
         receiver: CGMTransmitterDelegate) {
        self.serial = serial.uppercased()
        self.receiver = receiver
        super.init(addressAndName: address.map { .alreadyConnectedBefore(address: $0, name: name) }
                   ?? .notYetConnected(expectedName: "AC-" + serial.uppercased()),
                   CBUUID_Advertisement: SmartGuideProtocol.service,
                   servicesCBUUIDs: [CBUUID(string: "180A"), CBUUID(string: SmartGuideProtocol.service)],
                   CBUUID_ReceiveCharacteristic: SmartGuideProtocol.measurement,
                   CBUUID_WriteCharacteristic: SmartGuideProtocol.recordAccess,
                   bluetoothTransmitterDelegate: bluetoothDelegate)
    }

    override var announcesConnectionImmediately: Bool { false }
    override func permitsBluetoothConnectionAttempt() -> Bool { !blocked && SmartGuideProtocol.validSerial(serial) }
    override func discoveredPeripheralMatchesExpectedDevice(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        SmartGuideProtocol.matches(name: advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "", serial: serial)
    }

    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        generation = UUID()
        initializationToken = nil
        initializationRequested = false
        awaitingInitialization = false
        connectedPeripheral = peripheral
        characteristics.removeAll()
        enabledNotifications.removeAll()
        usesCRC = nil
        capabilities = nil
        statusReceivedAt = nil
        modelName = ""
        firmware = ""
        pending.removeAll()
        start = nil
        adopted = false
        historyRequested = false
        collectingHistory = false
        statusReadPending = false
        publish("Pairing… Enter the PIN from the blue cap if asked.")
        super.centralManager(central, didConnect: peripheral)
        // CoreBluetooth presents the PIN prompt when an encrypted characteristic is read.
        // Never log, store or auto-submit the PIN.
        let token = generation
        performOnBluetoothQueue { [weak self] in
            guard let self else { return }
            self.scheduleSetupTimeout(token)
        }
    }

    private func scheduleSetupTimeout(_ token: UUID) {
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) { [weak self] in
            self?.performOnBluetoothQueue { [weak self] in
                guard let self, self.generation == token, !self.adopted, !self.awaitingInitialization,
                      self.initializationToken == nil else { return }
                self.fail("Pairing did not finish. Check the cap PIN and Bluetooth permission, then retry.")
            }
        }
    }

    override func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        finishCalibration("Connection lost. Any sent calibration will not be repeated. Check calibration status after reconnecting.")
        initializationToken = nil
        generation = UUID()
        initializationRequested = false
        awaitingInitialization = false
        connectedPeripheral = nil
        adopted = false
        pending.removeAll()
        if !blocked { publish("Reconnecting…") }
        super.centralManager(central, didDisconnectPeripheral: peripheral, error: error)
    }

    override func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard !blocked else { return }
        guard error == nil else { fail("Couldn’t read SmartGuide services. Retry pairing."); return }
        for characteristic in service.characteristics ?? [] {
            characteristics[characteristic.uuid.uuidString.uppercased()] = characteristic
        }
        // Wait for both services; don't let the generic one-characteristic path subscribe early.
        guard peripheral.services?.allSatisfy({ $0.characteristics != nil }) == true else { return }
        guard ["2A29", "2A24", "2A25", SmartGuideProtocol.feature, SmartGuideProtocol.status,
               SmartGuideProtocol.sessionStart, SmartGuideProtocol.measurement, SmartGuideProtocol.recordAccess]
            .allSatisfy({ characteristics[$0] != nil }) else {
            fail("This sensor’s Bluetooth profile isn’t supported."); return
        }
        read("2A29")
    }

    private func read(_ uuid: String) {
        guard let peripheral = connectedPeripheral, let characteristic = characteristics[uuid],
              characteristic.properties.contains(.read) else {
            fail("A required SmartGuide characteristic is unavailable."); return
        }
        peripheral.readValue(for: characteristic)
    }

    override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !blocked else { return }
        if characteristic.uuid.uuidString.uppercased() == SmartGuideProtocol.controlPoint, error != nil {
            finishCalibration("Calibration couldn’t be read. Nothing will be resent; reconnect and check its status.")
            return
        }
        guard error == nil, let data = characteristic.value else {
            fail("SmartGuide couldn’t be read. Check pairing and retry."); return
        }
        let uuid = characteristic.uuid.uuidString.uppercased()
        // Only protocol status/time bytes: never log PINs, identity or glucose payloads.
        if uuid == SmartGuideProtocol.status || uuid == SmartGuideProtocol.sessionStart {
            diagnostic("Read \(uuid): \(data.map { String(format: "%02x", $0) }.joined())")
        }
        do {
            switch uuid {
            case "2A29":
                guard let manufacturer = String(data: data, encoding: .utf8), manufacturer.localizedCaseInsensitiveContains("Roche") else {
                    throw SmartGuideProtocol.Failure.unsupported
                }
                read("2A24")
            case "2A24":
                // Model/firmware are diagnostic information, not an invented current-batch allowlist.
                modelName = String(data: data, encoding: .utf8) ?? "Unknown"
                log.info("SmartGuide model: \(self.modelName, privacy: .public)")
                read("2A25")
            case "2A25":
                let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard value == serial else { throw SmartGuideProtocol.Failure.unsupported }
                read(SmartGuideProtocol.feature)
            case SmartGuideProtocol.feature:
                capabilities = try SmartGuideProtocol.capabilities(data)
                usesCRC = capabilities?.usesCRC
                if characteristics["2A26"] != nil { read("2A26") } else { readStatus() }
            case "2A26":
                firmware = String(data: data, encoding: .utf8) ?? "Unknown"
                log.info("SmartGuide firmware: \(self.firmware, privacy: .public)")
                readStatus()
            case SmartGuideProtocol.status:
                guard let usesCRC else { return }
                let result = try SmartGuideProtocol.sensorStatus(data, crcRequired: usesCRC)
                statusReadPending = false
                statusReceivedAt = Date()
                currentMinutes = result.minutes
                status = result.status
                if start == nil && (status.stopped || currentMinutes >= SmartGuideProtocol.maximumMinutes) {
                    subscribeCollection()
                } else if start == nil { read(SmartGuideProtocol.sessionStart) }
                else {
                    _ = try SmartGuideProtocol.anchor(minutes: currentMinutes, now: Date(), saved: start, reported: nil)
                    updateStatus()
                    deliverPending()
                    if calibrationPhase == .status {
                        guard readyForCalibration else {
                            finishCalibration(SmartGuideCalibration.Failure.unavailable.localizedDescription)
                            return
                        }
                        calibrationPhase = .previousRecord
                        writeControl(SmartGuideCalibration.lastRecord(usesCRC: usesCRC))
                    }
                }
            case SmartGuideProtocol.sessionStart:
                guard let usesCRC else { return }
                // Validate CRC even if the date itself is unknown/unset.
                _ = try SmartGuideProtocol.checked([UInt8](data), payloadSize: 9, crcRequired: usesCRC)
                let reported = try? SmartGuideProtocol.sessionDate(data, crcRequired: usesCRC)
                let saved = UserDefaults.standard.object(forKey: anchorKey) as? Date
                let attempted = FileManager.default.fileExists(atPath: initializationURL.path)
                diagnostic("Session check: minutes=\(currentMinutes), reported=\(String(describing: reported)), saved=\(String(describing: saved)), attempted=\(attempted), statusAt=\(String(describing: statusReceivedAt))")
                if status.calibration & 1 != 0 {
                    let allowed = SmartGuideProtocol.initializationAllowed(status: status, minutes: currentMinutes,
                        saved: saved, reported: reported, attempted: attempted)
                    awaitingInitialization = allowed
                    DispatchQueue.main.async { SmartGuideConnectionState.shared.canInitialize = allowed }
                    if initializationRequested && allowed {
                        initializationRequested = false
                        guard let c = characteristics[SmartGuideProtocol.sessionStart], c.properties.contains(.write) else {
                            fail("Sensor initialization is not supported."); return
                        }
                        let date = Date()
                        let packet = try SmartGuideProtocol.initializationPacket(date: date, usesCRC: usesCRC)
                        try FileManager.default.createDirectory(at: initializationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try JSONEncoder().encode(date).write(to: initializationURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                        awaitingInitialization = false
                        DispatchQueue.main.async { SmartGuideConnectionState.shared.canInitialize = false }
                        publish("Starting sensor… Keep your phone nearby.")
                        peripheral.writeValue(packet, for: c, type: .withResponse)
                        return
                    }
                    initializationRequested = false
                    initializationToken = nil
                    publish(allowed ? "Ready to start your new sensor" : attempted ? "Sensor start is unconfirmed. No command will be repeated; reconnect to check." : "Initialization needs review. No start command was sent; use mySugr if needed.")
                    return
                }
                initializationRequested = false
                awaitingInitialization = false
                DispatchQueue.main.async { SmartGuideConnectionState.shared.canInitialize = false }
                if attempted, saved == nil {
                    let attemptedAt = try JSONDecoder().decode(Date.self, from: Data(contentsOf: initializationURL))
                    guard let statusReceivedAt else { throw SmartGuideProtocol.Failure.invalidClock }
                    start = try SmartGuideProtocol.verifiedInitializationStart(reported: reported, minutes: currentMinutes,
                        statusAt: statusReceivedAt, attemptedAt: attemptedAt, now: Date())
                } else {
                    start = try SmartGuideProtocol.anchor(minutes: currentMinutes, now: Date(), saved: saved, reported: reported)
                }
                initializationToken = nil
                if saved == nil { UserDefaults.standard.set(start, forKey: anchorKey) }
                subscribeCollection()
            case SmartGuideProtocol.controlPoint:
                guard let usesCRC, calibrationPhase != .idle else { return }
                do {
                    try handleCalibrationResponse(SmartGuideCalibration.response(data, usesCRC: usesCRC))
                } catch {
                    finishCalibration("Calibration response couldn’t be verified. Nothing will be resent. Check its status before another calibration.")
                }
            case SmartGuideProtocol.measurement:
                guard adopted, let usesCRC else { return }
                let records = try SmartGuideProtocol.measurements(data, crcRequired: usesCRC)
                guard pending.count + records.count <= 4096 else { throw SmartGuideProtocol.Failure.malformed }
                pending.append(contentsOf: records)
                // History gets one fresh status read when the transfer finishes.
                if !collectingHistory { readStatus() }
            case SmartGuideProtocol.recordAccess:
                let b = [UInt8](data)
                guard b.count == 4, b[0] == 6, b[1] == 0, b[2] == 1 else { throw SmartGuideProtocol.Failure.malformed }
                collectingHistory = false
                readStatus()
                if b[3] != 1 && b[3] != 6 { publish("Live readings connected; history request was declined.") }
            default: break
            }
        } catch {
            diagnostic("Rejected \(uuid): \(String(describing: error))")
            log.error("Rejected SmartGuide packet on \(uuid, privacy: .public): \(String(describing: error), privacy: .public)")
            fail("Sensor data couldn’t be verified. No readings were added. Retry connection.")
        }
    }

    private var anchorKey: String { "GluLibre.SmartGuide.anchor." + serial }

    private var initializationURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SmartGuideInitialization").appendingPathComponent(serial + ".json")
    }

    func initializeNewSensor() {
        performOnBluetoothQueue { [weak self] in
            guard let self, !self.blocked, self.awaitingInitialization, self.connectedPeripheral != nil else { return }
            guard self.initializationToken == nil else { return }
            let token = UUID()
            self.initializationToken = token
            let connection = self.generation
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) { [weak self] in
                self?.performOnBluetoothQueue { [weak self] in
                    guard let self, self.generation == connection, self.initializationToken == token else { return }
                    self.initializationRequested = false
                    self.initializationToken = nil
                    self.fail("Initialization timed out. Reconnect to check; any sent command will not be repeated.")
                }
            }
            self.initializationRequested = true
            self.readStatus()
        }
    }

    private func readStatus() {
        guard !statusReadPending else { return }
        statusReadPending = true
        statusReadToken = UUID()
        let token = statusReadToken
        let connection = generation
        read(SmartGuideProtocol.status)
        DispatchQueue.global().asyncAfter(deadline: .now() + 20) { [weak self] in
            self?.performOnBluetoothQueue { [weak self] in
                guard let self, self.generation == connection,
                      self.statusReadToken == token, self.statusReadPending, !self.blocked else { return }
                self.fail("Sensor status timed out. No unverified readings were added. Reconnect to retry.")
            }
        }
    }

    private func subscribe(_ uuid: String) {
        guard let c = characteristics[uuid], c.properties.contains(.notify) || c.properties.contains(.indicate) else {
            fail("SmartGuide cannot send readings with this firmware."); return
        }
        connectedPeripheral?.setNotifyValue(true, for: c)
    }

    private var calibrationTransportAvailable: Bool {
        guard capabilities?.calibrationSupported == true, let c = characteristics[SmartGuideProtocol.controlPoint] else { return false }
        return c.properties.contains(.write) && c.properties.contains(.indicate)
    }

    private func subscribeCollection() {
        subscribe(SmartGuideProtocol.measurement)
        subscribe(SmartGuideProtocol.recordAccess)
        if calibrationTransportAvailable { subscribe(SmartGuideProtocol.controlPoint) }
    }

    override func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard !blocked else { return }
        if characteristic.uuid.uuidString.uppercased() == SmartGuideProtocol.controlPoint {
            if error == nil && characteristic.isNotifying {
                enabledNotifications.insert(SmartGuideProtocol.controlPoint)
            }
            // Optional calibration support must not break a working read-only collector.
            publishCapabilities()
            return
        }
        guard error == nil, characteristic.isNotifying else { fail("SmartGuide notifications could not be enabled."); return }
        enabledNotifications.insert(characteristic.uuid.uuidString.uppercased())
        guard enabledNotifications.isSuperset(of: [SmartGuideProtocol.measurement, SmartGuideProtocol.recordAccess]), !adopted else { return }
        adopted = true
        announceValidatedConnection()
        updateStatus()
        requestHistory()
    }

    private func requestHistory() {
        guard !historyRequested, start != nil, let c = characteristics[SmartGuideProtocol.recordAccess],
              c.properties.contains(.write), let peripheral = connectedPeripheral else { return }
        historyRequested = true
        collectingHistory = true
        // A complete 14-day session fits within 4,032 five-minute records. The existing
        // ingestion engine deduplicates persisted timestamps; no reset or delete request.
        peripheral.writeValue(SmartGuideProtocol.history(from: max(60, (seen.max() ?? 60) - 5)), for: c, type: .withResponse)
        log.info("SmartGuide history requested")
        let token = generation
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) { [weak self] in
            self?.performOnBluetoothQueue { [weak self] in
                guard let self, self.generation == token, self.collectingHistory else { return }
                // An interrupted history transfer never prevents subsequent live data.
                self.collectingHistory = false
                self.readStatus()
            }
        }
    }

    override func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !blocked, peripheral == connectedPeripheral else { return }
        if characteristic.uuid.uuidString.uppercased() == SmartGuideProtocol.sessionStart {
            guard error == nil else { fail("Sensor start is unconfirmed. Reconnect to check; it will not be sent again."); return }
            readStatus()
            return
        }
        if characteristic.uuid.uuidString.uppercased() == SmartGuideProtocol.controlPoint {
            if error != nil { finishCalibration("Calibration wasn’t confirmed. Check its status before trying again.") }
            // ATT write completion is NOT a successful sensor calibration.
            return
        }
        if error != nil {
            collectingHistory = false
            readStatus()
            publish("Live readings connected; history couldn’t be requested.")
        }
    }

    private func updateStatus() {
        publishCapabilities()
        if currentMinutes >= SmartGuideProtocol.maximumMinutes || status.stopped {
            publish("Sensor ended — start a new sensor in mySugr")
            if adopted, !reportedStop {
                reportedStop = true
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isActiveCollector else { return }
                    self.receiver?.sensorStopDetected()
                }
            }
            return
        }
        if currentMinutes < 60 { publish("Warming up · \(60 - currentMinutes) min remaining"); return }
        publish(status.message ?? "Connected · waiting for readings")
    }

    private func deliverPending() {
        guard adopted, !collectingHistory, let start else { return }
        let records = pending
        pending.removeAll()
        guard !reportedStop else { return }
        let now = Date()
        let readings = records.sorted { $0.minutes > $1.minutes }.compactMap { record -> GlucoseData? in
            guard !seen.contains(record.minutes), status.permitsReading,
                  SmartGuideProtocol.usable(record, status: status, start: start, now: now), let value = record.mgDl else { return nil }
            seen.insert(record.minutes)
            let reading = GlucoseData(timeStamp: start.addingTimeInterval(Double(record.minutes) * 60), glucoseLevelRaw: value)
            reading.isTrendOnly = record.status(fallback: status).calibrationRequired || status.calibrationRequired
            return reading
        }
        guard !readings.isEmpty else { return }
        log.info("SmartGuide accepted \(readings.count) readings")
        diagnostic("Accepted \(readings.count) readings; trend-only=\(readings.filter { $0.isTrendOnly }.count)")
        publish(status.message ?? "Receiving readings")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isActiveCollector else { return }
            let identity = "AC-" + self.serial
            if UserDefaults.standard.activeSensorTransmitterId != identity {
                self.receiver?.newSensorDetected(sensorStartDate: start)
                UserDefaults.standard.activeSensorTransmitterId = identity
            }
            var readings = readings
            self.receiver?.cgmTransmitterInfoReceived(glucoseData: &readings, transmitterBatteryInfo: nil,
                                                     sensorAge: now.timeIntervalSince(start))
        }
    }

    /// Called only on main, alongside the manager's Core Data access.
    private var isActiveCollector: Bool {
        guard let manager = bluetoothTransmitterDelegate as? BluetoothPeripheralManager,
              manager.getCGMTransmitter() as? CGMSmartGuideTransmitter === self,
              manager.getBluetoothPeripherals().contains(where: {
                  $0.blePeripheral.address == deviceAddress && $0.blePeripheral.shouldconnect
              }) else { return false }
        return true
    }

    private func publish(_ text: String) {
        diagnostic(text)
        publishCapabilities()
        DispatchQueue.main.async {
            SmartGuideConnectionState.shared.serial = self.serial
            SmartGuideConnectionState.shared.message = text
        }
    }

    private var attemptStore: SmartGuideCalibration.AttemptStore {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return .init(url: root.appendingPathComponent("SmartGuideCalibration", isDirectory: true)
            .appendingPathComponent(serial + ".json"))
    }

    private var readyForCalibration: Bool {
        guard adopted, !blocked, !collectingHistory, start != nil,
              enabledNotifications.contains(SmartGuideProtocol.controlPoint),
              let received = statusReceivedAt, (0...30).contains(Date().timeIntervalSince(received)),
              (60..<SmartGuideProtocol.maximumMinutes).contains(currentMinutes) else { return false }
        return status.permitsCalibration
    }

    private func publishCapabilities() {
        let connected = adopted && !blocked && connectedPeripheral != nil
        if blocked || connectedPeripheral == nil {
            DispatchQueue.main.async { SmartGuideConnectionState.shared.canInitialize = false }
        }
        let supportsCalibration = connected && enabledNotifications.contains(SmartGuideProtocol.controlPoint)
        // UI is advisory; all these conditions are checked again on the BLE queue before writing.
        let available = supportsCalibration && status.permitsCalibration && currentMinutes >= 60
            && currentMinutes < SmartGuideProtocol.maximumMinutes && calibrationPhase == .idle && !collectingHistory
        let model = modelName, version = firmware
        let canCheck = supportsCalibration && calibrationPhase == .idle
        var previous = ""
        var permitsNew = true
        do {
            if let attempt = try attemptStore.load() {
                previous = calibrationResult(attempt)
                do { try attempt.allowsNewAttempt(now: Date()) } catch { permitsNew = false }
            }
        } catch {
            permitsNew = false
            previous = "Calibration history couldn’t be read. No calibration will be sent."
        }
        DispatchQueue.main.async {
            let state = SmartGuideConnectionState.shared
            state.model = model
            state.firmware = version
            state.calibrationAvailable = available && permitsNew
            state.canCheckCalibration = canCheck
            state.calibrationResult = previous
        }
    }

    /// Entry point is main-thread only so ownership is checked against the live manager.
    func calibrate(_ input: SmartGuideCalibration.Input, completion: @escaping (String) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isActiveCollector else { completion("Connect this sensor before calibrating."); return }
        performOnBluetoothQueue { [weak self] in
            guard let self else { return }
            guard self.calibrationPhase == .idle, self.adopted, !self.blocked, !self.collectingHistory,
                  self.enabledNotifications.contains(SmartGuideProtocol.controlPoint), let start = self.start else {
                DispatchQueue.main.async { completion("Wait for the sensor connection and history download to finish.") }
                return
            }
            do {
                _ = try input.minute(start: start, now: Date())
                try self.attemptStore.load()?.allowsNewAttempt(now: Date())
            } catch {
                DispatchQueue.main.async { completion(error.localizedDescription) }
                return
            }
            self.calibrationInput = input
            self.calibrationCompletion = completion
            self.calibrationPhase = .status
            self.startCalibrationTimeout()
            self.readStatus() // Read fresh eligibility; never rely on the old screen state.
            self.publishCapabilities()
        }
    }

    /// Read-only reconciliation. Safe after a timeout/relaunch; it never resubmits a value.
    func checkCalibration(completion: @escaping (String) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isActiveCollector else { completion("Reconnect the sensor to check calibration."); return }
        performOnBluetoothQueue { [weak self] in
            guard let self else { return }
            guard self.calibrationPhase == .idle, self.adopted, !self.blocked,
                  self.enabledNotifications.contains(SmartGuideProtocol.controlPoint), let usesCRC = self.usesCRC else {
                DispatchQueue.main.async { completion("Calibration status isn’t available on this connection.") }
                return
            }
            self.calibrationCompletion = completion
            self.calibrationPhase = .confirmation
            self.startCalibrationTimeout()
            self.writeControl(SmartGuideCalibration.lastRecord(usesCRC: usesCRC))
            self.publishCapabilities()
        }
    }

    private func startCalibrationTimeout() {
        calibrationToken = UUID()
        let token = calibrationToken
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) { [weak self] in
            self?.performOnBluetoothQueue { [weak self] in
                guard let self, self.calibrationToken == token, self.calibrationPhase != .idle else { return }
                self.finishCalibration("The sensor didn’t confirm calibration. Nothing will be resent. Check calibration status after reconnecting.")
            }
        }
    }

    private func writeControl(_ data: Data) {
        guard !blocked, let peripheral = connectedPeripheral,
              let characteristic = characteristics[SmartGuideProtocol.controlPoint], characteristic.isNotifying else {
            finishCalibration("Calibration connection is unavailable. Nothing will be resent.")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    private func handleCalibrationResponse(_ response: SmartGuideCalibration.Response) throws {
        switch response {
        case .record(let record):
            if calibrationPhase == .previousRecord {
                guard readyForCalibration, let input = calibrationInput, let start, let usesCRC else {
                    throw SmartGuideCalibration.Failure.unavailable
                }
                let now = Date()
                // A recent calibration from another app also blocks an early repeat.
                if record.number != 0 {
                    let elapsed = currentMinutes - record.minute
                    guard elapsed >= (record.rejected ? 15 : 30) else { throw SmartGuideCalibration.Failure.recentAttempt }
                }
                let data = try SmartGuideCalibration.setValue(input, start: start, now: now, previous: record, usesCRC: usesCRC)
                let attempt = SmartGuideCalibration.Attempt(submittedAt: now, mgDl: input.mgDl,
                    minute: try input.minute(start: start, now: now), previousRecord: record.number)
                // If durable storage fails, do not issue the irreversible write.
                try attemptStore.save(attempt)
                calibrationPhase = .acknowledgement
                writeControl(data)
            } else if calibrationPhase == .confirmation {
                if var attempt = try attemptStore.load() {
                    attempt.reconcile(record)
                    try attemptStore.save(attempt)
                    finishCalibration(calibrationResult(attempt))
                } else if record.number == 0 {
                    finishCalibration("No calibration is stored on the sensor.")
                } else {
                    finishCalibration(record.pending ? "Sensor is processing calibration." : record.rejected
                        ? "The sensor rejected its last calibration. Take a new meter reading when prompted."
                        : "The sensor has a calibration record. Follow its next calibration request.")
                }
                readStatus()
            }
        case .acknowledgement(let request, let result):
            let expected: UInt8 = calibrationPhase == .acknowledgement ? 4 : 5
            guard request == expected else { throw SmartGuideProtocol.Failure.malformed }
            if result != 1 {
                if request == 4, var attempt = try attemptStore.load() {
                    attempt.outcome = .rejected
                    try attemptStore.save(attempt)
                }
                finishCalibration("The sensor declined the calibration operation (code \(result)). No automatic retry. Use Roche’s app if this firmware isn’t compatible.")
            } else if request == 4, let usesCRC {
                calibrationPhase = .confirmation
                writeControl(SmartGuideCalibration.lastRecord(usesCRC: usesCRC))
            }
        }
    }

    private func calibrationResult(_ attempt: SmartGuideCalibration.Attempt) -> String {
        switch attempt.outcome {
        case .unconfirmed: return "Calibration unconfirmed — check status before sending another value."
        case .accepted: return "Sensor accepted calibration. Follow its next calibration request."
        case .rejected: return "Sensor rejected calibration. Wait at least 15 minutes and take a new meter reading."
        }
    }

    private func finishCalibration(_ message: String) {
        guard calibrationPhase != .idle else { return }
        let completion = calibrationCompletion
        calibrationCompletion = nil
        calibrationInput = nil
        calibrationPhase = .idle
        calibrationToken = UUID()
        publishCapabilities()
        DispatchQueue.main.async { completion?(message) }
    }

    private func fail(_ text: String) {
        initializationRequested = false
        initializationToken = nil
        finishCalibration("Calibration interrupted. Any sent value will not be repeated; check its status after reconnecting.")
        blocked = true // No rapid bond/retry loop. Retry is explicit.
        pending.removeAll()
        seen.removeAll()
        publish(text)
        disconnect()
    }

    func retry() {
        performOnBluetoothQueue { [weak self] in
            guard let self else { return }
            self.blocked = false
            if self.getConnectionStatus() == .connected {
                self.readStatus()
                return
            }
            self.connect()
        }
    }

    func pauseCollection() {
        performOnBluetoothQueue { [weak self] in
            guard let self else { return }
            self.blocked = true
            self.initializationRequested = false
            self.initializationToken = nil
            self.awaitingInitialization = false
            self.finishCalibration("Connection paused. Any sent calibration will not be repeated.")
            self.generation = UUID()
            self.pending.removeAll()
            self.seen.removeAll()
            self.publish("Connection paused")
            self.disconnect()
        }
    }

    func cgmTransmitterType() -> CGMTransmitterType { .smartGuide }
    func isWebOOPEnabled() -> Bool { true }
    func nonWebOOPAllowed() -> Bool { false }
    func needsSensorStartTime() -> Bool { false }
    func maxSensorAgeInDays() -> Double? { 14 }
    func getCBUUID_Service() -> String { SmartGuideProtocol.service }
    func getCBUUID_Receive() -> String { SmartGuideProtocol.measurement }
}
