import SwiftUI
import Charts

// ============================================================
// MARK: - Subscription Detail View
// ============================================================

struct SubscriptionDetailView: View {
    let subscription: DetectedSubscription
    @StateObject private var engine = SubscriptionEngine.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showCancelAlert = false
    @State private var showDeleteAlert = false

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
        .alert("Cancel Subscription?", isPresented: $showCancelAlert) {
            Button("Keep Active", role: .cancel) {}
            Button("Mark Cancelled", role: .destructive) {
                engine.markAsCancelled(liveSub)
                Haptics.success()
            }
        } message: {
            Text("This marks '\(liveSub.merchantName.capitalized)' as cancelled. You'll need to actually cancel with the provider separately.")
        }
        .alert("Remove Subscription?", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                engine.removeSubscription(liveSub)
                Haptics.success()
                dismiss()
            }
        } message: {
            Text("This will remove '\(liveSub.merchantName.capitalized)' from your tracked subscriptions. It may be re-detected on next analysis.")
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
                            .fill(liveSub.category.tint.opacity(0.15))
                            .frame(width: 56, height: 56)

                        Image(systemName: liveSub.category.icon)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(liveSub.category.tint)
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
                    // Mini chart
                    Chart(liveSub.chargeHistory.sorted { $0.date < $1.date }) { charge in
                        LineMark(
                            x: .value("Date", charge.date),
                            y: .value("Amount", Double(charge.amount) / 100.0)
                        )
                        .foregroundStyle(liveSub.category.tint)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Date", charge.date),
                            y: .value("Amount", Double(charge.amount) / 100.0)
                        )
                        .foregroundStyle(liveSub.category.tint)
                        .symbolSize(30)
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
                            .fill(liveSub.category.tint)
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
                            return days == 0 ? "Today" : "\(days) days"
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

    // MARK: - Actions

    private var actionsCard: some View {
        VStack(spacing: 10) {
            if liveSub.status == .active {
                Button {
                    engine.markAsPaused(liveSub)
                    Haptics.medium()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mark as Paused")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.warning)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DS.Colors.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Colors.warning.opacity(0.2), lineWidth: 1)
                    )
                }

                Button {
                    showCancelAlert = true
                    Haptics.medium()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mark as Cancelled")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DS.Colors.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Colors.danger.opacity(0.2), lineWidth: 1)
                    )
                }
            } else if liveSub.status == .paused || liveSub.status == .cancelled {
                Button {
                    engine.markAsActive(liveSub)
                    Haptics.medium()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Mark as Active")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DS.Colors.positive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(DS.Colors.positive.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Colors.positive.opacity(0.2), lineWidth: 1)
                    )
                }
            }

            Button {
                showDeleteAlert = true
                Haptics.medium()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Remove Subscription")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Colors.subtext)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

    private var cycleShort: String {
        switch liveSub.billingCycle {
        case .weekly: return "wk"
        case .monthly: return "mo"
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
