import SwiftUI

// Wrapper that generates the briefing from current engine state
// and presents BriefingView.

struct MonthlyBriefingScreen: View {
    @Binding var store: Store
    @EnvironmentObject private var authManager: AuthManager

    @State private var briefing: MonthlyBriefing?

    var body: some View {
        Group {
            if let briefing {
                BriefingView(briefing: briefing)
            } else {
                ProgressView("Generating briefing...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Monthly Briefing")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await generateBriefing()
        }
    }

    private func generateBriefing() async {
        let cal = Calendar.current
        let y = cal.component(.year, from: store.selectedMonth)
        let m = cal.component(.month, from: store.selectedMonth)
        let monthKey = String(format: "%04d-%02d", y, m)

        let uid = authManager.currentUser?.uid ?? ""
        let householdSnap: HouseholdSnapshot? = uid.isEmpty ? nil : HouseholdManager.shared.dashboardSnapshot(
            monthKey: monthKey, currentUserId: uid
        )

        briefing = BriefingEngine.generate(
            store: store,
            forecast: ForecastEngine.shared.forecast,
            reviewSnapshot: ReviewEngine.shared.dashboardSnapshot,
            subscriptionSnapshot: SubscriptionEngine.shared.dashboardSnapshot,
            householdSnapshot: householdSnap,
            goalManager: GoalManager.shared
        )
    }
}
