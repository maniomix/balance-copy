import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Dynamic Island + Lock Screen views for the Budget Live Activity.
///
/// IMPORTANT: this file MUST be a member of the WIDGET EXTENSION target ONLY,
/// not the main app target.
struct BudgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BudgetActivityAttributes.self) { context in
            // Lock-screen / banner view
            LockScreenBudgetView(state: context.state, attributes: context.attributes)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLinkURL(forPage: context.state.pageIndex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedHeaderLeading(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedHeaderTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state, attributes: context.attributes)
                }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .keylineTint(barColor(for: context.state))
            .widgetURL(deepLinkURL(forPage: context.state.pageIndex))
        }
    }
}

/// Per-page deep-link target. Tapping the activity (compact or expanded
/// regions outside the Next button / dots) opens Centmond at the most
/// relevant tab for what the user was just looking at.
private func deepLinkURL(forPage pageIndex: Int) -> URL? {
    let host: String
    switch pageIndex {
    case 1: host = "transactions"   // Today → Transactions list
    case 2: host = "insights"       // Week → Insights/charts
    case 3: host = "insights"       // Top Category → Insights/categories
    case 4: host = "goals"          // Goal → Goals
    default: host = "budget"        // Budget → Budget
    }
    return URL(string: "centmond://\(host)")
}

// MARK: - Helpers

private func barColor(for state: BudgetActivityAttributes.ContentState) -> Color {
    if state.isOverBudget { return .red }
    if state.percentSpent >= 0.85 { return .orange }
    return Color(red: 0.30, green: 0.85, blue: 0.55)
}

private func formatAmount(_ cents: Int, symbol: String) -> String {
    "\(symbol)\(Int(Double(cents) / 100))"
}

private func formatAmountDecimal(_ cents: Int, symbol: String) -> String {
    "\(symbol)\(String(format: "%.2f", Double(cents) / 100))"
}

private struct PageMeta {
    let title: String
    let icon: String
}

private let pageMetas: [PageMeta] = [
    .init(title: "BUDGET",       icon: "chart.pie.fill"),
    .init(title: "TODAY",        icon: "sun.max.fill"),
    .init(title: "THIS WEEK",    icon: "calendar"),
    .init(title: "TOP CATEGORY", icon: "trophy.fill"),
    .init(title: "GOAL",         icon: "flag.fill"),
]

// MARK: - Compact

private struct CompactLeading: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        // Small filled ring — same visual language as the minimal view.
        // Sits to the LEFT of the sensor cutout; we add `.trailing` padding
        // so the ring doesn't crowd or clip under the sensor edge.
        ZStack {
            Circle()
                .stroke(barColor(for: state).opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.04, state.percentSpent))
                .stroke(barColor(for: state),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Center dot turns solid when over budget — instant urgency cue
            // even at this tiny size.
            if state.isOverBudget {
                Circle()
                    .fill(.red)
                    .frame(width: 4, height: 4)
            }
        }
        .frame(width: 16, height: 16)
        .padding(.trailing, 1)
    }
}

private struct CompactTrailing: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        // Health-tinted amount: green when on track, orange when ≥85%, red
        // when over. Sits to the RIGHT of the sensor cutout, so we add
        // `.leading` padding to push the text away from the sensor edge.
        Group {
            if state.totalCents == 0 {
                Text("—")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text(formatAmount(
                    state.isOverBudget ? (state.spentCents - state.totalCents) : state.remainingCents,
                    symbol: state.currencySymbol
                ))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(barColor(for: state))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.leading, 1)
    }
}

private struct MinimalView: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        ZStack {
            Circle()
                .stroke(barColor(for: state).opacity(0.25), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: max(0.04, state.percentSpent))
                .stroke(barColor(for: state),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Filled center when over budget — same urgency cue as compact,
            // visible even when this is sharing space with another activity.
            if state.isOverBudget {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(2)
    }
}

// MARK: - Expanded header (top regions)

private struct ExpandedHeaderLeading: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes
    private var meta: PageMeta { pageMetas[min(state.pageIndex, pageMetas.count - 1)] }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: meta.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(barColor(for: state))
            Text(meta.title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.leading, 4)
    }
}

private struct ExpandedHeaderTrailing: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        Group {
            if #available(iOS 17.0, *) {
                Button(intent: CycleBudgetPageIntent()) {
                    HStack(spacing: 4) {
                        Text("Next")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.18))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 4)
    }
}

// MARK: - Expanded bottom (page content + dots)

private struct ExpandedBottom: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes
    /// Fixed expanded-bottom height — keeps the activity from resizing every
    /// time the user taps Next. All four pages render inside this same box.
    /// 64pt accommodates the 28pt hero + 6pt spacer + ~16pt detail row.
    private static let pageBoxHeight: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Active page content — pinned to a fixed frame so iOS doesn't
            // resize the Dynamic Island between pages.
            Group {
                switch state.pageIndex {
                case 1: TodayPage(state: state)
                case 2: WeekPage(state: state)
                case 3: TopCategoryPage(state: state)
                case 4: GoalPage(state: state)
                default: BudgetPage(state: state, attributes: attributes)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.pageBoxHeight,
                   maxHeight: Self.pageBoxHeight, alignment: .topLeading)

            // Dot indicator — count is dynamic (4 normally, 5 with a goal).
            PageDots(currentPage: state.pageIndex, count: state.pageCount,
                     tint: barColor(for: state))
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Pages

// All four pages are designed to fit inside the same fixed 56pt box:
// Line 1: 22pt hero number
// Line 2: 11pt detail / progress bar

// Each page: hero on the left (~28pt) + a meaningful right-side stat-tile to
// fill the wide horizontal space, plus a detail row underneath.

private struct StatTile: View {
    let value: String
    let label: String
    let tint: Color
    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        // Hold natural width so a wide hero shrinks first instead of pushing
        // this tile off-screen.
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
    }
}

private struct PageHero: View {
    let amount: String
    let label: String
    let tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(amount)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .layoutPriority(2) // shrink last when crowded
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .layoutPriority(0) // shrink first
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BudgetPage: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes
    var body: some View {
        if state.totalCents == 0 {
            EmptyStatePage(
                icon: "chart.pie",
                title: "No budget set",
                subtitle: "Set a monthly budget in Centmond to see your remaining amount here."
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    PageHero(
                        amount: formatAmount(
                            state.isOverBudget ? (state.spentCents - state.totalCents) : state.remainingCents,
                            symbol: state.currencySymbol
                        ),
                        label: state.isOverBudget ? "over" : "left",
                        tint: barColor(for: state)
                    )
                    Spacer()
                    if state.isOverBudgetAlert == true {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Text("NEW")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.red))
                        .shadow(color: Color.red.opacity(0.55), radius: 6, x: 0, y: 0)
                        .fixedSize()
                        .layoutPriority(1)
                    } else {
                        StatTile(
                            value: "\(state.daysLeft)",
                            label: state.isHistorical == true ? "days in month" : "days left",
                            tint: .white
                        )
                    }
                }
                ProgressBar(percent: state.percentSpent, tint: barColor(for: state))
            }
        }
    }
}

private struct TodayPage: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                PageHero(
                    amount: formatAmountDecimal(state.todaySpentCents, symbol: state.currencySymbol),
                    label: state.todayLabel ?? "today",
                    tint: .white
                )
                if state.todayTxCount > 0 {
                    StatTile(
                        value: "\(state.todayTxCount)",
                        label: state.todayTxCount == 1 ? "transaction" : "transactions",
                        tint: barColor(for: state)
                    )
                }
            }
            HStack(spacing: 6) {
                Image(systemName: state.lastTransactionIcon ?? "clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                Text(state.lastTransactionTitle ?? "No transactions \(state.isHistorical == true ? "in this month" : "yet today")")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(state.lastTransactionTitle != nil ? 0.7 : 0.45))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct WeekPage: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        if state.weekSpentCents == 0 {
            EmptyStatePage(
                icon: "calendar",
                title: "Quiet week",
                subtitle: state.isHistorical == true
                    ? "No spending in the last 7 days of this month."
                    : "No spending logged in the last 7 days."
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    PageHero(
                        amount: formatAmountDecimal(state.weekSpentCents, symbol: state.currencySymbol),
                        label: state.isHistorical == true ? "last 7 days" : "7 days",
                        tint: .white
                    )
                    StatTile(
                        value: formatAmountDecimal(state.dailyAverageThisWeekCents, symbol: state.currencySymbol),
                        label: "average per day",
                        tint: barColor(for: state)
                    )
                }
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                    Text("Weekly spending pace")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct TopCategoryPage: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        if state.topCategoryCents == 0 {
            EmptyStatePage(
                icon: "trophy",
                title: "No spending yet",
                subtitle: state.isHistorical == true
                    ? "No transactions in this month."
                    : "Log a transaction to see your top category."
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    PageHero(
                        amount: formatAmountDecimal(state.topCategoryCents, symbol: state.currencySymbol),
                        label: "spent",
                        tint: .white
                    )
                    if state.spentCents > 0 {
                        let pct = Int((Double(state.topCategoryCents) / Double(state.spentCents)) * 100)
                        StatTile(value: "\(pct)%", label: "of month", tint: barColor(for: state))
                    }
                }
                HStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(barColor(for: state).opacity(0.2))
                            .frame(width: 20, height: 20)
                        Image(systemName: state.topCategoryIcon ?? "trophy.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(barColor(for: state))
                    }
                    Text(state.topCategoryTitle ?? "—")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct GoalPage: View {
    let state: BudgetActivityAttributes.ContentState

    private var symbol: String { state.currencySymbol }
    private var current: Int { state.goalCurrentCents ?? 0 }
    private var target: Int { state.goalTargetCents ?? 0 }
    private var pct: Double { state.goalPercent }

    var body: some View {
        if target == 0 {
            // Shouldn't normally render — page hides when no goal — but
            // safety net for in-flight activities mid-update.
            EmptyStatePage(
                icon: "flag",
                title: "No active goal",
                subtitle: "Add a goal in Centmond to track progress here."
            )
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    PageHero(
                        amount: "\(Int(pct * 100))%",
                        label: "complete",
                        tint: pct >= 1.0
                            ? Color(red: 0.30, green: 0.85, blue: 0.55)
                            : barColor(for: state)
                    )
                    StatTile(
                        value: formatAmount(max(0, target - current), symbol: symbol),
                        label: "remaining",
                        tint: .white
                    )
                }
                HStack(spacing: 8) {
                    Image(systemName: state.goalIcon ?? "flag.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.65))
                    Text(state.goalName ?? "Goal")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyStatePage: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Reusable bits

private struct ProgressBar: View {
    let percent: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(max(0.02, min(1.0, percent))))
            }
        }
        .frame(height: 6)
    }
}

private struct PageDots: View {
    let currentPage: Int
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Group {
                    if #available(iOS 17.0, *) {
                        Button(intent: JumpToBudgetPageIntent(page: i)) {
                            dotShape(for: i)
                                // Enlarge the actual hit target without
                                // changing the visual size — dots are tiny,
                                // we want a generous tap zone.
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        dotShape(for: i)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: currentPage)
    }

    @ViewBuilder
    private func dotShape(for i: Int) -> some View {
        if i == currentPage {
            Capsule()
                .fill(tint)
                .frame(width: 14, height: 4)
        } else {
            Circle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 4, height: 4)
        }
    }
}

// MARK: - Lock screen / banner / StandBy
//
// One view drives three surfaces:
// 1. Lock-screen banner (bottom of locked iPhone)
// 2. Notification-center banner
// 3. StandBy mode (iPhone sideways on charger) — iOS reuses this view
//    automatically; we just need to make sure it looks good in a taller frame
//    too. The vertical stack scales naturally.

private struct LockScreenBudgetView: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes

    var body: some View {
        if state.totalCents == 0 {
            LockScreenEmptyState()
                .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                header
                hero
                progress
                miniStats
                if let last = state.lastTransactionTitle {
                    lastTransactionRow(title: last)
                }
            }
            .padding(16)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(barColor(for: state))
                Text(attributes.monthLabel.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("\(state.daysLeft)d \(state.isHistorical == true ? "in mo" : "left")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.white.opacity(0.1))
            )
        }
    }

    // MARK: - Hero (amount + circular ring)

    private var hero: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatAmount(
                    state.isOverBudget ? (state.spentCents - state.totalCents) : state.remainingCents,
                    symbol: state.currencySymbol
                ))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(barColor(for: state))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(state.isOverBudget ? "OVER BUDGET" : "REMAINING")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .stroke(barColor(for: state).opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.04, state.percentSpent))
                    .stroke(barColor(for: state),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((Double(state.spentCents) / Double(max(1, state.totalCents))) * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            .frame(width: 56, height: 56)
        }
    }

    // MARK: - Progress bar with totals

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressBar(percent: state.percentSpent, tint: barColor(for: state))
            HStack {
                Text(formatAmount(state.spentCents, symbol: state.currencySymbol))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                Text("of \(formatAmount(state.totalCents, symbol: state.currencySymbol))")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer()
            }
        }
    }

    // MARK: - Mini stats (3 columns)

    private var miniStats: some View {
        HStack(spacing: 8) {
            miniStat(
                icon: "sun.max.fill",
                label: state.todayLabel?.uppercased() ?? "TODAY",
                value: formatAmount(state.todaySpentCents, symbol: state.currencySymbol)
            )
            miniStat(
                icon: "calendar",
                label: state.isHistorical == true ? "LAST 7" : "7 DAYS",
                value: formatAmount(state.weekSpentCents, symbol: state.currencySymbol)
            )
            miniStat(
                icon: state.topCategoryIcon ?? "trophy.fill",
                label: "TOP",
                value: state.topCategoryTitle ?? "—"
            )
        }
    }

    private func miniStat(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    // MARK: - Last transaction footer

    private func lastTransactionRow(title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: state.lastTransactionIcon ?? "creditcard.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            Text("Last: \(title)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct LockScreenEmptyState: View {
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 44, height: 44)
                Image(systemName: "chart.pie")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("No budget set")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Text("Open Centmond and set a monthly budget to track here.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
