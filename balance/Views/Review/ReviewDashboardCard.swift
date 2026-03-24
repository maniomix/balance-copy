import SwiftUI

// ============================================================
// MARK: - Review Dashboard Card (Redesigned)
// ============================================================
// Minimal banner-style card: icon + count + top issue + action.
// ============================================================

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
                    HStack(spacing: 12) {
                        // Icon with badge
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Colors.warning.opacity(0.12))
                                .frame(width: 40, height: 40)

                            Image(systemName: "tray.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Colors.warning)
                                .frame(width: 40, height: 40)

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

                        // Info
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(engine.pendingCount) items need review")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(DS.Colors.text)

                            // Top issue preview
                            if let top = engine.pendingItems.first {
                                Text(top.reason)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Colors.subtext)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        // Tags — show the most important categories
                        VStack(alignment: .trailing, spacing: 4) {
                            if engine.duplicateCount > 0 {
                                tagPill("\(engine.duplicateCount) duplicate", DS.Colors.danger)
                            }
                            if engine.spikeCount > 0 {
                                tagPill("\(engine.spikeCount) spike", Color(hexValue: 0x9B59B6))
                            }
                            if engine.uncategorizedCount > 0 {
                                tagPill("\(engine.uncategorizedCount) uncat.", DS.Colors.warning)
                            }
                            if engine.recurringCandidateCount > 0 && engine.duplicateCount == 0 && engine.spikeCount == 0 {
                                tagPill("\(engine.recurringCandidateCount) recurring", DS.Colors.accent)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Colors.subtext.opacity(0.3))
                    }
                }
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showReviewQueue) {
                ReviewQueueView(store: $store)
            }
        }
    }

    private func tagPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}
