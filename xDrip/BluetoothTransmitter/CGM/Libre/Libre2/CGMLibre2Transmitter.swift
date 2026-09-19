import CoreBluetooth
import Foundation
import os

#if canImport(CoreNFC)
import CoreNFC

@objcMembers
class CGMLibre2Transmitter: BluetoothTransmitter, CGMTransmitter {
    // MARK: - properties
    
    /// service to be discovered
    private let CBUUID_Service_Libre2: String = "FDE3"
    
    /// receive characteristic
    private let CBUUID_ReceiveCharacteristic_Libre2: String = "F002"
    
    /// write characteristic
    private let CBUUID_WriteCharacteristic_Libre2: String = "F001"
    
    /// how many bytes should we receive from Libre 2
    private let expectedBufferSize = 46
    
    /// will be used to pass back bluetooth and cgm related events
    private(set) weak var cgmTransmitterDelegate: CGMTransmitterDelegate?
    
    /// CGMLibre2TransmitterDelegate
    public weak var cGMLibre2TransmitterDelegate: CGMLibre2TransmitterDelegate?
    
    /// is nonFixed enabled for the transmitter or not
    private var nonFixedSlopeEnabled: Bool
    
    /// for trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMLibre2)
    
    /// used as parameter in call to cgmTransmitterDelegate.cgmTransmitterInfoReceived, when there's no glucosedata to send
    private var emptyArray: [GlucoseData] = []

    /// used when processing Libre 2 data packet
    private var startDate: Date
    
    /// receive buffer for Libre 2 packets
    private var rxBuffer: Data
    
    /// how long to wait for next packet before resetting the rxBuffer
    private static let maxWaitForpacketInSeconds = 3.0

    /// is the transmitter oop web enabled or not
    private var webOOPEnabled: Bool
    
    /// current sensor serial number, if nil then it's not known yet
    private var sensorSerialNumber: String?
    
    /// temp storage of libreSensorSerialNumber, value will be stored after NFC scanning, but possible there's no transmitter created yet (if this is a first scan for a new transmitter), so we can't store the serial number yet in coredata. As soon as transmitter is connected,  and if tempSensorSerialNumber is not nil, it will be sent to the delegate
    private var tempSensorSerialNumber: LibreSensorSerialNumber?
    
    // define libreNFC as NSObject, otherwise check on iOS14 wouuld need to be added.
    // it will be casted to LibreNFC when needed
    private var libreNFC: NSObject?
    
    /// sensor type
    private var libreSensorType: LibreSensorType?

#if DEBUG
    private enum DiagnosticDefaultsKey {
        static let sensorSerialNumber = "LibreDebugPeripheralSensorSerialNumber"
        static let peripheralAddress = "LibreDebugPeripheralAddress"
    }

    static func diagnosticRestoredAddress(for sensorSerialNumber: String) -> String? {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: DiagnosticDefaultsKey.sensorSerialNumber) == sensorSerialNumber,
           let persistedAddress = defaults.string(forKey: DiagnosticDefaultsKey.peripheralAddress),
           UUID(uuidString: persistedAddress) != nil {
            return persistedAddress
        }

        return nil
    }
#endif
    
    // MARK: - Initialization

    /// - parameters:
    ///     - address: if already connected before, then give here the address that was received during previous connect, if not give nil
    ///     - name : if already connected before, then give here the name that was received during previous connect, if not give nil
    ///     - bluetoothTransmitterDelegate : a bluetoothTransmitterDelegate
    ///     - cGMLibre2TransmitterDelegate : a CGMLibre2TransmitterDelegate
    ///     - sensorSerialNumber : optional, sensor serial number, should be set if already known from previous session
    ///     - cGMTransmitterDelegate : a CGMTransmitterDelegate
    ///     - webOOPEnabled : enabled or not, if nil then default false
    init(address: String?, name: String?, bluetoothTransmitterDelegate: BluetoothTransmitterDelegate, cGMLibre2TransmitterDelegate: CGMLibre2TransmitterDelegate, sensorSerialNumber: String?, cGMTransmitterDelegate: CGMTransmitterDelegate, nonFixedSlopeEnabled: Bool?, webOOPEnabled: Bool?) {
        // assign addressname and name or expected devicename
        // (actually this now isn't really necessary as for new devices, sensorSerialNumber will be nil and we'll update the superclass expectedName anyway after the NFC scan via the delegate)
        var newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.notYetConnected(expectedName: "ABBOTT" + (sensorSerialNumber ?? ""))
        
        if let address = address {
            newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.alreadyConnectedBefore(address: address, name: "ABBOTT" + (sensorSerialNumber ?? ""))
        }
        
        // initialize sensorSerialNumber
        self.sensorSerialNumber = sensorSerialNumber

        // assign CGMTransmitterDelegate
        cgmTransmitterDelegate = cGMTransmitterDelegate
        
        // assign cGMLibre2TransmitterDelegate
        self.cGMLibre2TransmitterDelegate = cGMLibre2TransmitterDelegate
        
        // initialize nonFixedSlopeEnabled
        self.nonFixedSlopeEnabled = nonFixedSlopeEnabled ?? false
        
        // initialize rxbuffer
        rxBuffer = Data()
        
        // initialize startDate
        startDate = Date()
        
        // initialize webOOPEnabled
        self.webOOPEnabled = webOOPEnabled ?? false

        super.init(addressAndName: newAddressAndName, CBUUID_Advertisement: nil, servicesCBUUIDs: [CBUUID(string: CBUUID_Service_Libre2)], CBUUID_ReceiveCharacteristic: CBUUID_ReceiveCharacteristic_Libre2, CBUUID_WriteCharacteristic: CBUUID_WriteCharacteristic_Libre2, bluetoothTransmitterDelegate: bluetoothTransmitterDelegate)
    }
    
    // MARK: - overriden  BluetoothTransmitter functions

    override func permitsBluetoothConnectionAttempt() -> Bool {
#if DEBUG
        guard let sensorUID = UserDefaults.standard.libreSensorUID,
              LibreNFC.diagnosticActivationAttemptIssued(sensorUID: sensorUID) else {
            return false
        }

        guard let remaining = LibreNFC.diagnosticWarmupSecondsRemaining(sensorUID: sensorUID) else {
            return true
        }

        return remaining <= 0
#else
        return true
#endif
    }
    
    override func startScanning() -> BluetoothTransmitter.startScanningResult {
        // overriding startScanning, because it's the time to trigger NFC Scan
        // when user clicks the scan button, an NFC read is initiated which will enable the bluetooth streaming
        // meanwhile, the real scanning can start

        guard permitsBluetoothConnectionAttempt() else {
            stopScanning()
#if DEBUG
            if let sensorUID = UserDefaults.standard.libreSensorUID,
               let remaining = LibreNFC.diagnosticWarmupSecondsRemaining(sensorUID: sensorUID) {
                trace("LIBRE_DIAG blocked NFC and BLE during activation warm-up remainingSeconds=%{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, Int(remaining).description)
            }
#endif
            return .other(reason: "Libre sensor activation warm-up is still running")
        }

#if DEBUG
        // Once the explicit activation warm-up has elapsed, diagnostic builds
        // may observe BLE without first marking the NFC streaming handoff as
        // verified. This path never creates an NFC session or sends a sensor
        // command; it only scans/connects using CoreBluetooth.
        if let sensorUID = UserDefaults.standard.libreSensorUID,
           LibreNFC.diagnosticActivationAttemptIssued(sensorUID: sensorUID),
           (LibreNFC.diagnosticWarmupSecondsRemaining(sensorUID: sensorUID) ?? 0) <= 0 {
            trace("LIBRE_DIAG startScanning using passive BLE-only mode; NFC is disabled", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            return super.startScanning()
        }

        // The diagnostic build can resume BLE discovery after a successful NFC
        // handoff without issuing another command to the sensor. This is useful
        // when the debugger/app is restarted while investigating pairing.
        if let sensorSerialNumber,
           !sensorSerialNumber.isEmpty,
           UserDefaults.standard.bool(forKey: "LibreDebugActivationVerified"),
           let sensorUID = UserDefaults.standard.libreSensorUID,
           sensorUID.count == 8,
           let patchInfo = UserDefaults.standard.libreInitialPatchInfo ?? UserDefaults.standard.librePatchInfo,
           !patchInfo.isEmpty {
            trace("LIBRE_DIAG resuming BLE scan from cached NFC handoff sensor=%{public}@ uid=%{public}@ patch=%{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, sensorSerialNumber, sensorUID.hexEncodedString(), patchInfo.hexEncodedString())
            return super.startScanning()
        }
        trace("LIBRE_DIAG cached NFC data exists but activation is not verified; opening a state-check NFC session", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
#endif
        
        // create libreNFC instance and start session
        if NFCTagReaderSession.readingAvailable {
            // startScanning is getting called several times, but we must restrict launch of nfc scan to one single time, therefore check if libreNFC == nil
            if libreNFC == nil {
                // NFC session creation must be on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
#if DEBUG
                    self.libreNFC = LibreNFC(libreNFCDelegate: self, diagnosticMode: .enableStreamingOnly)
#else
                    self.libreNFC = LibreNFC(libreNFCDelegate: self)
#endif
                    (self.libreNFC as! LibreNFC).startSession()
                }
            }
            
        } else {
            // delegate may touch UI/Core Data → ensure main thread
            DispatchQueue.main.async { [weak self] in
                self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.deviceMustSupportNFC)
            }
        }
        
        // start the NFC scan (not BLE scanning)
        return .nfcScanNeeded
    }

    override func discoveredPeripheralMatchesExpectedDevice(_ peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if super.discoveredPeripheralMatchesExpectedDevice(peripheral, advertisementData: advertisementData) {
            return true
        }

#if DEBUG
        // Libre 2/2+ 7F sensors advertise manufacturer data as Abbott's
        // two-byte prefix followed by the sensor UID. This remains available
        // after an app restart, whereas CoreBluetooth's identifier can still
        // refer to the previous sensor and the 7F device name is MAC-style
        // rather than ABBOTT+serial. Match the UID captured by the successful
        // NFC handoff so recovery cannot attach to a neighbouring sensor.
        guard let sensorUID = UserDefaults.standard.libreSensorUID,
              sensorUID.count == 8,
              let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              manufacturerData.count == 8,
              manufacturerData.dropFirst(2).elementsEqual(sensorUID.prefix(6)) else {
            return false
        }

        trace("LIBRE_DIAG BLE advertisement matched cached NFC sensor UID %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, sensorUID.hexEncodedString())
        return true
#else
        return false
#endif
    }

#if DEBUG
    /// Observe/connect to an already advertising Libre without touching NFC.
    /// This is deliberately the only automatic post-warm-up recovery action.
    func startDiagnosticBLEOnly() {
        guard permitsBluetoothConnectionAttempt() else {
            trace("LIBRE_DIAG passive BLE-only discovery refused by warm-up policy", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            return
        }

        // A restored CoreBluetooth object can remain indefinitely in
        // `connecting`, which prevents startScanning() from issuing a real
        // scan. Drop only that in-memory handle and constrain fresh discovery
        // to this sensor's advertised name. Persisted NFC/sensor data remains.
        if let sensorSerialNumber, !sensorSerialNumber.isEmpty {
            updateExpectedDeviceName(name: "ABBOTT" + sensorSerialNumber)
        }
        disconnectAndForget()
        trace("LIBRE_DIAG starting fresh passive BLE-only discovery after dropping stale restored handle; no NFC session or sensor command", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
        _ = super.startScanning()
    }

    /// Opens the normal Libre NFC handoff specifically to restore BLE
    /// streaming after a verified sensor stops advertising. LibreNFC reads and
    /// validates the current FRAM state before sending anything: a starting or
    /// ready sensor may receive enableStreaming, while a not-yet-started
    /// sensor is reported and left unchanged.
    func startDiagnosticNFCStreamingRepair() {
        guard getConnectionStatus() != .connected else {
            trace("LIBRE_DIAG NFC streaming repair skipped because BLE is already connected", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            return
        }

        guard NFCTagReaderSession.readingAvailable else {
            DispatchQueue.main.async { [weak self] in
                self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.deviceMustSupportNFC)
            }
            return
        }

        stopScanning()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.libreNFC == nil else { return }
            trace("LIBRE_DIAG opening streaming-only NFC session after the 60-minute lockout", log: self.log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            self.libreNFC = LibreNFC(libreNFCDelegate: self, diagnosticMode: .enableStreamingOnly)
            (self.libreNFC as? LibreNFC)?.startSession()
        }
    }

    /// Opens exactly one upstream-style activation NFC operation. After A1 1B
    /// it performs DiaBLE's immediate FRAM reread, but it cannot fall through
    /// to A1 1E or BLE.
    func startDiagnosticNFCActivation() {
        guard NFCTagReaderSession.readingAvailable else {
            DispatchQueue.main.async { [weak self] in
                self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.deviceMustSupportNFC)
            }
            return
        }

        // Activation is always an explicit user action. Stop any observation
        // of the previous sensor first; the NFC layer then CRC-checks the new
        // sensor, requires a supported non-Gen2 Libre 2 Plus (C6 or 7F) in
        // not-started/age-zero state, and persists its one-shot guard before
        // issuing A1 1B. It cannot continue into A1 1E or BLE.
        stopScanning()
        disconnect()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.libreNFC == nil else { return }
            trace("LIBRE_DIAG opening explicit one-shot fresh-sensor activation session", log: self.log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            self.libreNFC = LibreNFC(libreNFCDelegate: self, diagnosticMode: .activationOnly)
            (self.libreNFC as? LibreNFC)?.startSession()
        }
    }
#endif
    
    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        super.centralManager(central, didConnect: peripheral)

#if DEBUG
        if let sensorSerialNumber {
            UserDefaults.standard.set(sensorSerialNumber, forKey: DiagnosticDefaultsKey.sensorSerialNumber)
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: DiagnosticDefaultsKey.peripheralAddress)
            trace("LIBRE_DIAG persisted sensor-specific BLE identity sensor=%{public}@ address=%{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, sensorSerialNumber, peripheral.identifier.uuidString)

            // The recovery transmitter is adopted as a normal Libre device by
            // BluetoothPeripheralManager during super.didConnect. Queue the
            // serial update after that adoption so the Core Data row is fully
            // usable on subsequent launches without the diagnostic fallback.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.cGMLibre2TransmitterDelegate?.received(serialNumber: sensorSerialNumber, from: self)
            }
        }
#endif
        
        if let sensorSerialNumber = tempSensorSerialNumber {
            // we need to send the sensorSerialNumber here. Possibly this is a new transmitter being scanned for, in which case the call to cGMLibre2TransmitterDelegate?.received(sensorSerialNumber: ..) in NFCTagReaderSessionDelegate functions wouldn't have stored the status in coredata, because it' doesn't find the transmitter, so let's store it again, at each connect, if not nil
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.cGMLibre2TransmitterDelegate?.received(serialNumber: sensorSerialNumber.serialNumber, from: self)
            }
            
            // set to nil so we don't send it again to the delegate when there's a new connect
            tempSensorSerialNumber = nil
            
            // for Libre 2, the device name includes the sensor id
            // if tempSensorSerialNumber != deviceName, then it means the user has connected to another (older?) Libre 2 with bluetooth than the one for which NFC scan was done, in that case, inform user
            // compare only the last 10 characters. Normally it should be 10, but for some reason, xDrip4iOS does not correctly decode the sensor uid, the first character is not correct
            if let deviceName = deviceName, sensorSerialNumber.serialNumber.suffix(9).uppercased() != deviceName.suffix(9) {
                DispatchQueue.main.async { [weak self] in
                    self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.connectedLibre2DoesNotMatchScannedLibre2)
                }
                
            } else {
                // user should be informed not to scan with the Libre app
                DispatchQueue.main.async { [weak self] in
                    self?.bluetoothTransmitterDelegate?.error(message: TextsLibreNFC.donotusethelibrelinkapp)
                }
            }
        }
    }

    override func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateValueFor: characteristic, error: error)
        
        // there should be already stored a value for libreSensorUID in the userdefaults at this moment, otherwise processing is not possible
        guard let libreSensorUID = UserDefaults.standard.libreSensorUID else {
            trace("in peripheral didUpdateValueFor but libreSensorUID is not known, no further processing", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            
            return
        }
        
        if let value = characteristic.value {
            processValue(value: value, sensorUID: libreSensorUID)
            
        } else {
            trace("in peripheral didUpdateValueFor, value is nil, no further processing", log: log, category: ConstantsLog.categoryCGMLibre2, type: .error)
        }
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        super.peripheral(peripheral, didUpdateNotificationStateFor: characteristic, error: error)
        
        // there should be already stored a value for libreSensorUID in the userdefaults at this moment, otherwise processing is not possible
        guard let libreSensorUID = UserDefaults.standard.libreSensorUID else {
            trace("in peripheral didUpdateNotificationStateFor but libreSensorUID is not known, no further processing", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            
            return
        }
        
        // there should be already stored a value for librePatchInfo in the userdefaults at this moment, otherwise processing is not possible
        guard let librePatchInfo = UserDefaults.standard.libreInitialPatchInfo ?? UserDefaults.standard.librePatchInfo else {
            trace("in peripheral didUpdateNotificationStateFor but librePatchInfo is not known, no further processing", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            
            return
        }
        
        if error == nil && characteristic.isNotifying {
            UserDefaults.standard.libreActiveSensorUnlockCount += 1
            
            trace("sensorid as data =  %{public}@, patchinfo = %{public}@, unlockcode = %{public}@, unlockcount = %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, libreSensorUID.toHexString(), librePatchInfo.toHexString(), UserDefaults.standard.libreActiveSensorUnlockCode.description, UserDefaults.standard.libreActiveSensorUnlockCount.description)
            
            let unLockPayLoad = Data(Libre2BLEUtilities.streamingUnlockPayload(sensorUID: libreSensorUID, info: librePatchInfo, enableTime: UserDefaults.standard.libreActiveSensorUnlockCode, unlockCount: UserDefaults.standard.libreActiveSensorUnlockCount))
            
            trace("in peripheral didUpdateNotificationStateFor, writing streaming unlock payload: %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, unLockPayLoad.toHexString())
                
            // user may have chosen to run xDrip4iOS in parallel with other apps, in this case suppress sending unlockpayload
            if !UserDefaults.standard.suppressUnLockPayLoad {
                _ = writeDataToPeripheral(data: unLockPayLoad, type: .withResponse)
            }
        }
    }
    
    override func prepareForRelease() {
        // Clear base CB delegates + unsubscribe common receiveCharacteristic synchronously on main
        super.prepareForRelease()
        // Libre2-specific transient state cleanup
        let tearDown = {
            self.rxBuffer = Data()
            self.startDate = Date()
            self.tempSensorSerialNumber = nil
            self.libreNFC = nil
            self.libreSensorType = nil
        }
        if Thread.isMainThread {
            tearDown()
        } else {
            DispatchQueue.main.sync(execute: tearDown)
        }
    }

    deinit {
        // Defensive: clear transient buffers
        rxBuffer = Data()
    }

    // MARK: - helpers
    
    /// reset rxBuffer, reset startDate, stop packetRxMonitorTimer, set resendPacketCounter to 0
    private func resetRxBuffer() {
        rxBuffer = Data()
        startDate = Date()
    }
    
    /// process value received from transmitter
    public func processValue(value: Data, sensorUID: Data) {
        // check if buffer needs to be reset
        if Date() > startDate.addingTimeInterval(CGMLibre2Transmitter.maxWaitForpacketInSeconds) {
            trace("in peripheral didUpdateValueFor, more than %{public}@ seconds since last update - or first update since app launch, resetting buffer", log: log, category: ConstantsLog.categoryCGMLibre2, type: .debug, CGMLibre2Transmitter.maxWaitForpacketInSeconds.description)
            
            resetRxBuffer()
        }
        
        // add new value to rxBuffer
        rxBuffer.append(value)
        
        // check if enough bytes are received, and if yes start processing
        if rxBuffer.count == expectedBufferSize {
            // Log once per completed Libre2 frame (moved from didUpdateValueFor to avoid per-fragment duplication)
            do {
                var libre1DerivedAlgorithmParametersAsString: String!
                if let libre1DerivedAlgorithmParameters = UserDefaults.standard.libre1DerivedAlgorithmParameters {
                    libre1DerivedAlgorithmParametersAsString = libre1DerivedAlgorithmParameters.description
                } else {
                    libre1DerivedAlgorithmParametersAsString = "unknown"
                }
                trace("in peripheral didUpdateValueFor libreSensorUID = %{public}@, libre1DerivedAlgorithmParameters = %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .debug, sensorUID.toHexString(), libre1DerivedAlgorithmParametersAsString)
            }
            
            do {
                // if libre1DerivedAlgorithmParameters not nil, but not matching serial number, then assign to nil (copied from LibreDataParser)
                // if weboopenabled, then don't proceed, because weboop needs libre1DerivedAlgorithmParameters
                // if libre1DerivedAlgorithmParameters is nil, but not weboopenabled, then also no further processing
                // this may happen in case the serialNumber is not correctly read from NFC or stored in coredata - if all goes well this shouldn't occur
                if isWebOOPEnabled() {
                    guard let libre1DerivedAlgorithmParameters = UserDefaults.standard.libre1DerivedAlgorithmParameters, libre1DerivedAlgorithmParameters.serialNumber == sensorSerialNumber else {
                        trace("web oop enabled but libre1DerivedAlgorithmParameters is nil or libre1DerivedAlgorithmParameters.serialNumber != sensorSerialNumber, no further processing", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
                        
                        return
                    }
                }
                
                // decrypt buffer and parse
                // if oop web not enabled, then don't pass libre1DerivedAlgorithmParameters
                let parsedBLEData = try Libre2BLEUtilities.parseBLEData(Data(Libre2BLEUtilities.decryptBLE(sensorUID: sensorUID, data: rxBuffer)), libre1DerivedAlgorithmParameters: isWebOOPEnabled() ? UserDefaults.standard.libre1DerivedAlgorithmParameters : nil)
                
                // deliver glucose data and sensor age to delegates on main; use local copy for inout
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    var copy = parsedBLEData.bleGlucose
                    self.cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &copy, transmitterBatteryInfo: nil, sensorAge: TimeInterval(minutes: Double(parsedBLEData.sensorTimeInMinutes)))
                    self.cGMLibre2TransmitterDelegate?.received(sensorTimeInMinutes: Int(parsedBLEData.sensorTimeInMinutes), from: self)
                }
                
                // TODO: add sensor start date -> userdefaults
                
            } catch {
                trace("in peripheral didUpdateValueFor, error while parsing/decrypting data =  %{public}@ ", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, error.localizedDescription)
                
                resetRxBuffer()
            }
        }
    }

    // MARK: - CGMTransmitter protocol functions
    
    func setNonFixedSlopeEnabled(enabled: Bool) {
        if nonFixedSlopeEnabled != enabled {
            nonFixedSlopeEnabled = enabled
        }
    }
    
    /// set webOOPEnabled value
    func setWebOOPEnabled(enabled: Bool) {
        if webOOPEnabled != enabled {
            webOOPEnabled = enabled
        }
    }
    
    func cgmTransmitterType() -> CGMTransmitterType {
        return .Libre2
    }
    
    func isWebOOPEnabled() -> Bool {
        return webOOPEnabled
    }
    
    func isNonFixedSlopeEnabled() -> Bool {
        return nonFixedSlopeEnabled
    }
    
    func maxSensorAgeInDays() -> Double? {
        return libreSensorType?.maxSensorAgeInDays()
    }
    
    func getCBUUID_Service() -> String {
        return CBUUID_Service_Libre2
    }
    
    func getCBUUID_Receive() -> String {
        return CBUUID_ReceiveCharacteristic_Libre2
    }
}

#else

@objcMembers
class CGMLibre2Transmitter: BluetoothTransmitter, CGMTransmitter {}

#endif

// MARK: - LibreNFCDelegate functions

extension CGMLibre2Transmitter: LibreNFCDelegate {
    func received(fram: Data) {
        trace("received fram :  %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, fram.toHexString())
        
        // if we already know the patchinfo (which we should because normally received(sensorUID: Data, patchInfo: Data) gets called before received(fram: Data), then patchInfo should not be nil
        // same for sensorUID
        if let patchInfo = UserDefaults.standard.librePatchInfo, let sensorUID = UserDefaults.standard.libreSensorUID, let libreSensorType = LibreSensorType.type(patchInfo: patchInfo.hexEncodedString().uppercased()), let serialNumber = sensorSerialNumber {
            self.libreSensorType = libreSensorType
            
            var framCopy = fram
            
            if libreSensorType.decryptIfPossibleAndNeeded(rxBuffer: &framCopy, headerLength: 0, log: log, patchInfo: patchInfo.hexEncodedString().uppercased(), uid: Array(sensorUID)) {
                // we have all date to create libre1DerivedAlgorithmParameters
                UserDefaults.standard.libre1DerivedAlgorithmParameters = Libre1DerivedAlgorithmParameters(bytes: framCopy, serialNumber: serialNumber, libreSensorType: libreSensorType)
            }
        }
    }
    
    func received(sensorUID: Data, patchInfo: Data) {
        // store sensorUID as data in UserDefaults
        UserDefaults.standard.libreSensorUID = sensorUID
        
        // store the sensorUID as tempSensorSerialNumber (as LibreSensorSerialNumber)
        let receivedSensorSerialNumber = LibreSensorSerialNumber(withUID: sensorUID, with: LibreSensorType.type(patchInfo: patchInfo.toHexString()))
        if let receivedSensorSerialNumber = receivedSensorSerialNumber {
            tempSensorSerialNumber = receivedSensorSerialNumber
        }
        
        // sensor serial number as String
        let receivedSensorSerialNumberAsString = receivedSensorSerialNumber?.serialNumber
        
        if let receivedSensorSerialNumberAsString = receivedSensorSerialNumberAsString {
            // is it a new value ?
            if sensorSerialNumber != receivedSensorSerialNumberAsString {
                trace("new sensor detected :  %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, receivedSensorSerialNumberAsString)
                
                sensorSerialNumber = receivedSensorSerialNumberAsString
                
                // assign sensorStartDate, for this type of transmitter the sensorAge is passed in another call to cgmTransmitterDelegate
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.cgmTransmitterDelegate?.newSensorDetected(sensorStartDate: nil)
                    self.cGMLibre2TransmitterDelegate?.received(serialNumber: receivedSensorSerialNumberAsString, from: self)
                }
            }
            
        } else {
            trace("could not created sensor serial number from received sensorUID, sensorUID = %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, sensorUID.toHexString())
        }
        
        trace("patchInfo received :  %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, patchInfo.toHexString())
        
        UserDefaults.standard.librePatchInfo = patchInfo
    }
    
    func streamingEnabled(successful: Bool) {
        if successful {
            trace("received streaming enabled message from NFC with result successful, setting unlockCount to 0", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)

            // Preserve the patch info used by the successful enable-streaming
            // exchange. DiaBLE keeps the same distinction because subsequent
            // NFC reads may expose different current patch bytes, while BLE
            // unlocks must continue using this original value.
            if let patchInfo = UserDefaults.standard.librePatchInfo {
                UserDefaults.standard.libreInitialPatchInfo = patchInfo
                trace("LIBRE_DIAG preserved BLE initial patchInfo=%{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, patchInfo.toHexString())
            }
            
            UserDefaults.standard.libreActiveSensorUnlockCount = 0

        } else {
            trace("received streaming enabled message from NFC with result unsuccessful", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
        }
    }

#if DEBUG
    func activationCompleted() {
        trace("LIBRE_DIAG activation-only delegate completed; releasing NFC object and leaving BLE stopped for 60 minutes", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
        stopScanning()
        disconnect()
        libreNFC = nil
    }
#endif
    
    func nfcScanResult(successful: Bool) {
        if successful {
            trace("received NFC scan result from NFC with result successful", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            
            // only process if userdefaults needs changing to true to avoid triggering the observer unnecessarily
            if !UserDefaults.standard.nfcScanSuccessful {
                UserDefaults.standard.nfcScanSuccessful = true
            }
            
        } else {
            trace("received NFC scan result from NFC with result unsuccessful", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
            
            // only process if userdefaults needs changing to true to avoid triggering the observer unnecessarily
            if !UserDefaults.standard.nfcScanFailed {
                UserDefaults.standard.nfcScanFailed = true
            }
        }
    }
    
    func startBLEScanning() {
        trace("LIBRE_DIAG NFC handoff complete; starting BLE scan", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info)
        _ = super.startScanning()
    }
    
    func nfcScanExpectedDevice(serialNumber: String, macAddress: String) {
        // A replacement sensor has a different CoreBluetooth identifier. The
        // existing Libre transmitter instance may still contain the previous
        // sensor's address, which otherwise takes precedence over expectedName
        // and causes the correct advertisement to be ignored indefinitely.
        disconnectAndForget()

        if libreSensorType == .libre27F {
            trace("LIBRE_DIAG 7F sensor expects BLE MAC-style name %{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, macAddress)
            updateExpectedDeviceName(name: macAddress)
        } else {
            trace("LIBRE_DIAG sensor type %{public}@ expects ABBOTT serial-style name ABBOTT%{public}@", log: log, category: ConstantsLog.categoryCGMLibre2, type: .info, libreSensorType?.description ?? "nil", serialNumber)
            updateExpectedDeviceName(name: "ABBOTT" + serialNumber)
        }
    }
}
