import SwiftUI

/// A native presentation adapter for existing integration validation and persistence.
/// No storyboard controllers, duplicate credentials, or second preference store.
@MainActor
final class JournalServiceAdapter: ObservableObject {
  let model: SettingsViewModelProtocol
  @Published var action: SettingsSelectedRowAction?
  @Published var message: String?
  @Published var progress: Float?
  @Published var shareURL: URL?
  init(_ model: SettingsViewModelProtocol) {
    self.model = model
    model.storeMessageHandler { [weak self] title, message in
      self?.message = "\(title)\n\(message)"
      self?.refresh()
    }
    model.storeRowReloadClosure { [weak self] _ in self?.refresh() }
    model.storeSectionReloadClosure { [weak self] in self?.refresh() }
  }
  func refresh() { objectWillChange.send() }
  func select(_ index: Int) {
    let selection = model.onRowSelect(index: index)
    switch selection {
    case .nothing: break
    case .callFunction(let function):
      function()
      refresh()
    case .callFunctionAndShareFile(let function):
      progress = 0
      function { [weak self] result in
        DispatchQueue.main.async {
          guard let self else { return }
          guard let result else {
            self.progress = nil
            self.message = "Couldn’t create the export. Please try again."
            return
          }
          self.progress = result.complete ? nil : result.progress
          if result.complete { self.shareURL = result.data }
        }
      }
    default: action = selection
    }
  }
}

struct JournalServiceView: View {
  let title: String
  @StateObject private var adapter: JournalServiceAdapter
  init(title: String, model: SettingsViewModelProtocol) {
    self.title = title
    _adapter = StateObject(wrappedValue: JournalServiceAdapter(model))
  }
  var body: some View {
    Form {
      Section {
        ForEach(0..<adapter.model.numberOfRows(), id: \.self) { index in
          if let control = adapter.model.uiView(index: index) as? UISwitch {
            Toggle(
              adapter.model.settingsRowText(index: index),
              isOn: Binding(
                get: { control.isOn },
                set: {
                  control.setOn($0, animated: false)
                  control.sendActions(for: .valueChanged)
                  adapter.refresh()
                })
            )
            .disabled(!adapter.model.isEnabled(index: index))
          } else {
            Button {
              adapter.select(index)
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 4) {
                  Text(adapter.model.settingsRowText(index: index)).foregroundStyle(.primary)
                  if let detail = adapter.model.detailedText(index: index), !detail.isEmpty {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                  }
                }
                Spacer(minLength: 12)
                if adapter.model.accessoryType(index: index) != .none {
                  Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
                }
              }.padding(.vertical, 3)
            }.disabled(!adapter.model.isEnabled(index: index) || adapter.progress != nil)
          }
        }
      }
      if let progress = adapter.progress {
        Section { ProgressView("Preparing export…", value: progress) }
      }
    }.navigationTitle(title).navigationBarTitleDisplayMode(.inline)
      .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) {
        _ in adapter.refresh()
      }
      .sheet(
        isPresented: Binding(
          get: { adapter.action != nil },
          set: {
            if !$0 {
              adapter.action = nil
              adapter.refresh()
            }
          })
      ) {
        if let action = adapter.action {
          JournalServiceActionView(action: action) {
            adapter.action = nil
            adapter.refresh()
          }
        }
      }
      .sheet(
        isPresented: Binding(
          get: { adapter.shareURL != nil }, set: { if !$0 { adapter.shareURL = nil } })
      ) {
        if let url = adapter.shareURL { JournalShareView(items: [url]) }
      }
      .alert(
        title,
        isPresented: Binding(
          get: { adapter.message != nil }, set: { if !$0 { adapter.message = nil } })
      ) {
        Button("OK") { adapter.message = nil }
      } message: {
        Text(adapter.message ?? "")
      }
  }
}

private struct JournalServiceActionView: View {
  let action: SettingsSelectedRowAction
  let close: () -> Void
  @State private var text = ""
  @State private var selection = 0
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Group {
        switch action {
        case .askText(
          let title, let message, let keyboard, let initial, let placeholder, _, _, let save, _,
          let validate):
          Form {
            Section {
              if sensitive(title) {
                SecureField(placeholder ?? "Value", text: $text).textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
              } else {
                TextField(placeholder ?? "Value", text: $text).keyboardType(keyboard ?? .default)
                  .textInputAutocapitalization(.never).autocorrectionDisabled()
              }
            } footer: {
              if let message { Text(message) }
            }
            if let error { Text(error).foregroundStyle(.red) }
          }.navigationTitle(title ?? "Edit")
            .onAppear { text = initial ?? "" }
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                  if let problem = validate?(text) {
                    error = problem
                    return
                  }
                  save(text)
                  close()
                }
              }
            }
        case .selectFromList(let title, let options, let initial, _, _, let save, _, let preview):
          List {
            ForEach(options.indices, id: \.self) { index in
              Button {
                selection = index
                preview?(index)
              } label: {
                HStack {
                  Text(options[index])
                  Spacer()
                  if selection == index { Image(systemName: "checkmark") }
                }
              }
            }
          }.navigationTitle(title ?? "Choose")
            .onAppear { selection = initial ?? 0 }
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                  guard options.indices.contains(selection) else { return }
                  save(selection)
                  close()
                }
              }
            }
        case .askConfirmation(let title, let message, let save, _):
          Form {
            if let message { Text(message).foregroundStyle(.secondary) }
            Button("Continue") {
              save()
              close()
            }
          }.navigationTitle(title ?? "Confirm")
        case .showInfoText(let title, let message, let completion):
          ScrollView { Text(message).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle(title)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                  completion?()
                  close()
                }
              }
            }
        case .performSegue(_, let sender):
          if let schedule = sender as? TimeSchedule {
            JournalServiceSchedule(schedule: schedule, close: close)
          } else {
            Text("This control is unavailable in this build.").padding()
          }
        default: EmptyView()
        }
      }.navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: close) } }
    }.tint(JournalStyle.accent).interactiveDismissDisabled()
  }
  private func sensitive(_ title: String?) -> Bool {
    ["key", "password", "token", "secret", "heslo", "klíč"].contains {
      (title ?? "").localizedCaseInsensitiveContains($0)
    }
  }
}

private struct JournalServiceSchedule: View {
  let schedule: TimeSchedule
  let close: () -> Void
  @State private var times: [Int] = []
  @State private var error: String?
  var body: some View {
    Form {
      Section {
        LabeledContent("From midnight", value: "On")
        ForEach(times.indices, id: \.self) { index in
          DatePicker(
            index % 2 == 0 ? "Turn off" : "Turn on",
            selection: Binding(
              get: { JournalAlarmEditor.time(times[index]) },
              set: {
                times[index] =
                  Calendar.current.component(.hour, from: $0) * 60
                  + Calendar.current.component(.minute, from: $0)
              }), displayedComponents: .hourAndMinute)
        }.onDelete { times.remove(atOffsets: $0) }
        Button("Add change", systemImage: "plus") {
          times.append(min(1439, (times.last ?? 0) + 60))
        }
      } footer: {
        Text("Changes run in time order. Swipe to remove a change. Nothing changes until you save.")
      }
      if let error { Text(error).foregroundStyle(.red) }
    }.navigationTitle("Sharing schedule")
      .onAppear { times = schedule.getSchedule() }
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Save") {
            guard times.allSatisfy({ (1...1439).contains($0) }),
              zip(times, times.dropFirst()).allSatisfy({ $0 < $1 })
            else {
              error = "Use distinct times in increasing order after midnight."
              return
            }
            schedule.storeSchedule(schedule: times)
            close()
          }
        }
      }
  }
}

struct JournalShareView: UIViewControllerRepresentable {
  let items: [Any]
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: items, applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct JournalStorageView: View {
  @StateObject private var adapter: JournalServiceAdapter
  @State private var editing = false
  @State private var days = ""
  @State private var reduction: Int?
  @State private var error: String?
  init(model: SettingsViewModelProtocol) {
    _adapter = StateObject(wrappedValue: JournalServiceAdapter(model))
  }
  var body: some View {
    Form {
      Section {
        Button {
          days = String(UserDefaults.standard.retentionPeriodInDays)
          editing = true
        } label: {
          LabeledContent(
            "Keep glucose history", value: "\(UserDefaults.standard.retentionPeriodInDays) days")
        }
      } footer: {
        Text(
          "Also applies to older calibration and treatment records. Meal photos and notes are kept separately and aren’t removed by this setting."
        )
      }
      Section {
        Button("Export glucose & records") { adapter.select(1) }.disabled(adapter.progress != nil)
        if let progress = adapter.progress { ProgressView("Preparing export…", value: progress) }
      } footer: {
        Text(
          "JSON file of retained readings, calibrations and treatment records. Does not include meal photos, notes, sensor pairing or settings; it is not a full backup. Only share with someone you trust."
        )
      }
    }.navigationTitle("Storage & export").navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $editing) {
        NavigationStack {
          Form {
            TextField("Days", text: $days).keyboardType(.numberPad)
            if let error { Text(error).foregroundStyle(.red) }
          }.navigationTitle("Keep history").navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                  editing = false
                  error = nil
                }
              }
              ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                  guard let value = Int(days), (1...36500).contains(value) else {
                    error = "Enter 1 to 36,500 days."
                    return
                  }
                  if value < UserDefaults.standard.retentionPeriodInDays {
                    reduction = value
                  } else {
                    save(value)
                  }
                }
              }
            }
            .alert(
              "Remove older history?",
              isPresented: Binding(get: { reduction != nil }, set: { if !$0 { reduction = nil } })
            ) {
              Button("Cancel", role: .cancel) { reduction = nil }
              Button("Reduce retention", role: .destructive) {
                if let reduction { save(reduction) }
                reduction = nil
              }
            } message: {
              Text(
                "Records older than \(reduction ?? 0) days become eligible for permanent removal. Export them first if you want to keep a copy."
              )
            }
        }.tint(JournalStyle.accent)
      }
      .sheet(
        isPresented: Binding(
          get: { adapter.shareURL != nil }, set: { if !$0 { adapter.shareURL = nil } })
      ) {
        if let url = adapter.shareURL { JournalShareView(items: [url]) }
      }
      .alert(
        "Export",
        isPresented: Binding(
          get: { adapter.message != nil }, set: { if !$0 { adapter.message = nil } })
      ) {
        Button("OK") { adapter.message = nil }
      } message: {
        Text(adapter.message ?? "")
      }
  }
  private func save(_ value: Int) {
    UserDefaults.standard.retentionPeriodInDays = value
    editing = false
    error = nil
    adapter.refresh()
  }
}
