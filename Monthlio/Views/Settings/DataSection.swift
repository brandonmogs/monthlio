import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The "Data" rows of Settings: CSV export (Monthlio Pro), JSON backup and
/// restore, and CSV import. Backups are built when tapped, not on every
/// render.
struct DataSection: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrencyStore.self) private var currencyStore
    @Environment(ProStore.self) private var pro
    @Query(sort: \Expense.createdAt) private var expenses: [Expense]
    /// Owned by the Form so the alert isn't tied to a list row.
    @Binding var notice: DataNotice?
    /// Opens the Pro page. The Form presents it: a sheet hung off the
    /// locked row would lose its presenter the moment Pro unlocks and the
    /// row is replaced by the share link.
    var onUnlockPro: () -> Void = {}

    @State private var backupFile: BackupFileDocument?
    @State private var showingRestorePicker = false
    @State private var showingImportPicker = false
    @State private var pendingRestore: BackupDocument?
    @State private var pendingImport: CSVImportPreview?

    var body: some View {
        Section {
            if pro.isEntitled {
                ShareLink(
                    item: CSVExport(
                        csv: CSVExporter.csv(from: expenses, converter: currencyStore.converter),
                        fileName: "monthlio-expenses.csv"
                    ),
                    preview: SharePreview("Monthlio expenses", image: Image(systemName: "tablecells"))
                ) {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .disabled(expenses.isEmpty)
                .accessibilityIdentifier("data-export")
            } else {
                // Backups and import stay free, so the data is never locked in.
                ProLockedRow(title: "Export CSV", systemImage: "square.and.arrow.up", action: onUnlockPro)
                    .accessibilityIdentifier("data-export")
            }

            Button {
                backUp()
            } label: {
                Label("Back Up to File…", systemImage: "arrow.down.doc")
            }
            .accessibilityIdentifier("data-backup")
            .fileExporter(
                isPresented: Binding(get: { backupFile != nil }, set: { if !$0 { backupFile = nil } }),
                document: backupFile,
                contentType: .json,
                defaultFilename: BackupDocument.fileName()
            ) { result in
                if case .failure(let error) = result {
                    notice = DataNotice(title: String(localized: "Backup failed"), message: Text(error.localizedDescription))
                }
            }

            Button {
                showingRestorePicker = true
            } label: {
                Label("Restore from Backup…", systemImage: "arrow.up.doc")
            }
            .accessibilityIdentifier("data-restore")
            .fileImporter(isPresented: $showingRestorePicker, allowedContentTypes: [.json]) { result in
                handleRestorePick(result)
            }
            .confirmationDialog(
                "Restore this backup?",
                isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
                titleVisibility: .visible,
                presenting: pendingRestore
            ) { document in
                Button("Replace everything", role: .destructive) { restore(document, mode: .replace) }
                Button("Merge with current data") { restore(document, mode: .merge) }
                Button("Cancel", role: .cancel) { pendingRestore = nil }
            } message: { document in
                restoreWarning(for: document)
            }

            Button {
                showingImportPicker = true
            } label: {
                Label("Import CSV…", systemImage: "tablecells.badge.ellipsis")
            }
            .accessibilityIdentifier("data-import")
            .fileImporter(isPresented: $showingImportPicker, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
                handleImportPick(result)
            }
            .confirmationDialog(
                "Import expenses?",
                isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                titleVisibility: .visible,
                presenting: pendingImport
            ) { preview in
                Button("Import ^[\(preview.expenses.count) expense](inflect: true)") { commit(preview) }
                    .disabled(preview.expenses.isEmpty)
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: { preview in
                importSummary(preview)
            }
        } header: {
            Text("Data")
        } footer: {
            Text("Backups include expenses, budgets, exchange rates, history and income. Reminders and the app lock are device settings and aren't restored.")
        }
    }

    // MARK: Backup

    private func backUp() {
        do {
            backupFile = BackupFileDocument(data: try BackupService.data(from: modelContext))
        } catch {
            notice = DataNotice(title: String(localized: "Backup failed"), message: Text(error.localizedDescription))
        }
    }

    private func handleRestorePick(_ result: Result<URL, Error>) {
        guard let data = readPickedFile(result) else { return }
        do {
            let document = try BackupService.decode(data)
            // Skip the question only for a store that is empty and not
            // syncing; with sync on, the first iCloud import may still be
            // arriving and would duplicate a silent replace.
            if BackupService.isEmpty(modelContext), !MonthlioApp.isCloudSyncEnabled {
                restore(document, mode: .replace)
            } else {
                pendingRestore = document
            }
        } catch {
            notice = DataNotice(title: String(localized: "Couldn't restore"), message: Text(error.localizedDescription))
        }
    }

    /// Replacing on a synced store deletes on every device; two devices
    /// each restoring the same backup would double every expense.
    private func restoreWarning(for document: BackupDocument) -> Text {
        let summary = Text("Backup from \(document.exportedAt.formatted(date: .abbreviated, time: .shortened)) with ^[\(document.expenses.count) expense](inflect: true). Replacing deletes everything currently in Monthlio first.")
        guard MonthlioApp.isCloudSyncEnabled else { return summary }
        return summary + Text(verbatim: " ") + Text("With iCloud sync on, that happens on every device signed in to your iCloud. Restore on one device only and let the others sync.")
    }

    private func restore(_ document: BackupDocument, mode: RestoreMode) {
        pendingRestore = nil
        do {
            let summary = try BackupService.restore(document, into: modelContext, mode: mode)
            Haptics.success()
            var message = Text("Added ^[\(summary.expensesAdded) expense](inflect: true), ^[\(summary.budgetsAdded) budget](inflect: true) and ^[\(summary.snapshotsAdded) month](inflect: true) of history.")
            if summary.expensesSkipped > 0 {
                message = message + Text(verbatim: " ") + Text("^[\(summary.expensesSkipped) expense](inflect: true) already existed or couldn't be read.")
            }
            notice = DataNotice(title: String(localized: "Restore complete"), message: message)
        } catch {
            modelContext.rollback()
            Haptics.warning()
            notice = DataNotice(title: String(localized: "Couldn't restore"), message: Text(error.localizedDescription))
        }
    }

    // MARK: Import

    private func handleImportPick(_ result: Result<URL, Error>) {
        guard let data = readPickedFile(result) else { return }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            notice = DataNotice(title: String(localized: "Couldn't import"), message: Text("The file isn't text."))
            return
        }
        do {
            pendingImport = try CSVImporter.preview(text, baseCurrency: currencyStore.baseCode, existing: expenses)
        } catch {
            notice = DataNotice(title: String(localized: "Couldn't import"), message: Text(error.localizedDescription))
        }
    }

    private func commit(_ preview: CSVImportPreview) {
        pendingImport = nil
        do {
            let count = try CSVImporter.commit(preview, into: modelContext)
            Haptics.success()
            notice = DataNotice(title: String(localized: "Import complete"), message: Text("Added ^[\(count) expense](inflect: true). Check their categories and due days in the Expenses tab."))
        } catch {
            modelContext.rollback()
            Haptics.warning()
            notice = DataNotice(title: String(localized: "Couldn't import"), message: Text(error.localizedDescription))
        }
    }

    private func importSummary(_ preview: CSVImportPreview) -> Text {
        var parts = [Text("^[\(preview.expenses.count) expense](inflect: true) will be added.")]
        if preview.duplicates > 0 {
            parts.append(Text("^[\(preview.duplicates) duplicate row](inflect: true) will be skipped."))
        }
        if !preview.skipped.isEmpty {
            parts.append(Text("^[\(preview.skipped.count) row](inflect: true) couldn't be read."))
        }
        return parts.dropFirst().reduce(parts[0]) { $0 + Text(verbatim: " ") + $1 }
    }

    // MARK: Files

    private func readPickedFile(_ result: Result<URL, Error>) -> Data? {
        switch result {
        case .failure(let error):
            notice = DataNotice(title: String(localized: "Couldn't open the file"), message: Text(error.localizedDescription))
            return nil
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                return try Data(contentsOf: url)
            } catch {
                notice = DataNotice(title: String(localized: "Couldn't open the file"), message: Text(error.localizedDescription))
                return nil
            }
        }
    }
}

struct DataNotice: Identifiable {
    let id = UUID()
    let title: String
    let message: Text
}

extension View {
    /// Presents a `DataNotice` as an alert; applied by the Settings form.
    func dataNoticeAlert(_ notice: Binding<DataNotice?>) -> some View {
        alert(
            Text(notice.wrappedValue?.title ?? ""),
            isPresented: Binding(get: { notice.wrappedValue != nil }, set: { if !$0 { notice.wrappedValue = nil } }),
            presenting: notice.wrappedValue
        ) { _ in
            Button("OK") { notice.wrappedValue = nil }
        } message: { current in
            current.message
        }
    }
}

/// Wraps backup JSON for `fileExporter`, which saves through the Files picker.
struct BackupFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    Form {
        DataSection(notice: .constant(nil))
    }
    .modelContainer(PreviewContainer.shared)
    .environment(CurrencyStore())
}
