// ==========================================
// Upcoming Payments Banner
// ==========================================

import SwiftUI
import Combine

struct UpcomingPaymentsBanner: View {
    @Binding var store: Store
    @State private var showSheet = false
    
    var upcomingPayments: [(RecurringTransaction, Date)] {
        let now = Date()
        let calendar = Calendar.current
        
        var upcoming: [(RecurringTransaction, Date)] = []
        
        for recurring in store.recurringTransactions.filter({ $0.isActive }) {
            if let nextDate = recurring.nextOccurrence(from: now),
               let daysDiff = calendar.dateComponents([.day], from: now, to: nextDate).day,
               daysDiff <= 7 {
                upcoming.append((recurring, nextDate))
            }
        }
        
        return upcoming.sorted { $0.1 < $1.1 }.prefix(3).map { $0 }
    }
    
    var totalUpcoming: Int {
        upcomingPayments.reduce(0) { $0 + $1.0.amount }
    }
    
    var body: some View {
        if !upcomingPayments.isEmpty {
            Button {
                showSheet = true
                Haptics.light()
            } label: {
                HStack(spacing: 12) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Colors.warning.opacity(0.12))
                            .frame(width: 38, height: 38)
                        
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Colors.warning)
                    }
                    
                    // Text
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Upcoming")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                            
                            Spacer()
                            
                            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(totalUpcoming))")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                        }
                        
                        Text("\(upcomingPayments.count) payment\(upcomingPayments.count > 1 ? "s" : "") this week")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .padding(12)
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal)
            .sheet(isPresented: $showSheet) {
                UpcomingPaymentsSheet(store: $store, upcomingPayments: upcomingPayments)
            }
        }
    }
}

// MARK: - Upcoming Payments Sheet

struct UpcomingPaymentsSheet: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    let upcomingPayments: [(RecurringTransaction, Date)]
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Next 7 Days")
                                .font(DS.Typography.section)
                                .foregroundStyle(DS.Colors.text)
                                .padding(.horizontal)
                            
                            ForEach(upcomingPayments, id: \.0.id) { payment in
                                UpcomingPaymentRow(
                                    recurring: payment.0,
                                    nextDate: payment.1
                                )
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Upcoming")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
    }
    
    private var summaryCard: some View {
        DS.Card {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total Due")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                    
                    let total = upcomingPayments.reduce(0) { $0 + $1.0.amount }
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(total))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    StatPill(count: upcomingPayments.count, label: "Payments", color: .blue)
                    
                    let days = daysUntilNext()
                    StatPill(count: days, label: days == 1 ? "Day" : "Days", color: .orange)
                }
            }
        }
        .padding(.horizontal)
    }
    
    private func daysUntilNext() -> Int {
        guard let firstDate = upcomingPayments.first?.1 else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: Date(), to: firstDate).day ?? 0)
    }
}

// MARK: - Upcoming Payment Row

struct UpcomingPaymentRow: View {
    let recurring: RecurringTransaction
    let nextDate: Date
    
    private var daysUntil: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: nextDate).day ?? 0)
    }
    
    private var dateText: String {
        if daysUntil == 0 { return "Today" }
        if daysUntil == 1 { return "Tomorrow" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: nextDate)
    }
    
    var body: some View {
        DS.Card {
            HStack(spacing: 14) {
                // Category
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CategoryRegistry.shared.tint(for: recurring.category).opacity(0.12))
                        .frame(width: 42, height: 42)
                    
                    Image(systemName: CategoryRegistry.shared.icon(for: recurring.category))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(CategoryRegistry.shared.tint(for: recurring.category))
                }
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(recurring.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    
                    HStack(spacing: 6) {
                        // Date badge
                        Text(dateText)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (daysUntil == 0 ? DS.Colors.warning : DS.Colors.accent).opacity(0.12),
                                in: Capsule()
                            )
                            .foregroundStyle(daysUntil == 0 ? DS.Colors.warning : DS.Colors.accent)
                        
                        Text(recurring.frequency.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                
                Spacer()
                
                Text("\(DS.Format.currencySymbol())\(DS.Format.currency(recurring.amount))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
            }
        }
        .padding(.horizontal)
    }
}
