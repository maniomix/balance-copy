import SwiftUI
import Charts

// ============================================================
// MARK: - Subscription Detail View
// ============================================================

struct SubscriptionDetailView: View {
    let subscription: DetectedSubscription
    @Binding var store: Store
    @StateObject private var engine = SubscriptionEngine.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showCancelAlert = false
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false

    /// Convenience init preserved so call sites that don't yet pass a
    /// store binding keep working in previews. The binding is required
    /// for the Edit sheet's category picker; AI/proactive callers that
    /// open detail without a store get a no-op constant binding so the
    /// Edit button still renders but the picker is empty.
    init(subscription: DetectedSubscription, store: Binding<Store>) {
        self.subscription = subscription
        self._store = store
    }

    init(subscription: DetectedSubscription) {
        self.subscription = subscription
        self._store = .constant(Store())
    }

    /// Live data from engine
    private var liveSub: DetectedSubscription {
        engine.subscriptions.first(where: { $0.id == subscription.id }) ?? subscription
    }

    var body: some View {
        ZStack {
            DS.Colors.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    maybeUnusedCallout
                    insightLabels
                    costBreakdownCard
                    chargeHistoryCard
                    renewalInfoCard
                    detectionInfoCard
                    actionsCard
                }
                .padding(.vertical)
            }
        }
        .navigationTitle(liveSub.merchantName.capitalized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    Haptics.selection()
                    showEditSheet = true
                }
                .foregroundStyle(DS.Colors.accent)
                .accessibilityLabel("Edit subscription")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            AddSubscriptionSheet(store: $store, editing: liveSub)
        }
        .alert("Cancel Subscription?", isPresented: $showCancelAlert) {
            Button("Keep Active", role: .cancel) {}
            Button("Mark Cancelled", role: .destructive) {
                engine.markAsCancelled(liveSub)
                Haptics.success()
            }
        } message: {
            Text("This marks '\(liveSub.merchantName.capitalized)' as cancelled. You'll need to actually cancel with the provider separately.")
        }
        .alert("Hide Subscription?", isPresented: $showDeleteAlert) {
            Button("Keep", role: .cancel) {}
            Button("Hide", role: .destructive) {
                engine.removeSubscription(liveSub)
                Haptics.success()
                dismiss()
            }
        } message: {
            Text("'\(liveSub.merchantName.capitalized)' will move to the Hidden section. You can unhide it from there.")
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        DS.Card {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(CategoryRegistry.shared.tint(for: liveSub.category).opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: CategoryRegistry.shared.icon(for: liveSub.category))
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(CategoryRegistry.shared.tint(for: liveSub.category))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(liveSub.merchantName.capitalized)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)

                        HStack(spacing: 6) {
                            Image(systemName: liveSub.status.icon)
                                .font(.system(size: 12))
                            Text(liveSub.status.displayName)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(liveSub.status.color)

                        Text(liveSub.category.title + " · " + liveSub.billingCycle.displayName)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.subtext)
                    }

                    Spacer()
                }

                // Main cost
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(DS.Format.currencySymbol())\(DS.Format.currency(liveSub.expectedAmount))")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)

                    Text("/\(cycleShort)")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DS.Colors.subtext)

                    Spacer()

                    if liveSub.hasPriceIncrease, let change = liveSub.priceChangeAmount {
                        HStack(spacing: 3) {
                            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 12, weight: .bold))
                            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(abs(change)))")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(change > 0 ? DS.Colors.danger : DS.Colors.positive)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            (change > 0 ? DS.Colors.danger : DS.Colors.positive).opacity(0.1),
                            in: Capsule()
                        )
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Insight Labels

    @ViewBuilder
    private var insightLabels: some View {
        let labels = engine.insightsFor(liveSub)
        if !labels.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(labels) { insight in
                        HStack(spacing: 5) {
                            Image(systemName: insight.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(insight.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(insight.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(insight.color.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(insight.color.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Cost Breakdown

    private var costBreakdownCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cost Breakdown")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 0) {
                    costColumn(label: "Weekly", amount: liveSub.billingCycle == .weekly ? liveSub.expectedAmount : liveSub.monthlyCost / 4)
                    costColumn(label: "Monthly", amount: liveSub.monthlyCost)
                    costColumn(label: "Yearly", amount: liveSub.yearlyCost)
                }
            }
        }
        .padding(.horizontal)
    }

    private func costColumn(label: String, amount: Int) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Colors.subtext)

            Text("\(DS.Format.currencySymbol())\(DS.Format.currency(amount))")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Colors.text)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Charge History

    private var chargeHistoryCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Charge History")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                if liveSub.chargeHistory.count >= 2 {
                    // Mini chart with Phase 5c price-change annotation: the
                    // latest point gets a larger symbol and (if `priceChangePercent`
                    // is set) a colored % pill above it. Color matches the
                    // direction — danger for hike, positive for cut.
                    let sorted = liveSub.chargeHistory.sorted { $0.date < $1.date }
                    let latestId = sorted.last?.id
                    let pct = liveSub.priceChangePercent
                    let pctColor: Color = (pct ?? 0) > 0 ? DS.Colors.danger : DS.Colors.positive
                    Chart(sorted) { charge in
                        LineMark(
                            x: .value("Date", charge.date),
                            y: .value("Amount", Double(charge.amount) / 100.0)
                        )
                        .foregroundStyle(CategoryRegistry.shared.tint(for: liveSub.category))
                        .interpolationMethod(.catmullRom)

                        let isLatest = charge.id == latestId
                        PointMark(
                            x: .value("Date", charge.date),
                            y: .value("Amount", Double(charge.amount) / 100.0)
                        )
                        .foregroundStyle(
                            isLatest && pct != nil
                                ? pctColor
                                : CategoryRegistry.shared.tint(for: liveSub.category)
                        )
                        .symbolSize(isLatest && pct != nil ? 90 : 30)
                        .annotation(position: .top, alignment: .center, spacing: 2) {
                            if isLatest, let pct {
                                Text(String(format: "%+.1f%%", pct))
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(pctColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(pctColor.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text("\(DS.Format.currencySymbol())\(String(format: "%.0f", v))")
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(shortMonth(date))
                                        .font(.system(size: 10))
                                        .foregroundStyle(DS.Colors.subtext)
                                }
                            }
                        }
                    }
                    .frame(height: 120)
                }

                // List of charges
                let charges = liveSub.chargeHistory.sorted { $0.date > $1.date }.prefix(6)
                ForEach(Array(charges)) { charge in
                    HStack {
                        Circle()
                            .fill(CategoryRegistry.shared.tint(for: liveSub.category))
                            .frame(width: 6, height: 6)

                        Text(formatDate(charge.date))
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(DS.Colors.subtext)

                        Spacer()

                        Text("\(DS.Format.currencySymbol())\(DS.Format.currency(charge.amount))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)

                        // Price change indicator
                        if let prev = previousCharge(before: charge) {
                            let diff = charge.amount - prev.amount
                            if abs(diff) > 0 {
                                Image(systemName: diff > 0 ? "arrow.up" : "arrow.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(diff > 0 ? DS.Colors.danger : DS.Colors.positive)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Renewal Info

    private var renewalInfoCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Renewal Info")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                HStack {
                    infoRow(icon: "calendar", label: "Next Renewal", value: {
                        if let date = liveSub.nextRenewalDate {
                            return formatDate(date)
                        }
                        return "Unknown"
                    }())

                    Spacer()

                    infoRow(icon: "clock", label: "Days Until", value: {
                        if let days = liveSub.daysUntilRenewal {
                            if days < 0 { return "\(abs(days))d overdue" }
                            if days == 0 { return "Today" }
                            if days == 1 { return "Tomorrow" }
                            return "\(days) days"
                        }
                        return "—"
                    }())
                }

                HStack {
                    infoRow(icon: "calendar.badge.clock", label: "Last Charge", value: {
                        if let date = liveSub.lastChargeDate {
                            return formatDate(date)
                        }
                        return "Unknown"
                    }())

                    Spacer()

                    infoRow(icon: "repeat", label: "Cycle", value: liveSub.billingCycle.displayName)
                }
            }
        }
        .padding(.horizontal)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)

                Text(value)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
            }
        }
    }

    // MARK: - Detection Info

    private var detectionInfoCard: some View {
        DS.Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Detection Info")
                    .font(DS.Typography.section)
                    .foregroundStyle(DS.Colors.text)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                        Text(liveSub.isAutoDetected ? "Auto-detected" : "Manual")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confidence")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)

                        HStack(spacing: 4) {
                            Text("\(Int(liveSub.confidenceScore * 100))%")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(confidenceColor)

                            // Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(DS.Colors.surface2)
                                        .frame(height: 4)

                                    Capsule()
                                        .fill(confidenceColor)
                                        .frame(width: geo.size.width * liveSub.confidenceScore, height: 4)
                                }
                            }
                            .frame(width: 50, height: 4)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Charges Linked")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                        Text("\(liveSub.linkedTransactionIds.count)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.text)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Maybe-Unused Callout (Phase 5c)

    /// High-visibility prompt that surfaces only when detection has flagged
    /// this subscription as `.suspectedUnused` and the user hasn't yet
    /// dismissed the flag. Sits above the charge history so it's the first
    /// thing the user reads after the header — the action tile alone is
    /// easy to miss. Two CTAs: keep (dismiss the flag) and cancel.
    @ViewBuilder
    private var maybeUnusedCallout: some View {
        if liveSub.status == .suspectedUnused && !liveSub.dismissedSuspectedUnused {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hexValue: 0x9B59B6))
                    Text("Still using this?")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(DS.Colors.text)
                }

                Text(maybeUnusedExplanation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Colors.subtext)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button {
                        engine.dismissSuspectedUnused(liveSub)
                        Haptics.success()
                    } label: {
                        Text("Yes, I use this")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.positive)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DS.Colors.positive.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        showCancelAlert = true
                        Haptics.medium()
                    } label: {
                        Text("Cancel it")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(DS.Colors.danger)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(DS.Colors.danger.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(hexValue: 0x9B59B6).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color(hexValue: 0x9B59B6).opacity(0.2), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }

    /// Sentence shown inside the callout. Uses the actual days-since-last-
    /// charge when known so the prompt feels grounded ("36 days") rather
    /// than generic ("a while").
    private var maybeUnusedExplanation: String {
        if let days = liveSub.daysSinceLastCharge, days > 0 {
            return "We haven't seen a charge in \(days) days. If you're still using \(liveSub.merchantName.capitalized), tap to keep it active. Otherwise it's a candidate to cancel."
        }
        return "This looks unused. If you're still on it, tap to keep it active. Otherwise it's a candidate to cancel."
    }

    // MARK: - Actions (Phase 5b — compact tile grid)

    /// Action tile model. `id == label` keeps grid stable across rebuilds
    /// without spamming new UUIDs that would break SwiftUI animations.
    private struct ActionTile: Identifiable {
        var id: String { label }
        let label: String
        let icon: String
        let tint: Color
        let action: () -> Void
    }

    private var actionsCard: some View {
        let tiles = buildActionTiles()
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10),
                      GridItem(.flexible(), spacing: 10),
                      GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(tiles) { tile in
                actionTile(tile)
            }
        }
        .padding(.horizontal)
    }

    /// Build the visible action set for the current state. Status-conditional
    /// (Pause/Resume), provider-conditional (Cancel URL), and flag-conditional
    /// ("I use this" only when suspectedUnused and not yet dismissed).
    private func buildActionTiles() -> [ActionTile] {
        var tiles: [ActionTile] = []
        let s = liveSub

        // Pause / Resume
        if s.status == .active || s.status == .suspectedUnused {
            tiles.append(ActionTile(label: "Pause", icon: "pause.fill", tint: DS.Colors.warning) {
                engine.markAsPaused(s)
                Haptics.medium()
            })
            tiles.append(ActionTile(label: "Cancel", icon: "xmark.circle.fill", tint: DS.Colors.danger) {
                showCancelAlert = true
                Haptics.medium()
            })
        } else {
            tiles.append(ActionTile(label: "Resume", icon: "play.fill", tint: DS.Colors.positive) {
                engine.markAsActive(s)
                Haptics.medium()
            })
        }

        tiles.append(ActionTile(label: "Hide", icon: "eye.slash.fill", tint: DS.Colors.subtext) {
            showDeleteAlert = true
            Haptics.medium()
        })

        // Cancel URL — only when SubscriptionActionProvider has a curated link.
        if let info = SubscriptionActionProvider.lookup(merchantName: s.merchantName),
           let urlString = info.cancelURL,
           let url = URL(string: urlString) {
            tiles.append(ActionTile(label: "Cancel URL", icon: "arrow.up.right.square", tint: DS.Colors.accent) {
                openURL(url)
                Haptics.selection()
            })
        }

        // Dismiss suspected-unused. Phase 3 wired the engine API; this is
        // its primary surface — "I use this" reads better than "Dismiss".
        if s.status == .suspectedUnused && !s.dismissedSuspectedUnused {
            tiles.append(ActionTile(label: "I use this", icon: "checkmark.circle.fill", tint: DS.Colors.positive) {
                engine.dismissSuspectedUnused(s)
                Haptics.success()
            })
        }

        return tiles
    }

    private func actionTile(_ tile: ActionTile) -> some View {
        Button(action: tile.action) {
            VStack(spacing: 6) {
                Image(systemName: tile.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tile.tint)
                Text(tile.label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tile.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(tile.tint.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tile.label)
    }

    // MARK: - Helpers

    private var cycleShort: String {
        switch liveSub.billingCycle {
        case .weekly: return "wk"
        case .biweekly: return "2w"
        case .monthly: return "mo"
        case .quarterly: return "qtr"
        case .semiannual: return "6mo"
        case .yearly: return "yr"
        case .custom: return "mo"
        }
    }

    private var confidenceColor: Color {
        if liveSub.confidenceScore >= 0.75 { return DS.Colors.positive }
        if liveSub.confidenceScore >= 0.55 { return DS.Colors.warning }
        return DS.Colors.danger
    }

    private func previousCharge(before charge: ChargeRecord) -> ChargeRecord? {
        let sorted = liveSub.chargeHistory.sorted { $0.date < $1.date }
        guard let idx = sorted.firstIndex(where: { $0.id == charge.id }), idx > 0 else { return nil }
        return sorted[idx - 1]
    }

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, yyyy"
        return fmt.string(from: date)
    }

    private func shortMonth(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM"
        return fmt.string(from: date)
    }
}
