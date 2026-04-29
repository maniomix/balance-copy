import SwiftUI

// ============================================================
// MARK: - Subscriptions Overview
// ============================================================

struct SubscriptionsOverviewView: View {
    @Binding var store: Store
    @StateObject private var engine = SubscriptionEngine.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: SubscriptionPage = .overview
    @State private var sortOption: SortOption = .cost
    @State private var selectedInsight: SubscriptionInsight? = nil
    @State private var showAddSheet = false
    /// Phase 4c — session-only dismissals for the Insights tab. Tapping
    /// the X on a banner hides it for the rest of this view's lifetime;
    /// it returns next launch (re-derived from the engine's insight set).
    @State private var dismissedInsights: Set<SubscriptionInsight> = []

    /// Phase 10 — spring animation gated on reduce-motion. When the
    /// user has Reduce Motion enabled in iOS Accessibility settings the
    /// transitions become instantaneous instead of bouncy.
    private var transitionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)
    }

    enum SortOption: String, CaseIterable {
        case cost = "Cost"
        case renewal = "Renewal"
        case name = "Name"
    }

    /// Phase 4a — top-level page selector. Splits the old single scroll
    /// view into three focused pages, accessed via a pill control under
    /// the summary card. Matches the "don't overload a single chart"
    /// pattern used in the InsightsView and Dashboard rebuilds.
    enum SubscriptionPage: String, CaseIterable, Identifiable {
        case overview, calendar, insights
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: return "Overview"
            case .calendar: return "Calendar"
            case .insights: return "Insights"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Colors.bg.ignoresSafeArea()

                if engine.subscriptions.isEmpty && engine.hiddenSubscriptions.isEmpty && !engine.isLoading {
                    // No records at all — true empty state.
                    emptyState
                } else {
                    // Even if every visible record is hidden, render the
                    // page so the Hidden section is reachable from
                    // sectionedList. Phase 10 — guards against the user
                    // hiding everything and getting "stuck."
                    ScrollView {
                        VStack(spacing: 16) {
                            summaryCard
                            pageSelector
                            pageContent
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SectionHelpButton(screen: .subscriptions)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.selection()
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("Add subscription")
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddSubscriptionSheet(store: $store)
            }
        }
    }

    // MARK: - Summary Card (Phase 4c — single accent strip)

    /// Hero strip: one big monthly number in the accent color, with three
    /// small stats underneath. Replaces the Phase 4a/b card whose four
    /// status pills (positive/warning/purple/subtext) violated the
    /// "one accent per card" rule and duplicated information now shown
    /// natively by the sectioned list.
    private var summaryCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Monthly Cost")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)

                Text("\(DS.Format.currencySymbol())\(DS.Format.currency(engine.monthlyTotal))")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Colors.accent)

                Divider().background(DS.Colors.grid.opacity(0.5))

                HStack(alignment: .top, spacing: 0) {
                    summaryStat(
                        label: "Yearly",
                        value: "\(DS.Format.currencySymbol())\(DS.Format.currency(engine.yearlyTotal))"
                    )
                    statSeparator
                    summaryStat(
                        label: "Active",
                        value: "\(engine.activeCount)"
                    )
                    statSeparator
                    summaryStat(
                        label: "Next renewal",
                        value: nextRenewalShortText
                    )
                }
            }
        }
        .padding(.horizontal)
    }

    private func summaryStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statSeparator: some View {
        Rectangle()
            .fill(DS.Colors.grid.opacity(0.4))
            .frame(width: 1, height: 28)
    }

    /// Compact "in N days / today / —" for the next active renewal.
    private var nextRenewalShortText: String {
        guard let sub = engine.upcomingRenewals.first,
              let days = sub.daysUntilRenewal else { return "—" }
        if days < 0 { return "Overdue" }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days)d"
    }

    // MARK: - Page Selector

    private var pageSelector: some View {
        HStack(spacing: 6) {
            ForEach(SubscriptionPage.allCases) { p in
                Button {
                    Haptics.selection()
                    withAnimation(transitionAnimation) {
                        page = p
                    }
                } label: {
                    Text(p.label)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(page == p ? DS.Colors.text : DS.Colors.subtext)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            page == p ? DS.Colors.accent.opacity(0.15) : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().stroke(
                                page == p ? DS.Colors.accent.opacity(0.3) : DS.Colors.grid.opacity(0.4),
                                lineWidth: 1
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(p.label)")
                .accessibilityAddTraits(page == p ? .isSelected : [])
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Page Content

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .overview:
            sectionedList
        case .calendar:
            calendarPage
        case .insights:
            insightsPage
        }
    }

    // MARK: - Calendar Page (Phase 4a)

    /// Full-page upcoming-renewal list. Promoted from the old horizontal
    /// scroller; the chronological list reads better as a vertical surface.
    @ViewBuilder
    private var calendarPage: some View {
        let upcoming = engine.upcomingRenewals
        if upcoming.isEmpty {
            emptyPagePlaceholder(
                icon: "calendar.badge.clock",
                title: "No upcoming renewals",
                message: "Active subscriptions with a known renewal date will appear here."
            )
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Upcoming Renewals")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)
                    .padding(.horizontal)

                ForEach(upcoming) { sub in
                    NavigationLink(destination: SubscriptionDetailView(subscription: sub, store: $store)) {
                        renewalRow(sub)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func renewalRow(_ sub: DetectedSubscription) -> some View {
        DS.Card {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CategoryRegistry.shared.tint(for: sub.category).opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: CategoryRegistry.shared.icon(for: sub.category))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(CategoryRegistry.shared.tint(for: sub.category))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.merchantName.capitalized)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                    if let date = sub.nextRenewalDate {
                        Text(formatLongDate(date))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(sub.expectedAmount))")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                    if let days = sub.daysUntilRenewal {
                        Text(days < 0 ? "\(abs(days))d overdue"
                             : days == 0 ? "Today"
                             : days == 1 ? "Tomorrow"
                             : "In \(days) days")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(days < 0 ? DS.Colors.danger
                                             : days <= 3 ? DS.Colors.warning
                                             : DS.Colors.subtext)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Insights Page (Phase 4a)

    @ViewBuilder
    private var insightsPage: some View {
        if visibleInsights.isEmpty {
            emptyPagePlaceholder(
                icon: "checkmark.seal.fill",
                title: "All clear",
                message: "No price hikes, missed charges, or unused subscriptions to flag right now."
            )
        } else {
            insightBanners
        }
    }

    private func emptyPagePlaceholder(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(DS.Colors.subtext.opacity(0.5))
            Text(title)
                .font(DS.Typography.section)
                .foregroundStyle(DS.Colors.text)
            Text(message)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Insight Banners

    /// Insight banners filtered against the session-only dismissal set.
    /// Once every active insight has been dismissed the parent
    /// `insightsPage` collapses to its "All clear" placeholder.
    private var visibleInsights: [SubscriptionInsight] {
        engine.insights.filter { !dismissedInsights.contains($0) }
    }

    @ViewBuilder
    private var insightBanners: some View {
        if !visibleInsights.isEmpty {
            VStack(spacing: 8) {
                ForEach(visibleInsights) { insight in
                    insightBanner(insight)
                }
            }
            .padding(.horizontal)
            .sheet(item: $selectedInsight) { insight in
                InsightDetailSheet(insight: insight, engine: engine)
            }
        }
    }

    private func insightBanner(_ insight: SubscriptionInsight) -> some View {
        // Two-button layout: tap the body to drill in, X to dismiss for
        // this session. Don't wrap the whole row in a Button — that
        // swallows the X tap.
        HStack(spacing: 10) {
            Button {
                Haptics.selection()
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Haptics.selection()
                withAnimation(transitionAnimation) {
                    _ = dismissedInsights.insert(insight)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Colors.subtext)
                    .frame(width: 22, height: 22)
                    .background(DS.Colors.surface2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(insight.displayName) banner")
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

    private func insightCount(for insight: SubscriptionInsight) -> Int {
        switch insight {
        case .missedCharge: return engine.missedChargeSubs.count
        case .maybeUnused: return engine.unusedSubs.count
        case .priceIncreased: return engine.priceIncreasedSubs.count
        default: return 0
        }
    }

    // MARK: - Sort Menu (Phase 4c)

    /// Inline sort control sitting at the top of the sectioned list.
    /// Replaces the Phase 4b filter chip bar — sections cover the
    /// "filter by status" need on their own, so the only knob worth
    /// keeping is sort order.
    private var sortMenu: some View {
        HStack {
            Spacer()
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
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Sort: \(sortOption.rawValue)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(DS.Colors.subtext)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(DS.Colors.surface2, in: Capsule())
            }
            .accessibilityLabel("Sort subscriptions, currently \(sortOption.rawValue)")
        }
        .padding(.horizontal)
    }

    // MARK: - Sectioned List (Phase 4b)

    /// Subscriptions split into status buckets. Suspected-unused records
    /// stay inside Active — the row's inline status badge surfaces the
    /// flag without fragmenting the list. Empty sections collapse.
    private var sectionedList: some View {
        VStack(alignment: .leading, spacing: 18) {
            sortMenu
            sectionView(title: "Active", subs: activeSubs)
            sectionView(title: "Trials", subs: trialSubs)
            sectionView(title: "Paused", subs: pausedSubs)
            sectionView(title: "Cancelled", subs: cancelledSubs)
            sectionView(title: "Hidden", subs: hiddenSubs, isHiddenSection: true)
        }
    }

    @ViewBuilder
    private func sectionView(title: String, subs: [DetectedSubscription], isHiddenSection: Bool = false) -> some View {
        if !subs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(DS.Typography.section)
                        .foregroundStyle(DS.Colors.text)
                    Text("\(subs.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(DS.Colors.surface2, in: Capsule())
                }
                .padding(.horizontal)

                ForEach(subs) { sub in
                    if isHiddenSection {
                        hiddenRow(sub)
                    } else {
                        NavigationLink(destination: SubscriptionDetailView(subscription: sub, store: $store)) {
                            subscriptionRow(sub)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Hidden-section row: shows the same content as a regular row but
    /// swaps the chevron for an "Unhide" button, since tapping into the
    /// detail view doesn't make sense for a hidden record.
    private func hiddenRow(_ sub: DetectedSubscription) -> some View {
        DS.Card {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DS.Colors.subtext.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Image(systemName: CategoryRegistry.shared.icon(for: sub.category))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(sub.merchantName.capitalized)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(1)
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(sub.expectedAmount)) · \(sub.billingCycle.displayName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DS.Colors.subtext)
                }
                Spacer()
                Button {
                    Haptics.selection()
                    engine.unhideSubscription(sub)
                } label: {
                    Text("Unhide")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(DS.Colors.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Unhide \(sub.merchantName)")
            }
        }
        .padding(.horizontal)
        .opacity(0.85)
    }

    // MARK: - Section bucketers

    private var activeSubs: [DetectedSubscription] {
        sortedFor(engine.subscriptions.filter {
            ($0.status == .active || $0.status == .suspectedUnused) && !$0.isTrial
        })
    }

    private var trialSubs: [DetectedSubscription] {
        sortedFor(engine.subscriptions.filter { $0.isTrial })
    }

    private var pausedSubs: [DetectedSubscription] {
        sortedFor(engine.subscriptions.filter { $0.status == .paused })
    }

    private var cancelledSubs: [DetectedSubscription] {
        sortedFor(engine.subscriptions.filter { $0.status == .cancelled })
    }

    private var hiddenSubs: [DetectedSubscription] {
        sortedFor(engine.hiddenSubscriptions)
    }

    /// Apply the current sort option to a subscription bucket.
    private func sortedFor(_ list: [DetectedSubscription]) -> [DetectedSubscription] {
        switch sortOption {
        case .cost:
            return list.sorted { $0.monthlyCost > $1.monthlyCost }
        case .renewal:
            return list.sorted { ($0.nextRenewalDate ?? .distantFuture) < ($1.nextRenewalDate ?? .distantFuture) }
        case .name:
            return list.sorted { $0.merchantName.localizedCaseInsensitiveCompare($1.merchantName) == .orderedAscending }
        }
    }

    private func subscriptionRow(_ sub: DetectedSubscription) -> some View {
        DS.Card {
            HStack(spacing: 14) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(CategoryRegistry.shared.tint(for: sub.category).opacity(0.12))
                        .frame(width: 42, height: 42)

                    Image(systemName: CategoryRegistry.shared.icon(for: sub.category))
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(CategoryRegistry.shared.tint(for: sub.category))
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
                                .lineLimit(1)
                                .fixedSize()
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
                                        .lineLimit(1)
                                        .fixedSize()
                                }
                                .foregroundStyle(insight.color)
                                .padding(.horizontal, 6)
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

    private func formatLongDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
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
                        .fill(CategoryRegistry.shared.tint(for: sub.category).opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: CategoryRegistry.shared.icon(for: sub.category))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(CategoryRegistry.shared.tint(for: sub.category))
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
                .accessibilityLabel("Remove subscription")
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
