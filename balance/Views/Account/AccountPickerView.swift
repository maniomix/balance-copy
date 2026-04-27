import SwiftUI

// MARK: - Recently-Used Tracking

private enum RecentAccounts {
    private static let key = "accounts.recentlyPicked"
    private static let limit = 5

    static func load() -> [UUID] {
        guard let raw = UserDefaults.standard.array(forKey: key) as? [String] else { return [] }
        return raw.compactMap(UUID.init(uuidString:))
    }

    static func record(_ id: UUID) {
        var current = load().filter { $0 != id }
        current.insert(id, at: 0)
        if current.count > limit { current = Array(current.prefix(limit)) }
        UserDefaults.standard.set(current.map(\.uuidString), forKey: key)
    }
}

// MARK: - Account Picker View

/// Full-screen picker. Supports both single-select (`selectedAccountId`)
/// and multi-select (`selectedIds`) modes — the multi-select binding takes
/// priority when provided. Used by transaction forms (single) and by
/// Insights / Charts / AI scope filters (multi).
struct AccountPickerView: View {

    // Single-select binding (legacy — used by transaction forms, transfer sheet)
    @Binding var selectedAccountId: UUID?
    // Multi-select binding (new — used by filter screens). When non-nil,
    // the picker switches into multi-select mode.
    private let multiSelection: Binding<Set<UUID>>?

    @StateObject private var accountManager = AccountManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var showArchived = false

    // Convenience inits

    init(selectedAccountId: Binding<UUID?>) {
        self._selectedAccountId = selectedAccountId
        self.multiSelection = nil
    }

    init(selectedIds: Binding<Set<UUID>>) {
        // Use a constant binding for the unused single-select slot.
        self._selectedAccountId = .constant(nil)
        self.multiSelection = selectedIds
    }

    private var isMulti: Bool { multiSelection != nil }

    private var allAccounts: [Account] {
        showArchived ? accountManager.accounts : accountManager.activeAccounts
    }

    private func filtered(_ accounts: [Account]) -> [Account] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return accounts }
        return accounts.filter {
            $0.name.lowercased().contains(q)
                || ($0.institutionName?.lowercased().contains(q) ?? false)
                || $0.type.displayName.lowercased().contains(q)
        }
    }

    private var assets: [Account] { filtered(allAccounts.filter { $0.type.isAsset }) }
    private var liabilities: [Account] { filtered(allAccounts.filter { $0.type.isLiability }) }

    private var recentAccounts: [Account] {
        let ids = RecentAccounts.load()
        return ids.compactMap { id in allAccounts.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            List {
                if !isMulti {
                    Section {
                        Button {
                            selectedAccountId = nil
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(DS.Colors.subtext)
                                    .frame(width: 28)
                                Text("No Account").foregroundStyle(DS.Colors.text)
                                Spacer()
                                if selectedAccountId == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(DS.Colors.accent)
                                }
                            }
                        }
                    }
                }

                if !recentAccounts.isEmpty && search.isEmpty {
                    Section("Recently Used") {
                        ForEach(recentAccounts) { row($0) }
                    }
                }

                if !assets.isEmpty {
                    Section("Assets") {
                        ForEach(assets) { row($0) }
                    }
                }

                if !liabilities.isEmpty {
                    Section("Liabilities") {
                        ForEach(liabilities) { row($0) }
                    }
                }

                if accountManager.accounts.contains(where: \.isArchived) {
                    Section {
                        Toggle("Show archived", isOn: $showArchived)
                            .font(DS.Typography.body)
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search accounts")
            .navigationTitle(isMulti ? "Filter Accounts" : "Select Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isMulti {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Select All") { selectAll() }
                            Button("Select None") { selectNone() }
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                if accountManager.accounts.isEmpty { await accountManager.fetchAccounts() }
            }
        }
    }

    // MARK: - Row

    private func row(_ account: Account) -> some View {
        Button { tap(account) } label: {
            HStack(spacing: 10) {
                Image(systemName: account.type.iconName)
                    .foregroundStyle(AccountColorTag.color(for: account.colorTag))
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.text)
                        if account.isArchived {
                            Text("Archived")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(DS.Colors.subtext.opacity(0.12), in: Capsule())
                        }
                    }
                    if let inst = account.institutionName, !inst.isEmpty {
                        Text(inst).font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                    }
                }

                Spacer()

                if isSelected(account) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Colors.accent)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selection helpers

    private func isSelected(_ account: Account) -> Bool {
        if let multi = multiSelection?.wrappedValue {
            return multi.contains(account.id)
        }
        return selectedAccountId == account.id
    }

    private func tap(_ account: Account) {
        if let multi = multiSelection {
            var current = multi.wrappedValue
            if current.contains(account.id) {
                current.remove(account.id)
            } else {
                current.insert(account.id)
                RecentAccounts.record(account.id)
            }
            multi.wrappedValue = current
        } else {
            selectedAccountId = account.id
            RecentAccounts.record(account.id)
            dismiss()
        }
    }

    private func selectAll() {
        guard let multi = multiSelection else { return }
        multi.wrappedValue = Set(allAccounts.map(\.id))
    }

    private func selectNone() {
        guard let multi = multiSelection else { return }
        multi.wrappedValue = []
    }
}

// MARK: - Inline Account Selector

/// Compact row for embedding in transaction forms (single-select only).
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
                    .foregroundStyle(AccountColorTag.color(for: selectedAccount?.colorTag ?? nil))
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
