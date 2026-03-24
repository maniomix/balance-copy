import SwiftUI

// MARK: - Net Worth Dashboard Card

struct NetWorthDashboardCard: View {
    
    @StateObject private var accountManager = AccountManager.shared
    @StateObject private var netWorthManager = NetWorthManager.shared
    
    var body: some View {
        if !accountManager.accounts.isEmpty || netWorthManager.isLoading {
            NavigationLink(destination: AccountsListView()) {
                DS.Card {
                    VStack(spacing: 12) {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "chart.bar.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Colors.accent)
                                Text("Net Worth")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            Spacer()
                            if netWorthManager.isLoading {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else if netWorthManager.summary.changeFromLastMonth != 0 {
                                changeBadge
                            }
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text(fmtCurrency(netWorthManager.summary.netWorth))
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                                .redacted(reason: netWorthManager.isLoading ? .placeholder : [])
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                        }

                        HStack(spacing: 0) {
                            HStack(spacing: 4) {
                                Circle().fill(DS.Colors.positive).frame(width: 6, height: 6)
                                Text(fmtCompact(accountManager.totalAssets))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.positive)
                            }
                            Spacer()
                            assetLiabilityBar
                            Spacer()
                            HStack(spacing: 4) {
                                Text(fmtCompact(accountManager.totalLiabilities))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.danger)
                                Circle().fill(DS.Colors.danger).frame(width: 6, height: 6)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .task {
                await netWorthManager.computeSummary()
            }
        }
    }
    
    private var changeBadge: some View {
        let change = netWorthManager.summary.changeFromLastMonth
        let isPos = change >= 0
        let color: Color = isPos ? DS.Colors.positive : DS.Colors.danger
        return HStack(spacing: 2) {
            Image(systemName: isPos ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.1f%%", abs(netWorthManager.summary.changePercentage)))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    private var assetLiabilityBar: some View {
        let total = accountManager.totalAssets + accountManager.totalLiabilities
        let ratio: CGFloat = total > 0 ? CGFloat(accountManager.totalAssets / total) : 0.5
        return GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(DS.Colors.positive).frame(width: geo.size.width * ratio)
                RoundedRectangle(cornerRadius: 2).fill(DS.Colors.danger).frame(width: geo.size.width * (1 - ratio))
            }
        }.frame(height: 4).padding(.horizontal, 6)
    }
    
    private func fmtCurrency(_ value: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .currency
        f.currencyCode = UserDefaults.standard.string(forKey: "app.currency") ?? "EUR"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
    
    private func fmtCompact(_ value: Double) -> String {
        let s = DS.Format.currencySymbol(); let a = abs(value)
        if a >= 1_000_000 { return String(format: "%@%.1fM", s, value / 1_000_000) }
        if a >= 1_000 { return String(format: "%@%.0fK", s, value / 1_000) }
        return String(format: "%@%.0f", s, value)
    }
}
