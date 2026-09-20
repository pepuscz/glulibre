import CoreData
import SwiftUI

/// Presentation services reuse the live managers. Opening a screen never starts NFC,
/// replaces a transmitter, changes alarms, or migrates the user's database.
@MainActor
final class JournalManagement: ObservableObject {
  var contextProvider: () -> NSManagedObjectContext? = { nil }
  var managerProvider: () -> BluetoothPeripheralManager? = { nil }
  var settingsProvider: (JournalService) -> SettingsViewModelProtocol? = { _ in nil }
  var persistChanges: () -> Void = {}
  @Published var message: String?
  @Published private(set) var alarms: [AlertEntry] = []
  @Published private(set) var records: [TreatmentEntry] = []
  @Published private(set) var devices: [BluetoothPeripheral] = []

  func refresh() {
    devices = managerProvider()?.getBluetoothPeripherals() ?? []
    guard let context = contextProvider() else { return }
    do {
      let request: NSFetchRequest<AlertEntry> = AlertEntry.fetchRequest()
      request.sortDescriptors = [
        NSSortDescriptor(key: "alertkind", ascending: true),
        NSSortDescriptor(key: "start", ascending: true),
      ]
      alarms = try context.fetch(request)
      let history: NSFetchRequest<TreatmentEntry> = TreatmentEntry.fetchRequest()
      history.predicate = NSPredicate(format: "treatmentdeleted == NO")
      history.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
      records = try context.fetch(history)
    } catch { message = "Couldn’t read saved settings. Nothing has been changed." }
  }

  var warmupEnd: Date? {
    #if DEBUG
      guard let uid = UserDefaults.standard.libreSensorUID,
        let accepted = LibreNFC.diagnosticActivationAcceptedAt(sensorUID: uid)
      else { return nil }
      return accepted.addingTimeInterval(3600)
    #else
      return nil
    #endif
  }

  var isWarmingUp: Bool { warmupEnd.map { $0 > Date() } ?? false }

  private func libreTransmitter() -> CGMLibre2Transmitter? {
    guard let manager = managerProvider() else {
      message = "Sensor services are still starting."
      return nil
    }
    let saved = manager.getBluetoothPeripherals().filter {
      $0.bluetoothPeripheralType() == .Libre2Type
    }
    if let device = saved.first(where: {
      $0.blePeripheral.address == manager.currentCgmTransmitterAddress
    }) ?? saved.first(where: { $0.blePeripheral.shouldconnect }) ?? saved.first,
      let transmitter = manager.getBluetoothTransmitter(
        for: device, createANewOneIfNecesssary: true) as? CGMLibre2Transmitter
    {
      return transmitter
    }
    if let transmitter = manager.tempBlueToothTransmitterWhileScanningForNewBluetoothPeripheral
      as? CGMLibre2Transmitter
    {
      return transmitter
    }
    // Register with the same discovery/persistence path used by the working pairing flow.
    let transmitter = manager.createNewTransmitter(
      type: .Libre2Type, transmitterId: nil, bluetoothTransmitterDelegate: nil)
    manager.transmitterTypeBeingScannedFor = .Libre2Type
    manager.tempBlueToothTransmitterWhileScanningForNewBluetoothPeripheral = transmitter
    manager.callBackAfterDiscoveringDevice = { [weak self] _ in
      DispatchQueue.main.async {
        self?.refresh()
        JournalModel.shared.refreshSensor()
      }
    }
    return transmitter as? CGMLibre2Transmitter
  }

  func activateNewLibre() {
    #if DEBUG && !targetEnvironment(simulator)
      guard !isWarmingUp else {
        message = "Your sensor is warming up. No scan is needed."
        return
      }
      libreTransmitter()?.startDiagnosticNFCActivation()
    #else
      message = "Sensor activation is available on the paired iPhone development build."
    #endif
  }

  func finishLibreSetup() {
    #if DEBUG && !targetEnvironment(simulator)
      guard !isWarmingUp else {
        message = "Wait for the warm-up notification. No scan is needed yet."
        return
      }
      libreTransmitter()?.startDiagnosticNFCStreamingRepair()
    #else
      message = "NFC requires a physical iPhone. No sensor settings were changed."
    #endif
  }

  func reconnect() {
    guard !isWarmingUp else {
      message = "The sensor is warming up. Reconnection will resume afterward."
      return
    }
    guard let manager = managerProvider(),
      let device = manager.getBluetoothPeripherals().first(where: {
        $0.blePeripheral.address == manager.currentCgmTransmitterAddress
      })
        ?? manager.getBluetoothPeripherals().first(where: {
          $0.blePeripheral.shouldconnect && $0.bluetoothPeripheralType().category() == .CGM
        })
    else {
      message = "No saved sensor connection. Open sensor setup to continue."
      return
    }
    guard device.blePeripheral.shouldconnect else {
      message = "This saved device has its connection disabled."
      return
    }
    let transmitter = manager.getBluetoothTransmitter(for: device, createANewOneIfNecesssary: true)
    guard transmitter?.getConnectionStatus() != .connected else {
      message = "Bluetooth is already connected. Waiting for the next reading."
      return
    }
    #if DEBUG
      if let libre = transmitter as? CGMLibre2Transmitter {
        libre.startDiagnosticBLEOnly()
        return
      }
    #endif
    manager.connect(to: device)
  }

  func setConnection(_ enabled: Bool, for device: BluetoothPeripheral) {
    guard let manager = managerProvider() else {
      message = "Sensor services are still starting."
      return
    }
    if enabled {
      if device.bluetoothPeripheralType().category() == .CGM {
        guard UserDefaults.standard.isMaster else {
          message =
            "This app is receiving shared readings. Change Reading source before connecting a sensor directly."
          return
        }
        guard
          !manager.getBluetoothPeripherals().contains(where: {
            $0.blePeripheral.address != device.blePeripheral.address
              && $0.blePeripheral.shouldconnect && $0.bluetoothPeripheralType().category() == .CGM
          })
        else {
          message = "Another sensor is enabled. Pause its connection before enabling this one."
          return
        }
      }
      device.blePeripheral.shouldconnect = true
      persistChanges()
      manager.connect(to: device)
    } else {
      manager.disconnect(fromBluetoothPeripheral: device)
    }
    refresh()
    JournalModel.shared.refreshSensor()
  }

  func saveAlarm(_ draft: JournalAlarmDraft, entry: AlertEntry) throws {
    guard let context = entry.managedObjectContext, !entry.isDeleted,
      let kind = AlertKind(rawValue: Int(entry.alertkind))
    else { throw JournalManagementError.unavailable }
    guard (0...1439).contains(draft.start), (1...32767).contains(draft.value),
      (0...32767).contains(draft.trigger), (0...1440).contains(draft.snoozeMinutes),
      !draft.snooze || draft.snoozeMinutes > 0
    else { throw JournalManagementError.invalidAlarm }
    let siblings = try context.fetch(AlertEntry.fetchRequest()).filter {
      $0.alertkind == entry.alertkind
    }
    guard entry.start == 0 ? draft.start == 0 : draft.start > 0,
      !siblings.contains(where: { $0 !== entry && Int($0.start) == draft.start })
    else { throw JournalManagementError.duplicateTime }
    // Keep shared sound profiles untouched. An edited sound becomes this period's
    // own profile; all other alarms continue using their exact original settings.
    let original = JournalAlarmDraft(entry)
    let disabled = siblings.map { ($0, $0.isDisabled) }
    let oldType = entry.alertType
    var newType: AlertType?
    if draft.sound != original.sound || draft.vibrate != original.vibrate
      || draft.overrideMute != original.overrideMute || draft.snooze != original.snooze
      || draft.snoozeMinutes != original.snoozeMinutes
      || draft.profileEnabled != original.profileEnabled
    {
      newType = AlertType(
        enabled: draft.profileEnabled,
        name: "\(kind.alertTitle()) · \(UUID().uuidString.prefix(6))",
        overrideMute: draft.overrideMute, snooze: draft.snooze, snoozePeriod: draft.snoozeMinutes,
        vibrate: draft.vibrate,
        soundName: draft.sound == JournalAlarmDraft.systemSound ? nil : draft.sound,
        alertEntries: nil, nsManagedObjectContext: context)
      entry.alertType = newType!
    }
    siblings.forEach { $0.isDisabled = !draft.enabled }
    entry.start = Int16(draft.start)
    entry.value = Int16(draft.value)
    entry.triggerValue = Int16(draft.trigger)
    do {
      if let newType { try context.obtainPermanentIDs(for: [newType]) }
      try context.save()
    } catch {
      entry.start = Int16(original.start)
      entry.value = Int16(original.value)
      entry.triggerValue = Int16(original.trigger)
      entry.alertType = oldType
      disabled.forEach { $0.0.isDisabled = $0.1 }
      if let newType { context.delete(newType) }
      throw error
    }
    if kind == .missedreading { UserDefaults.standard.missedReadingAlertChanged = true }
    persistChanges()
    refresh()
  }

  func addAlarmPeriod(from entry: AlertEntry, start: Int) throws {
    guard let context = entry.managedObjectContext,
      let kind = AlertKind(rawValue: Int(entry.alertkind)), (1...1439).contains(start)
    else { throw JournalManagementError.duplicateTime }
    let siblings = try context.fetch(AlertEntry.fetchRequest()).filter {
      $0.alertkind == entry.alertkind
    }
    guard !siblings.contains(where: { Int($0.start) == start }) else {
      throw JournalManagementError.duplicateTime
    }
    let added = AlertEntry(
      isDisabled: entry.isDisabled, value: Int(entry.value), triggerValue: Int(entry.triggerValue),
      alertKind: kind, start: start, alertType: entry.alertType, nsManagedObjectContext: context)
    do {
      try context.obtainPermanentIDs(for: [added])
      try context.save()
    } catch {
      context.delete(added)
      throw error
    }
    if kind == .missedreading { UserDefaults.standard.missedReadingAlertChanged = true }
    persistChanges()
    refresh()
  }

  func removeAlarmPeriod(_ entry: AlertEntry) throws {
    guard entry.start > 0, let context = entry.managedObjectContext else {
      throw JournalManagementError.duplicateTime
    }
    if entry.objectID.isTemporaryID { try context.obtainPermanentIDs(for: [entry]) }
    // A child context makes deletion failure safe without rolling back unrelated readings.
    let child = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
    child.parent = context
    let object = try child.existingObject(with: entry.objectID)
    child.delete(object)
    let missed = Int(entry.alertkind) == AlertKind.missedreading.rawValue
    try child.save()
    if missed { UserDefaults.standard.missedReadingAlertChanged = true }
    persistChanges()
    refresh()
  }
}

enum JournalManagementError: LocalizedError {
  case unavailable, invalidAlarm, duplicateTime
  var errorDescription: String? {
    switch self {
    case .unavailable: return "The saved record is unavailable. Reopen this screen and try again."
    case .invalidAlarm:
      return "Enter a positive threshold and a snooze between 1 and 1,440 minutes."
    case .duplicateTime:
      return "Choose a different start time. The first period must start at midnight."
    }
  }
}

struct JournalAlarmDraft: Equatable {
  static let systemSound = "__system__"
  var enabled: Bool
  var profileEnabled: Bool
  var start: Int
  var value: Int
  var trigger: Int
  var sound: String
  var vibrate: Bool
  var overrideMute: Bool
  var snooze: Bool
  var snoozeMinutes: Int
  init(_ entry: AlertEntry) {
    enabled = !entry.isDisabled
    profileEnabled = entry.alertType.enabled
    start = Int(entry.start)
    value = Int(entry.value)
    trigger = Int(entry.triggerValue)
    sound = entry.alertType.soundname ?? Self.systemSound
    vibrate = entry.alertType.vibrate
    overrideMute = entry.alertType.overridemute
    snooze = entry.alertType.snooze
    snoozeMinutes = Int(entry.alertType.snoozeperiod)
  }
}

enum JournalService: String, CaseIterable, Identifiable {
  case nightscout = "Nightscout"
  case dexcom = "Dexcom Share"
  case watch = "Apple Watch"
  case speech = "Spoken readings"
  case calendar = "Calendar"
  case contact = "Contact image"
  case source = "Reading source"
  case data = "Storage & export"
  var id: String { rawValue }
}

#if DEBUG && targetEnvironment(simulator)
  extension JournalManagement {
    /// Uses an isolated store and the same parent/child topology as the live app.
    /// Never reads or writes the user's sensor or alert database.
    static func runAlarmChecks() {
      do {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague")!
        for components in [DateComponents(year: 2026, month: 3, day: 29), DateComponents(year: 2026, month: 10, day: 25)] {
          let day = calendar.date(from: components)!
          let morning = JournalAlarmEditor.time(480, on: day, calendar: calendar)
          precondition(calendar.component(.hour, from: morning) == 8 && calendar.component(.minute, from: morning) == 0)
        }
        let url = Bundle.main.url(forResource: ConstantsCoreData.modelName, withExtension: "momd")!
        let coordinator = NSPersistentStoreCoordinator(
          managedObjectModel: NSManagedObjectModel(contentsOf: url)!)
        try coordinator.addPersistentStore(
          ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
        let parent = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        parent.persistentStoreCoordinator = coordinator
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.parent = parent
        let service = JournalManagement()
        service.contextProvider = { context }
        let sound = AlertType(
          enabled: true, name: "Existing shared sound", overrideMute: true, snooze: true,
          snoozePeriod: 15, vibrate: true, soundName: nil, alertEntries: nil,
          nsManagedObjectContext: context)
        let low = AlertEntry(
          isDisabled: false, value: 71, triggerValue: 0, alertKind: .low, start: 0,
          alertType: sound, nsManagedObjectContext: context)
        let high = AlertEntry(
          isDisabled: false, value: 181, triggerValue: 0, alertKind: .high, start: 0,
          alertType: sound, nsManagedObjectContext: context)
        try context.save()
        try parent.save()
        service.refresh()
        let original = JournalAlarmDraft(low)
        _ = JournalAlarmDraft(low)  // Opening/cancelling is read-only.
        service.refresh()
        precondition(JournalAlarmDraft(low) == original && !context.hasChanges)
        try service.saveAlarm(original, entry: low)
        precondition(low.alertType === sound && low.value == 71)
        var changed = original
        changed.sound = ""
        changed.value = 72
        changed.profileEnabled = false
        try service.saveAlarm(changed, entry: low)
        precondition(low.alertType !== sound && high.alertType === sound)
        precondition(
          sound.enabled && sound.soundname == nil && sound.overridemute && sound.snoozeperiod == 15)
        precondition(high.value == 181 && !high.isDisabled && !low.alertType.enabled)
        try service.addAlarmPeriod(from: low, start: 480)
        let added = service.alarms.first { $0.alertkind == low.alertkind && $0.start == 480 }!
        precondition(added.value == low.value && added.alertType === low.alertType)
        do {
          try service.addAlarmPeriod(from: low, start: 480)
          preconditionFailure("Duplicate alarm time accepted")
        } catch {}
        do {
          try service.removeAlarmPeriod(low)
          preconditionFailure("Midnight alarm deleted")
        } catch {}
        var off = JournalAlarmDraft(added)
        off.enabled = false
        try service.saveAlarm(off, entry: added)
        precondition(low.isDisabled && added.isDisabled && !high.isDisabled)
        try service.removeAlarmPeriod(added)
        try context.save()
        try parent.save()
        service.refresh()
        let remainingPeriods = service.alarms.map { "\($0.alertkind):\($0.start)" }
        precondition(
          service.alarms.count == 2 && service.alarms.contains { $0 === low },
          "After deletion: \(remainingPeriods)")
        var invalid = original
        invalid.start = 120
        do {
          try service.saveAlarm(invalid, entry: low)
          preconditionFailure("Midnight alarm moved")
        } catch {}
        precondition(low.start == 0 && high.alertType === sound)
        NSLog(
          "JOURNAL_ALARM_CHECKS PASS read-only opening, exact thresholds, shared profile isolation, add/delete, midnight protection, duplicate rejection, global enable, child-context persistence"
        )
      } catch { preconditionFailure("Journal alarm checks failed: \(error)") }
    }
  }
#endif
