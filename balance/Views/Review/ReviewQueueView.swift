import SwiftUI

// ============================================================
// MARK: - Review Queue View
// ============================================================

struct ReviewQueueView: View {
    @Binding var store: Store
    @StateObject private var engine = ReviewEngine.shared
    @State private var filterType: ReviewType? = nil
    @State private var selectedItem: ReviewItem? = nil

    private var filtered: [ReviewItem] {
        var list = engine.pendingItems
        if let type = filterType {
            list = list.filter { $0.type == type }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                if engine.pendingItems.isEmpty && !engine.isLoading {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryRow
                            filterBar
                            itemsList
                        }
                        .padding(.vertical)
                    }
                }

                if engine.isLoading {
                    ProgressView()
                        .tint(DS.Colors.accent)
                }
            }
            .navigationTitle("Review")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                AnalyticsManager.shared.track(.reviewQueueOpened(pendingCount: engine.pendingItems.count))
            }
            .trackScreen("review_queue")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !engine.pendingItems.isEmpty {
                        Menu {
                            Button {
                                dismissAllLowPriority()
                            } label: {
                                Label("Dismiss Low Priority", systemImage: "hand.raised")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Colors.text)
                        }
                    }
                }
            }
            .sheet(item: $selectedItem) { item in
                ReviewActionSheet(item: item, store: $store)
            }
        }
    }

    // MARK: - Summary Row

    private var summaryRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                summaryChip(
                    count: engine.pendingCount,
                    label: "Total",
                    color: DS.Colors.accent,
                    icon: "tray"
                )
                summaryChip(
                    count: engine.highPriorityCount,
                    label: "High Priority",
                    color: DS.Colors.danger,
                    icon: "exclamationmark.triangle.fill"
                )
                summaryChip(
                    count: engine.uncategorizedCount,
                    label: "Uncategorized",
                    color: DS.Colors.warning,
                    icon: "tag.slash"
                )
                summaryChip(
                    count: engine.duplicateCount,
                    label: "Duplicates",
                    color: DS.Colors.danger,
                    icon: "doc.on.doc"
                )
            }
            .padding(.horizontal)
        }
    }

    private func summaryChip(count: Int, label: String, color: Color, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            Text("\(count)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? DS.Colors.text : DS.Colors.subtext.opacity(0.5))

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            color.opacity(count > 0 ? 0.08 : 0.03),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(count > 0 ? 0.15 : 0.05), lineWidth: 1)
        )
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: filterType == nil) {
                    withAnimation(.spring(response: 0.3)) { filterType = nil }
                }
                ForEach(ReviewType.allCases) { type in
                    let count = engine.pendingByType(type).count
                    filterChip(
                        label: "\(type.displayName) (\(count))",
                        isSelected: filterType == type
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            filterType = filterType == type ? nil : type
                        }
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? DS.Colors.text : DS.Colors.subtext)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? DS.Colors.accent.opacity(0.15) : DS.Colors.surface2,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? DS.Colors.accent.opacity(0.3) : DS.Colors.grid.opacity(0.5),
                        lineWidth: 1
                    )
                )
        }
    }

    // MARK: - Items List

    private var itemsList: some View {
        VStack(spacing: 8) {
            ForEach(filtered) { item in
                reviewRow(item)
            }
        }
    }

    private func reviewRow(_ item: ReviewItem) -> some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                // Header: type + priority
                HStack(spacing: 8) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item.type.color)

                    Text(item.type.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(item.type.color)

                    Spacer()

                    // Priority badge
                    Text(item.priority.displayName)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(item.priority.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(item.priority.color.opacity(0.12), in: Capsule())
                }

                // Reason
                Text(item.reason)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(3)

                // Transaction info
                if let txInfo = transactionInfo(for: item) {
                    HStack(spacing: 6) {
                        Text(txInfo)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                // Quick action buttons
                HStack(spacing: 8) {
                    // Primary action
                    Button {
                        selectedItem = item
                        Haptics.medium()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: item.suggestedAction.icon)
                                .font(.system(size: 11, weight: .semibold))
                            Text(item.suggestedAction.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(item.type.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(item.type.color.opacity(0.1), in: Capsule())
                    }

                    // Dismiss
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            engine.dismiss(item)
                        }
                        Haptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Dismiss")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DS.Colors.surface2, in: Capsule())
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        ))
    }

    // MARK: - Helpers

    private func transactionInfo(for item: ReviewItem) -> String? {
        guard let txId = item.transactionIds.first,
              let tx = store.transactions.first(where: { $0.id == txId }) else { return nil }

        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let dateStr = fmt.string(from: tx.date)
        let amount = "\(DS.Format.currencySymbol())\(DS.Format.currency(tx.amount))"

        if item.transactionIds.count > 1 {
            return "\(item.transactionIds.count) transactions · \(amount) · \(dateStr)"
        }
        return "\(amount) · \(dateStr) · \(tx.note.isEmpty ? tx.category.title : tx.note)"
    }

    private func dismissAllLowPriority() {
        let low = engine.items.filter { $0.status == .pending && $0.priority == .low }
        for item in low {
            engine.dismiss(item)
        }
        Haptics.success()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(DS.Colors.positive.opacity(0.6))

            Text("All Clean!")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text("No transactions need review right now.\nWe'll flag issues as they appear.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}
