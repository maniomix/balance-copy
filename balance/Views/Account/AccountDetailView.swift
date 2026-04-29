import SwiftUI
import Charts
import Supabase
import PostgREST

// MARK: - Account Detail View

struct AccountDetailView: View {

    let account: Account
    @Binding var store: Store

    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var householdManager = HouseholdManager.shared
    @State private var balanceHistory: [AccountBalanceSnapshot] = []
    @State private var showEditSheet = false
    @State private var showAddTransaction = false
    @State private var showTransfer = false
    @State private var showDetails = false
    @State private var visibleMonths = 3
    @State private var range: HistoryRange = .threeMonths

    // Refetch detail-scoped account from manager so balance updates after
    // transaction edits surface live.
    private var liveAccount: Account {
        accountManager.accounts.first(where: { $0.id == account.id }) ?? account
    }

    private var accent: Color {
        AccountColorTag.color(for: liveAccount.colorTag)
    }

    private var transactions: [Transaction] {
        store.transactions
            .filter { $0.accountId == account.id }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                balanceCard
                quickActionsRow
                if !balanceHistory.isEmpty { balanceChartCard }
                transactionsCard
                detailsCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 24)
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle(liveAccount.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
                    .foregroundStyle(DS.Colors.accent)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddEditAccountView(mode: .edit(liveAccount), store: $store)
        }
        .sheet(isPresented: $showAddTransaction) {
            TransactionSheet(
                .add(initialMonth: store.selectedMonth, accountId: account.id),
                in: $store,
                source: .accountDetail
            )
        }
        .sheet(isPresented: $showTransfer) {
            TransferSheet(store: $store, preselectedSourceId: account.id)
        }
        .task { await loadHistory() }
    }

    // MARK: - Balance hero

    private var balanceCard: some View {
        DS.Card {
            VStack(spacing: 12) {
                Image(systemName: liveAccount.type.iconName)
                    .font(.title2)
                    .foregroundStyle(accent)
                    .frame(width: 50, height: 50)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("Current Balance")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                Text(fmtCurrency(liveAccount.currentBalance))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)

                if let converted = convertedBalanceText {
                    Text(converted)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                }

                HStack(spacing: 6) {
                    badge(liveAccount.type.isAsset ? "Asset" : "Liability",
                          tint: liveAccount.type.isAsset ? DS.Colors.positive : DS.Colors.danger)
                    if !liveAccount.includeInNetWorth {
                        badge("Excluded", tint: DS.Colors.subtext)
                    }
                    if liveAccount.isArchived {
                        badge("Archived", tint: DS.Colors.warning)
                    }
                    if householdManager.isAccountShared(liveAccount.id) {
                        badge("Shared", tint: DS.Colors.accent)
                    }
                }

                if liveAccount.type == .creditCard, let limit = liveAccount.creditLimit, limit > 0 {
                    creditBar(used: abs(liveAccount.currentBalance), limit: limit)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func creditBar(used: Double, limit: Double) -> some View {
        let ratio = min(used / limit, 1.0)
        let color: Color = ratio > 0.75 ? DS.Colors.danger : (ratio > 0.5 ? DS.Colors.warning : DS.Colors.positive)
        return VStack(spacing: 6) {
            HStack {
                Text("Credit Used").font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
                Spacer()
                Text("\(Int(ratio * 100))%").font(DS.Typography.caption.weight(.semibold)).foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(DS.Colors.grid).frame(height: 5)
                    RoundedRectangle(cornerRadius: 3).fill(color).frame(width: geo.size.width * ratio, height: 5)
                }
            }.frame(height: 5)
            HStack {
                Text("\(fmtCurrency(used)) used").font(.system(size: 10)).foregroundStyle(DS.Colors.subtext)
                Spacer()
                Text("\(fmtCurrency(limit)) limit").font(.system(size: 10)).foregroundStyle(DS.Colors.subtext)
            }
        }.padding(.top, 8)
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: 10) {
            quickAction("Add", icon: "plus") { showAddTransaction = true }
            quickAction("Transfer", icon: "arrow.left.arrow.right") { showTransfer = true }
            quickAction("Edit", icon: "pencil") { showEditSheet = true }
            quickAction(
                liveAccount.includeInNetWorth ? "Exclude" : "Include",
                icon: liveAccount.includeInNetWorth ? "minus.circle" : "plus.circle"
            ) {
                Task {
                    var copy = liveAccount
                    copy.includeInNetWorth.toggle()
                    _ = await accountManager.updateAccount(copy)
                }
            }
            if liveAccount.isArchived {
                quickAction("Restore", icon: "tray.and.arrow.up") {
                    Task { _ = await accountManager.restoreArchived(liveAccount) }
                }
            } else {
                quickAction("Archive", icon: "archivebox") {
                    Task { _ = await accountManager.archiveAccount(liveAccount) }
                }
            }
        }
    }

    private func quickAction(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accent)
                Text(label)
                    .font(DS.Typography.caption.weight(.medium))
                    .foregroundStyle(DS.Colors.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Balance history chart

    private enum HistoryRange: String, CaseIterable, Identifiable {
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case all = "All"
        var id: String { rawValue }

        var cutoff: Date? {
            let cal = Calendar.current
            let now = Date()
            switch self {
            case .oneMonth:    return cal.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: return cal.date(byAdding: .month, value: -3, to: now)
            case .sixMonths:   return cal.date(byAdding: .month, value: -6, to: now)
            case .oneYear:     return cal.date(byAdding: .year, value: -1, to: now)
            case .all:         return nil
            }
        }
    }

    private var filteredHistory: [AccountBalanceSnapshot] {
        guard let cutoff = range.cutoff else { return balanceHistory }
        return balanceHistory.filter { $0.snapshotDate >= cutoff }
    }

    private var balanceChartCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Balance History").font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                    Spacer()
                    rangePill
                }
                if #available(iOS 16.0, *) {
                    let data = filteredHistory
                    if data.isEmpty {
                        Text("No data in this range")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    } else {
                        Chart(data) { s in
                            LineMark(x: .value("Date", s.snapshotDate), y: .value("Balance", s.balance))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(accent)
                            AreaMark(x: .value("Date", s.snapshotDate), y: .value("Balance", s.balance))
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(LinearGradient(colors: [accent.opacity(0.2), accent.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { v in
                                AxisValueLabel {
                                    if let a = v.as(Double.self) {
                                        Text(fmtCompact(a))
                                            .font(.system(size: 10))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                }
                            }
                        }
                        .chartXAxis {
                            AxisMarks { v in
                                AxisValueLabel {
                                    if let d = v.as(Date.self) {
                                        Text(d, format: .dateTime.month(.abbreviated))
                                            .font(.system(size: 10))
                                            .foregroundStyle(DS.Colors.subtext)
                                    }
                                }
                            }
                        }
                        .frame(height: 170)
                    }
                }
            }
        }
    }

    private var rangePill: some View {
        Menu {
            ForEach(HistoryRange.allCases) { r in
                Button { range = r } label: {
                    if r == range {
                        Label(r.rawValue, systemImage: "checkmark")
                    } else {
                        Text(r.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(range.rawValue).font(DS.Typography.caption.weight(.semibold))
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(DS.Colors.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(DS.Colors.surface))
        }
    }

    // MARK: - Transactions

    private struct MonthGroup: Identifiable {
        let id: Date
        let label: String
        let items: [Transaction]
        let net: Double
    }

    private var monthGroups: [MonthGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: transactions) { tx -> Date in
            let comps = cal.dateComponents([.year, .month], from: tx.date)
            return cal.date(from: comps) ?? tx.date
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return grouped
            .map { (key, items) in
                // Net excludes transfer legs — they're not real income/expense.
                let net = items.reduce(0.0) { acc, tx in
                    guard !tx.isTransfer else { return acc }
                    let amt = Double(tx.amount) / 100.0
                    return acc + (tx.type == .income ? amt : -amt)
                }
                return MonthGroup(
                    id: key,
                    label: formatter.string(from: key),
                    items: items.sorted { $0.date > $1.date },
                    net: net
                )
            }
            .sorted { $0.id > $1.id }
    }

    private var transactionsCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Transactions").font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                    Spacer()
                    Text("\(transactions.count)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }

                if transactions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 26))
                            .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                        Text("No transactions yet")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                        Button { showAddTransaction = true } label: {
                            Label("Add transaction", systemImage: "plus")
                                .font(DS.Typography.caption.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    ForEach(monthGroups.prefix(visibleMonths)) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(group.label)
                                    .font(DS.Typography.caption.weight(.semibold))
                                    .foregroundStyle(DS.Colors.subtext)
                                Spacer()
                                Text(fmtCurrency(group.net))
                                    .font(DS.Typography.caption.weight(.semibold))
                                    .foregroundStyle(group.net >= 0 ? DS.Colors.positive : DS.Colors.danger)
                            }
                            .padding(.horizontal, 4)

                            ForEach(group.items) { tx in
                                txRow(tx)
                            }
                        }
                        .padding(.top, 4)
                    }

                    if monthGroups.count > visibleMonths {
                        Button { visibleMonths += 3 } label: {
                            Text("Show earlier months")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func txRow(_ tx: Transaction) -> some View {
        let amount = Double(tx.amount) / 100.0
        let isIncome = tx.type == .income
        let isTransfer = tx.isTransfer
        let icon = isTransfer ? "arrow.left.arrow.right" : tx.category.icon
        let amountTint: Color = isTransfer
            ? DS.Colors.subtext
            : (isIncome ? DS.Colors.positive : DS.Colors.text)

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isTransfer ? DS.Colors.accent : DS.Colors.subtext)
                .frame(width: 28, height: 28)
                .background(DS.Colors.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tx.note.isEmpty ? tx.category.title : tx.note)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                    if isTransfer {
                        Text("Transfer")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DS.Colors.accent.opacity(0.12),
                                        in: Capsule())
                    }
                }
                Text(tx.date.formatted(date: .abbreviated, time: .omitted))
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
            Spacer()
            Text((isIncome ? "+" : "−") + fmtCurrency(amount))
                .font(DS.Typography.number)
                .foregroundStyle(amountTint)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Details (collapsible)

    private var detailsCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation { showDetails.toggle() } } label: {
                    HStack {
                        Text("Details").font(DS.Typography.section).foregroundStyle(DS.Colors.text)
                        Spacer()
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                .buttonStyle(.plain)

                if showDetails {
                    VStack(alignment: .leading, spacing: 0) {
                        Divider().padding(.vertical, 8)
                        row("Type", liveAccount.type.displayName)
                        if let inst = liveAccount.institutionName, !inst.isEmpty {
                            Divider().padding(.vertical, 6); row("Institution", inst)
                        }
                        Divider().padding(.vertical, 6); row("Currency", liveAccount.currency)
                        if let rate = liveAccount.interestRate {
                            Divider().padding(.vertical, 6); row("Interest Rate", String(format: "%.2f%%", rate))
                        }
                        Divider().padding(.vertical, 6); row("Created", liveAccount.createdAt.formatted(date: .abbreviated, time: .omitted))
                        Divider().padding(.vertical, 6); row("Updated", liveAccount.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(DS.Typography.body).foregroundStyle(DS.Colors.subtext)
            Spacer()
            Text(value).font(DS.Typography.body.weight(.medium)).foregroundStyle(DS.Colors.text)
        }
    }

    // MARK: - Helpers

    private func loadHistory() async {
        do {
            let snapshots: [AccountBalanceSnapshot] = try await SupabaseManager.shared.client
                .from("account_balance_snapshots").select()
                .eq("account_id", value: account.id.uuidString)
                .order("snapshot_date", ascending: true).execute().value
            balanceHistory = snapshots
        } catch {
            SecureLogger.error("Balance history load failed", error)
        }
    }

    private func fmtCurrency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = liveAccount.currency
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private var convertedBalanceText: String? {
        CurrencyConverter.shared.convertedDisplayText(liveAccount.currentBalance, from: liveAccount.currency)
    }

    private func fmtCompact(_ value: Double) -> String {
        let s = DS.Format.currencySymbol()
        let a = abs(value)
        if a >= 1_000_000 { return String(format: "%@%.1fM", s, value / 1_000_000) }
        if a >= 1_000 { return String(format: "%@%.0fK", s, value / 1_000) }
        return String(format: "%@%.0f", s, value)
    }
}
