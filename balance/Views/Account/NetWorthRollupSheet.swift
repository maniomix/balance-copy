import SwiftUI

// Tap-on-net-worth-card destination. Shows the breakdown that gets hidden
// when the hero card stays compact: per-currency totals, contributions per
// account, and which accounts are excluded from the roll-up.
struct NetWorthRollupSheet: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var accountManager = AccountManager.shared

    private var appCurrency: String {
        UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
    }

    private var includedAssets: [Account] { accountManager.assetAccountsForNetWorth }
    private var includedLiabilities: [Account] { accountManager.liabilityAccountsForNetWorth }
    private var excluded: [Account] {
        accountManager.activeAccounts.filter { !$0.includeInNetWorth }
    }

    /// Group active accounts by currency for the multi-currency breakdown.
    private var byCurrency: [(code: String, total: Double)] {
        let groups = Dictionary(grouping: accountManager.activeAccounts.filter(\.includeInNetWorth)) {
            $0.currency
        }
        return groups
            .map { (code: $0.key, total: $0.value.reduce(0) { $0 + $1.effectiveBalance }) }
            .sorted { $0.code < $1.code }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    headerCard
                    if byCurrency.count > 1 { currencyCard }
                    contributionsCard(title: "Assets", accounts: includedAssets, tint: DS.Colors.positive)
                    contributionsCard(title: "Liabilities", accounts: includedLiabilities, tint: DS.Colors.danger)
                    if !excluded.isEmpty { excludedCard }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(DS.Colors.bg.ignoresSafeArea())
            .navigationTitle("Net Worth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        DS.Card {
            VStack(spacing: 10) {
                Text("Net Worth")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                Text(fmt(accountManager.convertedNetWorth, code: appCurrency))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                HStack(spacing: 24) {
                    cell("Assets", accountManager.convertedTotalAssets, DS.Colors.positive)
                    Rectangle().fill(DS.Colors.grid).frame(width: 1, height: 28)
                    cell("Liabilities", accountManager.convertedTotalLiabilities, DS.Colors.danger)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func cell(_ label: String, _ value: Double, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(DS.Typography.caption).foregroundStyle(DS.Colors.subtext)
            Text(fmt(value, code: appCurrency))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
        }
    }

    // MARK: - Currency breakdown

    private var currencyCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("By Currency")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)
                ForEach(byCurrency, id: \.code) { row in
                    HStack {
                        Text(row.code).font(DS.Typography.body).foregroundStyle(DS.Colors.text)
                        Spacer()
                        Text(fmt(row.total, code: row.code))
                            .font(DS.Typography.number)
                            .foregroundStyle(row.total >= 0 ? DS.Colors.positive : DS.Colors.danger)
                    }
                }
            }
        }
    }

    // MARK: - Contributions

    private func contributionsCard(title: String, accounts: [Account], tint: Color) -> some View {
        Group {
            if accounts.isEmpty {
                EmptyView()
            } else {
                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                        ForEach(accounts) { account in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(AccountColorTag.color(for: account.colorTag))
                                    .frame(width: 8, height: 8)
                                Text(account.name).font(DS.Typography.body).foregroundStyle(DS.Colors.text)
                                Spacer()
                                Text(fmt(abs(account.currentBalance), code: account.currency))
                                    .font(DS.Typography.number)
                                    .foregroundStyle(tint)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Excluded

    private var excludedCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(DS.Colors.subtext)
                    Text("Excluded from Net Worth")
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                }
                Text("These accounts are still tracked but don't roll up into the totals above.")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
                ForEach(excluded) { account in
                    HStack {
                        Text(account.name).font(DS.Typography.body).foregroundStyle(DS.Colors.subtext)
                        Spacer()
                        Text(fmt(account.currentBalance, code: account.currency))
                            .font(DS.Typography.number)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
            }
        }
    }

    private func fmt(_ value: Double, code: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = code; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
