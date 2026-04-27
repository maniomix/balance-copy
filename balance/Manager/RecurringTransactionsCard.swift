// ==========================================
// Recurring Transactions Card
// ==========================================

import SwiftUI

struct RecurringTransactionsCard: View {
    @Binding var store: Store
    @State private var showRecurringView = false
    
    var activeCount: Int {
        store.recurringTransactions.filter { $0.isActive }.count
    }
    
    var monthlyTotal: Int {
        store.recurringTransactions
            .filter { $0.isActive && $0.frequency == .monthly }
            .reduce(0) { $0 + $1.amount }
    }
    
    var body: some View {
        Button {
            showRecurringView = true
            Haptics.medium()
        } label: {
            DS.Card {
                HStack(spacing: 14) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DS.Colors.accent.opacity(0.1))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: "repeat")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.Colors.accent)
                    }
                    
                    // Content
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Recurring Transactions")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)
                            DS.BetaBadge()
                        }
                        
                        if activeCount > 0 {
                            HStack(spacing: 8) {
                                Text("\(activeCount) active")
                                    .font(.system(size: 12, weight: .medium))
                                
                                if monthlyTotal > 0 {
                                    Text("·")
                                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(monthlyTotal))/mo")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .foregroundStyle(DS.Colors.subtext)
                        } else {
                            Text("Auto-detected from your transactions")
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showRecurringView) {
            RecurringTransactionsView(store: $store)
        }
    }
}
