import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The Dynamic Island + Lock Screen views for the Budget Live Activity.
///
/// IMPORTANT: this file MUST be a member of the WIDGET EXTENSION target ONLY,
/// not the main app target.
struct BudgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BudgetActivityAttributes.self) { context in
            // Lock-screen / banner view
            LockScreenBudgetView(state: context.state, attributes: context.attributes)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(deepLinkURL(forPage: context.state.pageIndex))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedHeaderLeading(state: context.state, attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedHeaderTrailing(state: context.state)
                }
                DynamicIslandExpandedRegion(.center) {
                    EmptyView()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottom(state: context.state, attributes: context.attributes)
                }
            } compactLeading: {
                CompactLeading(state: context.state)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                MinimalView(state: context.state)
            }
            .keylineTint(barColor(for: context.state))
            .widgetURL(deepLinkURL(forPage: context.state.pageIndex))
        }
    }
}
