import SwiftUI

// MARK: - Accounts List View

struct AccountsListView: View {

    @Binding var store: Store
    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var householdManager = HouseholdManager.shared
    @State private var showAddAccount = false
    @State private var accountToEdit: Account?
    @State private var showReorderSheet = false
    @State private var showNetWorthSheet = false
    @State private var showArchived = false
    @State private var showTransfer = false
    @AppStorage("accounts.sortMode") private var sortRaw: String = AccountSort.custom.rawValue

    private var sortMode: AccountSort {
        AccountSort(rawValue: sortRaw) ?? .custom
    }

    private var assets: [Account] {
        sortMode.apply(to: accountManager.assetAccounts)
    }
    private var liabilities: [Account] {
        sortMode.apply(to: accountManager.liabilityAccounts)
    }
    private var archived: [Account] {
        accountManager.accounts.filter(\.isArchived)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                netWorthCard

                sortBar

                if !assets.isEmpty {
                    accountSection(
                        title: "Assets",
                        accounts: assets,
                        total: accountManager.convertedTotalAssets,
                        color: DS.Colors.positive
                    )
                }

                if !liabilities.isEmpty {
                    accountSection(
                        title: "Liabilities",
                        accounts: liabilities,
                        total: accountManager.convertedTotalLiabilities,
                        color: DS.Colors.danger
                    )
                }

                if !archived.isEmpty {
                    archivedSection
                }

                if accountManager.activeAccounts.isEmpty && !accountManager.isLoading {
                    emptyState
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                SectionHelpButton(screen: .accounts)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showAddAccount = true } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                    Button { showTransfer = true } label: {
                        Label("Transfer", systemImage: "arrow.left.arrow.right")
                    }
                    .disabled(accountManager.activeAccounts.count < 2)
                    Button { showReorderSheet = true } label: {
                        Label("Reorder", systemImage: "line.3.horizontal")
                    }
                    .disabled(accountManager.activeAccounts.count < 2)
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Colors.accent)
                }
                .accessibilityLabel("Account actions")
            }
        }
        .sheet(isPresented: $showAddAccount) {
            AddEditAccountView(mode: .add, store: $store)
        }
        .sheet(item: $accountToEdit) { account in
            AddEditAccountView(mode: .edit(account), store: $store)
        }
        .sheet(isPresented: $showReorderSheet) {
            AccountReorderSheet()
        }
        .sheet(isPresented: $showNetWorthSheet) {
            NetWorthRollupSheet()
        }
        .sheet(isPresented: $showTransfer) {
            TransferSheet(store: $store)
        }
        .task { await accountManager.fetchAccounts() }
        .refreshable { await accountManager.fetchAccounts() }
    }

    // MARK: - Net Worth Card

    private var netWorthCard: some View {
        Button { showNetWorthSheet = true } label: {
            DS.Card {
                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text("Net Worth")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext.opacity(0.6))
                    }

                    Text(fmtCurrency(accountManager.convertedNetWorth))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    HStack(spacing: 24) {
                        VStack(spacing: 4) {
                            Text("Assets").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                            Text(fmtCurrency(accountManager.convertedTotalAssets))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.positive)
                        }
                        Rectangle().fill(DS.Colors.grid).frame(width: 1, height: 30)
                        VStack(spacing: 4) {
                            Text("Liabilities").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                            Text(fmtCurrency(accountManager.convertedTotalLiabilities))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.danger)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Net worth breakdown")
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AccountSort.allCases) { mode in
                    sortPill(mode)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func sortPill(_ mode: AccountSort) -> some View {
        let selected = mode == sortMode
        return Button {
            sortRaw = mode.rawValue
        } label: {
            HStack(spacing: 6) {
                Image(systemName: mode.icon).font(.system(size: 11, weight: .semibold))
                Text(mode.label).font(DS.Typography.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.white : DS.Colors.text)
            .background(
                Capsule().fill(selected ? DS.Colors.accent : DS.Colors.surface)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(mode.label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Account Section

    private func accountSection(title: String, accounts: [Account], total: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                Spacer()
                Text(fmtCurrency(total)).font(DS.Typography.section).foregroundStyle(color)
            }
            .padding(.horizontal, 4)

            ForEach(accounts) { account in
                NavigationLink(destination: AccountDetailView(account: account, store: $store)) {
                    AccountRowView(
                        account: account,
                        sharedWithHousehold: householdManager.isAccountShared(account.id)
                    )
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { accountToEdit = account } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        Task {
                            var copy = account
                            copy.includeInNetWorth.toggle()
                            _ = await accountManager.updateAccount(copy)
                        }
                    } label: {
                        Label(
                            account.includeInNetWorth ? "Exclude from Net Worth" : "Include in Net Worth",
                            systemImage: account.includeInNetWorth ? "minus.circle" : "plus.circle"
                        )
                    }
                    Button(role: .destructive) {
                        Task { _ = await accountManager.archiveAccount(account) }
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
            }
        }
    }

    // MARK: - Archived Section

    private var archivedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation { showArchived.toggle() } } label: {
                HStack {
                    Text("Archived")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.subtext)
                    Text("(\(archived.count))")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    Spacer()
                    Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)

            if showArchived {
                ForEach(archived) { account in
                    AccountRowView(
                        account: account,
                        dimmed: true,
                        sharedWithHousehold: householdManager.isAccountShared(account.id)
                    )
                        .contextMenu {
                            Button {
                                Task { _ = await accountManager.restoreArchived(account) }
                            } label: {
                                Label("Restore", systemImage: "tray.and.arrow.up")
                            }
                            Button(role: .destructive) {
                                accountToEdit = account
                            } label: {
                                Label("Delete…", systemImage: "trash")
                            }
                        }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "building.columns")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
            Text("No Accounts Yet")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)
            Text("Add your bank accounts, credit cards, and other financial accounts to track your net worth.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button { showAddAccount = true } label: {
                Label("Add Account", systemImage: "plus")
                    .font(DS.Typography.body.weight(.semibold))
            }
            .buttonStyle(DS.ColoredButton())
            .padding(.horizontal, 60)
        }
        .padding(.vertical, 40)
    }

    private func fmtCurrency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Account Row

struct AccountRowView: View {
    let account: Account
    var dimmed: Bool = false
    var sharedWithHousehold: Bool = false

    private var appCurrency: String {
        UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
    }

    private var isDifferentCurrency: Bool {
        account.currency != appCurrency
    }

    private var accent: Color {
        AccountColorTag.color(for: account.colorTag)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(account.name)
                        .font(DS.Typography.body.weight(.medium))
                        .foregroundStyle(DS.Colors.text)
                    if !account.includeInNetWorth {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                            .accessibilityLabel("Excluded from net worth")
                    }
                    if sharedWithHousehold {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .accessibilityLabel("Shared with household")
                    }
                }
                HStack(spacing: 4) {
                    Text(account.type.displayName)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    if let inst = account.institutionName, !inst.isEmpty {
                        Text("·").foregroundStyle(DS.Colors.subtext)
                        Text(inst).font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(fmtCurrency(account.currentBalance, code: account.currency))
                    .font(DS.Typography.number)
                    .foregroundStyle(DS.Colors.text)

                if isDifferentCurrency,
                   let converted = CurrencyConverter.shared.convertedDisplayText(
                       account.currentBalance, from: account.currency
                   ) {
                    Text(converted)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                }

                if account.type == .creditCard, let avail = account.availableCredit {
                    Text("\(fmtCurrency(avail, code: account.currency)) available")
                        .font(.system(size: 10))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
        }
        .padding(12)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(dimmed ? 0.6 : 1)
    }

    private func fmtCurrency(_ value: Double, code: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = code; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
