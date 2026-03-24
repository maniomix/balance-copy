import SwiftUI

// MARK: - Account Picker View

/// Full-screen picker for selecting an account (used in sheets)
struct AccountPickerView: View {
    
    @Binding var selectedAccountId: UUID?
    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                // No account
                Button {
                    selectedAccountId = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(width: 28)
                        Text("No Account")
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        if selectedAccountId == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DS.Colors.accent)
                        }
                    }
                }
                
                if !accountManager.assetAccounts.isEmpty {
                    Section("Assets") {
                        ForEach(accountManager.assetAccounts) { account in
                            accountRow(account)
                        }
                    }
                }
                
                if !accountManager.liabilityAccounts.isEmpty {
                    Section("Liabilities") {
                        ForEach(accountManager.liabilityAccounts) { account in
                            accountRow(account)
                        }
                    }
                }
            }
            .navigationTitle("Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                if accountManager.accounts.isEmpty {
                    await accountManager.fetchAccounts()
                }
            }
        }
    }
    
    private func accountRow(_ account: Account) -> some View {
        Button {
            selectedAccountId = account.id
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: account.type.iconName)
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.text)
                    if let inst = account.institutionName {
                        Text(inst)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                
                Spacer()
                
                if selectedAccountId == account.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Colors.accent)
                }
            }
        }
    }
}

// MARK: - Inline Account Selector

/// Compact row for embedding in transaction forms
struct InlineAccountSelector: View {
    
    @Binding var selectedAccountId: UUID?
    @State private var showPicker = false
    @StateObject private var accountManager = AccountManager.shared
    
    var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Image(systemName: selectedAccount?.type.iconName ?? "building.columns")
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 22)
                
                Text(selectedAccount?.name ?? "No Account")
                    .font(DS.Typography.body)
                    .foregroundStyle(
                        selectedAccount != nil ? DS.Colors.text : DS.Colors.subtext
                    )
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Colors.subtext.opacity(0.4))
            }
        }
        .sheet(isPresented: $showPicker) {
            AccountPickerView(selectedAccountId: $selectedAccountId)
        }
    }
    
    private var selectedAccount: Account? {
        guard let id = selectedAccountId else { return nil }
        return accountManager.accounts.first { $0.id == id }
    }
}
