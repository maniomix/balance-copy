import SwiftUI

// MARK: - Add/Edit Account View

struct AddEditAccountView: View {

    enum Mode: Identifiable {
        case add
        case edit(Account)

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let a): return a.id.uuidString
            }
        }
    }

    let mode: Mode
    @Binding var store: Store

    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var householdManager = HouseholdManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var assetSide: Side = .asset
    @State private var accountType: AccountType = .bank
    @State private var balance = ""
    @State private var currency = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
    @State private var institutionName = ""
    @State private var creditLimit = ""
    @State private var interestRate = ""
    @State private var colorTag: String? = nil
    @State private var includeInNetWorth = true
    @State private var isSaving = false
    @State private var showCurrencyPicker = false
    @State private var showDelete = false
    @State private var validationError: String? = nil

    private enum Side: String, CaseIterable, Identifiable {
        case asset, liability
        var id: String { rawValue }
        var label: String { self == .asset ? "Asset" : "Liability" }
        var types: [AccountType] {
            self == .asset ? [.cash, .bank, .savings, .investment] : [.creditCard, .loan]
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var existingAccount: Account? {
        if case .edit(let a) = mode { return a }
        return nil
    }

    private var currencySymbol: String {
        CurrencyFormatter.SupportedCurrency(rawValue: currency)?.symbol ?? currency
    }

    private var canSave: Bool {
        validate() == nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                identitySection
                balanceSection
                colorSection
                netWorthSection
                householdSection
                institutionSection
                if accountType == .creditCard || accountType == .loan {
                    creditLoanSection
                }
                if let err = validationError {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.danger)
                    }
                }
                if isEditing { dangerSection }
            }
            .navigationTitle(isEditing ? "Edit Account" : "New Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Add") {
                        Task { await saveAccount() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                CurrencyPickerSheet(selection: $currency)
            }
            .sheet(isPresented: $showDelete) {
                if let account = existingAccount {
                    DeleteAccountSheet(
                        account: account,
                        store: $store,
                        onArchived: { dismiss() },
                        onDeleted: { dismiss() }
                    )
                }
            }
            .onAppear { loadExistingData() }
            .onChange(of: assetSide) { _, side in
                if !side.types.contains(accountType) {
                    accountType = side.types.first ?? .bank
                }
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identity") {
            TextField("Account Name", text: $name)
                .submitLabel(.next)

            Picker("", selection: $assetSide) {
                ForEach(Side.allCases) { side in
                    Text(side.label).tag(side)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 8) {
                Text("Type")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                    ForEach(assetSide.types) { type in
                        typeChip(type)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func typeChip(_ type: AccountType) -> some View {
        let selected = type == accountType
        return Button { accountType = type } label: {
            HStack(spacing: 6) {
                Image(systemName: type.iconName).font(.system(size: 12, weight: .semibold))
                Text(type.displayName).font(DS.Typography.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Color.white : DS.Colors.text)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? DS.Colors.accent : DS.Colors.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private var balanceSection: some View {
        Section("Balance") {
            Button {
                showCurrencyPicker = true
            } label: {
                HStack {
                    Text("Currency")
                        .foregroundStyle(DS.Colors.text)
                    Spacer()
                    Text("\(currency) \(currencySymbol)")
                        .foregroundStyle(DS.Colors.subtext)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext.opacity(0.5))
                }
            }
            .buttonStyle(.plain)

            HStack {
                Text(currencySymbol)
                    .foregroundStyle(DS.Colors.subtext)
                TextField("Current Balance", text: $balance)
                    .keyboardType(.decimalPad)
            }
        }
    }

    private var colorSection: some View {
        Section("Color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    colorSwatch(tag: nil)
                    ForEach(AccountColorTag.allCases) { tag in
                        colorSwatch(tag: tag.rawValue)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func colorSwatch(tag: String?) -> some View {
        let selected = tag == colorTag
        let color = AccountColorTag.color(for: tag)
        return Button { colorTag = tag } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                if selected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 30, height: 30)
                    Circle()
                        .stroke(color, lineWidth: 2)
                        .frame(width: 36, height: 36)
                }
                if tag == nil {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tag ?? "Default")
    }

    private var netWorthSection: some View {
        Section {
            Toggle("Include in Net Worth", isOn: $includeInNetWorth)
        } footer: {
            Text("When off, this account's balance is excluded from the net-worth roll-up. Transactions still affect budgets.")
                .font(DS.Typography.caption)
        }
    }

    private var institutionSection: some View {
        Section("Institution") {
            TextField("Institution Name (optional)", text: $institutionName)
        }
    }

    @ViewBuilder
    private var householdSection: some View {
        // Only meaningful in edit mode (account must exist) and when this user
        // is in a household with transaction sharing turned on. Otherwise the
        // section is hidden — the privacy parent toggle lives in Household.
        if let acc = existingAccount,
           householdManager.isInHousehold,
           householdManager.currentMember?.shareTransactions == true {

            let bound = Binding(
                get: { householdManager.isAccountShared(acc.id) },
                set: { newValue in
                    let allActive = accountManager.activeAccounts.map(\.id)
                    householdManager.setAccountShared(acc.id, shared: newValue, allActiveIds: allActive)
                }
            )

            Section {
                Toggle("Share with Household", isOn: bound)
            } footer: {
                Text("When on, this account's transactions are visible to household members. Balance is authoritative on your device.")
                    .font(DS.Typography.caption)
            }
        }
    }

    private var creditLoanSection: some View {
        Section(accountType == .creditCard ? "Credit Card" : "Loan") {
            if accountType == .creditCard {
                HStack {
                    Text(currencySymbol).foregroundStyle(DS.Colors.subtext)
                    TextField("Credit Limit", text: $creditLimit)
                        .keyboardType(.decimalPad)
                }
            }
            HStack {
                TextField("Interest Rate", text: $interestRate)
                    .keyboardType(.decimalPad)
                Text("%").foregroundStyle(DS.Colors.subtext)
            }
        }
    }

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showDelete = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Account")
                }
            }
        } footer: {
            Text("Hard delete is permanent. Archive is reversible.")
                .font(DS.Typography.caption)
        }
    }

    // MARK: - Validation

    /// Returns the first user-friendly validation error, or nil if OK.
    private func validate() -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Name is required." }
        if !balance.isEmpty, Double(balance) == nil {
            return "Balance must be a number."
        }
        if !interestRate.isEmpty {
            guard let rate = Double(interestRate) else { return "Interest rate must be a number." }
            if rate < 0 { return "Interest rate can't be negative." }
        }
        if accountType == .creditCard {
            if creditLimit.isEmpty { return "Credit limit is required for cards." }
            guard let limit = Double(creditLimit) else { return "Credit limit must be a number." }
            if limit <= 0 { return "Credit limit must be greater than zero." }
        }
        return nil
    }

    // MARK: - Load + Save

    private func loadExistingData() {
        guard let account = existingAccount else { return }
        name = account.name
        accountType = account.type
        assetSide = account.type.isAsset ? .asset : .liability
        balance = String(format: "%.2f", account.currentBalance)
        currency = account.currency
        institutionName = account.institutionName ?? ""
        creditLimit = account.creditLimit.map { String(format: "%.2f", $0) } ?? ""
        interestRate = account.interestRate.map { String(format: "%.2f", $0) } ?? ""
        colorTag = account.colorTag
        includeInNetWorth = account.includeInNetWorth
    }

    private func saveAccount() async {
        if let err = validate() {
            validationError = err
            return
        }
        validationError = nil

        guard let uidString = AuthManager.shared.currentUser?.uid,
              let userId = UUID(uuidString: uidString) else { return }
        isSaving = true
        defer { isSaving = false }

        let balanceValue = Double(balance) ?? 0
        let creditLimitValue = creditLimit.isEmpty ? nil : Double(creditLimit)
        let interestRateValue = interestRate.isEmpty ? nil : Double(interestRate)
        let institutionValue = institutionName.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil : institutionName

        if var existing = existingAccount {
            existing.name = name
            existing.type = accountType
            existing.currentBalance = balanceValue
            existing.currency = currency
            existing.institutionName = institutionValue
            existing.creditLimit = creditLimitValue
            existing.interestRate = interestRateValue
            existing.colorTag = colorTag
            existing.includeInNetWorth = includeInNetWorth

            if await accountManager.updateAccount(existing) { dismiss() }
        } else {
            let newAccount = Account(
                name: name,
                type: accountType,
                currentBalance: balanceValue,
                currency: currency,
                institutionName: institutionValue,
                creditLimit: creditLimitValue,
                interestRate: interestRateValue,
                userId: userId,
                displayOrder: 0,
                colorTag: colorTag,
                includeInNetWorth: includeInNetWorth
            )
            if await accountManager.createAccount(newAccount) { dismiss() }
        }
    }
}

// MARK: - Delete Sheet (typed-confirm + reference-aware)

struct DeleteAccountSheet: View {

    let account: Account
    @Binding var store: Store
    var onArchived: () -> Void
    var onDeleted: () -> Void

    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var working = false

    private var refCount: Int {
        accountManager.transactionReferenceCount(for: account, in: store)
    }

    private var typedMatches: Bool {
        typed.trimmingCharacters(in: .whitespaces) == account.name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    if refCount > 0 {
                        blockedCard
                    } else {
                        confirmCard
                    }
                }
                .padding(16)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Delete Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                Label(account.name, systemImage: account.type.iconName)
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.text)
                Text("This action removes the account and all its balance history. It cannot be undone.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var blockedCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Label("\(refCount) transactions reference this account", systemImage: "link")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.warning)
                Text("Hard delete is blocked while transactions still point to this account. Archive it instead — archived accounts are reversible and stay linked to their history.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.subtext)
                Button {
                    Task {
                        working = true
                        _ = await accountManager.archiveAccount(account)
                        working = false
                        onArchived()
                        dismiss()
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text("Archive Instead")
                    }
                    .font(DS.Typography.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DS.Colors.warning, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(working)
            }
        }
    }

    private var confirmCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Type the account name to confirm")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)
                Text(account.name)
                    .font(DS.Typography.body.weight(.semibold))
                    .foregroundStyle(DS.Colors.subtext)
                TextField("Account name", text: $typed)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button(role: .destructive) {
                    Task {
                        working = true
                        let ok = await accountManager.deleteAccount(account)
                        working = false
                        if ok {
                            onDeleted()
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        if working { ProgressView().tint(.white) }
                        Text("Permanently Delete")
                    }
                    .font(DS.Typography.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        (typedMatches ? DS.Colors.danger : DS.Colors.danger.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!typedMatches || working)
            }
        }
    }
}
