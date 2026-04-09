import SwiftUI

// MARK: - Recent Transactions Dashboard Card

struct RecentTransactionsDashboardCard: View {
    @Binding var store: Store
    var onTapViewAll: (() -> Void)? = nil

    private var recentTransactions: [Transaction] {
        let monthTx = Analytics.monthTransactions(store: store)
        return Array(monthTx.sorted { $0.date > $1.date }.prefix(5))
    }

    var body: some View {
        if !recentTransactions.isEmpty {
            DS.Card {
                VStack(alignment: .leading, spacing: 10) {
                    // Header
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                        Text("Recent Transactions")
                            .font(DS.Typography.section)
                            .foregroundStyle(DS.Colors.text)
                        Spacer()
                        if let onTap = onTapViewAll {
                            Button {
                                onTap()
                            } label: {
                                HStack(spacing: 2) {
                                    Text("\(Analytics.monthTransactions(store: store).count) total")
                                        .font(DS.Typography.caption)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundStyle(DS.Colors.subtext)
                            }
                            .accessibilityLabel("View all transactions")
                        } else {
                            Text("\(Analytics.monthTransactions(store: store).count) total")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }

                    Divider().opacity(0.3)

                    // Transaction rows
                    ForEach(recentTransactions) { t in
                        HStack(spacing: 10) {
                            // Category icon
                            if t.type == .income {
                                Circle()
                                    .fill(DS.Colors.positive.opacity(0.10))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: "arrow.down.circle.fill")
                                            .foregroundStyle(DS.Colors.positive)
                                            .font(.system(size: 14, weight: .semibold))
                                    )
                                    .accessibilityLabel("Income")
                            } else {
                                Circle()
                                    .fill(t.category.tint.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Image(systemName: t.category.icon)
                                            .foregroundStyle(t.category.tint)
                                            .font(.system(size: 13, weight: .semibold))
                                    )
                            }

                            // Name + note/date
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.type == .income ? "Income" : t.category.title)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)
                                    .lineLimit(1)
                                Text(t.note.isEmpty ? DS.Format.relativeDateTime(t.date) : t.note)
                                    .font(.system(size: 11, weight: .regular, design: .rounded))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Amount
                            Text(t.type == .expense ? "-\(DS.Format.money(t.amount))" : "+\(DS.Format.money(t.amount))")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(t.type == .income ? DS.Colors.positive : DS.Colors.text)
                        }

                        if t.id != recentTransactions.last?.id {
                            Divider().opacity(0.15)
                        }
                    }
                }
            }
        }
    }
}
