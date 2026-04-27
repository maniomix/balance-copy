import SwiftUI

// Wrapper that generates the briefing from current engine state,
// presents BriefingView, and handles section taps by opening
// AIChatView seeded with a section-specific prompt.

struct MonthlyBriefingScreen: View {
    @Binding var store: Store
    @EnvironmentObject private var authManager: AuthManager

    @State private var briefing: MonthlyBriefing?
    @State private var chatPrefill: String? = nil

    var body: some View {
        Group {
            if let briefing {
                BriefingView(briefing: briefing) { section in
                    chatPrefill = chatSeed(for: section)
                }
            } else {
                ProgressView("Generating briefing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(DS.Colors.bg.ignoresSafeArea())
        .navigationTitle("Monthly Briefing")
        .navigationBarTitleDisplayMode(.inline)
        .task { await generateBriefing() }
        .sheet(item: Binding(
            get: { chatPrefill.map { ChatPrefillBox(text: $0) } },
            set: { chatPrefill = $0?.text }
        )) { box in
            AIChatView(store: $store, initialInput: box.text)
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

    private func chatSeed(for section: BriefingSection) -> String {
        switch section.kind {
        case .overview:      return "Walk me through how I did this month."
        case .spending:      return "Break down where my money went this month."
        case .forecast:      return "How is my budget tracking and what's the risk this month?"
        case .subscriptions: return "Help me review my subscriptions and find ones to cancel."
        case .review:        return "What transactions need my review?"
        case .goals:         return "How am I doing on my goals?"
        case .household:     return "Walk me through our shared household spending this month."
        }
    }
}

private struct ChatPrefillBox: Identifiable {
    let id = UUID()
    let text: String
}
