import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Backup Manager

struct BackupManager {
    struct BackupData: Codable {
        let version: String = "1.0"
        let createdAt: Date
        let transactions: [Transaction]
        let budgetsByMonth: [String: Int]
        let customCategoryNames: [String]
        let categoryBudgetsByMonth: [String: [String: Int]]

        var transactionCount: Int { transactions.count }
        var sizeInBytes: Int { (try? JSONEncoder().encode(self).count) ?? 0 }
        var formattedSize: String {
            let bytes = Double(sizeInBytes)
            if bytes < 1024 {
                return "\(Int(bytes)) B"
            } else if bytes < 1024 * 1024 {
                return String(format: "%.1f KB", bytes / 1024)
            } else {
                return String(format: "%.1f MB", bytes / (1024 * 1024))
            }
        }
    }

    static func createBackup(from store: Store) -> BackupData {
        return BackupData(
            createdAt: Date(),
            transactions: store.transactions,
            budgetsByMonth: store.budgetsByMonth,
            customCategoryNames: store.customCategoryNames,
            categoryBudgetsByMonth: store.categoryBudgetsByMonth
        )
    }

    static func exportBackup(from store: Store) -> Data? {
        let backup = createBackup(from: store)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(backup)
    }

    enum BackupError: Error {
        case invalidFormat
        case unsupportedVersion

        var localizedDescription: String {
            switch self {
            case .invalidFormat: return "Invalid backup file format"
            case .unsupportedVersion: return "Unsupported backup version"
            }
        }
    }

    /// Restore from a JSON backup file. Intentionally bypasses TransactionService
    /// (bulk data replacement with no balance/goal side-effects).
    /// Replace mode tracks all existing transactions as deleted for cloud sync.
    /// Caller is responsible for persistence (typically via ContentView onChange).
    ///
    /// Validation performed on every restored transaction:
    /// - `amount > 0` required (zero/negative silently dropped)
    /// - Duplicate UUIDs against existing store rejected (merge only)
    /// - `accountId` / `linkedGoalId` cleared if the referenced entity no longer exists
    ///
    /// - Parameters:
    ///   - knownAccountIds: Current set of valid account UUIDs (caller provides from AccountManager).
    ///   - knownGoalIds: Current set of valid goal UUIDs (caller provides from GoalManager).
    static func restoreBackup(
        _ data: Data,
        to store: inout Store,
        mode: RestoreMode,
        knownAccountIds: Set<UUID> = [],
        knownGoalIds: Set<UUID> = []
    ) -> Result<Int, BackupError> {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let backup = try? decoder.decode(BackupData.self, from: data) else {
            return .failure(.invalidFormat)
        }

        guard backup.version == "1.0" else {
            return .failure(.unsupportedVersion)
        }

        let accountIds = knownAccountIds
        let goalIds = knownGoalIds

        switch mode {
        case .merge:
            var existingSigs = Set<String>()
            for t in store.transactions {
                existingSigs.insert(transactionSignature(t))
            }

            var sigFiltered: [Transaction] = []
            for t in backup.transactions {
                let sig = transactionSignature(t)
                if !existingSigs.contains(sig) {
                    sigFiltered.append(t)
                    existingSigs.insert(sig)
                }
            }

            let validation = store.validateForImport(
                sigFiltered,
                existingAccountIds: accountIds,
                existingGoalIds: goalIds
            )

            if validation.totalSkipped > 0 || validation.totalSanitized > 0 {
                SecureLogger.info(
                    "Restore merge: \(validation.accepted.count) accepted, "
                    + "\(validation.skippedZeroAmount) zero-amount, "
                    + "\(validation.skippedDuplicateUUID) duplicate-UUID, "
                    + "\(validation.sanitizedAccountIds) orphan accountId, "
                    + "\(validation.sanitizedGoalIds) orphan goalId"
                )
            }

            for t in validation.accepted {
                store.add(t)
            }

            for (key, value) in backup.budgetsByMonth {
                if store.budgetsByMonth[key] == nil {
                    store.budgetsByMonth[key] = value
                }
            }

            for cat in backup.customCategoryNames {
                if !store.customCategoryNames.contains(cat) {
                    store.customCategoryNames.append(cat)
                }
            }

            for (monthKey, catBudgets) in backup.categoryBudgetsByMonth {
                if store.categoryBudgetsByMonth[monthKey] == nil {
                    store.categoryBudgetsByMonth[monthKey] = catBudgets
                } else {
                    for (catKey, budget) in catBudgets {
                        if store.categoryBudgetsByMonth[monthKey]?[catKey] == nil {
                            store.categoryBudgetsByMonth[monthKey]?[catKey] = budget
                        }
                    }
                }
            }

            return .success(validation.accepted.count)

        case .replace:
            let wipedIds = Set(store.transactions.map { $0.id })
            for tx in store.transactions {
                store.trackDeletion(of: tx.id)
            }
            store.transactions.removeAll()
            store.budgetsByMonth.removeAll()
            store.customCategoryNames.removeAll()
            store.categoryBudgetsByMonth.removeAll()
            // Cascade: drop household split expenses tied to the wiped transactions.
            if !wipedIds.isEmpty {
                HouseholdManager.shared.removeSplitExpenses(forTransactions: wipedIds)
            }

            let validation = store.validateForImport(
                backup.transactions,
                existingAccountIds: accountIds,
                existingGoalIds: goalIds
            )

            if validation.totalSkipped > 0 || validation.totalSanitized > 0 {
                SecureLogger.info(
                    "Restore replace: \(validation.accepted.count) accepted, "
                    + "\(validation.skippedZeroAmount) zero-amount, "
                    + "\(validation.skippedDuplicateUUID) duplicate-UUID, "
                    + "\(validation.sanitizedAccountIds) orphan accountId, "
                    + "\(validation.sanitizedGoalIds) orphan goalId"
                )
            }

            for t in validation.accepted {
                store.add(t)
            }

            store.budgetsByMonth = backup.budgetsByMonth
            store.customCategoryNames = backup.customCategoryNames
            store.categoryBudgetsByMonth = backup.categoryBudgetsByMonth

            return .success(validation.accepted.count)
        }
    }

    private static func transactionSignature(_ t: Transaction) -> String {
        let cal = Calendar.current
        let day = cal.startOfDay(for: t.date)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let dayStr = df.string(from: day)
        let noteNorm = t.note.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(dayStr)|\(t.amount)|\(t.category.storageKey)|\(noteNorm)"
    }

    static func exportBackupFile(store: Store) -> URL? {
        guard let data = exportBackup(from: store) else { return nil }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let filename = "Centmond_Backup_\(timestamp).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    enum RestoreMode {
        case merge
        case replace
    }
}

// MARK: - Backup & Data Section

struct BackupDataSection: View {
    @Binding var store: Store
    @State private var showBackupAlert = false
    @State private var showRestoreAlert = false
    @State private var showRestorePicker = false
    @State private var backupStatus: String?
    @State private var isProcessing = false

    var body: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Colors.text)
                    Text("Backup & Data")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                }

                Divider().foregroundStyle(DS.Colors.grid)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total Transactions")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Text("\(store.transactions.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)
                    }

                    HStack {
                        Text("Total Budgets")
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Text("\(store.budgetsByMonth.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)
                    }
                }

                Divider().foregroundStyle(DS.Colors.grid)

                Button {
                    showBackupAlert = true
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(DS.Colors.accent)
                        Text("Create Backup")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .tint(DS.Colors.text)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Colors.surface2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                Button {
                    showRestoreAlert = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc")
                            .foregroundStyle(.orange)
                        Text("Restore from Backup")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        if isProcessing {
                            ProgressView()
                                .tint(DS.Colors.text)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Colors.surface2)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)

                if let status = backupStatus {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(status.contains("Success") ? .green : .red)
                        .padding(.top, 4)
                }

                Text("\u{26A0}\u{FE0F} Backups include all transactions, budgets, and settings. Store them safely!")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
        .alert("Create Backup", isPresented: $showBackupAlert) {
            Button("Create", role: .none) {
                createBackup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will create a backup file with all your data. You can save it for safekeeping.")
        }
        .alert("Restore Backup", isPresented: $showRestoreAlert) {
            Button("Choose File", role: .none) {
                showRestorePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\u{26A0}\u{FE0F} Warning: This will REPLACE all current data with the backup. Make sure you have a recent backup before proceeding.")
        }
        .sheet(isPresented: $showRestorePicker) {
            BackupRestorePicker(store: $store) { success, message in
                backupStatus = message
                if success {
                    Haptics.backupRestored()
                } else {
                    Haptics.error()
                }
                isProcessing = false
            }
        }
    }

    private func createBackup() {
        isProcessing = true
        Haptics.medium()

        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = BackupManager.exportBackupFile(store: store) else {
                DispatchQueue.main.async {
                    backupStatus = "\u{274C} Failed to create backup"
                    isProcessing = false
                    Haptics.error()
                }
                return
            }

            DispatchQueue.main.async {
                let activityVC = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )

                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootVC = window.rootViewController {

                    var topVC = rootVC
                    while let presented = topVC.presentedViewController {
                        topVC = presented
                    }

                    activityVC.completionWithItemsHandler = { _, completed, _, _ in
                        if completed {
                            backupStatus = "\u{2705} Backup created successfully!"
                            Haptics.backupCreated()
                        } else {
                            backupStatus = "\u{274C} Backup cancelled"
                        }
                        isProcessing = false
                    }

                    topVC.present(activityVC, animated: true)
                }
            }
        }
    }
}

// MARK: - Backup Restore Picker

struct BackupRestorePicker: UIViewControllerRepresentable {
    @Binding var store: Store
    let completion: (Bool, String) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(store: $store, completion: completion, dismiss: dismiss)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        @Binding var store: Store
        let completion: (Bool, String) -> Void
        let dismiss: DismissAction

        init(store: Binding<Store>, completion: @escaping (Bool, String) -> Void, dismiss: DismissAction) {
            self._store = store
            self.completion = completion
            self.dismiss = dismiss
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                completion(false, "\u{274C} No file selected")
                dismiss()
                return
            }

            guard url.startAccessingSecurityScopedResource() else {
                completion(false, "\u{274C} Cannot access file")
                dismiss()
                return
            }

            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let data = try Data(contentsOf: url)
                var storeCopy = store

                // Restore bypasses TransactionService intentionally (bulk data replacement,
                // no balance/goal side-effects). Persistence via onChange(of: store) safety net.
                // Pass current account/goal IDs so orphan references are sanitized.
                let accountIds = Set(AccountManager.shared.accounts.map(\.id))
                let goalIds = Set(GoalManager.shared.goals.map(\.id))
                let result = BackupManager.restoreBackup(
                    data, to: &storeCopy, mode: .replace,
                    knownAccountIds: accountIds, knownGoalIds: goalIds
                )
                switch result {
                case .success(let count):
                    store = storeCopy
                    completion(true, "\u{2705} Backup restored successfully! \(count) transaction(s)")
                case .failure(let error):
                    completion(false, "\u{274C} \(error.localizedDescription)")
                }
            } catch {
                let safe = AppConfig.shared.safeErrorMessage(
                    detail: error.localizedDescription,
                    fallback: "Could not read backup file. Please try again."
                )
                completion(false, "\u{274C} \(safe)")
            }

            dismiss()
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(false, "Cancelled")
            dismiss()
        }
    }
}
