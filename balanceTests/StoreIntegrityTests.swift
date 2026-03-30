import XCTest
@testable import balance

/// Regression tests for Store category/budget integrity.
/// Protects hardened invariants from the Category/Budget Integrity pass.
final class StoreIntegrityTests: XCTestCase {

    // MARK: - Helpers

    private func makeStore() -> Store {
        var store = Store()
        store.customCategoryNames = ["Coffee", "Pets"]
        store.customCategoriesWithIcons = [
            CustomCategoryModel(id: "c1", name: "Coffee", icon: "cup.and.saucer.fill", colorHex: "A0522D"),
            CustomCategoryModel(id: "c2", name: "Pets", icon: "pawprint.fill", colorHex: "FF6B6B"),
        ]
        return store
    }

    private func makeTx(
        id: UUID = UUID(),
        amount: Int = 500,
        category: Category = .other,
        type: TransactionType = .expense,
        date: Date = Date()
    ) -> Transaction {
        Transaction(
            id: id,
            amount: amount,
            date: date,
            category: category,
            note: "",
            paymentMethod: .card,
            type: type
        )
    }

    // MARK: - Category Name Existence

    func testCustomCategoryNameExistsIsCaseInsensitive() {
        let store = makeStore()
        XCTAssertTrue(store.customCategoryNameExists("coffee"))
        XCTAssertTrue(store.customCategoryNameExists("COFFEE"))
        XCTAssertTrue(store.customCategoryNameExists("Coffee"))
    }

    func testSystemCategoryNameBlocksCustom() {
        let store = makeStore()
        XCTAssertTrue(store.customCategoryNameExists("Groceries"))
        XCTAssertTrue(store.customCategoryNameExists("groceries"))
        XCTAssertTrue(store.customCategoryNameExists("Other"))
    }

    func testNonexistentNameReturnsFalse() {
        let store = makeStore()
        XCTAssertFalse(store.customCategoryNameExists("Travel"))
    }

    func testEmptyNameReturnsFalse() {
        let store = makeStore()
        XCTAssertFalse(store.customCategoryNameExists(""))
        XCTAssertFalse(store.customCategoryNameExists("   "))
    }

    // MARK: - Add Custom Category

    func testAddCustomCategoryBlocksDuplicate() {
        var store = makeStore()
        store.addCustomCategory(name: "coffee") // case-insensitive dup
        // Should still only have 2 categories
        XCTAssertEqual(store.customCategoryNames.count, 2)
    }

    func testAddCustomCategoryBlocksSystemName() {
        var store = makeStore()
        store.addCustomCategory(name: "Groceries")
        XCTAssertFalse(store.customCategoryNames.contains("Groceries"))
    }

    func testAddCustomCategorySortsAlphabetically() {
        var store = Store()
        store.addCustomCategory(name: "Zebra")
        store.addCustomCategory(name: "Alpha")
        store.addCustomCategory(name: "Middle")
        XCTAssertEqual(store.customCategoryNames, ["Alpha", "Middle", "Zebra"])
    }

    // MARK: - Rename Custom Category

    func testRenameUpdatesTransactions() {
        var store = makeStore()
        store.transactions = [
            makeTx(category: .custom("Coffee")),
            makeTx(category: .groceries),
            makeTx(category: .custom("Coffee")),
        ]
        store.renameCustomCategory(oldName: "Coffee", newName: "Café")

        let coffeeCount = store.transactions.filter {
            if case .custom("Coffee") = $0.category { return true }
            return false
        }.count
        let cafeCount = store.transactions.filter {
            if case .custom("Café") = $0.category { return true }
            return false
        }.count
        XCTAssertEqual(coffeeCount, 0, "Old name should be gone from transactions")
        XCTAssertEqual(cafeCount, 2, "New name should be on both transactions")
    }

    func testRenameUpdatesBudgetKeys() {
        var store = makeStore()
        let oldKey = Category.custom("Coffee").storageKey
        let newKey = Category.custom("Café").storageKey

        store.categoryBudgetsByMonth["2025-03"] = [oldKey: 5000, "groceries": 10000]
        store.categoryBudgetsByMonth["2025-04"] = [oldKey: 6000]

        store.renameCustomCategory(oldName: "Coffee", newName: "Café")

        // Old key gone, new key present with same value
        XCTAssertNil(store.categoryBudgetsByMonth["2025-03"]?[oldKey])
        XCTAssertEqual(store.categoryBudgetsByMonth["2025-03"]?[newKey], 5000)
        XCTAssertEqual(store.categoryBudgetsByMonth["2025-03"]?["groceries"], 10000)
        XCTAssertNil(store.categoryBudgetsByMonth["2025-04"]?[oldKey])
        XCTAssertEqual(store.categoryBudgetsByMonth["2025-04"]?[newKey], 6000)
    }

    func testRenameUpdatesCustomCategoryNames() {
        var store = makeStore()
        store.renameCustomCategory(oldName: "Coffee", newName: "Café")

        XCTAssertFalse(store.customCategoryNames.contains("Coffee"))
        XCTAssertTrue(store.customCategoryNames.contains("Café"))
    }

    func testRenameUpdatesCustomCategoriesWithIcons() {
        var store = makeStore()
        store.renameCustomCategory(oldName: "Coffee", newName: "Café")

        XCTAssertNil(store.customCategoriesWithIcons.first(where: { $0.name == "Coffee" }))
        let renamed = store.customCategoriesWithIcons.first(where: { $0.name == "Café" })
        XCTAssertNotNil(renamed)
        XCTAssertEqual(renamed?.id, "c1") // Same ID, just name changed
    }

    func testRenameUpdatesRecurringTransactions() {
        var store = makeStore()
        store.recurringTransactions = [
            RecurringTransaction(name: "Daily Coffee", amount: 500, category: .custom("Coffee"), frequency: .daily, startDate: Date(), isActive: true, paymentMethod: .card, note: ""),
        ]
        store.renameCustomCategory(oldName: "Coffee", newName: "Café")

        if case .custom(let name) = store.recurringTransactions[0].category {
            XCTAssertEqual(name, "Café")
        } else {
            XCTFail("Recurring transaction should have custom(Café) category")
        }
    }

    func testRenameBlockedByConflict() {
        var store = makeStore()
        store.renameCustomCategory(oldName: "Coffee", newName: "Pets") // Pets already exists
        // Coffee should still be there, unchanged
        XCTAssertTrue(store.customCategoryNames.contains("Coffee"))
    }

    func testRenameSameNameNoOp() {
        var store = makeStore()
        store.transactions = [makeTx(category: .custom("Coffee"))]
        let originalModified = store.transactions[0].lastModified

        store.renameCustomCategory(oldName: "Coffee", newName: "Coffee")

        // Nothing should change
        XCTAssertEqual(store.transactions[0].lastModified, originalModified)
    }

    func testRenameCaseOnlyAllowed() {
        var store = makeStore()
        store.renameCustomCategory(oldName: "Coffee", newName: "COFFEE")
        XCTAssertTrue(store.customCategoryNames.contains("COFFEE"))
        XCTAssertFalse(store.customCategoryNames.contains("Coffee"))
    }

    // MARK: - Delete Custom Category

    func testDeleteMigratesTransactionsToOther() {
        var store = makeStore()
        store.transactions = [
            makeTx(category: .custom("Coffee")),
            makeTx(category: .groceries),
        ]
        store.deleteCustomCategory(name: "Coffee")

        XCTAssertEqual(store.transactions[0].category, .other)
        XCTAssertEqual(store.transactions[1].category, .groceries) // Unaffected
    }

    func testDeleteRemovesBudgetKeys() {
        var store = makeStore()
        let key = Category.custom("Coffee").storageKey
        store.categoryBudgetsByMonth["2025-03"] = [key: 5000, "groceries": 10000]

        store.deleteCustomCategory(name: "Coffee")

        XCTAssertNil(store.categoryBudgetsByMonth["2025-03"]?[key])
        XCTAssertEqual(store.categoryBudgetsByMonth["2025-03"]?["groceries"], 10000)
    }

    func testDeleteRemovesFromBothNameLists() {
        var store = makeStore()
        store.deleteCustomCategory(name: "Coffee")

        XCTAssertFalse(store.customCategoryNames.contains("Coffee"))
        XCTAssertNil(store.customCategoriesWithIcons.first(where: { $0.name == "Coffee" }))
    }

    func testDeleteUpdatesRecurringTransactions() {
        var store = makeStore()
        store.recurringTransactions = [
            RecurringTransaction(name: "Daily Coffee", amount: 500, category: .custom("Coffee"), frequency: .daily, startDate: Date(), isActive: true, paymentMethod: .card, note: ""),
        ]
        store.deleteCustomCategory(name: "Coffee")

        XCTAssertEqual(store.recurringTransactions[0].category, .other)
    }

    // MARK: - Purge Stale Budget Keys

    func testPurgeRemovesOrphanedBudgetKeys() {
        var store = makeStore()
        store.categoryBudgetsByMonth["2025-03"] = [
            "groceries": 10000,
            "custom:Coffee": 5000,
            "custom:DeletedCategory": 3000, // Orphan
            "nonexistent_key": 999,          // Garbage
        ]

        store.purgeStaleCustomCategoryBudgetKeys()

        let month = store.categoryBudgetsByMonth["2025-03"]!
        XCTAssertEqual(month["groceries"], 10000)
        XCTAssertEqual(month["custom:Coffee"], 5000)
        XCTAssertNil(month["custom:DeletedCategory"], "Orphan should be removed")
        XCTAssertNil(month["nonexistent_key"], "Garbage key should be removed")
    }

    func testPurgePreservesAllValidKeys() {
        var store = makeStore()
        // Set budgets for every system category + both custom categories
        var budgets: [String: Int] = [:]
        for cat in store.allCategories {
            budgets[cat.storageKey] = 1000
        }
        store.categoryBudgetsByMonth["2025-03"] = budgets

        let countBefore = store.categoryBudgetsByMonth["2025-03"]!.count
        store.purgeStaleCustomCategoryBudgetKeys()
        let countAfter = store.categoryBudgetsByMonth["2025-03"]!.count

        XCTAssertEqual(countBefore, countAfter, "No valid keys should be removed")
    }

    // MARK: - Store Computations

    func testSpentAndIncomeForMonth() {
        var store = Store()
        let march2025 = makeDate(year: 2025, month: 3, day: 15)
        let april2025 = makeDate(year: 2025, month: 4, day: 10)

        store.transactions = [
            makeTx(amount: 1000, type: .expense, date: march2025),
            makeTx(amount: 2000, type: .expense, date: march2025),
            makeTx(amount: 5000, type: .income, date: march2025),
            makeTx(amount: 9999, type: .expense, date: april2025), // Different month
        ]

        XCTAssertEqual(store.spent(for: march2025), 3000)
        XCTAssertEqual(store.income(for: march2025), 5000)
        XCTAssertEqual(store.spent(for: april2025), 9999)
    }

    func testRemainingIncludesBudgetPlusIncomeMinusSpent() {
        var store = Store()
        let march = makeDate(year: 2025, month: 3, day: 15)
        store.budgetsByMonth["2025-03"] = 100000 // $1000 budget
        store.transactions = [
            makeTx(amount: 30000, type: .expense, date: march),
            makeTx(amount: 10000, type: .income, date: march),
        ]

        // remaining = budget(100000) + income(10000) - spent(30000) = 80000
        XCTAssertEqual(store.remaining(for: march), 80000)
    }

    // MARK: - Category StorageKey

    func testStorageKeyForSystemCategories() {
        XCTAssertEqual(Category.groceries.storageKey, "groceries")
        XCTAssertEqual(Category.other.storageKey, "other")
    }

    func testStorageKeyForCustomCategory() {
        XCTAssertEqual(Category.custom("Coffee").storageKey, "custom:Coffee")
        XCTAssertEqual(Category.custom("My Cat").storageKey, "custom:My Cat")
    }

    func testStorageKeyPreservesCasing() {
        // Critical: custom:Coffee != custom:coffee
        XCTAssertNotEqual(
            Category.custom("Coffee").storageKey,
            Category.custom("coffee").storageKey
        )
    }

    // MARK: - MonthKey

    func testMonthKeyFormat() {
        let date = makeDate(year: 2025, month: 3, day: 15)
        XCTAssertEqual(Store.monthKey(date), "2025-03")

        let jan = makeDate(year: 2024, month: 1, day: 1)
        XCTAssertEqual(Store.monthKey(jan), "2024-01")
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        return Calendar.current.date(from: comps)!
    }
}
