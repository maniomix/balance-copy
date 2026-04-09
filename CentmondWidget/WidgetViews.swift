//
//  WidgetViews.swift
//  CentmondWidget
//
//  Premium widgets with custom charts, bold typography, and rich visuals
//

import WidgetKit
import SwiftUI

// ============================================================
// MARK: - Widget Design System (mirrors app's DS.Colors)
// ============================================================
//
// Widgets live in their own target and can't pull `DS` from the
// app, so we mirror the brand palette here. Values match
// balance/DesignSystem/DS.swift so the widgets feel like they
// belong to the same app instead of shipping stock SwiftUI colors.
private enum WDS {
    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    static let accent = Color(red: 0.27, green: 0.35, blue: 0.96)  // #4559F5
    static let positive = adaptive(
        light: UIColor(red: 0.18, green: 0.75, blue: 0.50, alpha: 1),
        dark:  UIColor(red: 0.40, green: 0.85, blue: 0.65, alpha: 1)
    )
    static let warning = adaptive(
        light: UIColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1),
        dark:  UIColor(red: 1.00, green: 0.78, blue: 0.40, alpha: 1)
    )
    static let danger = adaptive(
        light: UIColor(red: 0.92, green: 0.28, blue: 0.30, alpha: 1),
        dark:  UIColor(red: 0.98, green: 0.45, blue: 0.47, alpha: 1)
    )
    static let bg = adaptive(
        light: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1),
        dark:  UIColor(red: 0.11, green: 0.11, blue: 0.14, alpha: 1)
    )
}

// ============================================================
// MARK: - Helpers
// ============================================================

private func money(_ cents: Int, _ sym: String) -> String {
    let v = Double(cents) / 100.0
    if abs(v) >= 1000 { return String(format: "%@%.1fk", sym, v / 1000.0) }
    return String(format: "%@%.0f", sym, v)
}

private func moneyFull(_ cents: Int, _ sym: String) -> String {
    let v = Double(cents) / 100.0
    return v == v.rounded() ? String(format: "%@%.0f", sym, v) : String(format: "%@%.2f", sym, v)
}

private func moneyCompact(_ cents: Int, _ sym: String) -> String {
    let v = Double(cents) / 100.0
    if abs(v) >= 10000 { return String(format: "%@%.0fk", sym, v / 1000.0) }
    if abs(v) >= 1000  { return String(format: "%@%.1fk", sym, v / 1000.0) }
    return String(format: "%@%.0f", sym, v)
}

private func budgetColor(_ ratio: Double) -> Color {
    ratio > 0.9 ? WDS.danger : (ratio > 0.7 ? WDS.warning : WDS.positive)
}

private func riskColor(_ level: String) -> Color {
    switch level {
    case "highRisk": return WDS.danger
    case "caution":  return WDS.warning
    default:         return WDS.positive
    }
}

private func colorFromHex(_ hex: String) -> Color {
    let scanner = Scanner(string: hex)
    var rgb: UInt64 = 0
    scanner.scanHexInt64(&rgb)
    return Color(
        red: Double((rgb >> 16) & 0xFF) / 255.0,
        green: Double((rgb >> 8) & 0xFF) / 255.0,
        blue: Double(rgb & 0xFF) / 255.0
    )
}

private let weekdayLabels: [String] = {
    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    return (0..<7).reversed().map { offset in
        let day = cal.date(byAdding: .day, value: -offset, to: today)!
        let sym = cal.shortWeekdaySymbols[cal.component(.weekday, from: day) - 1]
        return String(sym.prefix(2))
    }
}()

private let monthName: String = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM"
    return formatter.string(from: Date())
}()

// ============================================================
// MARK: - Deep Links
// ============================================================

private enum DL {
    static let dash = URL(string: "centmond://dashboard")!
    static let budget = URL(string: "centmond://budget")!
    static let bills = URL(string: "centmond://subscriptions")!
    static let safe = URL(string: "centmond://forecast")!
    static let net = URL(string: "centmond://accounts")!
    static let add = URL(string: "centmond://add")!
}

// ============================================================
// MARK: - Custom Chart Shapes
// ============================================================

/// Mini bar chart — 7 vertical bars with optional highlighted bar and dashed average line
private struct MiniBarChart: View {
    let values: [Int]
    let highlightIndex: Int      // typically 6 (today)
    let accentColor: Color
    let showLabels: Bool
    let showAvgLine: Bool

    init(values: [Int], highlightIndex: Int = 6, accentColor: Color = WDS.accent,
         showLabels: Bool = false, showAvgLine: Bool = true) {
        self.values = values
        self.highlightIndex = highlightIndex
        self.accentColor = accentColor
        self.showLabels = showLabels
        self.showAvgLine = showAvgLine
    }

    var body: some View {
        let maxVal = Double(values.max() ?? 1)
        let avg = values.isEmpty ? 0.0 : Double(values.reduce(0, +)) / Double(values.count)

        GeometryReader { geo in
            let barWidth = (geo.size.width - CGFloat(values.count - 1) * 3) / CGFloat(values.count)
            let chartH = geo.size.height - (showLabels ? 14 : 0)

            ZStack(alignment: .bottom) {
                // Bars
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(values.enumerated()), id: \.offset) { i, val in
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: barWidth / 2.5)
                                .fill(i == highlightIndex ? accentColor : accentColor.opacity(0.25))
                                .frame(width: barWidth, height: max(2, chartH * CGFloat(Double(val) / max(maxVal, 1))))

                            if showLabels {
                                Text(i < weekdayLabels.count ? weekdayLabels[i] : "")
                                    .font(.system(size: 8, weight: i == highlightIndex ? .bold : .regular))
                                    .foregroundStyle(i == highlightIndex ? .primary : .secondary)
                                    .frame(height: 12)
                            }
                        }
                    }
                }

                // Average dashed line
                if showAvgLine && maxVal > 0 {
                    let lineY = chartH * (1 - CGFloat(avg / maxVal))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: lineY))
                        p.addLine(to: CGPoint(x: geo.size.width, y: lineY))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary.opacity(0.5))
                }
            }
        }
    }
}

/// Smooth area chart with gradient fill
private struct MiniAreaChart: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        let range = max(maxV - minV, 1)

        var path = Path()
        let stepX = rect.width / CGFloat(values.count - 1)

        func point(_ i: Int) -> CGPoint {
            let y = rect.height - (CGFloat((values[i] - minV) / range) * rect.height * 0.85 + rect.height * 0.05)
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }

        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: point(0))

        for i in 1..<values.count {
            let prev = point(i - 1)
            let curr = point(i)
            let midX = (prev.x + curr.x) / 2
            path.addCurve(to: curr,
                          control1: CGPoint(x: midX, y: prev.y),
                          control2: CGPoint(x: midX, y: curr.y))
        }

        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

/// Area chart line (no fill, just the top stroke)
private struct MiniAreaLine: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1 else { return Path() }
        let maxV = values.max() ?? 1
        let minV = values.min() ?? 0
        let range = max(maxV - minV, 1)

        var path = Path()
        let stepX = rect.width / CGFloat(values.count - 1)

        func point(_ i: Int) -> CGPoint {
            let y = rect.height - (CGFloat((values[i] - minV) / range) * rect.height * 0.85 + rect.height * 0.05)
            return CGPoint(x: CGFloat(i) * stepX, y: y)
        }

        path.move(to: point(0))
        for i in 1..<values.count {
            let prev = point(i - 1)
            let curr = point(i)
            let midX = (prev.x + curr.x) / 2
            path.addCurve(to: curr,
                          control1: CGPoint(x: midX, y: prev.y),
                          control2: CGPoint(x: midX, y: curr.y))
        }
        return path
    }
}

/// Custom thick circular progress ring
private struct ProgressRing: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, progress))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

// ============================================================
// MARK: - Shared Components
// ============================================================

private struct WidgetEmpty: View {
    let icon: String; let title: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text("Open Balance to start")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Category pill: icon + amount in a rounded capsule
private struct CategoryPill: View {
    let category: WidgetCategory
    let currencySymbol: String

    var body: some View {
        let catColor = colorFromHex(category.colorHex)
        HStack(spacing: 4) {
            Image(systemName: category.icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(catColor)
            Text(moneyCompact(category.amount, currencySymbol))
                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(catColor.opacity(0.1), in: Capsule())
    }
}

/// Add Expense button — large dark circle with white "+"
private struct AddButton: View {
    let size: CGFloat

    var body: some View {
        Link(destination: DL.add) {
            ZStack {
                Circle()
                    .fill(.primary)
                    .frame(width: size, height: size)
                Image(systemName: "plus")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Color(UIColor.systemBackground))
            }
        }
    }
}

// ============================================================
// MARK: - Timeline
// ============================================================

struct BalanceTimelineProvider: TimelineProvider {
    typealias Entry = BalanceTimelineEntry
    func placeholder(in context: Context) -> Entry { .init(date: .now, data: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(.init(date: .now, data: context.isPreview ? .sample : WidgetDataBridge.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let e = Entry(date: .now, data: WidgetDataBridge.read())
        completion(Timeline(entries: [e], policy: .after(Calendar.current.date(byAdding: .minute, value: 30, to: .now)!)))
    }
}

struct BalanceTimelineEntry: TimelineEntry {
    let date: Date; let data: WidgetSharedData
    var relevance: TimelineEntryRelevance? {
        let r = data.budgetUsedRatio
        if r > 0.9 { return .init(score: 90) }
        if r > 0.7 { return .init(score: 60) }
        if data.spentToday > data.dailyAverage && data.dailyAverage > 0 { return .init(score: 50) }
        return .init(score: 20)
    }
}

// ============================================================
// MARK: - 1 · Today Spending
// ============================================================

struct TodaySpendingWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var fam

    var body: some View {
        let d = entry.data, s = d.currencySymbol
        if d.isEmpty { WidgetEmpty(icon: "creditcard", title: "Track Spending") }
        else {
            switch fam {
            case .systemSmall:          small(d, s)
            case .systemMedium:         medium(d, s)
            case .accessoryCircular:    circ(d, s)
            case .accessoryRectangular: rect(d, s)
            case .accessoryInline:      Label("Today: \(moneyCompact(d.spentToday, s))", systemImage: "creditcard.fill")
            default: small(d, s)
            }
        }
    }

    // ── Small: Hero number + bar chart ──
    private func small(_ d: WidgetSharedData, _ s: String) -> some View {
        let weekly = d.weeklySpending ?? Array(repeating: d.dailyAverage, count: 7)
        let over = d.spentToday > d.dailyAverage && d.dailyAverage > 0

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("TODAY")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Day \(d.dayOfMonth)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            // Hero amount
            Text(moneyFull(d.spentToday, s))
                .font(.system(size: 34, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(over ? WDS.warning : .primary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text("avg \(money(d.dailyAverage, s))/day")
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 6)

            // 7-day bar chart
            MiniBarChart(
                values: weekly,
                highlightIndex: 6,
                accentColor: over ? WDS.warning : WDS.accent,
                showLabels: false,
                showAvgLine: true
            )
            .frame(height: 30)
        }
        .padding(16)
    }

    // ── Medium: Spending + categories + add button ──
    private func medium(_ d: WidgetSharedData, _ s: String) -> some View {
        let weekly = d.weeklySpending ?? Array(repeating: d.dailyAverage, count: 7)
        let cats = d.topCategories ?? []

        return HStack(spacing: 0) {
            // LEFT: Hero + area chart
            VStack(alignment: .leading, spacing: 0) {
                Text("Spent in \(monthName)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 2)

                Text(moneyFull(d.spentThisMonth, s))
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Area chart with gradient
                ZStack(alignment: .bottom) {
                    MiniAreaChart(values: weekly.map { Double($0) })
                        .fill(
                            LinearGradient(
                                colors: [WDS.accent.opacity(0.3), WDS.accent.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    MiniAreaLine(values: weekly.map { Double($0) })
                        .stroke(WDS.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
                .frame(height: 40)

                Spacer(minLength: 4)

                // Today badge
                HStack(spacing: 4) {
                    Circle().fill(WDS.accent).frame(width: 5, height: 5)
                    Text("Today")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text(moneyFull(d.spentToday, s))
                        .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Thin divider
            Rectangle()
                .fill(.quaternary)
                .frame(width: 0.5)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)

            // RIGHT: Categories + Add button
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("CATEGORIES")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Spacer(minLength: 4)

                // Category pills — flow layout
                if !cats.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(cats.prefix(3)), id: \.id) { cat in
                            CategoryPill(category: cat, currencySymbol: s)
                        }
                    }
                } else {
                    Text("No data yet")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 6)

                // Add button
                HStack {
                    Spacer()
                    AddButton(size: 36)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private func circ(_ d: WidgetSharedData, _ s: String) -> some View {
        Gauge(value: min(1, Double(d.dayOfMonth) / Double(max(1, d.daysInMonth)))) {
            Image(systemName: "creditcard.fill")
        } currentValueLabel: {
            Text(moneyCompact(d.spentToday, s))
                .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func rect(_ d: WidgetSharedData, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Today", systemImage: "creditcard.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            Text(moneyFull(d.spentToday, s))
                .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
            Text("Avg \(money(d.dailyAverage, s)) · Month \(money(d.spentThisMonth, s))")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct TodaySpendingWidget: Widget {
    let kind = "TodaySpendingWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            TodaySpendingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DL.dash)
        }
        .configurationDisplayName("Today's Spending")
        .description("See how much you've spent today.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ============================================================
// MARK: - 2 · Budget
// ============================================================

struct BudgetWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var fam

    var body: some View {
        let d = entry.data, s = d.currencySymbol
        if d.isEmpty { WidgetEmpty(icon: "chart.pie", title: "Set Your Budget") }
        else {
            switch fam {
            case .systemSmall:          small(d, s)
            case .systemMedium:         medium(d, s)
            case .systemLarge:          large(d, s)
            case .accessoryCircular:    circ(d, s)
            case .accessoryRectangular: rect(d, s)
            default: small(d, s)
            }
        }
    }

    // ── Small: Ring + remaining ──
    private func small(_ d: WidgetSharedData, _ s: String) -> some View {
        let ratio = d.budgetUsedRatio
        let color = budgetColor(ratio)

        return VStack(spacing: 0) {
            HStack {
                Text("BUDGET")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(d.daysRemainingInMonth)d left")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 6)

            // Custom ring
            ZStack {
                ProgressRing(progress: min(1, ratio), color: color, lineWidth: 8, size: 72)
                VStack(spacing: 1) {
                    Text("\(Int(min(ratio, 9.99) * 100))%")
                        .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                    Text("used")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 6)

            Text(money(d.remainingBudget, s) + " left")
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(16)
    }

    // ── Medium: Ring + stats + bar chart ──
    private func medium(_ d: WidgetSharedData, _ s: String) -> some View {
        let ratio = d.budgetUsedRatio
        let color = budgetColor(ratio)
        let weekly = d.weeklySpending ?? Array(repeating: d.dailyAverage, count: 7)
        let dayProg = d.daysInMonth > 0 ? Double(d.dayOfMonth) / Double(d.daysInMonth) : 0
        let ahead = ratio > dayProg + 0.05

        return HStack(spacing: 14) {
            // Ring
            VStack(spacing: 6) {
                ZStack {
                    ProgressRing(progress: min(1, ratio), color: color, lineWidth: 8, size: 76)
                    VStack(spacing: 1) {
                        Text("\(Int(min(ratio, 9.99) * 100))%")
                            .font(.system(size: 24, weight: .heavy, design: .rounded).monospacedDigit())
                        Text("used")
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                // Pace pill
                HStack(spacing: 3) {
                    Circle().fill(ahead ? WDS.danger : WDS.positive).frame(width: 5, height: 5)
                    Text(ahead ? "Over pace" : "On track")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(ahead ? WDS.danger : WDS.positive)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background((ahead ? WDS.danger : WDS.positive).opacity(0.1), in: Capsule())
            }

            // Stats + chart
            VStack(alignment: .leading, spacing: 0) {
                Text("MONTHLY BUDGET")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(money(d.remainingBudget, s))
                            .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(color)
                        Text("remaining of \(money(d.budgetTotal, s))")
                            .font(.system(size: 9, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Spacer(minLength: 6)

                // Bar chart
                MiniBarChart(
                    values: weekly,
                    highlightIndex: 6,
                    accentColor: color,
                    showLabels: true,
                    showAvgLine: true
                )
                .frame(height: 42)
            }
        }
        .padding(16)
    }

    // ── Large: Full dashboard ──
    private func large(_ d: WidgetSharedData, _ s: String) -> some View {
        let ratio = d.budgetUsedRatio
        let color = budgetColor(ratio)
        let weekly = d.weeklySpending ?? Array(repeating: d.dailyAverage, count: 7)
        let dayProg = d.daysInMonth > 0 ? Double(d.dayOfMonth) / Double(d.daysInMonth) : 0
        let ahead = ratio > dayProg + 0.05

        return VStack(spacing: 0) {
            // Header row
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text("MONTHLY BUDGET")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Day \(d.dayOfMonth) of \(d.daysInMonth)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 10)

            // Ring + hero stats
            HStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: min(1, ratio), color: color, lineWidth: 10, size: 96)
                    VStack(spacing: 1) {
                        Text("\(Int(min(ratio, 9.99) * 100))%")
                            .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                        Text("used")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    statRow("Budget", moneyFull(d.budgetTotal, s), .primary)
                    statRow("Spent", moneyFull(d.spentThisMonth, s), .primary)
                    statRow("Remaining", moneyFull(d.remainingBudget, s), color)
                }
            }

            Spacer(minLength: 10)

            // Divider
            Rectangle().fill(.quaternary).frame(height: 0.5)

            Spacer(minLength: 10)

            // Bar chart with labels
            MiniBarChart(
                values: weekly,
                highlightIndex: 6,
                accentColor: color,
                showLabels: true,
                showAvgLine: true
            )
            .frame(height: 60)

            Spacer(minLength: 10)

            // Metrics row
            HStack(spacing: 0) {
                metricCol("calendar", "\(d.daysRemainingInMonth)", "Days Left")
                metricCol("arrow.down", money(d.dailyAverage, s), "Daily Avg")
                metricCol("shield.checkered", money(d.safeToSpendPerDay, s), "Safe/Day")
                metricCol("arrow.up", money(d.incomeThisMonth, s), "Income")
            }

            Spacer(minLength: 8)

            // Pace bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.06)).frame(height: 6)
                    Capsule().fill(color).frame(width: geo.size.width * min(1, ratio), height: 6)
                    // Time marker
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: 12)
                        .offset(x: geo.size.width * min(1, dayProg) - 1)
                }
            }
            .frame(height: 12)

            HStack {
                Text("Budget pace")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Circle().fill(ahead ? WDS.danger : WDS.positive).frame(width: 4, height: 4)
                    Text(ahead ? "Spending too fast" : "On track")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(ahead ? WDS.danger : WDS.positive)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
    }

    private func statRow(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label).font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit()).foregroundStyle(color)
        }
    }

    private func metricCol(_ icon: String, _ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func circ(_ d: WidgetSharedData, _ s: String) -> some View {
        Gauge(value: min(1, d.budgetUsedRatio)) {
            Text(s).font(.system(size: 10, weight: .bold))
        } currentValueLabel: {
            Text("\(Int(min(d.budgetUsedRatio, 9.99) * 100))%")
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func rect(_ d: WidgetSharedData, _ s: String) -> some View {
        let ratio = d.budgetUsedRatio
        return VStack(alignment: .leading, spacing: 2) {
            Label("Budget · \(Int(min(ratio, 9.99) * 100))%", systemImage: "chart.pie.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            Text(money(d.remainingBudget, s) + " left")
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
            Gauge(value: min(1, ratio)) { SwiftUI.EmptyView() }.gaugeStyle(.accessoryLinear)
        }
    }
}

struct BudgetWidget: Widget {
    let kind = "BudgetWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            BudgetWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DL.budget)
        }
        .configurationDisplayName("Budget")
        .description("Track your monthly budget at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular])
    }
}

// ============================================================
// MARK: - 3 · Upcoming Bills
// ============================================================

struct UpcomingBillsWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var fam

    var body: some View {
        let d = entry.data, s = d.currencySymbol
        if d.isEmpty { WidgetEmpty(icon: "calendar.badge.clock", title: "Track Bills") }
        else {
            switch fam {
            case .accessoryRectangular: rect(d, s)
            default: home(d, s)
            }
        }
    }

    private func home(_ d: WidgetSharedData, _ s: String) -> some View {
        let bills = d.upcomingBills.prefix(fam == .systemSmall ? 2 : 4)
        let total = d.upcomingBills.reduce(0) { $0 + $1.amount }

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WDS.accent)
                    Text("UPCOMING BILLS")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !bills.isEmpty {
                    Text(money(total, s))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WDS.accent)
                }
            }

            if bills.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(WDS.positive)
                    Text("All clear!")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                Spacer(minLength: 8)
                ForEach(Array(bills.enumerated()), id: \.element.id) { i, bill in
                    billRow(bill, s)
                    if i < bills.count - 1 {
                        Rectangle()
                            .fill(.quaternary)
                            .frame(height: 0.5)
                            .padding(.leading, 28)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
    }

    private func billRow(_ bill: WidgetBill, _ s: String) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: bill.dueDate)).day ?? 0
        let overdue = days < 0
        let urgent = days >= 0 && days <= 3
        let dot: Color = overdue ? WDS.danger : (urgent ? WDS.warning : WDS.accent)

        return HStack(spacing: 10) {
            // Status dot with glow
            ZStack {
                Circle().fill(dot.opacity(0.2)).frame(width: 18, height: 18)
                Circle().fill(dot).frame(width: 7, height: 7)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(bill.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(overdue ? "\(abs(days))d overdue" : (days == 0 ? "Due today" : "in \(days) days"))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(dot)
            }
            Spacer()
            Text(moneyFull(bill.amount, s))
                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
        }
        .padding(.vertical, 4)
    }

    private func rect(_ d: WidgetSharedData, _ s: String) -> some View {
        let bills = d.upcomingBills.prefix(2)
        return VStack(alignment: .leading, spacing: 2) {
            Label("Bills", systemImage: "calendar.badge.clock")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            if bills.isEmpty {
                Text("All clear ✓").font(.system(size: 12, weight: .semibold))
            } else {
                ForEach(Array(bills.enumerated()), id: \.element.id) { _, bill in
                    HStack {
                        Text(bill.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
                        Spacer()
                        Text(moneyCompact(bill.amount, s)).font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
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
                .widgetURL(DL.bills)
        }
        .configurationDisplayName("Upcoming Bills")
        .description("Never miss a bill payment.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// ============================================================
// MARK: - 4 · Safe to Spend
// ============================================================

struct SafeToSpendWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var fam

    var body: some View {
        let d = entry.data, s = d.currencySymbol
        if d.isEmpty { WidgetEmpty(icon: "shield.checkered", title: "Safe to Spend") }
        else {
            switch fam {
            case .systemSmall:          small(d, s)
            case .systemMedium:         medium(d, s)
            case .accessoryCircular:    circ(d, s)
            case .accessoryRectangular: rect(d, s)
            case .accessoryInline:      Label("Safe: \(moneyCompact(d.safeToSpendTotal, s))", systemImage: "shield.checkered")
            default: small(d, s)
            }
        }
    }

    // ── Small: Ring + amount + status ──
    private func small(_ d: WidgetSharedData, _ s: String) -> some View {
        let risk = riskColor(d.riskLevel)
        let label = d.riskLevel == "highRisk" ? "High Risk" : (d.riskLevel == "caution" ? "Caution" : "Healthy")
        let ratio = d.budgetTotal > 0 ? min(1.0, max(0, Double(d.safeToSpendTotal) / Double(d.budgetTotal))) : 0.5
        let statusIcon = d.riskLevel == "safe" ? "checkmark" : (d.riskLevel == "caution" ? "exclamationmark" : "xmark")

        return VStack(spacing: 0) {
            HStack {
                Text("SAFE TO SPEND")
                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Spacer(minLength: 4)

            // Ring with status icon
            ZStack {
                ProgressRing(progress: ratio, color: risk, lineWidth: 7, size: 64)
                Image(systemName: statusIcon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(risk)
            }

            Spacer(minLength: 4)

            Text(moneyFull(d.safeToSpendTotal, s))
                .font(.system(size: 22, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(risk)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            HStack(spacing: 4) {
                Text(money(d.safeToSpendPerDay, s) + "/day")
                    .font(.system(size: 10, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 2)

            // Status pill
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(risk)
                .padding(.horizontal, 10).padding(.vertical, 3)
                .background(risk.opacity(0.1), in: Capsule())
        }
        .padding(16)
    }

    // ── Medium: Ring + stats + add button ──
    private func medium(_ d: WidgetSharedData, _ s: String) -> some View {
        let risk = riskColor(d.riskLevel)
        let label = d.riskLevel == "highRisk" ? "High Risk" : (d.riskLevel == "caution" ? "Caution" : "Healthy")
        let ratio = d.budgetTotal > 0 ? min(1.0, max(0, Double(d.safeToSpendTotal) / Double(d.budgetTotal))) : 0.5
        let statusIcon = d.riskLevel == "safe" ? "checkmark" : (d.riskLevel == "caution" ? "exclamationmark" : "xmark")
        let weekly = d.weeklySpending ?? Array(repeating: d.dailyAverage, count: 7)

        return HStack(spacing: 14) {
            // Left: Ring + pill
            VStack(spacing: 6) {
                ZStack {
                    ProgressRing(progress: ratio, color: risk, lineWidth: 8, size: 76)
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(risk)
                }

                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(risk)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(risk.opacity(0.1), in: Capsule())
            }

            // Right: Amount + breakdown + chart
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("SAFE TO SPEND")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    AddButton(size: 28)
                }

                Spacer(minLength: 2)

                Text(moneyFull(d.safeToSpendTotal, s))
                    .font(.system(size: 26, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(risk)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Mini area chart
                ZStack(alignment: .bottom) {
                    MiniAreaChart(values: weekly.map { Double($0) })
                        .fill(
                            LinearGradient(
                                colors: [risk.opacity(0.25), risk.opacity(0.02)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    MiniAreaLine(values: weekly.map { Double($0) })
                        .stroke(risk, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
                .frame(height: 28)

                Spacer(minLength: 4)

                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Text(money(d.safeToSpendPerDay, s)).font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        Text("/day").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 3) {
                        Text("\(d.daysRemainingInMonth)").font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                        Text("days left").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
    }

    private func circ(_ d: WidgetSharedData, _ s: String) -> some View {
        let ratio = d.budgetTotal > 0 ? Double(d.safeToSpendTotal) / Double(d.budgetTotal) : 0
        return Gauge(value: min(1, max(0, ratio))) {
            Image(systemName: "shield.checkered").font(.system(size: 10, weight: .bold))
        } currentValueLabel: {
            Text(moneyCompact(d.safeToSpendTotal, s))
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircular)
    }

    private func rect(_ d: WidgetSharedData, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Safe to Spend", systemImage: "shield.checkered")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            Text(moneyFull(d.safeToSpendTotal, s))
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
            Text("\(moneyCompact(d.safeToSpendPerDay, s))/day · \(d.daysRemainingInMonth)d left")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

struct SafeToSpendWidget: Widget {
    let kind = "SafeToSpendWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            SafeToSpendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DL.safe)
        }
        .configurationDisplayName("Safe to Spend")
        .description("Your financial health at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// ============================================================
// MARK: - 5 · Net Worth
// ============================================================

struct NetWorthWidgetView: View {
    let entry: BalanceTimelineEntry
    @Environment(\.widgetFamily) var fam

    var body: some View {
        let d = entry.data, s = d.currencySymbol
        if d.isEmpty { WidgetEmpty(icon: "building.columns", title: "Track Net Worth") }
        else {
            switch fam {
            case .systemSmall:  smallNW(d, s)
            case .systemMedium: mediumNW(d, s)
            case .accessoryRectangular: rectNW(d, s)
            default: smallNW(d, s)
            }
        }
    }

    // ── Small: Hero + asset/liability bars ──
    private func smallNW(_ d: WidgetSharedData, _ s: String) -> some View {
        let positive = d.netWorth >= 0

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WDS.accent)
                Text("NET WORTH")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            Text(moneyFull(d.netWorth, s))
                .font(.system(size: 28, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(positive ? WDS.accent : WDS.danger)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Spacer(minLength: 8)

            // Stacked horizontal bars
            if d.totalAssets + abs(d.totalLiabilities) > 0 {
                let maxV = max(d.totalAssets, abs(d.totalLiabilities), 1)
                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Assets").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(WDS.positive)
                                .frame(width: geo.size.width * CGFloat(Double(d.totalAssets) / Double(maxV)), height: 6)
                        }.frame(height: 6)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Debt").font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(WDS.danger)
                                .frame(width: geo.size.width * CGFloat(Double(abs(d.totalLiabilities)) / Double(maxV)), height: 6)
                        }.frame(height: 6)
                    }
                }
            }

            Spacer(minLength: 6)

            HStack {
                Text("\(d.accountCount) accounts")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(d.lastUpdated, style: .relative)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
    }

    // ── Medium: Full layout with bars ──
    private func mediumNW(_ d: WidgetSharedData, _ s: String) -> some View {
        let positive = d.netWorth >= 0

        return HStack(spacing: 0) {
            // Left: Hero
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WDS.accent)
                    Text("NET WORTH")
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Text(moneyFull(d.netWorth, s))
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(positive ? WDS.accent : WDS.danger)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Spacer(minLength: 6)

                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                    Text(d.lastUpdated, style: .relative)
                        .font(.system(size: 9, design: .rounded))
                }
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(.quaternary)
                .frame(width: 0.5)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

            // Right: Breakdown
            VStack(alignment: .leading, spacing: 10) {
                // Assets
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(WDS.positive).frame(width: 3, height: 14)
                        Text("Assets").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text(money(d.totalAssets, s))
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WDS.positive)
                }

                // Liabilities
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(WDS.danger).frame(width: 3, height: 14)
                        Text("Liabilities").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Text(money(d.totalLiabilities, s))
                        .font(.system(size: 18, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WDS.danger)
                }

                Text("\(d.accountCount) accounts")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }

    private func rectNW(_ d: WidgetSharedData, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Net Worth", systemImage: "building.columns.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
            Text(moneyFull(d.netWorth, s))
                .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
            Text("\(d.accountCount) accounts")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
    }
}

struct NetWorthWidget: Widget {
    let kind = "NetWorthWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            NetWorthWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(DL.net)
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
#Preview("Today - Small", as: .systemSmall) {
    TodaySpendingWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Today - Medium", as: .systemMedium) {
    TodaySpendingWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Budget - Small", as: .systemSmall) {
    BudgetWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Budget - Medium", as: .systemMedium) {
    BudgetWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Budget - Large", as: .systemLarge) {
    BudgetWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Safe - Small", as: .systemSmall) {
    SafeToSpendWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Safe - Medium", as: .systemMedium) {
    SafeToSpendWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Bills - Small", as: .systemSmall) {
    UpcomingBillsWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Bills - Medium", as: .systemMedium) {
    UpcomingBillsWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Net Worth - Small", as: .systemSmall) {
    NetWorthWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Net Worth - Medium", as: .systemMedium) {
    NetWorthWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Empty", as: .systemSmall) {
    BudgetWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .empty) }

#Preview("Lock - Budget", as: .accessoryCircular) {
    BudgetWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Lock - Safe Rect", as: .accessoryRectangular) {
    SafeToSpendWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }

#Preview("Lock - Inline", as: .accessoryInline) {
    TodaySpendingWidget()
} timeline: { BalanceTimelineEntry(date: .now, data: .sample) }
#endif
