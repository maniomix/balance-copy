import AppIntents
import SwiftUI

/// Tappable page rail — each dot is a button that jumps directly to that
/// page via `JumpToBudgetPageIntent`. Generous invisible hit areas around
/// the small visible dot — same trick the system uses on pagination dots.
struct PageRail: View {
    let currentPage: Int
    let count: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                Group {
                    if #available(iOS 17.0, *) {
                        Button(intent: JumpToBudgetPageIntent(page: i)) {
                            cell(for: i)
                        }
                        .buttonStyle(.plain)
                    } else {
                        cell(for: i)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: currentPage)
    }

    @ViewBuilder
    private func cell(for i: Int) -> some View {
        let isActive = i == currentPage
        ZStack {
            // Invisible hit target — much larger than the visible dot so
            // taps don't miss. 28pt wide × 18pt tall per cell.
            Color.clear
                .frame(width: 28, height: 18)
                .contentShape(Rectangle())
            Capsule()
                .fill(isActive ? tint : Color.white.opacity(0.3))
                .frame(width: isActive ? 14 : 4, height: 4)
        }
    }
}

/// Big, obvious "Next" fallback in the header — guaranteed-working tap
/// target. Kept alongside the tappable rail for users who prefer it.
struct NextPageButton: View {
    let tint: Color

    var body: some View {
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
                .background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
    }
}
