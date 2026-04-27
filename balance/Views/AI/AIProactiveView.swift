import SwiftUI

// ============================================================
// MARK: - AI Proactive View (Phase 6)
// ============================================================
//
// Displays proactive AI items as dismissable cards.
// Shows morning briefings, budget risks, upcoming bills,
// unusual spending alerts, and more — sorted by severity.
//
// ============================================================

struct AIProactiveView: View {
    @Binding var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var engine = AIProactiveEngine.shared

    @State private var expandedItemId: UUID? = nil
    @State private var showWorkflow: Bool = false
    @State private var showChat: Bool = false
    @State private var showIngestion: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if engine.items.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(engine.items) { item in
                            proactiveCard(item)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity.combined(with: .scale(scale: 0.9))
                                ))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .background(DS.Colors.bg)
            .navigationTitle("Proactive Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Text("\(engine.activeCount) item(s)")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                }
            }
            .onAppear {
                engine.clearStaleDismissals()
                engine.refresh(store: store)
            }
            .sheet(isPresented: $showWorkflow) {
                AIWorkflowView(store: $store)
            }
            .sheet(isPresented: $showChat) {
                AIChatView(store: $store)
            }
            .sheet(isPresented: $showIngestion) {
                AIIngestionView(store: $store)
            }
        }
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Proactive Card
    // ══════════════════════════════════════════════════════════

    @ViewBuilder
    private func proactiveCard(_ item: ProactiveItem) -> some View {
        let isExpanded = expandedItemId == item.id
        let hasSections = !item.sections.isEmpty

        VStack(alignment: .leading, spacing: 10) {
            // ── Header row ──
            HStack(spacing: 10) {
                Image(systemName: item.type.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(severityColor(item.severity))
                    .frame(width: 28, height: 28)
                    .background(severityColor(item.severity).opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(DS.Typography.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.Colors.text)
                    Text(item.summary)
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.subtext)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                severityBadge(item.severity)
            }

            // ── Detail text ──
            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            // ── Expandable sections (briefing/review) ──
            if hasSections {
                if isExpanded {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(item.sections) { section in
                            sectionView(section)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedItemId = isExpanded ? nil : item.id
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isExpanded ? "Show Less" : "Show Details")
                            .font(DS.Typography.caption)
                            .fontWeight(.medium)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(DS.Colors.accent)
                }
            }

            // ── Action + Dismiss row ──
            HStack(spacing: 10) {
                if let action = item.action, !action.isDismissOnly {
                    Button {
                        handleAction(item: item, action: action)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: action.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(action.label)
                                .font(DS.Typography.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(DS.Colors.accent, in: Capsule())
                    }
                }

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        engine.dismiss(item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Colors.subtext)
                        .padding(6)
                        .background(DS.Colors.subtext.opacity(0.1), in: Circle())
                }
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(severityColor(item.severity).opacity(0.25), lineWidth: 1)
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Section View (Briefing / Review)
    // ══════════════════════════════════════════════════════════

    private func sectionView(_ section: ProactiveBriefingSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(severityColor(section.severity))
                Text(section.title)
                    .font(DS.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.text)
            }

            ForEach(section.lines, id: \.self) { line in
                Text(line)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.subtext)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(severityColor(section.severity).opacity(0.06))
        )
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Empty State
    // ══════════════════════════════════════════════════════════

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(DS.Colors.positive)
            Text("All Clear")
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.text)
            Text("No proactive items right now.\nEverything looks good!")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.subtext)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // ══════════════════════════════════════════════════════════
    // MARK: - Helpers
    // ══════════════════════════════════════════════════════════

    private func severityColor(_ severity: ProactiveSeverity) -> Color {
        switch severity {
        case .critical: return DS.Colors.danger
        case .warning:  return DS.Colors.warning
        case .info:     return DS.Colors.accent
        case .positive: return DS.Colors.positive
        }
    }

    private func severityBadge(_ severity: ProactiveSeverity) -> some View {
        Text(severity.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(severityColor(severity))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(severityColor(severity).opacity(0.12), in: Capsule())
    }

    private func handleAction(item: ProactiveItem, action: ProactiveAction) {
        engine.markActedOn(item.id)

        switch action.kind {
        case .startWorkflow:
            showWorkflow = true
        case .openChat:
            showChat = true
        case .openIngestion:
            showIngestion = true
        case .dismissOnly:
            withAnimation { engine.dismiss(item.id) }
        }
    }
}

// ══════════════════════════════════════════════════════════════
// MARK: - Dashboard Proactive Banner
// ══════════════════════════════════════════════════════════════

/// Compact banner for dashboard — shows top proactive items horizontally.
struct AIProactiveBanner: View {
    @Binding var store: Store
    @StateObject private var engine = AIProactiveEngine.shared
    @Environment(\.colorScheme) private var colorScheme

    var onOpenFeed: (() -> Void)? = nil
    var onOpenChat: (() -> Void)? = nil
    var onOpenDetail: ((ProactiveItem) -> Void)? = nil

    var body: some View {
        let top = engine.topItems
        if !top.isEmpty || engine.morningBriefing != nil {
            VStack(alignment: .leading, spacing: 8) {
                // Morning briefing as priority banner
                if let briefing = engine.morningBriefing {
                    briefingBanner(briefing)
                }

                // Top alerts as horizontal scroll
                if !top.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(top) { item in
                                Button {
                                    onOpenDetail?(item)
                                } label: {
                                    compactCard(item)
                                        .frame(width: 260)
                                }
                                .buttonStyle(.plain)
                            }

                            // "See all" pill
                            if engine.activeCount > top.count {
                                Button {
                                    onOpenFeed?()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("+\(engine.activeCount - top.count) more")
                                            .font(DS.Typography.caption)
                                            .fontWeight(.semibold)
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundStyle(DS.Colors.accent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(DS.Colors.accent.opacity(0.1), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Briefing Banner ──

    private func briefingBanner(_ item: ProactiveItem) -> some View {
        let (icon, accent, bgTint) = briefingTheme()
        return Button {
            onOpenDetail?(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(DS.Colors.text)
                        Text(item.summary)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Colors.subtext)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        withAnimation { engine.dismiss(item.id) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DS.Colors.subtext)
                            .padding(6)
                            .background(Circle().fill(DS.Colors.subtext.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }

                if !item.sections.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(item.sections.prefix(4)) { section in
                            HStack(spacing: 4) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 9, weight: .semibold))
                                Text(section.title)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(severityColor(section.severity))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(severityColor(section.severity).opacity(0.12))
                            )
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [bgTint.opacity(colorScheme == .dark ? 0.22 : 0.14),
                             bgTint.opacity(colorScheme == .dark ? 0.08 : 0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .background(
                colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(accent.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// Time-aware icon + accent color for the briefing banner.
    private func briefingTheme() -> (icon: String, accent: Color, bgTint: Color) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:
            // Morning — sunrise yellow
            return ("sun.horizon.fill", Color(red: 1.0, green: 0.75, blue: 0.25), Color(red: 1.0, green: 0.85, blue: 0.4))
        case 12..<17:
            // Afternoon — bright orange
            return ("sun.max.fill", Color(red: 1.0, green: 0.6, blue: 0.2), Color(red: 1.0, green: 0.7, blue: 0.3))
        case 17..<22:
            // Evening — sunset purple
            return ("sunset.fill", Color(red: 0.85, green: 0.4, blue: 0.6), Color(red: 0.7, green: 0.3, blue: 0.7))
        default:
            // Night — moon indigo
            return ("moon.stars.fill", Color(red: 0.45, green: 0.55, blue: 0.95), Color(red: 0.3, green: 0.4, blue: 0.85))
        }
    }

    // ── Compact Card ──

    private func compactCard(_ item: ProactiveItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: item.type.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(severityColor(item.severity))
                Text(item.title)
                    .font(DS.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DS.Colors.text)
                    .lineLimit(1)
                Spacer()
                Button {
                    withAnimation { engine.dismiss(item.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Colors.subtext)
                }
            }

            Text(item.summary)
                .font(.system(size: 11))
                .foregroundStyle(DS.Colors.subtext)
                .lineLimit(2)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(colorScheme == .dark ? DS.Colors.surfaceElevated : DS.Colors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(severityColor(item.severity).opacity(0.2), lineWidth: 1)
        )
    }

    private func severityColor(_ severity: ProactiveSeverity) -> Color {
        switch severity {
        case .critical: return DS.Colors.danger
        case .warning:  return DS.Colors.warning
        case .info:     return DS.Colors.accent
        case .positive: return DS.Colors.positive
        }
    }
}
