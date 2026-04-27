import SwiftUI

struct ReviewDashboardCard: View {
    @Binding var store: Store
    @StateObject private var engine = ReviewEngine.shared
    @State private var showReviewQueue = false

    var body: some View {
        if engine.pendingCount > 0 {
            Button {
                showReviewQueue = true
                Haptics.medium()
            } label: {
                DS.Card {
                    VStack(alignment: .leading, spacing: 12) {

                        // ── Header row ──
                        HStack(spacing: 10) {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DS.Colors.warning.opacity(0.12))
                                    .frame(width: 38, height: 38)
                                Image(systemName: "tray.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(DS.Colors.warning)
                                    .frame(width: 38, height: 38)
                                if engine.highPriorityCount > 0 {
                                    Circle()
                                        .fill(DS.Colors.danger)
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Text("\(engine.highPriorityCount)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                        .offset(x: 4, y: -4)
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Needs Review")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(DS.Colors.text)
                                Text("\(engine.pendingCount) transaction\(engine.pendingCount == 1 ? "" : "s") flagged")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                            }

                            Spacer()

                            Text("Review")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(DS.Colors.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(DS.Colors.accentLight, in: Capsule())

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DS.Colors.subtext.opacity(0.4))
                        }

                        // ── Issue type breakdown ──
                        let chips = issueChips()
                        if !chips.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(chips, id: \.label) { chip in
                                    HStack(spacing: 4) {
                                        Image(systemName: chip.icon)
                                            .font(.system(size: 9, weight: .bold))
                                        Text(chip.label)
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .foregroundStyle(chip.color)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(chip.color.opacity(0.1), in: Capsule())
                                }
                                Spacer()
                            }
                        }

                        // ── Top issue preview ──
                        if let top = engine.pendingItems.first {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "sparkle.magnifyingglass")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .padding(.top, 1)

                                Text(top.reason)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.text.opacity(0.85))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Colors.surface2.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showReviewQueue) {
                ReviewQueueView(store: $store)
            }
        }
    }

    private struct IssueChip {
        let icon: String
        let label: String
        let color: Color
    }

    private func issueChips() -> [IssueChip] {
        var chips: [IssueChip] = []
        if engine.duplicateCount > 0 {
            chips.append(IssueChip(icon: "doc.on.doc.fill", label: "\(engine.duplicateCount) duplicate", color: DS.Colors.danger))
        }
        if engine.spikeCount > 0 {
            chips.append(IssueChip(icon: "arrow.up.right", label: "\(engine.spikeCount) spike", color: DS.Colors.warning))
        }
        if engine.uncategorizedCount > 0 {
            chips.append(IssueChip(icon: "tag.slash.fill", label: "\(engine.uncategorizedCount) untagged", color: DS.Colors.subtext))
        }
        if engine.recurringCandidateCount > 0 && chips.isEmpty {
            chips.append(IssueChip(icon: "repeat", label: "\(engine.recurringCandidateCount) recurring", color: DS.Colors.accent))
        }
        return chips
    }
}
