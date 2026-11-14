import CoreData
import Combine

/// A standalone BLEPeripheral is sufficient: SmartGuide needs no new Core Data
/// entity or schema migration. The namespaced discriminator is never a PIN.
extension BLEPeripheral: BluetoothPeripheral {
    static let smartGuideMarker = "GluLibre.SmartGuide.v1:"
    var isSmartGuide: Bool {
        transmitterId?.hasPrefix(Self.smartGuideMarker) == true
            && libre2 == nil && dexcomG5 == nil && dexcomG7 == nil && bubble == nil
            && miaoMiao == nil && m5Stack == nil && libre2heartbeat == nil
            && dexcomG7HeartBeat == nil && omniPodHeartBeat == nil
    }
    var smartGuideSerial: String {
        guard isSmartGuide else { return "" }
        return String(transmitterId!.dropFirst(Self.smartGuideMarker.count))
    }
    var blePeripheral: BLEPeripheral { self }
    func bluetoothPeripheralType() -> BluetoothPeripheralType { .smartGuide }

    static func makeSmartGuide(address: String, name: String, context: NSManagedObjectContext) -> BLEPeripheral {
        let device = BLEPeripheral(address: address, name: name, alias: nil, bluetoothPeripheralType: .smartGuide,
                                   nsManagedObjectContext: context)
        let serial = name.uppercased().hasPrefix("AC-") ? String(name.dropFirst(3)).uppercased() : ""
        device.transmitterId = smartGuideMarker + serial
        device.sensorSerialNumber = serial
        device.nonFixedSlopeEnabled = false
        device.webOOPEnabled = true
        return device
    }
}

@MainActor
final class SmartGuideConnectionState: ObservableObject {
    static let shared = SmartGuideConnectionState()
    @Published var serial = ""
    @Published var message = "Ready to connect"
    @Published var model = ""
    @Published var firmware = ""
    @Published var calibrationAvailable = false
    @Published var calibrationUnavailableReason = "Connect your sensor to calibrate."
    @Published var canCheckCalibration = false
    @Published var calibrationResult = ""
    @Published var canInitialize = false
}

#if DEBUG && targetEnvironment(simulator)
extension BLEPeripheral {
    static func runSmartGuidePersistenceChecks() {
        do {
            let modelURL = Bundle.main.url(forResource: ConstantsCoreData.modelName, withExtension: "momd")!
            let coordinator = NSPersistentStoreCoordinator(managedObjectModel: NSManagedObjectModel(contentsOf: modelURL)!)
            try coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
            let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            let libre = Libre2(address: UUID().uuidString, name: "Synthetic Libre", alias: nil, nsManagedObjectContext: context)
            let device = makeSmartGuide(address: UUID().uuidString, name: "AC-12345678", context: context)
            try context.save()
            let id = device.objectID
            context.reset()
            let saved = try context.existingObject(with: id) as! BLEPeripheral
            precondition(saved.isSmartGuide && saved.smartGuideSerial == "12345678")
            precondition(saved.bluetoothPeripheralType() == .smartGuide && saved.shouldconnect)
            precondition(saved.webOOPEnabled && !saved.nonFixedSlopeEnabled)
            precondition(!saved.isDeleted && saved.libre2 == nil && saved.dexcomG7 == nil)
            let all = try context.fetch(BLEPeripheral.fetchRequest())
            precondition(all.count == 2 && all.filter { $0.libre2 != nil && !$0.isSmartGuide }.count == 1)
            _ = libre // Retain original fixture until after the reset; never a real sensor.
            saved.shouldconnect = false
            try context.save()
            context.reset()
            let paused = try context.existingObject(with: id) as! BLEPeripheral
            precondition(paused.isSmartGuide && !paused.shouldconnect)
            NSLog("SMARTGUIDE_STORAGE_CHECKS PASS identity, persistence, pause, no schema migration, Libre preserved")
        } catch { preconditionFailure("SmartGuide persistence check: \(error)") }
    }
}
#endif
