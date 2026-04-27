import Foundation

// ============================================================
// MARK: - Category Reference Repair (Phase 6a — iOS port)
// ============================================================
//
// Repairs orphan custom-category references. Transactions and
// category-scoped budgets can point at a `CustomCategoryModel` that
// the user has since deleted; on iOS those manifest as orphan
// `Category.custom(...)` values with a `storageKey` like
// `custom:Coffee` when there's no matching `customCategoryNames`
// entry.
//
// Ported from macOS Centmond but iOS-specific: iOS does NOT use
// SwiftData, so there are no tombstone crashes — just orphaned
// string keys that need scrubbing. Safe to run at app launch.
//
// Recovery policy:
//   - Transactions with a dead custom category → re-tag to
//     `.other` (the existing iOS "unknown" bucket).
//   - Category budgets keyed to a dead custom storageKey → dropped.
// ============================================================

enum CategoryReferenceRepair {

    /// Returns a summary of how much was repaired. Safe to call at launch.
    @discardableResult
    static func run(store: inout Store) -> Summary {
        // Phase 7: `customCategoriesWithIcons` is the single source of truth.
        let liveCustomKeys: Set<String> = Set(
            store.customCategoriesWithIcons.map { "custom:\($0.name)" }
        )

        var retaggedTxns = 0
        var droppedBudgetKeys = 0

        // Transactions: re-tag any whose custom category is no longer defined.
        for i in store.transactions.indices {
            let key = store.transactions[i].category.storageKey
            guard key.hasPrefix("custom:") else { continue }
            if !liveCustomKeys.contains(key) {
                store.transactions[i].category = .other
                retaggedTxns += 1
            }
        }

        // Category budgets: drop entries pointing at a dead custom key.
        for monthKey in store.categoryBudgetsByMonth.keys {
            guard var monthBudgets = store.categoryBudgetsByMonth[monthKey] else { continue }
            let before = monthBudgets.count
            for key in monthBudgets.keys where key.hasPrefix("custom:") && !liveCustomKeys.contains(key) {
                monthBudgets.removeValue(forKey: key)
            }
            let diff = before - monthBudgets.count
            if diff > 0 {
                droppedBudgetKeys += diff
                store.categoryBudgetsByMonth[monthKey] = monthBudgets
            }
        }

        return Summary(retaggedTransactions: retaggedTxns, droppedBudgetKeys: droppedBudgetKeys)
    }

    struct Summary {
        let retaggedTransactions: Int
        let droppedBudgetKeys: Int

        var hasRepairs: Bool { retaggedTransactions > 0 || droppedBudgetKeys > 0 }
    }
}
