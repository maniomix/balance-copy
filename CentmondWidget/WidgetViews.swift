//
//  WidgetViews.swift
//  CentmondWidget
//
//  Created by Mani on 16.03.26.
//

import WidgetKit
import SwiftUI

// ============================================================
// MARK: - Shared Helpers
// ============================================================

private let brandGradient = LinearGradient(
    colors: [Color(red: 0.4, green: 0.49, blue: 0.92),
             Color(red: 0.46, green: 0.29, blue: 0.64)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

private let brandColor = Color(red: 0.4, green: 0.49, blue: 0.92)

private func formatCents(_ cents: Int, symbol: String) -> String {
    let value = Double(cents) / 100.0
    if abs(value) >= 1000 {
        let k = value / 1000.0
        return String(format: "%@%.1fk", symbol, k)
    }
    return String(format: "%@%.0f", symbol, value)
}

private func formatCentsFull(_ cents: Int, symbol: String) -> String {
    let value = Double(cents) / 100.0
    if value == value.rounded() {
        return String(format: "%@%.0f", symbol, value)
    }
    return String(format: "%@%.2f", symbol, value)
}

/// Compact format for lock-screen accessories
private func formatCentsCompact(_ cents: Int, symbol: String) -> String {
    let value = Double(cents) / 100.0
    if abs(value) >= 10000 {
        return String(format: "%@%.0fk", symbol, value / 1000.0)
    } else if abs(value) >= 1000 {
        return String(format: "%@%.1fk", symbol, value / 1000.0)
    }
    return String(format: "%@%.0f", symbol, value)
}

private func riskColor(for level: String) -> Color {
    switch level {
    case "highRisk": return .red
    case "caution": return .orange
    default: return .green
    }
}

private func statusColor(ratio: Double) -> Color {
    ratio > 0.9 ? .red : (ratio > 0.7 ? .orange : .green)
}

// ============================================================
// MARK: - Deep Link URLs
// ============================================================

enum WidgetDeepLink {
    static let dashboard    = URL(string: "centmond://dashboard")!
    static let budget       = URL(string: "centmond://budget")!
    static let bills        = URL(string: "centmond://subscriptions")!
    static let safeToSpend  = URL(string: "centmond://forecast")!
    static let netWorth     = URL(string: "centmond://accounts")!
}

// ============================================================
// MARK: - Empty / Stale State Views
// ============================================================

/// Shown when the app has never written widget data
private struct WidgetEmptyView: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Open Centmond to get started")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Stale data banner overlay
private struct StaleBanner: View {
    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 7))
                Text("Open app to refresh")
                    .font(.system(size: 8))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// ============================================================
// MARK: - Timeline Provider (Shared)
// ============================================================

struct BalanceTimelineProvider: TimelineProvider {
    typealias Entry = BalanceTimelineEntry

    func placeholder(in context: Context) -> BalanceTimelineEntry {
        BalanceTimelineEntry(date: Date(), data: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceTimelineEntry) -> Void) {
        if context.isPreview {
            // Widget gallery preview — show sample data
            completion(BalanceTimelineEntry(date: Date(), data: .sample))
        } else {
            let data = WidgetDataBridge.read()
            completion(BalanceTimelineEntry(date: Date(), data: data))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceTimelineEntry>) -> Void) {
        let data = WidgetDataBridge.read()
        let entry = BalanceTimelineEntry(date: Date(), data: data)

        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct BalanceTimelineEntry: TimelineEntry {
    let date: Date
    let data: WidgetSharedData

    /// Relevance score for Smart Stack ordering.
    /// Higher = more relevant right now.
    var relevance: TimelineEntryRelevance? {
        let ratio = data.budgetUsedRatio
        if ratio > 0.9 { return TimelineEntryRelevance(score: 90) }
        if ratio > 0.7 { return TimelineEntryRelevance(score: 60) }
        if data.spentToday > data.dailyAverage && data.dailyAverage > 0 {
            return TimelineEntryRelevance(score: 50)
        }
        return TimelineEntryRelevance(score: 20)
    }
}

// ============================================================
// MARK: - 1. Today Spending Widget
// ============================================================

struct TodaySpendingWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let sym = d.currencySymbol

        if d.isEmpty {
            WidgetEmptyView(icon: "creditcard.fill", title: "Track Spending")
        } else {
            ZStack {
                mainContent(d: d, sym: sym)
                if d.isStale { StaleBanner() }
            }
        }
    }

    @ViewBuilder
    private func mainContent(d: WidgetSharedData, sym: String) -> some View {
        switch family {
        case .systemSmall:
            smallView(d: d, sym: sym)
        case .systemMedium:
            mediumView(d: d, sym: sym)
        case .accessoryCircular:
            accessoryCircularView(d: d, sym: sym)
        case .accessoryRectangular:
            accessoryRectangularView(d: d, sym: sym)
        case .accessoryInline:
            accessoryInlineView(d: d, sym: sym)
        default:
            smallView(d: d, sym: sym)
        }
    }

    private func smallView(d: WidgetSharedData, sym: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(formatCentsFull(d.spentToday, symbol: sym))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer()

            HStack {
                Text("Avg")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(formatCents(d.dailyAverage, symbol: sym))
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }

            // Day progress
            let progress = d.daysInMonth > 0
                ? Double(d.dayOfMonth) / Double(d.daysInMonth)
                : 0
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 4)
                    Capsule()
                        .fill(brandGradient)
                        .frame(width: geo.size.width * max(0, min(1, progress)), height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding()
    }

    private func mediumView(d: WidgetSharedData, sym: String) -> some View {
        HStack(spacing: 16) {
            // Left: today spending
            VStack(alignment: .leading, spacing: 6) {
                Label("Today's Spending", systemImage: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formatCentsFull(d.spentToday, symbol: sym))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 12) {
                    VStack(alignment: .leading) {
                        Text("Daily Avg")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formatCents(d.dailyAverage, symbol: sym))
                            .font(.caption.bold())
                    }
                    VStack(alignment: .leading) {
                        Text("This Month")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formatCents(d.spentThisMonth, symbol: sym))
                            .font(.caption.bold())
                    }
                }
            }

            Divider()

            // Right: budget status
            VStack(alignment: .leading, spacing: 6) {
                Text("Budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let ratio = d.budgetUsedRatio
                let color = statusColor(ratio: ratio)

                Text(formatCents(d.remainingBudget, symbol: sym))
                    .font(.title3.bold())
                    .foregroundStyle(color)

                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                ProgressView(value: min(1, ratio))
                    .tint(color)
            }
        }
        .padding()
    }

    // MARK: Lock Screen Accessories

    private func accessoryCircularView(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.daysInMonth > 0
            ? Double(d.dayOfMonth) / Double(d.daysInMonth)
            : 0
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text(formatCentsCompact(d.spentToday, symbol: sym))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                Text("today")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .widgetLabel {
            ProgressView(value: min(1, ratio))
        }
    }

    private func accessoryRectangularView(d: WidgetSharedData, sym: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 10))
                Text("Today")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(formatCentsFull(d.spentToday, symbol: sym))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)

            Text("Avg \(formatCents(d.dailyAverage, symbol: sym)) · Month \(formatCents(d.spentThisMonth, symbol: sym))")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func accessoryInlineView(d: WidgetSharedData, sym: String) -> some View {
        Label(
            "Today: \(formatCentsCompact(d.spentToday, symbol: sym))",
            systemImage: "creditcard.fill"
        )
    }
}

struct TodaySpendingWidget: Widget {
    let kind = "TodaySpendingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            TodaySpendingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetDeepLink.dashboard)
        }
        .configurationDisplayName("Today's Spending")
        .description("See how much you've spent today.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// ============================================================
// MARK: - 2. Budget Widget
// ============================================================

struct BudgetWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let sym = d.currencySymbol

        if d.isEmpty {
            WidgetEmptyView(icon: "chart.pie.fill", title: "Set Your Budget")
        } else {
            ZStack {
                mainContent(d: d, sym: sym)
                if d.isStale && family != .accessoryCircular { StaleBanner() }
            }
        }
    }

    @ViewBuilder
    private func mainContent(d: WidgetSharedData, sym: String) -> some View {
        switch family {
        case .systemSmall:
            smallBudget(d: d, sym: sym)
        case .systemMedium:
            mediumBudget(d: d, sym: sym)
        case .systemLarge:
            largeBudget(d: d, sym: sym)
        case .accessoryCircular:
            accessoryCircularBudget(d: d, sym: sym)
        case .accessoryRectangular:
            accessoryRectangularBudget(d: d, sym: sym)
        default:
            smallBudget(d: d, sym: sym)
        }
    }

    private func smallBudget(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.budgetUsedRatio
        let color = statusColor(ratio: ratio)

        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, ratio))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(Int(min(ratio, 9.99) * 100))%")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("used")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 70, height: 70)

            Text(formatCents(d.remainingBudget, symbol: sym) + " left")
                .font(.caption2.bold())
                .foregroundStyle(color)
        }
        .padding()
    }

    private func mediumBudget(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.budgetUsedRatio
        let color = statusColor(ratio: ratio)

        return HStack(spacing: 16) {
            // Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(1, ratio))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(Int(min(ratio, 9.99) * 100))%")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("used")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly Budget")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    VStack(alignment: .leading) {
                        Text("Budget")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formatCents(d.budgetTotal, symbol: sym))
                            .font(.caption.bold())
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Spent")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formatCents(d.spentThisMonth, symbol: sym))
                            .font(.caption.bold())
                    }
                }

                HStack {
                    VStack(alignment: .leading) {
                        Text("Remaining")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text(formatCents(d.remainingBudget, symbol: sym))
                            .font(.caption.bold())
                            .foregroundStyle(color)
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("Days Left")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Text("\(d.daysRemainingInMonth)")
                            .font(.caption.bold())
                    }
                }
            }
        }
        .padding()
    }

    // MARK: Large Budget

    private func largeBudget(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.budgetUsedRatio
        let color = statusColor(ratio: ratio)
        let dayProgress = d.daysInMonth > 0
            ? Double(d.dayOfMonth) / Double(d.daysInMonth)
            : 0

        return VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.subheadline)
                    .foregroundStyle(brandColor)
                Text("Monthly Budget")
                    .font(.subheadline.bold())
                Spacer()
                Text("Day \(d.dayOfMonth) of \(d.daysInMonth)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Big ring + summary
            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.15), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: min(1, ratio))
                        .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 2) {
                        Text("\(Int(min(ratio, 9.99) * 100))%")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text("used")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 90, height: 90)

                VStack(alignment: .leading, spacing: 10) {
                    largeStat(label: "Budget", value: formatCentsFull(d.budgetTotal, symbol: sym), color: .primary)
                    largeStat(label: "Spent", value: formatCentsFull(d.spentThisMonth, symbol: sym), color: .primary)
                    largeStat(label: "Remaining", value: formatCentsFull(d.remainingBudget, symbol: sym), color: color)
                }
            }

            Divider()

            // Bottom metrics
            HStack(spacing: 0) {
                largeMetric(icon: "calendar", label: "Days Left", value: "\(d.daysRemainingInMonth)")
                Spacer()
                largeMetric(icon: "arrow.down", label: "Daily Avg", value: formatCents(d.dailyAverage, symbol: sym))
                Spacer()
                largeMetric(icon: "shield.checkered", label: "Safe/Day", value: formatCents(d.safeToSpendPerDay, symbol: sym))
                Spacer()
                largeMetric(icon: "arrow.up", label: "Income", value: formatCents(d.incomeThisMonth, symbol: sym))
            }

            // Progress bar: budget vs time
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Budget pace")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    let paceStatus = ratio > dayProgress + 0.1 ? "Ahead of budget" : (ratio < dayProgress - 0.1 ? "Under budget" : "On track")
                    Text(paceStatus)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(ratio > dayProgress + 0.1 ? .red : .green)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Full track
                        Capsule().fill(Color.gray.opacity(0.15)).frame(height: 6)
                        // Budget usage
                        Capsule().fill(color).frame(width: geo.size.width * min(1, ratio), height: 6)
                        // Time marker
                        Rectangle()
                            .fill(Color.primary.opacity(0.4))
                            .frame(width: 2, height: 10)
                            .offset(x: geo.size.width * min(1, dayProgress) - 1)
                    }
                }
                .frame(height: 10)
            }
        }
        .padding()
    }

    private func largeStat(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
    }

    private func largeMetric(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 55)
    }

    // MARK: Lock Screen Accessories

    private func accessoryCircularBudget(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.budgetUsedRatio
        return Gauge(value: min(1, ratio)) {
            Text(sym)
                .font(.system(size: 10))
        } currentValueLabel: {
            Text("\(Int(min(ratio, 9.99) * 100))%")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func accessoryRectangularBudget(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.budgetUsedRatio
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 10))
                Text("Budget · \(Int(min(ratio, 9.99) * 100))% used")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(formatCents(d.remainingBudget, symbol: sym) + " left")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)

            Gauge(value: min(1, ratio)) { EmptyView() }
                .gaugeStyle(.accessoryLinear)
        }
    }
}

struct BudgetWidget: Widget {
    let kind = "BudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetDeepLink.budget)
        }
        .configurationDisplayName("Budget")
        .description("Track your monthly budget at a glance.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}

// ============================================================
// MARK: - 3. Upcoming Bills Widget
// ============================================================

struct UpcomingBillsWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let sym = d.currencySymbol

        if d.isEmpty {
            WidgetEmptyView(icon: "calendar.badge.clock", title: "Track Bills")
        } else {
            ZStack {
                mainContent(d: d, sym: sym)
                if d.isStale { StaleBanner() }
            }
        }
    }

    @ViewBuilder
    private func mainContent(d: WidgetSharedData, sym: String) -> some View {
        switch family {
        case .accessoryRectangular:
            accessoryRectangularBills(d: d, sym: sym)
        default:
            homeScreenBills(d: d, sym: sym)
        }
    }

    private func homeScreenBills(d: WidgetSharedData, sym: String) -> some View {
        let bills = d.upcomingBills.prefix(family == .systemSmall ? 2 : 4)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Upcoming Bills")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !bills.isEmpty {
                    let total = d.upcomingBills.reduce(0) { $0 + $1.amount }
                    Text(formatCents(total, symbol: sym))
                        .font(.caption2.bold())
                        .foregroundStyle(brandColor)
                }
            }

            if bills.isEmpty {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("All clear!")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                ForEach(Array(bills.enumerated()), id: \.element.id) { _, bill in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(bill.name)
                                .font(.caption.bold())
                                .lineLimit(1)
                            Text(bill.dueDate, style: .date)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatCentsFull(bill.amount, symbol: sym))
                            .font(.caption.bold())
                            .foregroundStyle(brandColor)
                    }
                    if bill.id != bills.last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }

    private func accessoryRectangularBills(d: WidgetSharedData, sym: String) -> some View {
        let bills = d.upcomingBills.prefix(2)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 10))
                Text("Bills")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            if bills.isEmpty {
                Text("No upcoming bills")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(bills.enumerated()), id: \.element.id) { _, bill in
                    HStack {
                        Text(bill.name)
                            .font(.caption2.bold())
                            .lineLimit(1)
                        Spacer()
                        Text(formatCentsCompact(bill.amount, symbol: sym))
                            .font(.caption2)
                    }
                }
            }
        }
    }
}

struct UpcomingBillsWidget: Widget {
    let kind = "UpcomingBillsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            UpcomingBillsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetDeepLink.bills)
        }
        .configurationDisplayName("Upcoming Bills")
        .description("Never miss a bill payment.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// ============================================================
// MARK: - 4. Safe to Spend Widget
// ============================================================

struct SafeToSpendWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let sym = d.currencySymbol

        if d.isEmpty {
            WidgetEmptyView(icon: "shield.checkered", title: "Safe to Spend")
        } else {
            ZStack {
                mainContent(d: d, sym: sym)
                if d.isStale && family != .accessoryCircular { StaleBanner() }
            }
        }
    }

    @ViewBuilder
    private func mainContent(d: WidgetSharedData, sym: String) -> some View {
        switch family {
        case .systemSmall:
            smallSafe(d: d, sym: sym)
        case .systemMedium:
            mediumSafe(d: d, sym: sym)
        case .accessoryCircular:
            accessoryCircularSafe(d: d, sym: sym)
        case .accessoryRectangular:
            accessoryRectangularSafe(d: d, sym: sym)
        case .accessoryInline:
            accessoryInlineSafe(d: d, sym: sym)
        default:
            smallSafe(d: d, sym: sym)
        }
    }

    private func smallSafe(d: WidgetSharedData, sym: String) -> some View {
        let risk = riskColor(for: d.riskLevel)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(risk)
                Text("Safe to Spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(formatCentsFull(d.safeToSpendTotal, symbol: sym))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(risk)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer()

            HStack {
                Text(formatCents(d.safeToSpendPerDay, symbol: sym))
                    .font(.caption.bold())
                Text("/ day")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Risk indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(risk)
                    .frame(width: 6, height: 6)
                Text(d.riskLevel == "highRisk" ? "High Risk" : (d.riskLevel == "caution" ? "Caution" : "Safe"))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(risk)
            }
        }
        .padding()
    }

    private func mediumSafe(d: WidgetSharedData, sym: String) -> some View {
        let risk = riskColor(for: d.riskLevel)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.caption)
                    .foregroundStyle(risk)
                Text("Safe to Spend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                // Risk badge
                HStack(spacing: 4) {
                    Circle().fill(risk).frame(width: 6, height: 6)
                    Text(d.riskLevel == "highRisk" ? "High Risk" : (d.riskLevel == "caution" ? "Caution" : "Safe"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(risk)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(risk.opacity(0.12), in: Capsule())
            }

            Text(formatCentsFull(d.safeToSpendTotal, symbol: sym))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(risk)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 16) {
                infoBlock(title: "Per Day", value: formatCents(d.safeToSpendPerDay, symbol: sym))
                infoBlock(title: "Bills Reserved", value: formatCents(d.reservedForBills, symbol: sym))
                infoBlock(title: "Goals Reserved", value: formatCents(d.reservedForGoals, symbol: sym))
                infoBlock(title: "Days Left", value: "\(d.daysRemainingInMonth)")
            }
        }
        .padding()
    }

    private func infoBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }

    // MARK: Lock Screen Accessories

    private func accessoryCircularSafe(d: WidgetSharedData, sym: String) -> some View {
        let ratio = d.budgetTotal > 0
            ? Double(d.safeToSpendTotal) / Double(d.budgetTotal)
            : 0
        return Gauge(value: min(1, max(0, ratio))) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 10))
        } currentValueLabel: {
            Text(formatCentsCompact(d.safeToSpendTotal, symbol: sym))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func accessoryRectangularSafe(d: WidgetSharedData, sym: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 10))
                Text("Safe to Spend")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(formatCentsFull(d.safeToSpendTotal, symbol: sym))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)

            Text("\(formatCentsCompact(d.safeToSpendPerDay, symbol: sym))/day · \(d.daysRemainingInMonth)d left")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func accessoryInlineSafe(d: WidgetSharedData, sym: String) -> some View {
        Label(
            "Safe: \(formatCentsCompact(d.safeToSpendTotal, symbol: sym))",
            systemImage: "shield.checkered"
        )
    }
}

struct SafeToSpendWidget: Widget {
    let kind = "SafeToSpendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetDeepLink.safeToSpend)
        }
        .configurationDisplayName("Safe to Spend")
        .description("Know how much you can safely spend.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

// ============================================================
// MARK: - 5. Net Worth Widget
// ============================================================

struct NetWorthWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let d = entry.data
        let sym = d.currencySymbol

        if d.isEmpty {
            WidgetEmptyView(icon: "building.columns.fill", title: "Track Net Worth")
        } else {
            ZStack {
                mainContent(d: d, sym: sym)
                if d.isStale { StaleBanner() }
            }
        }
    }

    @ViewBuilder
    private func mainContent(d: WidgetSharedData, sym: String) -> some View {
        switch family {
        case .systemSmall:
            smallNetWorth(d: d, sym: sym)
        case .systemMedium:
            mediumNetWorth(d: d, sym: sym)
        case .accessoryRectangular:
            accessoryRectangularNetWorth(d: d, sym: sym)
        default:
            smallNetWorth(d: d, sym: sym)
        }
    }

    private func smallNetWorth(d: WidgetSharedData, sym: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "building.columns.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Net Worth")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(formatCentsFull(d.netWorth, symbol: sym))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(d.netWorth >= 0 ? brandColor : .red)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer()

            HStack {
                Text("\(d.accountCount) accounts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Last updated
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(d.lastUpdated, style: .relative)
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
    }

    private func mediumNetWorth(d: WidgetSharedData, sym: String) -> some View {
        HStack(spacing: 16) {
            // Left: headline
            VStack(alignment: .leading, spacing: 6) {
                Label("Net Worth", systemImage: "building.columns.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(formatCentsFull(d.netWorth, symbol: sym))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(d.netWorth >= 0 ? brandColor : .red)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Spacer()

                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                    Text(d.lastUpdated, style: .relative)
                        .font(.system(size: 8))
                }
                .foregroundStyle(.tertiary)
            }

            Divider()

            // Right: breakdown
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Assets")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(formatCents(d.totalAssets, symbol: sym))
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Liabilities")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(formatCents(d.totalLiabilities, symbol: sym))
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Accounts")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("\(d.accountCount)")
                        .font(.caption.bold())
                }
            }
        }
        .padding()
    }

    private func accessoryRectangularNetWorth(d: WidgetSharedData, sym: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 10))
                Text("Net Worth")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)

            Text(formatCentsFull(d.netWorth, symbol: sym))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)

            Text("\(d.accountCount) accounts")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

struct NetWorthWidget: Widget {
    let kind = "NetWorthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            NetWorthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetDeepLink.netWorth)
        }
        .configurationDisplayName("Net Worth")
        .description("Your total net worth at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// ============================================================
// MARK: - Previews
// ============================================================

#if DEBUG
#Preview("Today Spending - Small", as: .systemSmall) {
    TodaySpendingWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Budget - Medium", as: .systemMedium) {
    BudgetWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Budget - Large", as: .systemLarge) {
    BudgetWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Safe to Spend - Small", as: .systemSmall) {
    SafeToSpendWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Bills - Medium", as: .systemMedium) {
    UpcomingBillsWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Net Worth - Medium", as: .systemMedium) {
    NetWorthWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Empty State - Small", as: .systemSmall) {
    BudgetWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .empty)
}

#Preview("Budget - Lock Screen", as: .accessoryCircular) {
    BudgetWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Safe - Lock Rect", as: .accessoryRectangular) {
    SafeToSpendWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}

#Preview("Today - Inline", as: .accessoryInline) {
    TodaySpendingWidget()
} timeline: {
    BalanceTimelineEntry(date: Date(), data: .sample)
}
#endif
