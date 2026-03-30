import Foundation

// ============================================================
// MARK: - Action Card Engine
// ============================================================
//
// Generates prioritized action cards from all 4 engine snapshots.
// Cards are ranked by priority and deduped by type.
// Dismissed cards are persisted in UserDefaults per month.
//
// Max 3 cards shown at any time to avoid overwhelm.
//
// ============================================================

@MainActor
enum ActionCardEngine {

    private static let maxCards = 3
    private static let dismissKeyPrefix = "actioncard.dismissed."

    /// Generate action cards from current app state.
    static func generate(
        store: Store,
        forecast: ForecastResult?,
        reviewSnapshot: ReviewSnapshot?,
        subscriptionSnapshot: SubscriptionSnapshot?,
        householdSnapshot: HouseholdSnapshot?,
        goalManager: GoalManager?
    ) -> [ActionCard] {
        var cards: [ActionCard] = []
        let monthKey = monthKeyString(from: store.selectedMonth)

        // 1. Forecast risk — critical priority
        if let f = forecast {
            if f.safeToSpend.isOvercommitted {
                cards.append(ActionCard(
                    id: "overcommitted.\(monthKey)",
                    type: .overBudget,
                    priority: .critical,
                    title: "Over-committed",
                    subtitle: "Bills + goals exceed your budget by \(DS.Format.money(f.safeToSpend.overcommitAmount))",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: 0xFF3B30,
                    deepLink: .forecast
                ))
            } else if f.riskLevel == .highRisk {
                cards.append(ActionCard(
                    id: "highrisk.\(monthKey)",
                    type: .forecastRisk,
                    priority: .critical,
                    title: "High spending risk",
                    subtitle: f.urgentRiskSummary ?? "Reduce spending to stay on track",
                    icon: "chart.line.downtrend.xyaxis",
                    iconColor: 0xFF3B30,
                    deepLink: .forecast
                ))
            } else if f.riskLevel == .caution {
                cards.append(ActionCard(
                    id: "caution.\(monthKey)",
                    type: .forecastRisk,
                    priority: .medium,
                    title: "Spending pace elevated",
                    subtitle: "Safe to spend: \(DS.Format.money(f.safeToSpend.perDay))/day",
                    icon: "gauge.with.dots.needle.50percent",
                    iconColor: 0xFF9F0A,
                    deepLink: .forecast
                ))
            }

            // Overdue bills
            if f.overdueBillCount > 0 {
                cards.append(ActionCard(
                    id: "overdue.\(monthKey)",
                    type: .overdueBill,
                    priority: .critical,
                    title: "\(f.overdueBillCount) overdue bill\(f.overdueBillCount == 1 ? "" : "s")",
                    subtitle: "Check and resolve overdue payments",
                    icon: "exclamationmark.circle.fill",
                    iconColor: 0xFF3B30,
                    deepLink: .forecast
                ))
            }

            // Upcoming bills (next 3 days)
            let soon = f.upcomingBills.prefix(2)
            for bill in soon {
                let cal = Calendar.current
                let daysUntil = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: bill.dueDate)).day ?? 0
                if daysUntil <= 3 && daysUntil >= 0 {
                    let timeDesc = daysUntil == 0 ? "today" : daysUntil == 1 ? "tomorrow" : "in \(daysUntil) days"
                    cards.append(ActionCard(
                        id: "bill.\(bill.name).\(monthKey)",
                        type: .billDue,
                        priority: .high,
                        title: "\(bill.name) due \(timeDesc)",
                        subtitle: DS.Format.money(bill.amount),
                        icon: "calendar.badge.clock",
                        iconColor: 0x4559F5,
                        deepLink: .forecast
                    ))
                }
            }
        }

        // 2. Review items — high priority for duplicates
        if let rs = reviewSnapshot {
            if rs.duplicateCount > 0 {
                cards.append(ActionCard(
                    id: "duplicates.\(monthKey)",
                    type: .duplicateTransactions,
                    priority: .high,
                    title: "\(rs.duplicateCount) potential duplicate\(rs.duplicateCount == 1 ? "" : "s")",
                    subtitle: "Review and remove duplicate transactions",
                    icon: "doc.on.doc.fill",
                    iconColor: 0xFF3B30,
                    deepLink: .review
                ))
            }

            if rs.uncategorizedCount > 0 {
                cards.append(ActionCard(
                    id: "uncategorized.\(monthKey)",
                    type: .uncategorized,
                    priority: .low,
                    title: "\(rs.uncategorizedCount) uncategorized",
                    subtitle: "Assign categories for better insights",
                    icon: "tag.fill",
                    iconColor: 0x8E8E93,
                    deepLink: .review
                ))
            }

            if rs.pendingCount > 0 && rs.duplicateCount == 0 && rs.uncategorizedCount == 0 {
                cards.append(ActionCard(
                    id: "review.\(monthKey)",
                    type: .reviewQueue,
                    priority: .medium,
                    title: "\(rs.pendingCount) item\(rs.pendingCount == 1 ? "" : "s") to review",
                    subtitle: rs.topIssueReason ?? "Clean up your transactions",
                    icon: "checkmark.circle.fill",
                    iconColor: 0xFF9F0A,
                    deepLink: .review
                ))
            }
        }

        // 3. Household — settlement needed
        if let hs = householdSnapshot, hs.hasPartner {
            if hs.youOwe > 0 {
                cards.append(ActionCard(
                    id: "settle.\(monthKey)",
                    type: .settlementNeeded,
                    priority: .high,
                    title: "Settle \(DS.Format.money(hs.youOwe))",
                    subtitle: "\(hs.unsettledCount) unsettled expense\(hs.unsettledCount == 1 ? "" : "s")",
                    icon: "arrow.left.arrow.right.circle.fill",
                    iconColor: 0xE91E63,
                    deepLink: .household
                ))
            } else if hs.unsettledCount > 3 {
                cards.append(ActionCard(
                    id: "unsettled.\(monthKey)",
                    type: .settlementNeeded,
                    priority: .medium,
                    title: "\(hs.unsettledCount) expenses to settle",
                    subtitle: "Keep your household balanced",
                    icon: "person.2.circle.fill",
                    iconColor: 0xE91E63,
                    deepLink: .household
                ))
            }
        }

        // 4. Unused subscriptions
        if let ss = subscriptionSnapshot, ss.unusedCount > 0 {
            cards.append(ActionCard(
                id: "unused_subs.\(monthKey)",
                type: .unusedSubscriptions,
                priority: .medium,
                title: "Cancel \(ss.unusedCount) unused sub\(ss.unusedCount == 1 ? "" : "s")",
                subtitle: "Save \(DS.Format.money(ss.potentialSavings))/mo",
                icon: "scissors",
                iconColor: 0xFF9F0A,
                deepLink: .subscriptions
            ))
        }

        // 5. Goals behind
        if let gm = goalManager {
            let behind = gm.behindGoals
            if !behind.isEmpty {
                let topBehind = behind.first!
                cards.append(ActionCard(
                    id: "goal_behind.\(monthKey)",
                    type: .goalBehind,
                    priority: .medium,
                    title: "\(topBehind.name) falling behind",
                    subtitle: "Increase contributions to stay on track",
                    icon: "target",
                    iconColor: 0x3498DB,
                    deepLink: .goals
                ))
            }
        }

        // 6. Category cap warnings
        let monthTx = Analytics.monthTransactions(store: store)
        for c in store.allCategories {
            let cap = store.categoryBudget(for: c)
            guard cap > 0 else { continue }
            let spent = monthTx.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
            let ratio = Double(spent) / Double(max(1, cap))
            if ratio >= 1.0 {
                cards.append(ActionCard(
                    id: "catcap.\(c.storageKey).\(monthKey)",
                    type: .categoryCap,
                    priority: .high,
                    title: "\(c.title) over budget",
                    subtitle: "\(DS.Format.money(spent - cap)) over your \(DS.Format.money(cap)) cap",
                    icon: "chart.bar.fill",
                    iconColor: 0xFF3B30,
                    deepLink: .budget
                ))
                break  // only show the worst one
            } else if ratio >= 0.90 {
                cards.append(ActionCard(
                    id: "catcap.\(c.storageKey).\(monthKey)",
                    type: .categoryCap,
                    priority: .medium,
                    title: "\(c.title) at \(DS.Format.percent(ratio))",
                    subtitle: "\(DS.Format.money(cap - spent)) left in cap",
                    icon: "chart.bar.fill",
                    iconColor: 0xFF9F0A,
                    deepLink: .budget
                ))
                break
            }
        }

        // Filter dismissed, sort by priority, limit
        let dismissed = dismissedCardIds(monthKey: monthKey)
        let filtered = cards
            .filter { !dismissed.contains($0.id) }
            .sorted { $0.priority < $1.priority }

        // Deduplicate by type (keep highest priority per type)
        var seenTypes: Set<ActionCardType> = []
        let deduped = filtered.filter { card in
            if seenTypes.contains(card.type) { return false }
            seenTypes.insert(card.type)
            return true
        }

        return Array(deduped.prefix(maxCards))
    }

    // MARK: - Dismiss

    static func dismiss(_ card: ActionCard, monthKey: String) {
        var dismissed = dismissedCardIds(monthKey: monthKey)
        dismissed.insert(card.id)
        UserDefaults.standard.set(Array(dismissed), forKey: dismissKeyPrefix + monthKey)
    }

    private static func dismissedCardIds(monthKey: String) -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: dismissKeyPrefix + monthKey) ?? []
        return Set(arr)
    }

    // MARK: - Helpers

    private static func monthKeyString(from date: Date) -> String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }
}
