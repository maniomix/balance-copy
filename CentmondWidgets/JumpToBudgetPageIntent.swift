import ActivityKit
import AppIntents
import Foundation

/// Live Activity intent — jumps the expanded view straight to a specific page.
/// Bound to each tappable dot in `PageDots`.
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
        print("🟢 [JumpToBudgetPageIntent] perform() invoked → page \(page)")

        for activity in Activity<BudgetActivityAttributes>.activities {
            var newState = activity.content.state
            // Clamp against this activity's own dynamic page count.
            let target = max(0, min(newState.pageCount - 1, page))
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
