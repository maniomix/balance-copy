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
    
    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var accountType: AccountType = .bank
    @State private var balance = ""
    @State private var currency = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
    @State private var institutionName = ""
    @State private var creditLimit = ""
    @State private var interestRate = ""
    @State private var isSaving = false
    @State private var showDeleteConfirmation = false
    
    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }
    
    private var existingAccount: Account? {
        if case .edit(let a) = mode { return a }
        return nil
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // Account Info
                Section {
                    TextField("Account Name", text: $name)
                    
                    Picker("Type", selection: $accountType) {
                        ForEach(AccountType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    
                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(DS.Colors.subtext)
                        TextField("Current Balance", text: $balance)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("Account Information")
                }
                
                // Details
                Section {
                    TextField("Institution Name (optional)", text: $institutionName)
                    
                    Picker("Currency", selection: $currency) {
                        Text("USD ($)").tag("USD")
                        Text("EUR (€)").tag("EUR")
                        Text("GBP (£)").tag("GBP")
                        Text("IRR (﷼)").tag("IRR")
                        Text("CAD (C$)").tag("CAD")
                        Text("AUD (A$)").tag("AUD")
                    }
                } header: {
                    Text("Details")
                }
                
                // Credit Card / Loan fields
                if accountType == .creditCard || accountType == .loan {
                    Section {
                        if accountType == .creditCard {
                            HStack {
                                Text(currencySymbol)
                                    .foregroundStyle(DS.Colors.subtext)
                                TextField("Credit Limit", text: $creditLimit)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        
                        HStack {
                            TextField("Interest Rate", text: $interestRate)
                                .keyboardType(.decimalPad)
                            Text("%")
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    } header: {
                        Text(accountType == .creditCard ? "Credit Card Details" : "Loan Details")
                    }
                }
                
                // Delete
                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Account")
                                Spacer()
                            }
                        }
                    }
                }
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
                    .disabled(name.isEmpty || isSaving)
                }
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        if let account = existingAccount {
                            _ = await accountManager.deleteAccount(account)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text("This will permanently delete this account and all its balance history. This action cannot be undone.")
            }
            .onAppear { loadExistingData() }
        }
    }
    
    // MARK: - Helpers
    
    private var currencySymbol: String {
        switch currency {
        case "EUR": return "€"
        case "GBP": return "£"
        case "IRR": return "﷼"
        default: return "$"
        }
    }
    
    private func loadExistingData() {
        guard let account = existingAccount else { return }
        name = account.name
        accountType = account.type
        balance = String(format: "%.2f", account.currentBalance)
        currency = account.currency
        institutionName = account.institutionName ?? ""
        creditLimit = account.creditLimit.map { String(format: "%.2f", $0) } ?? ""
        interestRate = account.interestRate.map { String(format: "%.2f", $0) } ?? ""
    }
    
    private func saveAccount() async {
        guard let uidString = AuthManager.shared.currentUser?.uid,
              let userId = UUID(uuidString: uidString) else { return }
        isSaving = true
        
        let balanceValue = Double(balance) ?? 0
        let creditLimitValue = creditLimit.isEmpty ? nil : Double(creditLimit)
        let interestRateValue = interestRate.isEmpty ? nil : Double(interestRate)
        let institutionValue = institutionName.isEmpty ? nil : institutionName
        
        if var existing = existingAccount {
            existing.name = name
            existing.type = accountType
            existing.currentBalance = balanceValue
            existing.currency = currency
            existing.institutionName = institutionValue
            existing.creditLimit = creditLimitValue
            existing.interestRate = interestRateValue
            
            let success = await accountManager.updateAccount(existing)
            if success { dismiss() }
        } else {
            let newAccount = Account(
                name: name,
                type: accountType,
                currentBalance: balanceValue,
                currency: currency,
                institutionName: institutionValue,
                creditLimit: creditLimitValue,
                interestRate: interestRateValue,
                userId: userId
            )
            let success = await accountManager.createAccount(newAccount)
            if success { dismiss() }
        }
        
        isSaving = false
    }
}
