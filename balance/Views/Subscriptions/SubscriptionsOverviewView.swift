import SwiftUI

// ============================================================
// MARK: - Subscriptions Overview
// ============================================================

struct SubscriptionsOverviewView: View {
    @StateObject private var engine = SubscriptionEngine.shared
    @State private var filterStatus: SubscriptionStatus? = nil
    @State private var sortOption: SortOption = .cost
    @State private var selectedInsight: SubscriptionInsight? = nil
    // Manual add navigates user to Recurring (in Transactions)

    enum SortOption: String, CaseIterable {
        case cost = "Cost"
        case renewal = "Renewal"
        case name = "Name"
    }

    private var filtered: [DetectedSubscription] {
        var list = engine.subscriptions
        if let status = filterStatus {
            list = list.filter { $0.status == status }
        }
        switch sortOption {
        case .cost:
            list.sort { $0.monthlyCost > $1.monthlyCost }
        case .renewal:
            list.sort { ($0.nextRenewalDate ?? .distantFuture) < ($1.nextRenewalDate ?? .distantFuture) }
        case .name:
            list.sort { $0.merchantName.localizedCaseInsensitiveCompare($1.merchantName) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                if engine.subscriptions.isEmpty && !engine.isLoading {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard
                            manualAddHint
                            insightBanners
                            filterBar
                            renewalCalendarSection
                            subscriptionsList
                        }
                        .padding(.vertical)
                    }
                }

                if engine.isLoading {
                    ProgressView()
                        .tint(DS.Colors.accent)
                }
            }
            .navigationTitle("Subscriptions")
            .navigationBarTitleDisplayMode(.large)
            .trackScreen("subscriptions")
        }
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        DS.Card {
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Cost")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)

                        Text("\(DS.Format.currencySymbol())\(DS.Format.currency(engine.monthlyTotal))")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Yearly Cost")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)

                        Text("\(DS.Format.currencySymbol())\(DS.Format.currency(engine.yearlyTotal))")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }

                // Status pills
                HStack(spacing: 10) {
                    statusPill(
                        count: engine.subscriptions.filter { $0.status == .active }.count,
                        label: "Active",
                        color: DS.Colors.positive
                    )
                    statusPill(
                        count: engine.subscriptions.filter { $0.status == .paused }.count,
                        label: "Paused",
                        color: DS.Colors.warning
                    )
                    statusPill(
                        count: engine.subscriptions.filter { $0.status == .suspectedUnused }.count,
                        label: "Unused?",
                        color: Color(hexValue: 0x9B59B6)
                    )
                    statusPill(
                        count: engine.subscriptions.filter { $0.status == .cancelled }.count,
                        label: "Cancelled",
                        color: DS.Colors.subtext
                    )

                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }

    private func statusPill(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(count > 0 ? color : DS.Colors.subtext.opacity(0.5))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (count > 0 ? color : DS.Colors.subtext).opacity(0.08),
            in: Capsule()
        )
    }

    // MARK: - Manual Add Hint

    private var manualAddHint: some View {
        let isPro = SubscriptionManager.shared.isPro

        return HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(DS.Colors.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("For adding Subscriptions manually :")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.text)

                if isPro {
                    Text("Go to Transactions → Recurring to add custom subscriptions")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Colors.positive)
                        Text("Subscription Auto-detection is free")
                            .foregroundStyle(DS.Colors.positive)
                    }
                    .font(.system(size: 10, weight: .medium))

                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.Colors.warning)
                        Text("Manual entry requires Pro (via Recurring)")
                            .foregroundStyle(DS.Colors.subtext)
                    }
                    .font(.system(size: 10, weight: .medium))
                }
            }

            Spacer()
        }
        .padding(12)
        .background(DS.Colors.accent.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Colors.accent.opacity(0.15), lineWidth: 1)
        )
        .padding(.horizontal)
    }

    // MARK: - Insight Banners

    @ViewBuilder
    private var insightBanners: some View {
        if !engine.insights.isEmpty {
            VStack(spacing: 8) {
                ForEach(engine.insights) { insight in
                    Button {
                        selectedInsight = insight
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: insight.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(insight.color)

                            Text(insight.displayName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)

                            if insightCount(for: insight) > 0 {
                                Text("\(insightCount(for: insight))")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(insight.color)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(insight.color.opacity(0.15), in: Capsule())
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                        }
                        .padding(12)
                        .background(
                            insight.color.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(insight.color.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .sheet(item: $selectedInsight) { insight in
                InsightDetailSheet(insight: insight, engine: engine)
            }
        }
    }

    private func insightCount(for insight: SubscriptionInsight) -> Int {
        switch insight {
        case .missedCharge: return engine.missedChargeSubs.count
        case .maybeUnused: return engine.unusedSubs.count
        case .priceIncreased: return engine.priceIncreasedSubs.count
        default: return 0
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", isSelected: filterStatus == nil) {
                    withAnimation(.spring(response: 0.3)) { filterStatus = nil }
                }
                ForEach(SubscriptionStatus.allCases) { status in
                    filterChip(label: status.displayName, isSelected: filterStatus == status) {
                        withAnimation(.spring(response: 0.3)) {
                            filterStatus = filterStatus == status ? nil : status
                        }
                    }
                }

                Spacer(minLength: 8)

                // Sort menu
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(width: 32, height: 32)
                        .background(DS.Colors.accent.opacity(0.1), in: Circle())
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

    // MARK: - Renewal Calendar

    @ViewBuilder
    private var renewalCalendarSection: some View {
        let upcoming = engine.upcomingRenewals.prefix(5)
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upcoming Renewals")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)
                    .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(upcoming)) { sub in
                            NavigationLink(destination: SubscriptionDetailView(subscription: sub)) {
                                renewalCard(sub)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private func renewalCard(_ sub: DetectedSubscription) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: sub.category.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(sub.category.tint)

                Text(sub.merchantName.capitalized)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
            }

            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(sub.expectedAmount))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)

            if let days = sub.daysUntilRenewal {
                Text(days < 0 ? "\(abs(days))d overdue" : days == 0 ? "Today" : days == 1 ? "Tomorrow" : "In \(days) days")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(days < 0 ? DS.Colors.danger : days <= 3 ? DS.Colors.warning : DS.Colors.subtext)
            }
        }
        .frame(width: 140, alignment: .leading)
        .padding(12)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        
    }

    // MARK: - Subscriptions List

    private var subscriptionsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("All Subscriptions (\(filtered.count))")
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
                .padding(.horizontal)

            ForEach(filtered) { sub in
                NavigationLink(destination: SubscriptionDetailView(subscription: sub)) {
                    subscriptionRow(sub)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func subscriptionRow(_ sub: DetectedSubscription) -> some View {
        DS.Card {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(sub.category.tint.opacity(0.12))
                        .frame(width: 42, height: 42)

                    Image(systemName: sub.category.icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(sub.category.tint)
                }

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sub.merchantName.capitalized)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                            .lineLimit(1)

                        // Status badge
                        if sub.status != .active {
                            Text(sub.status.displayName)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(sub.status.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(sub.status.color.opacity(0.12), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(sub.billingCycle.displayName)
                            .font(.system(size: 12, weight: .medium))

                        if let date = sub.nextRenewalDate {
                            Text("·")
                            Text(formatShortDate(date))
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(DS.Colors.subtext)

                    // Insight labels
                    let insights = SubscriptionEngine.shared.insightsFor(sub)
                    if !insights.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(insights.prefix(2)) { insight in
                                HStack(spacing: 3) {
                                    Image(systemName: insight.icon)
                                        .font(.system(size: 8))
                                    Text(insight.displayName)
                                        .font(.system(size: 9, weight: .semibold))
                                }
                                .foregroundStyle(insight.color)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(insight.color.opacity(0.1), in: Capsule())
                            }
                        }
                    }
                }

                Spacer()

                // Amount
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(sub.expectedAmount))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    Text("/\(sub.billingCycle == .yearly ? "yr" : sub.billingCycle == .weekly ? "wk" : "mo")")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)

                    if sub.hasPriceIncrease, let change = sub.priceChangeAmount, change > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(change))")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(DS.Colors.danger)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Colors.subtext.opacity(0.5))
            }
        }
        .padding(.horizontal)
        .opacity(sub.status == .cancelled ? 0.5 : 1)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 48))
                .foregroundStyle(DS.Colors.subtext.opacity(0.4))

            Text("No Subscriptions Detected")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)

            Text("Add more transactions and we'll automatically\ndetect your recurring subscriptions.")
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    // MARK: - Helpers

    private func formatShortDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}

// MARK: - Insight Detail Sheet

private struct InsightDetailSheet: View {
    let insight: SubscriptionInsight
    @ObservedObject var engine: SubscriptionEngine
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveAlert = false
    @State private var subToRemove: DetectedSubscription?

    private var matchingSubs: [DetectedSubscription] {
        switch insight {
        case .missedCharge: return engine.missedChargeSubs
        case .maybeUnused: return engine.unusedSubs
        case .priceIncreased: return engine.priceIncreasedSubs
        case .newlyDetected:
            return engine.subscriptions.filter { sub in
                engine.insightsFor(sub).contains(.newlyDetected)
            }
        default: return []
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                if matchingSubs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(DS.Colors.positive)
                        Text("All clear!")
                            .font(DS.Typography.title)
                            .foregroundStyle(DS.Colors.text)
                        Text("No subscriptions match this insight.")
                            .font(DS.Typography.body)
                            .foregroundStyle(DS.Colors.subtext)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            // Description
                            HStack(spacing: 10) {
                                Image(systemName: insight.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(insight.color)
                                Text(insightDescription)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(insight.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.horizontal)

                            ForEach(matchingSubs) { sub in
                                NavigationLink(destination: SubscriptionDetailView(subscription: sub)) {
                                    insightSubRow(sub)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle(insight.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DS.Colors.accent)
                }
            }
            .alert("Remove Subscription?", isPresented: $showRemoveAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    if let sub = subToRemove {
                        engine.removeSubscription(sub)
                    }
                }
            } message: {
                Text("This subscription will be removed from tracking. It may be re-detected later.")
            }
        }
    }

    private func insightSubRow(_ sub: DetectedSubscription) -> some View {
        DS.Card {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(sub.category.tint.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: sub.category.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(sub.category.tint)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.merchantName.capitalized)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(sub.expectedAmount)) / \(sub.billingCycle.displayName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }

                Spacer()

                // Quick remove button
                Button {
                    subToRemove = sub
                    showRemoveAlert = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                }
            }
        }
        .padding(.horizontal)
    }

    private var insightDescription: String {
        switch insight {
        case .missedCharge: return "These subscriptions have missed their expected charge date."
        case .maybeUnused: return "You haven't used these subscriptions recently. Consider cancelling."
        case .priceIncreased: return "These subscriptions have increased in price recently."
        case .newlyDetected: return "Recently detected subscriptions. Confirm or remove them."
        default: return ""
        }
    }
}
