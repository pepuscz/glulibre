import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let gluLibreBackup = UTType(exportedAs: "org.glulibre.journal-backup", conformingTo: .data)
}

struct JournalBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.gluLibreBackup] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw JournalBackupError.invalidArchive }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct JournalBackupView: View {
    @ObservedObject var management: JournalManagement
    @StateObject private var backup = JournalBackupController()
    @State private var password = ""
    @State private var confirmation = ""
    @State private var passwordSheet = false
    @State private var showImporter = false
    @State private var restoreURL: URL?

    var body: some View {
        Form {
            Section {
                Label("Saved on this iPhone", systemImage: "iphone.gen3")
                if let date = backup.lastExport {
                    LabeledContent("Last export", value: date.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("No backup exported yet").foregroundStyle(.secondary)
                }
            } footer: { Text("Keep an encrypted copy outside this iPhone before replacing it. Apple Health isn’t a backup of your journal.") }
            Section {
                Button { restoreURL = nil; password = ""; confirmation = ""; passwordSheet = true } label: {
                    Label("Export backup", systemImage: "square.and.arrow.up")
                }.accessibilityIdentifier("backup.export")
                Button { showImporter = true } label: {
                    Label("Restore backup", systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("backup.restore")
            } footer: { Text("Meals, original photos, notes, estimates and glucose history. Password-protected. API keys, sensor pairing, settings and treatment records aren’t included.") }
            if backup.busy { Section { ProgressView("Working…") } }
            if let preview = backup.preview {
                Section {
                    LabeledContent("Created", value: preview.archive.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Meals", value: "\(preview.meals.count)")
                    LabeledContent("Readings", value: "\(preview.archive.readings.count)")
                    Button("Add missing records") { backup.restore(context: management.contextProvider()) }
                        .accessibilityIdentifier("backup.confirmRestore")
                    Button("Cancel", role: .cancel) { backup.preview = nil }
                } header: { Text("Ready to restore") } footer: {
                    Text("Existing records win. Restored readings are history only; they won’t trigger alerts or change your sensor. Photos won’t be sent for analysis.")
                }
            }
        }
        .navigationTitle("Backup & restore").navigationBarTitleDisplayMode(.inline)
        .disabled(backup.busy)
        .sheet(isPresented: $passwordSheet, onDismiss: { password = ""; confirmation = "" }) {
            NavigationStack {
                Form {
                    Section {
                        SecureField("Password", text: $password).textContentType(restoreURL == nil ? .newPassword : .password)
                            .accessibilityIdentifier("backup.password")
                        if restoreURL == nil {
                            SecureField("Repeat password", text: $confirmation).textContentType(.newPassword)
                                .accessibilityIdentifier("backup.confirmPassword")
                        }
                    } footer: {
                        Text(restoreURL == nil ? "At least 12 characters. Save it in Passwords separately from the backup. A forgotten password can’t be recovered." : "Enter the password used when this backup was exported.")
                    }
                }.navigationTitle(restoreURL == nil ? "Protect backup" : "Unlock backup").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { passwordSheet = false; restoreURL = nil } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(restoreURL == nil ? "Export" : "Continue") {
                                let secret = password
                                passwordSheet = false
                                if let restoreURL { backup.inspect(url: restoreURL, password: secret) }
                                else { backup.export(password: secret, context: management.contextProvider()) }
                                password = ""; confirmation = ""
                            }.disabled(restoreURL == nil ? password.count < 12 || password != confirmation : password.isEmpty)
                        }
                    }
            }.tint(JournalStyle.accent)
        }
        .fileExporter(isPresented: $backup.showExporter, document: backup.document, contentType: .gluLibreBackup,
                      defaultFilename: "GluLibre-\(Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))",
                      onCompletion: backup.exportFinished)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.gluLibreBackup, .data]) { result in
            switch result {
            case .success(let url): restoreURL = url; password = ""; passwordSheet = true
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { backup.message = error.localizedDescription }
            }
        }
        .alert("Backup & restore", isPresented: Binding(get: { backup.message != nil }, set: { if !$0 { backup.message = nil } })) {
            Button("OK") { backup.message = nil }
        } message: { Text(backup.message ?? "") }
    }
}
