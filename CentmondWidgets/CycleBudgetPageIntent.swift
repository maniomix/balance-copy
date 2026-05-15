import ActivityKit
import AppIntents
import Foundation
import os

private let log = Logger(subsystem: "com.centmond.liveactivity", category: "CycleBudgetPage")

/// Live Activity button intent — advances the expanded view to the next page.
///
/// CRITICAL: this intent's `perform()` runs in the HOST APP's process, not
/// the widget's. The type therefore MUST be a member of the `balance` target.
/// It must ALSO be a member of `CentmondWidgetsExtension` so the widget's
/// `Button(intent: CycleBudgetPageIntent())` can construct an instance.
///
/// In Xcode → File Inspector → Target Membership → both checkboxes ON.
@available(iOS 17.0, *)
struct CycleBudgetPageIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Budget Page"
    static var description = IntentDescription("Cycle to the next page of the budget Live Activity.")

    /// Don't bring the app to the foreground when this fires — defeats the
    /// purpose of the Live Activity.
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        for activity in Activity<BudgetActivityAttributes>.activities {
            var newState = activity.content.state
            newState.pageIndex = (newState.pageIndex + 1) % max(1, newState.pageCount)
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
