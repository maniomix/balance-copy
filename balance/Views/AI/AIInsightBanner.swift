import SwiftUI

// ============================================================
// MARK: - AI Insight Banner
// ============================================================
//
// Compact banner card for displaying a single AIInsight.
// Used on the dashboard and insights screen.
//
// ============================================================

struct AIInsightBanner: View {
    let insight: AIInsight
    var onAction: ((AIAction) -> Void)? = nil
    /// Compact layout for horizontal scrolling rows — suppresses body bullets
    /// and the action button, shows only title + first body line.
    var compact: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle()
                        .fill(severityColor.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(severityColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(insight.title)
                        .font(.system(size: compact ? 14 : 16, weight: .bold))
                        .foregroundStyle(DS.Colors.text)
                        .lineLimit(compact ? 2 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if let firstLine = insight.body.components(separatedBy: "\n").first,
                       !firstLine.isEmpty {
                        Text(firstLine)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                            .lineLimit(compact ? 2 : 1)
                    }
                }

                Spacer()
                severityDot
            }

            // Remaining body lines (after the first shown in header)
            let remainingLines = Array(insight.body.components(separatedBy: "\n").dropFirst())
            if !remainingLines.isEmpty && !compact {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(remainingLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(severityColor.opacity(0.6))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [severityColor.opacity(colorScheme == .dark ? 0.18 : 0.10),
                         severityColor.opacity(colorScheme == .dark ? 0.04 : 0.02)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .background(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(severityColor.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var iconName: String {
        // Time-of-day icon for morning briefing; normal icons otherwise.
        if insight.type == .morningBriefing {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:  return "sun.horizon.fill"
            case 12..<17: return "sun.max.fill"
            case 17..<22: return "sunset.fill"
            default:      return "moon.stars.fill"
            }
        }
        switch insight.type {
        case .budgetWarning: return "exclamationmark.triangle"
        case .spendingAnomaly: return "exclamationmark.circle"
        case .savingsOpportunity: return "lightbulb"
        case .recurringDetected: return "repeat.circle"
        case .weeklyReport: return "calendar"
        case .goalProgress: return "target"
        case .patternDetected: return "chart.bar"
        case .morningBriefing: return "sun.max"
        // Phase 2 additions
        case .cashflowRisk: return "drop.triangle"
        case .duplicateDetected: return "doc.on.doc"
        case .subscriptionAlert: return "arrow.triangle.2.circlepath"
        case .householdAlert: return "person.2"
        case .netWorthMilestone: return "flag.checkered"
        case .reviewQueueAlert: return "tray.and.arrow.down"
        }
    }

    private var severityColor: Color {
        if insight.type == .morningBriefing {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:  return Color(red: 1.0, green: 0.75, blue: 0.25)
            case 12..<17: return Color(red: 1.0, green: 0.6, blue: 0.2)
            case 17..<22: return Color(red: 0.85, green: 0.4, blue: 0.6)
            default:      return Color(red: 0.45, green: 0.55, blue: 0.95)
            }
        }
        switch insight.severity {
        case .critical: return DS.Colors.danger
        case .warning: return DS.Colors.warning
        case .info: return DS.Colors.accent
        case .positive: return DS.Colors.positive
        }
    }

    private var severityDot: some View {
        Circle()
            .fill(severityColor)
            .frame(width: 8, height: 8)
    }

}

// MARK: - Dashboard Insight Row

/// A horizontal scrolling row of insight banners for the dashboard.
struct AIInsightRow: View {
    let insights: [AIInsight]
    var onTap: ((AIInsight) -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(insights.prefix(3)) { insight in
                Button {
                    onTap?(insight)
                } label: {
                    AIInsightBanner(insight: insight, compact: true)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Insight Detail Sheet

struct AIInsightDetailSheet: View {
    let insight: AIInsight

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: iconName)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(DS.Colors.text)
                            Text(severityLabel)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(accent.opacity(0.15)))
                        }
                    }

                    // Body as bulleted lines
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(insight.body.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                            if !line.isEmpty {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(accent.opacity(0.6))
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 7)
                                    Text(line)
                                        .font(.system(size: 14))
                                        .foregroundStyle(DS.Colors.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
                    )

                    if let advice = insight.advice, !advice.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Suggestion", systemImage: "lightbulb.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Colors.positive)
                            Text(advice)
                                .font(.system(size: 14))
                                .foregroundStyle(DS.Colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DS.Colors.positive.opacity(0.08))
                        )
                    }

                    if let cause = insight.cause, !cause.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Why", systemImage: "info.circle")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                            Text(cause)
                                .font(.system(size: 13))
                                .foregroundStyle(DS.Colors.subtext)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DS.Colors.subtext.opacity(0.08))
                        )
                    }

                }
                .padding(18)
            }
            .background(DS.Colors.bg)
            .navigationTitle("Insight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var iconName: String {
        switch insight.type {
        case .budgetWarning: return "exclamationmark.triangle.fill"
        case .spendingAnomaly: return "exclamationmark.circle.fill"
        case .savingsOpportunity: return "lightbulb.fill"
        case .recurringDetected: return "repeat.circle.fill"
        case .weeklyReport: return "calendar"
        case .goalProgress: return "target"
        case .patternDetected: return "chart.bar.fill"
        case .morningBriefing:
            let h = Calendar.current.component(.hour, from: Date())
            switch h { case 5..<12: return "sun.horizon.fill"
                      case 12..<17: return "sun.max.fill"
                      case 17..<22: return "sunset.fill"
                      default: return "moon.stars.fill" }
        case .cashflowRisk: return "drop.triangle.fill"
        case .duplicateDetected: return "doc.on.doc.fill"
        case .subscriptionAlert: return "arrow.triangle.2.circlepath"
        case .householdAlert: return "person.2.fill"
        case .netWorthMilestone: return "flag.checkered"
        case .reviewQueueAlert: return "tray.and.arrow.down.fill"
        }
    }

    private var accent: Color {
        switch insight.severity {
        case .critical: return DS.Colors.danger
        case .warning:  return DS.Colors.warning
        case .info:     return DS.Colors.accent
        case .positive: return DS.Colors.positive
        }
    }

    private var severityLabel: String {
        switch insight.severity {
        case .critical: return "Critical"
        case .warning:  return "Needs attention"
        case .info:     return "Info"
        case .positive: return "Good news"
        }
    }
}

// MARK: - Proactive Detail Sheet

struct AIProactiveDetailSheet: View {
    let item: ProactiveItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: item.type.icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(DS.Colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(severityLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(accent.opacity(0.15)))
                        }
                        Spacer()
                    }

                    // Summary body card — primary text of the insight
                    if !item.summary.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("What we noticed", systemImage: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                            Text(item.summary)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DS.Colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
                        )
                    }

                    // Long-form detail if provided
                    if let detail = item.detail, !detail.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Details", systemImage: "text.alignleft")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                            Text(detail)
                                .font(.system(size: 14))
                                .foregroundStyle(DS.Colors.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
                        )
                    }

                    if !item.sections.isEmpty {
                        VStack(spacing: 10) {
                            ForEach(item.sections) { section in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Image(systemName: section.icon)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(sectionColor(section.severity))
                                        Text(section.title)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(DS.Colors.text)
                                    }
                                    ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                                        HStack(alignment: .top, spacing: 8) {
                                            Circle()
                                                .fill(sectionColor(section.severity).opacity(0.6))
                                                .frame(width: 5, height: 5)
                                                .padding(.top, 7)
                                            Text(line)
                                                .font(.system(size: 13))
                                                .foregroundStyle(DS.Colors.text)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
                                )
                            }
                        }
                    }

                    // Signals as capsule chips (what triggered this)
                    if !item.signals.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Signals", systemImage: "waveform")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext)
                            HStack(spacing: 6) {
                                ForEach(Array(item.signals.enumerated()), id: \.offset) { _, signal in
                                    Text(signal)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(DS.Colors.subtext)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill(DS.Colors.subtext.opacity(0.12)))
                                }
                            }
                        }
                    }

                    // Timestamp footer
                    Text("Detected \(relativeDate(item.createdAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Colors.subtext)
                }
                .padding(18)
            }
            .background(DS.Colors.bg)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var severityLabel: String {
        switch item.severity {
        case .critical: return "Critical"
        case .warning:  return "Needs attention"
        case .info:     return "Info"
        case .positive: return "Good news"
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let fmt = RelativeDateTimeFormatter()
        fmt.unitsStyle = .full
        return fmt.localizedString(for: date, relativeTo: Date())
    }

    private var accent: Color {
        switch item.severity {
        case .critical: return DS.Colors.danger
        case .warning:  return DS.Colors.warning
        case .info:     return DS.Colors.accent
        case .positive: return DS.Colors.positive
        }
    }

    private func sectionColor(_ s: ProactiveSeverity) -> Color {
        switch s {
        case .critical: return DS.Colors.danger
        case .warning:  return DS.Colors.warning
        case .info:     return DS.Colors.accent
        case .positive: return DS.Colors.positive
        }
    }
}
