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
        // Use both print and Logger — Xcode console catches print, Console.app
        // catches both. If neither shows up, the intent is not dispatching.
        print("🟢 [CycleBudgetPageIntent] perform() invoked")
        log.notice("perform() invoked")

        let activities = Activity<BudgetActivityAttributes>.activities
        print("🟢 [CycleBudgetPageIntent] Found \(activities.count) activities")
        log.notice("Found \(activities.count, privacy: .public) activities")

        for activity in activities {
            var newState = activity.content.state
            let oldPage = newState.pageIndex
            // pageCount is dynamic (4 normally, 5 when a goal is featured).
            newState.pageIndex = (oldPage + 1) % max(1, newState.pageCount)
            print("🟢 [CycleBudgetPageIntent] Updating: page \(oldPage) → \(newState.pageIndex) (of \(newState.pageCount))")

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
