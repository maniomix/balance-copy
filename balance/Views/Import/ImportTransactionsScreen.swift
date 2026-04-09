import SwiftUI

// MARK: - Import Mode

enum ImportMode {
    case merge    // اضافه کردن به موجودی
    case replace  // پاک کردن موجودی و جایگزینی
}

// MARK: - Import Transactions Screen

struct ImportTransactionsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var store: Store
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var supabaseManager: SupabaseManager
    
    @State private var showPaywall = false

    @State private var pickedURL: URL? = nil
    @State private var parsed: ParsedCSV? = nil
    @State private var statusText: String? = nil
    @State private var isPicking = false
    @State private var showImportModeAlert = false  // ← جدید
    @State private var pendingImportParsed: ParsedCSV? = nil  // ← موقت نگه داری

    // Column mapping
    @State private var colDate: Int? = nil
    @State private var colAmount: Int? = nil
    @State private var colCategory: Int? = nil
    @State private var colNote: Int? = nil
    @State private var colPaymentMethod: Int? = nil  // جدید
    @State private var colType: Int? = nil  // جدید - برای income/expense

    @State private var hasHeaderRow: Bool = true

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    DS.Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Import from CSV")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("CSV Format Requirements")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Colors.text)
                                Text("Note: If you import the same CSV again, Centmond will only add transactions that aren’t already in the app (duplicates are skipped).")
                            }
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)

                            Button {
                                // SUBSCRIPTION DISABLED
                                // guard subscriptionManager.isPro else {
                                //     showPaywall = true
                                //     return
                                // }
                                isPicking = true
                            } label: {
                                HStack {
                                    Image(systemName: "doc")
                                    Text(pickedURL == nil ? "Choose CSV file" : pickedURL!.lastPathComponent)
                                        .lineLimit(1)
                                }
                            }
                            .buttonStyle(DS.PrimaryButton())

                            Text("Excel files also supported")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    // SUBSCRIPTION DISABLED - CSV Import overlay
                    /*
                    .overlay(alignment: .center) {
                            ZStack {
                                // Blur background
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(.ultraThinMaterial)
                                
                                // Lock content
                                VStack(spacing: 12) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 40))
                                        .foregroundStyle(
                                            LinearGradient(
                                                colors: [.yellow, .orange],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                    
                                    Text("Import Transactions")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(DS.Colors.text)
                                    
                                    Text("Upgrade to Pro to unlock")
                                        .font(.system(size: 14))
                                        .foregroundColor(DS.Colors.subtext)
                                    
                                    Button {
                                        showPaywall = true
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: "crown.fill")
                                            Text("Upgrade Now")
                                                .fontWeight(.semibold)
                                        }
                                        .font(.system(size: 15))
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 12)
                                        .background(
                                            LinearGradient(
                                                colors: [.yellow, .orange],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .cornerRadius(12)
                                    }
                                }
                                .padding(.vertical, 20)
                            }
                        }
                    }
                    .zIndex(1)
                    */

                    if let parsed {
                        DS.Card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Columns")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                Toggle("First row is header", isOn: $hasHeaderRow)
                                    .tint(DS.Colors.positive)

                                columnPicker(title: "Date", columns: parsed.columns, selection: $colDate)
                                columnPicker(title: "Amount", columns: parsed.columns, selection: $colAmount)
                                columnPicker(title: "Category", columns: parsed.columns, selection: $colCategory)
                                columnPicker(title: "Type (optional - income/expense)", columns: parsed.columns, selection: $colType)
                                columnPicker(title: "Payment Method (optional)", columns: parsed.columns, selection: $colPaymentMethod)
                                columnPicker(title: "Note (optional)", columns: parsed.columns, selection: $colNote)

                                Divider().foregroundStyle(DS.Colors.grid)

                                Text("Preview")
                                    .font(DS.Typography.section)
                                    .foregroundStyle(DS.Colors.text)

                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(parsed.previewRows.prefix(10).indices, id: \.self) { i in
                                        let row = parsed.previewRows[i]
                                        Text(row.joined(separator: "  |  "))
                                            .font(DS.Typography.caption)
                                            .foregroundStyle(DS.Colors.subtext)
                                            .lineLimit(1)
                                    }
                                }

                                Divider().foregroundStyle(DS.Colors.grid)

                                Button {
                                    // Check if transactions exist
                                    if !store.transactions.isEmpty {
                                        // Ask user: merge or replace
                                        pendingImportParsed = parsed
                                        showImportModeAlert = true
                                    } else {
                                        // No transactions, just import
                                        importNow(parsed, mode: .merge)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "square.and.arrow.down")
                                        Text("Import")
                                    }
                                }
                                .buttonStyle(DS.PrimaryButton())
                                .disabled(colDate == nil || colAmount == nil || colCategory == nil)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let statusText {
                        DS.Card {
                            Text(statusText)
                                .font(DS.Typography.caption)
                                .foregroundStyle(statusText.hasPrefix("Imported") ? DS.Colors.positive : DS.Colors.danger)
                        }
                        .transition(.opacity)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardManagement()  // Global keyboard handling
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
        .sheet(isPresented: $isPicking) {
            CSVDocumentPicker { url in
                pickedURL = url
                parse(url: url)
            }
        }
        .onChange(of: hasHeaderRow) { _, _ in
            if let parsed { autoDetectMapping(parsed) }
        }
        .alert("Import Mode", isPresented: $showImportModeAlert) {
            Button("Merge") {
                if let p = pendingImportParsed {
                    importNow(p, mode: .merge)
                    pendingImportParsed = nil
                }
            }
            
            Button("Replace All", role: .destructive) {
                if let p = pendingImportParsed {
                    importNow(p, mode: .replace)
                    pendingImportParsed = nil
                }
            }
            
            Button("Cancel", role: .cancel) {
                pendingImportParsed = nil
            }
        } message: {
            Text(String(format: "You have %d existing transactions", store.transactions.count))
        }
        .sheet(isPresented: $showPaywall) {
        }
    }

    // MARK: UI helpers

    private func columnPicker(title: String, columns: [String], selection: Binding<Int?>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)

            Picker(title, selection: Binding(get: {
                selection.wrappedValue ?? -1
            }, set: { newValue in
                selection.wrappedValue = (newValue >= 0 ? newValue : nil)
            })) {
                Text("—").tag(-1)
                ForEach(columns.indices, id: \.self) { idx in
                    Text(columns[idx]).tag(idx)
                }
            }
            .pickerStyle(.menu)
            .tint(DS.Colors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Parsing / Mapping

    private func readCSVText(from url: URL) throws -> String {
        // DocumentPicker URLs may require security-scoped access
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let data = try Data(contentsOf: url)

        let encodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1252, // Excel in many locales (e.g., €)
            .isoLatin1
        ]

        for enc in encodings {
            if let s = String(data: data, encoding: enc) {
                return s
            }
        }

        throw NSError(domain: "CSV", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unsupported text encoding"])
    }

    private func parse(url: URL) {
        statusText = nil
        parsed = nil

        do {
            let text = try readCSVText(from: url)
            let table = CSV.parse(text)

            guard !table.isEmpty else {
                statusText = "CSV is empty."
                return
            }

            let header = table.first ?? []
            let rows = Array(table.dropFirst())

            let columns: [String]
            let previewRows: [[String]]

            if hasHeaderRow {
                columns = header.map { $0.isEmpty ? "(empty)" : $0 }
                previewRows = Array(rows.prefix(14))
            } else {
                let maxCols = table.map { $0.count }.max() ?? 0
                columns = (0..<maxCols).map { "Column \($0 + 1)" }
                previewRows = Array(table.prefix(14))
            }

            let parsedCSV = ParsedCSV(raw: table, columns: columns, previewRows: previewRows)
            parsed = parsedCSV
            autoDetectMapping(parsedCSV)

        } catch {
            statusText = "Could not read file. Export as CSV UTF-8 (or a standard CSV)."
        }
    }

    private func autoDetectMapping(_ parsed: ParsedCSV) {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }

        let names = parsed.columns.map(norm)

        func firstIndex(matching any: [String]) -> Int? {
            for a in any {
                if let idx = names.firstIndex(where: { $0 == a || $0.contains(a) }) { return idx }
            }
            return nil
        }

        colDate = firstIndex(matching: ["date", "day", "datum"])
        colAmount = firstIndex(matching: ["amount", "value", "spent", "cost", "eur", "€"])
        colCategory = firstIndex(matching: ["category", "cat", "type"])
        colNote = firstIndex(matching: ["note", "description", "desc", "memo"])
        colPaymentMethod = firstIndex(matching: ["payment", "method", "zahlungsmethode", "cash", "card"])
    }

    private func parseDate(_ s: String) -> Date? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        // 1) Try plain date formats (most common)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")

        let fmts = [
            "yyyy-MM-dd",
            "dd.MM.yyyy",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "yyyy/MM/dd"
        ]
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: trimmed) { return d }
        }

        // 2) Try dates with time (Excel / Numbers often exports these)
        let fmtsWithTime = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        for f in fmtsWithTime {
            df.dateFormat = f
            if let d = df.date(from: trimmed) { return d }
        }

        // 3) Try ISO 8601 (with/without fractional seconds)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }

        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        if let d = iso2.date(from: trimmed) { return d }

        return nil
    }

    private func mapCategory(_ s: String) -> Category {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return .other }

        for c in store.allCategories {
            if c.title.lowercased() == t { return c }
            if c.storageKey.lowercased() == t { return c }
        }

        if t.contains("groc") { return .groceries }
        if t.contains("rent") { return .rent }
        if t.contains("bill") { return .bills }
        if t.contains("trans") || t.contains("uber") || t.contains("taxi") { return .transport }
        if t.contains("health") || t.contains("pharm") { return .health }
        if t.contains("edu") || t.contains("school") { return .education }
        if t.contains("dining") || t.contains("food") || t.contains("restaurant") { return .dining }
        if t.contains("shop") { return .shopping }
        if t.contains("ent") || t.contains("movie") || t.contains("game") { return .other }
        return .other
    }
    
    private func mapPaymentMethod(_ s: String) -> PaymentMethod {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return .cash }  // default
        
        // Check for exact matches
        if t == "cash" || t == "bar" || t == "bargeld" || t == "efectivo" || t == "نقدی" { return .cash }
        if t == "card" || t == "karte" || t == "tarjeta" || t == "کارت" { return .card }
        
        // Check for partial matches
        if t.contains("cash") || t.contains("bar") { return .cash }
        if t.contains("card") || t.contains("kart") { return .card }
        
        return .cash  // default to cash if unknown
    }
    
    private func mapType(_ s: String) -> TransactionType {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty { return .expense }  // default
        
        // Check for income keywords
        if t == "income" || t == "درآمد" || t == "einkommen" || t == "ingreso" { return .income }
        if t == "in" || t == "+" || t == "credit" { return .income }
        if t.contains("income") || t.contains("earning") || t.contains("salary") { return .income }
        if t.contains("revenue") || t.contains("deposit") { return .income }
        
        // Check for expense keywords
        if t == "expense" || t == "هزینه" || t == "ausgabe" || t == "gasto" { return .expense }
        if t == "out" || t == "-" || t == "debit" { return .expense }
        if t.contains("expense") || t.contains("spending") { return .expense }
        if t.contains("payment") || t.contains("withdrawal") { return .expense }
        
        return .expense  // default to expense if unknown
    }

    private func importNow(_ parsed: ParsedCSV, mode: ImportMode) {
        guard let dIdx = colDate, let aIdx = colAmount, let cIdx = colCategory else {
            statusText = "Please map Date, Amount, Category columns."
            return
        }

        let table = parsed.raw
        let dataRows: [[String]] = hasHeaderRow ? Array(table.dropFirst()) : table

        // If mode is Replace, track all existing transactions as deleted (for cloud sync)
        // then clear them. Without trackDeletion, the cloud would never learn these were removed.
        if mode == .replace {
            let wipedIds = Set(store.transactions.map { $0.id })
            for tx in store.transactions {
                store.trackDeletion(of: tx.id)
            }
            store.transactions.removeAll()
            // Cascade: drop household split expenses tied to the wiped transactions.
            if !wipedIds.isEmpty {
                HouseholdManager.shared.removeSplitExpenses(forTransactions: wipedIds)
            }
        }

        // Build a signature set for existing transactions so we can prevent re-importing
        // the same data even if the filename differs.
        func txSignature(date: Date, amountCents: Int, category: Category, note: String) -> String {
            let day = Calendar.current.startOfDay(for: date)
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            let dayStr = df.string(from: day)
            let noteNorm = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(dayStr)|\(amountCents)|\(category.storageKey)|\(noteNorm)"
        }

        var existingSigs: Set<String> = []
        existingSigs.reserveCapacity(store.transactions.count)
        for t in store.transactions {
            existingSigs.insert(txSignature(date: t.date, amountCents: t.amount, category: t.category, note: t.note))
        }

        // First pass: validate + detect duplicates (against store and within the CSV)
        var newTransactions: [Transaction] = []
        newTransactions.reserveCapacity(max(0, dataRows.count))

        var newSigs: Set<String> = []
        var added = 0
        var skipped = 0
        var dupesFound = 0
        var importedMonths: Set<String> = []
        var latestImportedDate: Date? = nil

        for r in dataRows {
            func cell(_ idx: Int) -> String { idx < r.count ? r[idx] : "" }

            guard let date = parseDate(cell(dIdx)) else { skipped += 1; continue }

            let amountCents = DS.Format.cents(from: cell(aIdx))
            if amountCents <= 0 { skipped += 1; continue }

            let category = mapCategory(cell(cIdx))
            let note = (colNote == nil) ? "" : cell(colNote!)
            let paymentMethod = (colPaymentMethod == nil) ? .cash : mapPaymentMethod(cell(colPaymentMethod!))
            let type = (colType == nil) ? .expense : mapType(cell(colType!))

            let sig = txSignature(date: date, amountCents: amountCents, category: category, note: note)

            // Duplicate against existing store OR repeated rows inside the CSV.
            if existingSigs.contains(sig) || newSigs.contains(sig) {
                dupesFound += 1
                continue
            }

            newSigs.insert(sig)
            importedMonths.insert(Store.monthKey(date))
            if let cur = latestImportedDate {
                if date > cur { latestImportedDate = date }
            } else {
                latestImportedDate = date
            }

            newTransactions.append(Transaction(
                amount: amountCents,
                date: date,
                category: category,
                note: note,
                paymentMethod: paymentMethod,
                type: type
            ))
            added += 1
        }

        if added == 0 {
            if dupesFound > 0 {
                statusText = "Nothing new to import. \(dupesFound) duplicate transaction(s) detected and skipped."
            } else {
                statusText = "No rows imported. Check date format and amount values."
            }
            SecureLogger.info("CSV import: 0 added, \(skipped) invalid, \(dupesFound) duplicates")
            return
        }

        // Second pass: apply validated transactions.
        // CSV import creates fresh UUIDs and nil accountId/linkedGoalId,
        // so UUID collision and orphan-reference checks are not needed here.
        for t in newTransactions {
            store.add(t)
        }

        SecureLogger.info("CSV import: \(added) added, \(skipped) invalid, \(dupesFound) duplicates")

        // Jump to a relevant month so the user can immediately see what was imported.
        // If multiple months exist in the CSV, jump to the latest imported month.
        if let latestImportedDate {
            store.selectedMonth = latestImportedDate
        } else if let anyKey = importedMonths.first {
            // Fallback: should rarely happen, but keep it safe.
            // Keep selectedMonth unchanged if we can't derive a date.
            _ = anyKey
        }

        // Clean up any category budget keys that reference deleted/missing categories
        store.purgeStaleCustomCategoryBudgetKeys()

        // Save — this path intentionally bypasses TransactionService (bulk CSV import
        // with no balance/goal side-effects) and owns its own persistence directly.
        if let userId = self.authManager.currentUser?.uid {
            store.save(userId: userId)
            
            // Push imported data to cloud via SyncCoordinator
            let importedStore = store
            Task {
                _ = await SyncCoordinator.shared.pushToCloud(store: importedStore, userId: userId)
            }
        }
        
        Haptics.importSuccess()  // ← استفاده از haptic مخصوص import
        AnalyticsManager.shared.track(.csvImported(count: added))
        statusText = "Imported \(added) new transaction(s). Skipped \(skipped). Duplicates skipped: \(dupesFound)."
    }

    // MARK: Models

    private struct ParsedCSV {
        let raw: [[String]]
        let columns: [String]
        let previewRows: [[String]]
    }
}
