import AppIntents
import SwiftUI

// Expanded view regions — header (leading + trailing) and bottom container
// that dispatches to the active page. The bottom box is pinned to a fixed
// height so iOS doesn't resize the Dynamic Island between pages.

struct ExpandedHeaderLeading: View {
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
        // Uniform leading inset — header sits at the same x as the page
        // content below it.
        .padding(.leading, 10)
    }
}

struct ExpandedHeaderTrailing: View {
    let state: BudgetActivityAttributes.ContentState
    var body: some View {
        NextPageButton(tint: barColor(for: state))
            .padding(.trailing, 10)
    }
}

struct ExpandedBottom: View {
    let state: BudgetActivityAttributes.ContentState
    let attributes: BudgetActivityAttributes
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Fixed page content height — keeps the activity from resizing between
    /// pages. Bumped from 64 → 90 so the hero amount can render at its
    /// reference-screenshot size without cramping the bottom row.
    private static let pageBoxHeight: CGFloat = 90

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                switch state.pageIndex {
                case 1: TodayPage(state: state)
                case 2: WeekPage(state: state)
                case 3: TopCategoryPage(state: state)
                default: BudgetPage(state: state, attributes: attributes)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.pageBoxHeight,
                   maxHeight: Self.pageBoxHeight, alignment: .topLeading)
            // In-view transition keyed on pageIndex — gives the user a visual
            // confirmation of the page change *before* the next activity.update
            // round-trip lands. Reduce-motion users get an opacity-only fade,
            // no slide.
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
            .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.2), value: state.pageIndex)

            PageRail(currentPage: state.pageIndex, count: state.pageCount,
                     tint: barColor(for: state))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        // Light inset for the bottom region — matches the leading/trailing
        // header insets so the entire DI content reads as one uniformly
        // padded block, not a heavily-indented middle row.
        .padding(.horizontal, 10)
    }
}
