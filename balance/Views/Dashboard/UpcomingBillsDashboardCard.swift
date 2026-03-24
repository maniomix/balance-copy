import SwiftUI

// MARK: - Upcoming Bills Dashboard Card

struct UpcomingBillsDashboardCard: View {
    @StateObject private var engine = ForecastEngine.shared

    private var bills: [UpcomingBill] {
        guard let f = engine.forecast else { return [] }
        return Array(f.upcomingBills.prefix(4))
    }

    private var totalUpcoming: Int {
        bills.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        if !bills.isEmpty {
            NavigationLink(destination: ForecastDetailView()) {
                DS.Card {
                    VStack(alignment: .leading, spacing: 10) {
                        // Header
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Colors.warning)
                            Text("Upcoming Bills")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                            Spacer()
                            Text(DS.Format.money(totalUpcoming))
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Colors.text)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.5))
                        }

                        Divider().opacity(0.3)

                        // Bill rows
                        ForEach(bills) { bill in
                            HStack(spacing: 10) {
                                // Category icon
                                Circle()
                                    .fill(bill.category.tint.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                    .overlay(
                                        Image(systemName: bill.category.icon)
                                            .foregroundStyle(bill.category.tint)
                                            .font(.system(size: 12, weight: .semibold))
                                    )

                                // Name
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bill.name)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(DS.Colors.text)
                                        .lineLimit(1)
                                    Text(billDateLabel(bill.dueDate))
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .foregroundStyle(daysUntil(bill.dueDate) <= 3 ? DS.Colors.warning : DS.Colors.subtext)
                                }

                                Spacer()

                                // Amount
                                Text(DS.Format.money(bill.amount))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DS.Colors.text)
                            }

                            if bill.id != bills.last?.id {
                                Divider().opacity(0.15)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func daysUntil(_ date: Date) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        return max(0, cal.dateComponents([.day], from: today, to: target).day ?? 0)
    }

    private func billDateLabel(_ date: Date) -> String {
        let days = daysUntil(date)
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        if days <= 7 { return "In \(days) days" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}
