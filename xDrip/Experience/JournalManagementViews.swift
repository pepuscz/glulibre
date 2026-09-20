import CoreData
import SwiftUI

struct JournalSensorSetupView: View {
  @ObservedObject var model: JournalModel
  @ObservedObject var management: JournalManagement
  @State private var activating = false
  @State private var finishing = false
  var body: some View {
    List {
      Section {
        VStack(alignment: .leading, spacing: 16) {
          Image(systemName: management.isWarmingUp ? "timer" : "sensor.tag.radiowaves.forward")
            .font(.system(size: 42)).foregroundStyle(JournalStyle.accent).accessibilityHidden(true)
          Text(management.isWarmingUp ? "Getting ready" : "Connect your sensor").font(
            .title2.bold())
          if management.isWarmingUp, let end = management.warmupEnd {
            Text(end, style: .timer).font(.largeTitle.monospacedDigit())
            Text("We’ll notify you when it’s ready. No more scans during warm-up.").foregroundStyle(
              .secondary)
          } else {
            Text("Libre 2 / 2 Plus EU").foregroundStyle(.secondary)
          }
        }.padding(.vertical, 12)
      }
      if !management.isWarmingUp {
        Section {
          Label("Apply a new sensor", systemImage: "1.circle")
          Button {
            activating = true
          } label: {
            Label("Start a new sensor", systemImage: "2.circle")
          }
          Label("Leave it to warm up", systemImage: "3.circle")
          Button {
            finishing = true
          } label: {
            Label("Finish connection", systemImage: "4.circle")
          }
        } footer: {
          Text(
            "Keep the top edge of your iPhone against the sensor until TWO strong vibrations. The first detection pulse isn’t the finish signal."
          )
        }
      }
      if model.sensor.hasDevice {
        Section("Current sensor") {
          LabeledContent("Status", value: model.sensor.link)
          if let serial = management.devices.first(where: {
            $0.bluetoothPeripheralType() == .Libre2Type
          })?.blePeripheral.sensorSerialNumber {
            LabeledContent("Serial number", value: serial).textSelection(.enabled)
          }
        }
      }
    }.navigationTitle("Sensor setup").navigationBarTitleDisplayMode(.inline)
      .onAppear { management.refresh() }
      .onReceive(model.$now) { _ in management.objectWillChange.send() }
      .alert("Start a newly applied sensor?", isPresented: $activating) {
        Button("Cancel", role: .cancel) {}
        Button("Start new sensor") { management.activateNewLibre() }
      } message: {
        Text(
          "Only for a new, unused sensor. This begins its one-hour warm-up. It is not a repair for missing readings."
        )
      }
      .alert("Finish the warmed-up sensor’s connection?", isPresented: $finishing) {
        Button("Cancel", role: .cancel) {}
        Button("Scan to finish") { management.finishLibreSetup() }
      } message: {
        Text(
          "Use after the warm-up notification. This step does not activate the sensor again. Keep holding until two strong vibrations."
        )
      }
      .journalManagementMessage(management)
  }
}

struct JournalDeviceDetailsView: View {
  @ObservedObject var management: JournalManagement
  @State private var changing: BluetoothPeripheral?
  var body: some View {
    List {
      ForEach(management.devices, id: \.blePeripheral.address) { device in
        Section(device.bluetoothPeripheralType().rawValue) {
          LabeledContent("Name", value: device.blePeripheral.alias ?? device.blePeripheral.name)
          LabeledContent(
            "Connection", value: device.blePeripheral.shouldconnect ? "Enabled" : "Disabled")
          if let serial = device.blePeripheral.sensorSerialNumber {
            LabeledContent("Serial number", value: serial).textSelection(.enabled)
          }
          Button(device.blePeripheral.shouldconnect ? "Pause connection" : "Resume connection") {
            changing = device
          }
        }
      }
      if management.devices.isEmpty {
        Label("No saved devices", systemImage: "sensor.tag.radiowaves.forward")
      }
    }.navigationTitle("Saved devices").navigationBarTitleDisplayMode(.inline).onAppear {
      management.refresh()
    }
    .alert(
      changing?.blePeripheral.shouldconnect == true
        ? "Pause this connection?" : "Resume this connection?",
      isPresented: Binding(get: { changing != nil }, set: { if !$0 { changing = nil } })
    ) {
      Button("Cancel", role: .cancel) { changing = nil }
      Button("Confirm") {
        if let changing {
          management.setConnection(!changing.blePeripheral.shouldconnect, for: changing)
        }
        changing = nil
      }
    } message: {
      Text(
        "Pausing stops new readings from this device and may prevent glucose alerts. Saved readings and pairing are kept. Resuming uses Bluetooth; it does not activate the sensor again."
      )
    }
    .journalManagementMessage(management)
  }
}

struct JournalAlarmList: View {
  @ObservedObject var management: JournalManagement
  var body: some View {
    List {
      Section {
        ForEach([AlertKind.verylow, .low, .high, .veryhigh, .missedreading], id: \.rawValue) {
          kind in alarmLink(kind)
        }
      } header: {
        Text("Glucose & connection")
      } footer: {
        Text(
          "These are alert thresholds, not food scores or longevity targets. Your existing settings are preserved."
        )
      }
      Section {
        ForEach(
          [AlertKind.fastdrop, .fastrise, .calibration, .batterylow, .phonebatterylow],
          id: \.rawValue
        ) { kind in alarmLink(kind) }
      } header: {
        Text("Additional alerts")
      }
    }.navigationTitle("Alarms").navigationBarTitleDisplayMode(.inline)
      .onAppear { management.refresh() }.journalManagementMessage(management)
  }
  @ViewBuilder private func alarmLink(_ kind: AlertKind) -> some View {
    let entries = management.alarms.filter { Int($0.alertkind) == kind.rawValue }
    if !entries.isEmpty {
      NavigationLink {
        JournalAlarmSchedule(management: management, kind: kind)
      } label: {
        HStack {
          Text(kind.alertTitle())
          Spacer()
          Text(
            entries.allSatisfy { $0.isDisabled || !$0.alertType.enabled }
              ? "Off" : entries.count > 1 ? "\(entries.count) periods" : "On"
          ).foregroundStyle(.secondary)
        }
      }
    }
  }
}

struct JournalAlarmSchedule: View {
  @ObservedObject var management: JournalManagement
  let kind: AlertKind
  @State private var adding = false
  @State private var newTime = JournalAlarmEditor.time(480)
  @State private var deleting: AlertEntry?
  @State private var error: String?
  var body: some View {
    List {
      Section {
        ForEach(management.alarms.filter { Int($0.alertkind) == kind.rawValue }, id: \.objectID) {
          entry in
          NavigationLink {
            JournalAlarmEditor(management: management, entry: entry)
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 4) {
                Text(
                  entry.start == 0
                    ? "From midnight"
                    : "From \(JournalAlarmEditor.time(Int(entry.start)).formatted(date: .omitted, time: .shortened))"
                )
                Text(
                  entry.isDisabled || !entry.alertType.enabled
                    ? "Off"
                    : "\(kind.valueIsABgValue() ? Double(entry.value).mgDlToMmolAndToString(mgDl: UserDefaults.standard.bloodGlucoseUnitIsMgDl) : String(entry.value)) \(kind.valueUnitText(transmitterType: UserDefaults.standard.cgmTransmitterType))"
                )
                .font(.subheadline).foregroundStyle(.secondary)
              }
              Spacer()
            }
          }
          .swipeActions {
            if entry.start > 0 { Button("Delete", role: .destructive) { deleting = entry } }
          }
        }
      } footer: {
        Text("Each period runs until the next one. Times follow this iPhone’s time zone.")
      }
    }.navigationTitle(kind.alertTitle()).navigationBarTitleDisplayMode(.inline).onAppear {
      management.refresh()
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button("Add period", systemImage: "plus") { adding = true }
      }
    }
    .sheet(isPresented: $adding) {
      NavigationStack {
        Form {
          DatePicker("Starts at", selection: $newTime, displayedComponents: .hourAndMinute)
          Text("Copies the preceding period’s threshold and sound. You can edit them after adding.")
            .font(.subheadline).foregroundStyle(.secondary)
          if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle("Add period").navigationBarTitleDisplayMode(.inline)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Cancel") {
                adding = false
                error = nil
              }
            }
            ToolbarItem(placement: .confirmationAction) {
              Button("Add") {
                let start =
                  Calendar.current.component(.hour, from: newTime) * 60
                  + Calendar.current.component(.minute, from: newTime)
                guard
                  let base = management.alarms.last(where: {
                    Int($0.alertkind) == kind.rawValue && Int($0.start) <= start
                  })
                else {
                  error = "No preceding period is available."
                  return
                }
                do {
                  try management.addAlarmPeriod(from: base, start: start)
                  adding = false
                  error = nil
                } catch { self.error = error.localizedDescription }
              }
            }
          }
      }.tint(JournalStyle.accent)
    }
    .confirmationDialog(
      "Remove this alarm period?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button("Remove period", role: .destructive) {
        guard let entry = deleting else { return }
        do { try management.removeAlarmPeriod(entry) } catch {
          management.message = error.localizedDescription
        }
        deleting = nil
      }
    } message: {
      Text(
        "The preceding period will continue until the next one. Other alert types stay unchanged.")
    }
    .journalManagementMessage(management)
  }
}

struct JournalAlarmEditor: View {
  @ObservedObject var management: JournalManagement
  let entry: AlertEntry
  @Environment(\.dismiss) private var dismiss
  @State private var draft: JournalAlarmDraft
  @State private var threshold: String
  @State private var trigger: String
  @State private var error: String?
  private let original: JournalAlarmDraft
  private let usesMgDl: Bool
  private let kind: AlertKind
  init(management: JournalManagement, entry: AlertEntry) {
    self.management = management
    self.entry = entry
    let initial = JournalAlarmDraft(entry)
    original = initial
    _draft = State(initialValue: initial)
    let kind = AlertKind(rawValue: Int(entry.alertkind)) ?? .low
    self.kind = kind
    usesMgDl = UserDefaults.standard.bloodGlucoseUnitIsMgDl
    _threshold = State(
      initialValue: kind.valueIsABgValue()
        ? Double(entry.value).mgDlToMmolAndToString(mgDl: usesMgDl) : String(entry.value))
    _trigger = State(initialValue: Double(entry.triggerValue).mgDlToMmolAndToString(mgDl: usesMgDl))
  }
  var body: some View {
    Form {
      Section {
        Toggle("Enable this alert", isOn: $draft.enabled)
        if entry.start != 0 {
          DatePicker(
            "Starts at",
            selection: Binding(
              get: { Self.time(draft.start) },
              set: {
                draft.start =
                  Calendar.current.component(.hour, from: $0) * 60
                  + Calendar.current.component(.minute, from: $0)
              }), displayedComponents: .hourAndMinute)
        }
        LabeledContent(
          "Threshold (\(kind.valueUnitText(transmitterType: UserDefaults.standard.cgmTransmitterType)))"
        ) {
          TextField("Threshold", text: $threshold).keyboardType(.decimalPad).multilineTextAlignment(
            .trailing
          ).accessibilityIdentifier("alarm.threshold")
        }
        if kind.needsAlertTriggerValue() {
          LabeledContent("Only beyond (\(usesMgDl ? "mg/dL" : "mmol/L"))") {
            TextField("Trigger", text: $trigger).keyboardType(.decimalPad).multilineTextAlignment(
              .trailing)
          }
        }
      } footer: {
        Text(
          "Enable applies to all periods for this alert. Threshold and sound apply to this period.")
      }
      Section("Sound & attention") {
        Toggle("Notify during this period", isOn: $draft.profileEnabled)
        Picker("Sound", selection: $draft.sound) {
          Text("System sound").tag(JournalAlarmDraft.systemSound)
          Text("Silent").tag("")
          ForEach(ConstantsSounds.allCases, id: \.rawValue) { sound in
            Text(ConstantsSounds.getSoundName(forSound: sound)).tag(
              ConstantsSounds.getSoundName(forSound: sound))
          }
          if draft.sound != "", draft.sound != JournalAlarmDraft.systemSound,
            !ConstantsSounds.allCases.contains(where: {
              ConstantsSounds.getSoundName(forSound: $0) == draft.sound
            })
          {
            Text(draft.sound).tag(draft.sound)
          }
        }
        Toggle("Vibrate", isOn: $draft.vibrate)
        Toggle("Override silent mode", isOn: $draft.overrideMute)
      }
      Section("Snooze") {
        Toggle("Allow snoozing", isOn: $draft.snooze)
        if draft.snooze {
          Stepper("\(draft.snoozeMinutes) minutes", value: $draft.snoozeMinutes, in: 1...1440)
        }
      }
      if let error { Section { Text(error).foregroundStyle(.red) } }
    }.navigationTitle(kind.alertTitle()).navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save).accessibilityIdentifier("alarm.save")
        }
      }
  }
  static func time(_ minutes: Int, on day: Date = Date(), calendar: Calendar = .current) -> Date {
    // Schedules use local clock minutes, not elapsed seconds since midnight.
    calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
  }
  private func save() {
    guard let value = Double(threshold.replacingOccurrences(of: ",", with: ".")), value.isFinite,
      value > 0
    else {
      error = "Enter a valid positive threshold."
      return
    }
    let initialText =
      kind.valueIsABgValue()
      ? Double(original.value).mgDlToMmolAndToString(mgDl: usesMgDl) : String(original.value)
    let converted = kind.valueIsABgValue() ? value.mmolToMgdl(mgDl: usesMgDl) : value
    guard converted <= 32767 else {
      error = "Threshold is too large."
      return
    }
    draft.value = threshold == initialText ? original.value : Int(converted.rounded())
    if kind.needsAlertTriggerValue() {
      guard let value = Double(trigger.replacingOccurrences(of: ",", with: ".")), value.isFinite,
        value >= 0, value.mmolToMgdl(mgDl: usesMgDl) <= 32767
      else {
        error = "Enter a valid glucose trigger."
        return
      }
      draft.trigger =
        trigger == Double(original.trigger).mgDlToMmolAndToString(mgDl: usesMgDl)
        ? original.trigger : Int(value.mmolToMgdl(mgDl: usesMgDl).rounded())
    }
    do {
      try management.saveAlarm(draft, entry: entry)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct JournalSavedRecordsView: View {
  @ObservedObject var management: JournalManagement
  @State private var query = ""
  var body: some View {
    List {
      Section {
        ForEach(
          management.records.filter {
            query.isEmpty || $0.treatmentType.asString().localizedCaseInsensitiveContains(query)
          }, id: \.objectID
        ) { record in
          HStack {
            VStack(alignment: .leading, spacing: 5) {
              Text(record.treatmentType.asString())
              Text(record.date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(
              "\(record.treatmentType == .BgCheck ? record.value.mgDlToMmolAndToString(mgDl: UserDefaults.standard.bloodGlucoseUnitIsMgDl) : record.value.formatted()) \(record.treatmentType.unit())"
            )
          }.accessibilityElement(children: .combine)
        }
        if management.records.isEmpty { Label("No saved records", systemImage: "tray") }
      } footer: {
        Text(
          "Your existing treatment records are preserved. New meals belong in Journal; workouts come from Apple Health."
        )
      }
    }.searchable(text: $query, prompt: "Find a record type")
      .navigationTitle("Saved records").navigationBarTitleDisplayMode(.inline).onAppear {
        management.refresh()
      }
  }
}

private struct JournalManagementMessage: ViewModifier {
  @ObservedObject var management: JournalManagement
  func body(content: Content) -> some View {
    content.alert(
      "Sensor & settings",
      isPresented: Binding(
        get: { management.message != nil }, set: { if !$0 { management.message = nil } })
    ) {
      Button("OK") { management.message = nil }
    } message: {
      Text(management.message ?? "")
    }
  }
}
extension View {
  func journalManagementMessage(_ management: JournalManagement) -> some View {
    modifier(JournalManagementMessage(management: management))
  }
}

/// The alert engine still determines eligibility, sound and snooze behavior.
/// This replaces only its modal presentation, retaining both completion paths.
struct JournalAlarmResponse: View {
  let data: PickerViewData
  @Environment(\.dismiss) private var dismiss
  @State private var selection: Int
  init(data: PickerViewData) {
    self.data = data
    _selection = State(initialValue: data.selectedRow)
  }
  var body: some View {
    NavigationStack {
      List {
        if data.priority == .high {
          Label(data.mainTitle ?? "Glucose alert", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
        if let subtitle = data.subTitle { Section { Text(subtitle).foregroundStyle(.secondary) } }
        ForEach(data.data.indices, id: \.self) { index in
          Button {
            selection = index
            data.didSelectRowHandler?(index)
          } label: {
            HStack {
              Text(data.data[index])
              Spacer()
              if selection == index { Image(systemName: "checkmark") }
            }
          }.accessibilityAddTraits(selection == index ? .isSelected : [])
        }
      }.navigationTitle(data.mainTitle ?? "Glucose alert").navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(data.cancelTitle ?? "Close") {
              data.cancelHandler?()
              finish()
            }
          }
          ToolbarItem(placement: .confirmationAction) {
            Button(data.actionTitle ?? "Snooze") {
              data.actionHandler(selection)
              finish()
            }.disabled(!data.data.indices.contains(selection))
          }
        }
    }.tint(JournalStyle.accent).interactiveDismissDisabled()
  }
  private func finish() {
    UserDefaults.standard.updateSnoozeStatus.toggle()
    dismiss()
  }
}
