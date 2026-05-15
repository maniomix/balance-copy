import ActivityKit
import AppIntents
import Foundation

/// Live Activity intent — jumps the expanded view straight to a specific page.
/// Bound to each tappable dot in `PageRail`.
///
/// MUST be a member of BOTH the `balance` target AND the
/// `CentmondWidgetsExtension` target.
@available(iOS 17.0, *)
struct JumpToBudgetPageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Jump to Budget Page"
    static var description = IntentDescription("Jump to a specific page of the budget Live Activity.")

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Page")
    var page: Int

    init() {
        self.page = 0
    }

    init(page: Int) {
        self.page = page
    }

    func perform() async throws -> some IntentResult {
        for activity in Activity<BudgetActivityAttributes>.activities {
            var newState = activity.content.state
            let target = max(0, min(newState.pageCount - 1, page))
            // Skip the activity.update round-trip if nothing changed —
            // saves a system call on accidental re-taps of the active dot.
            guard target != newState.pageIndex else { continue }
            newState.pageIndex = target
            await activity.update(
                ActivityContent(
                    state: newState,
                    staleDate: Date().addingTimeInterval(60 * 60 * 8)
                )
            )
        }
        return .result()
    }
}
